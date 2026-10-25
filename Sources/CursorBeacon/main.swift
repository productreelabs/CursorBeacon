// CursorBeacon
// Draws a large, visible pointer that follows the mouse, so it shows up
// in VNC and screen-sharing streams that hide the real cursor.

import AppKit

// MARK: - Configuration

struct Config {
    var size: CGFloat = 40
    var fill: NSColor = .systemYellow
    var stroke: NSColor = .black
    var strokeWidth: CGFloat = 2
    var refreshRate: Double = 60

    static func parse(_ arguments: [String]) -> Config {
        var config = Config()
        var iterator = arguments.dropFirst().makeIterator()

        while let arg = iterator.next() {
            switch arg {
            case "--size":
                if let value = iterator.next(), let size = Double(value), size >= 12, size <= 200 {
                    config.size = CGFloat(size)
                }
            case "--color":
                if let value = iterator.next(), let color = NSColor.parse(value) {
                    config.fill = color
                }
            case "--fps":
                if let value = iterator.next(), let fps = Double(value), fps >= 10, fps <= 120 {
                    config.refreshRate = fps
                }
            case "-h", "--help":
                print("""
                Usage: CursorBeacon [--size 12-200] [--color name|#RRGGBB] [--fps 10-120]

                Colors: yellow, red, green, blue, pink, orange, white, or a hex value.
                """)
                exit(0)
            default:
                print("Unknown option: \(arg). Use --help for usage.")
            }
        }
        return config
    }
}

extension NSColor {
    static func parse(_ value: String) -> NSColor? {
        let named: [String: NSColor] = [
            "yellow": .systemYellow, "red": .systemRed, "green": .systemGreen,
            "blue": .systemBlue, "pink": .systemPink, "orange": .systemOrange,
            "white": .white
        ]
        if let color = named[value.lowercased()] { return color }

        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Pointer drawing

final class PointerView: NSView {
    private let config: Config

    init(config: Config) {
        self.config = config
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Distance from the view edge to the arrow tip, so the stroke isn't clipped.
    var inset: CGFloat { config.strokeWidth }

    override func draw(_ dirtyRect: NSRect) {
        // Classic arrow shape in unit coordinates, tip at (0, 0).
        let points: [(CGFloat, CGFloat)] = [
            (0.00, 0.00), (0.00, 0.85), (0.22, 0.66), (0.36, 0.98),
            (0.50, 0.92), (0.36, 0.60), (0.62, 0.60)
        ]

        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: inset + point.0 * config.size, y: inset + point.1 * config.size)
            index == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        path.lineJoinStyle = .round

        config.fill.setFill()
        path.fill()
        config.stroke.setStroke()
        path.lineWidth = config.strokeWidth
        path.stroke()
    }
}

// MARK: - Overlay window

final class OverlayWindow: NSPanel {
    init(view: PointerView, size: CGFloat) {
        let side = size + view.inset * 2
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = view
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // Clicks pass straight through.
        level = .screenSaver               // Above menus, docks and full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Cursor tracking

final class PointerTracker: NSObject {
    private let window: NSWindow
    private let inset: CGFloat
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastLocation: NSPoint?

    init(window: NSWindow, inset: CGFloat, refreshRate: Double) {
        self.window = window
        self.inset = inset
        self.interval = 1 / refreshRate
    }

    func start() {
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    @objc private func tick() {
        let location = NSEvent.mouseLocation
        guard location != lastLocation else { return }
        lastLocation = location

        // Screen coordinates start at the bottom left; place the arrow tip on the cursor.
        let origin = NSPoint(x: location.x - inset, y: location.y - window.frame.height + inset)
        window.setFrameOrigin(origin)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: Config
    private var window: OverlayWindow?
    private var tracker: PointerTracker?
    private var statusItem: NSStatusItem?

    init(config: Config) {
        self.config = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = PointerView(config: config)
        let window = OverlayWindow(view: view, size: config.size)
        window.orderFrontRegardless()

        let tracker = PointerTracker(window: window, inset: view.inset, refreshRate: config.refreshRate)
        tracker.start()

        self.window = window
        self.tracker = tracker
        setUpMenuBarItem()
    }

    private func setUpMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "CursorBeacon")

        let menu = NSMenu()
        menu.addItem(withTitle: "CursorBeacon is running", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(config: Config.parse(CommandLine.arguments))
app.delegate = delegate
app.setActivationPolicy(.accessory)   // No Dock icon.
app.run()
