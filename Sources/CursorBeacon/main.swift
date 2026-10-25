// CursorBeacon
// Draws a large, visible pointer that follows the mouse, so it shows up
// in VNC and screen-sharing streams that hide the real cursor.

import AppKit
import Carbon.HIToolbox

// MARK: - Configuration

/// When the pointer is drawn.
enum ShowMode: String, CaseIterable {
    case always, sharing, off

    var title: String {
        switch self {
        case .always: return "Always"
        case .sharing: return "Only While Screen Sharing"
        case .off: return "Off"
        }
    }
}

struct Config {
    var size: CGFloat = 40
    var fill: NSColor = .systemYellow
    var stroke: NSColor = .black
    var strokeWidth: CGFloat = 2
    var showMode: ShowMode = .sharing
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
            case "--show":
                if let value = iterator.next(), let mode = ShowMode(rawValue: value.lowercased()) {
                    config.showMode = mode
                }
            case "--debug":
                config.debug = true
            case "-h", "--help":
                print("""
                Usage: CursorBeacon [--size 12-200] [--color name|#RRGGBB] [--show always|sharing|off] [--debug]

                Colors: yellow, red, green, blue, pink, orange, white, or a hex value.
                --show sharing (the default) draws the pointer only while someone is connected by VNC or Screen Sharing.
                --debug prints how many milliseconds CursorBeacon adds to each mouse move.
                Control-Option-Command-B shows or hides the pointer at any time.
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
    private var isVisible = true
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

    /// Shows or hides the pointer. While hidden, the display-synced check is paused to save power.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            windows.forEach { $0.orderFrontRegardless() }
            if let displayLink { CVDisplayLinkStart(displayLink) }
            lastLocation = nil
            update()
        } else {
            windows.forEach { $0.orderOut(nil) }
            if let displayLink { CVDisplayLinkStop(displayLink) }
        }
    }

    /// One overlay per screen, recreated when screens are added, removed or rearranged.
    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.compactMap { OverlayWindow(screen: $0, config: config) }
        if isVisible { windows.forEach { $0.orderFrontRegardless() } }
        lastLocation = nil
        update()
    }

    private func update(eventTime: TimeInterval? = nil) {
        guard isVisible else { return }
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

// MARK: - Screen sharing detection

/// Watches for an open VNC connection: macOS Screen Sharing, or RealVNC and other
/// VNC servers accepting direct connections. Both listen on port 5900.
final class SharingMonitor {
    private(set) var isSharing = false
    var onChange: ((Bool) -> Void)?
    private let port: UInt16 = 5900
    private var timer: Timer?

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        let sharing = hasEstablishedConnection(onLocalPort: port)
        guard sharing != isSharing else { return }
        isSharing = sharing
        onChange?(sharing)
    }

    /// Reads the kernel's TCP connection table directly (what `netstat` shows), which needs
    /// no permissions and takes well under a millisecond.
    private func hasEstablishedConnection(onLocalPort port: UInt16) -> Bool {
        let name = "net.inet.tcp.pcblist_n"
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return false }
        size += size / 4                   // Room for connections opened in between.
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return false }

        // The table is a header, then for each connection a run of records (address, socket,
        // buffers, stats, TCP state), each starting with its length and kind, padded to 8 bytes.
        let inpcbKind: UInt32 = 0x10, tcpcbKind: UInt32 = 0x20, established: Int32 = 4
        return buffer.withUnsafeBytes { raw in
            func u32(_ offset: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            let padded = { (length: Int) in (length + 7) & ~7 }

            var offset = padded(Int(u32(0)))
            var localPort: UInt16?
            while offset + 40 <= size {
                let length = Int(u32(offset)), kind = u32(offset + 4)
                if length <= 24 { break }      // The closing header.
                if kind == inpcbKind {
                    localPort = UInt16(bigEndian: raw.loadUnaligned(fromByteOffset: offset + 18, as: UInt16.self))
                } else if kind == tcpcbKind {
                    let state = Int32(bitPattern: u32(offset + 36))
                    if localPort == port && state == established { return true }
                    localPort = nil
                }
                offset += padded(length)
            }
            return false
        }
    }
}

// MARK: - Global shortcut

/// A system-wide keyboard shortcut. Uses the Carbon hot key API, which needs no permissions.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            if let userData { Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4342_4E4B), id: 1)   // "CBNK"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: Config
    private var mode: ShowMode
    /// Set by the shortcut or "Show/Hide Now"; cleared when the mode changes or a session starts or ends.
    private var manualOverride: Bool?
    private var tracker: PointerTracker?
    private let sharing = SharingMonitor()
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleNow), keyEquivalent: "b")
    private var modeItems: [ShowMode: NSMenuItem] = [:]

    init(config: Config) {
        self.config = config
        self.mode = config.showMode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let tracker = PointerTracker(config: config)
        tracker.start()
        self.tracker = tracker
        setUpMenuBarItem()

        sharing.onChange = { [weak self] connected in
            if self?.config.debug == true { print(connected ? "Screen sharing started." : "Screen sharing ended.") }
            self?.manualOverride = nil
            self?.refresh()
        }
        sharing.start()

        hotKey = HotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.toggleNow()
        }
        refresh()
    }

    private var shouldShow: Bool {
        if let manualOverride { return manualOverride }
        switch mode {
        case .always: return true
        case .sharing: return sharing.isSharing
        case .off: return false
        }
    }

    private func refresh() {
        let visible = shouldShow
        tracker?.setVisible(visible)

        statusItem?.button?.appearsDisabled = !visible
        statusLine.title = sharing.isSharing ? "Screen sharing: connected" : "Screen sharing: not connected"
        toggleItem.title = visible ? "Hide Pointer Now" : "Show Pointer Now"
        for (itemMode, item) in modeItems {
            item.state = itemMode == mode ? .on : .off
        }
    }

    @objc private func toggleNow() {
        manualOverride = !shouldShow
        refresh()
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let newMode = ShowMode(rawValue: raw) else { return }
        mode = newMode
        manualOverride = nil
        refresh()
    }

    private func setUpMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "CursorBeacon")

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Show Pointer", action: nil, keyEquivalent: "")
        for showMode in ShowMode.allCases {
            let modeItem = NSMenuItem(title: showMode.title, action: #selector(chooseMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = showMode.rawValue
            modeItem.indentationLevel = 1
            menu.addItem(modeItem)
            modeItems[showMode] = modeItem
        }
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(toggleItem)
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
