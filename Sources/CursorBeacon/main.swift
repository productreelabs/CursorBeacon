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
    var debug = false

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
                _ = iterator.next()
                print("--fps is no longer needed: CursorBeacon now follows the mouse and the display refresh rate.")
            case "--debug":
                config.debug = true
            case "-h", "--help":
                print("""
                Usage: CursorBeacon [--size 12-200] [--color name|#RRGGBB] [--debug]

                Colors: yellow, red, green, blue, pink, orange, white, or a hex value.
                --debug prints how many milliseconds CursorBeacon adds to each mouse move.
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

// MARK: - Pointer image

/// The arrow is drawn once into a bitmap per screen scale, then only moved around.
struct PointerImage {
    let image: CGImage
    let side: CGFloat
    /// Arrow tip in unit coordinates of the image, bottom-left origin (Core Animation's anchor point).
    let tip: CGPoint

    // Classic arrow shape in unit coordinates, tip at (0, 0), y pointing down.
    private static let arrow: [(CGFloat, CGFloat)] = [
        (0.00, 0.00), (0.00, 0.85), (0.22, 0.66), (0.36, 0.98),
        (0.50, 0.92), (0.36, 0.60), (0.62, 0.60)
    ]

    init?(config: Config, scale: CGFloat) {
        // Inset the shape so the stroke isn't clipped.
        let inset = config.strokeWidth
        let side = config.size + inset * 2
        let pixels = Int((side * scale).rounded(.up))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Flip so y grows downward, matching the shape coordinates.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)

        let path = CGMutablePath()
        for (index, point) in Self.arrow.enumerated() {
            let p = CGPoint(x: inset + point.0 * config.size, y: inset + point.1 * config.size)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(config.fill.cgColor)
        context.setStrokeColor(config.stroke.cgColor)
        context.setLineWidth(config.strokeWidth)
        context.setLineJoin(.round)
        context.drawPath(using: .fillStroke)

        guard let image = context.makeImage() else { return nil }
        self.image = image
        self.side = side
        self.tip = CGPoint(x: inset / side, y: 1 - inset / side)
    }
}

// MARK: - Overlay window

/// A transparent, click-through window covering one screen. Only the pointer layer inside it moves.
final class OverlayWindow: NSPanel {
    private let pointer = CALayer()

    init?(screen: NSScreen, config: Config) {
        guard let image = PointerImage(config: config, scale: screen.backingScaleFactor) else { return nil }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // Clicks pass straight through.
        level = .screenSaver               // Above menus, docks and full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view

        pointer.contents = image.image
        pointer.contentsScale = screen.backingScaleFactor
        pointer.bounds = CGRect(x: 0, y: 0, width: image.side, height: image.side)
        pointer.anchorPoint = image.tip    // So `position` is where the tip goes.
        pointer.isHidden = true
        // No implicit animations: the pointer should jump, not glide.
        pointer.actions = ["position": NSNull(), "hidden": NSNull()]
        view.layer?.addSublayer(pointer)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Moves the arrow tip to a global screen location, or hides it if the location is on another screen.
    func place(at location: NSPoint) {
        let onScreen = location.x >= frame.minX && location.x <= frame.maxX
            && location.y >= frame.minY && location.y <= frame.maxY
        pointer.isHidden = !onScreen
        if onScreen {
            pointer.position = CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        }
    }
}

// MARK: - Cursor tracking

/// Moves the pointer on every mouse event, with a display-synced check as a safety net
/// for moves that don't produce events (for example, a VNC client warping the cursor).
final class PointerTracker {
    private let config: Config
    private var windows: [OverlayWindow] = []
    private var monitors: [Any] = []
    private var displayLink: CVDisplayLink?
    private var lastLocation: NSPoint?
    private let latency = LatencyStats()

    init(config: Config) {
        self.config = config
    }

    func start() {
        rebuildWindows()

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let handler: (NSEvent) -> Void = { [weak self] event in self?.update(eventTime: event.timestamp) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: handler) {
            monitors.append(global)
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: events) { event in
            handler(event)
            return event
        } as Any)

        var link: CVDisplayLink?
        if CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link {
            CVDisplayLinkSetOutputHandler(link) { _, _, _, _, _ in
                DispatchQueue.main.async { [weak self] in self?.update() }
                return kCVReturnSuccess
            }
            CVDisplayLinkStart(link)
            displayLink = link
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }

        if config.debug { latency.start() }
    }

    /// One overlay per screen, recreated when screens are added, removed or rearranged.
    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.compactMap { OverlayWindow(screen: $0, config: config) }
        windows.forEach { $0.orderFrontRegardless() }
        lastLocation = nil
        update()
    }

    private func update(eventTime: TimeInterval? = nil) {
        if let eventTime, config.debug {
            latency.record(ProcessInfo.processInfo.systemUptime - eventTime)
        }

        let location = NSEvent.mouseLocation
        guard location != lastLocation else { return }
        lastLocation = location
        windows.forEach { $0.place(at: location) }
    }
}

/// Prints how long mouse events take to reach the pointer, every two seconds while the mouse moves.
final class LatencyStats {
    private var samples: [TimeInterval] = []

    func start() {
        print("Debug: move the mouse to see timings.")
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.report() }
    }

    func record(_ seconds: TimeInterval) {
        samples.append(seconds)
    }

    private func report() {
        guard !samples.isEmpty else { return }
        let average = samples.reduce(0, +) / Double(samples.count) * 1000
        let worst = (samples.max() ?? 0) * 1000
        print(String(format: "Mouse event to pointer: avg %.1f ms, worst %.1f ms (%d moves)", average, worst, samples.count))
        samples.removeAll()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: Config
    private var tracker: PointerTracker?
    private var statusItem: NSStatusItem?

    init(config: Config) {
        self.config = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let tracker = PointerTracker(config: config)
        tracker.start()
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

setvbuf(stdout, nil, _IOLBF, 0)      // Print each line right away, even when piped to a file.

let app = NSApplication.shared
let delegate = AppDelegate(config: Config.parse(CommandLine.arguments))
app.delegate = delegate
app.setActivationPolicy(.accessory)   // No Dock icon.
app.run()
