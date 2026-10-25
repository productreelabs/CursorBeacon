# CursorBeacon

A tiny macOS helper that draws a big, bright pointer on top of your screen and keeps it on the mouse.

Some VNC and screen-sharing setups don't show the Mac's cursor, so on a phone or tablet you can't tell where you're pointing. CursorBeacon draws the pointer into the screen image itself, so every viewer sees it: RealVNC, Screens, Jump Desktop, TigerVNC, Zoom, or a screen recording.

- No permissions needed
- Clicks pass straight through it
- Changes shape with the real cursor: arrow, text beam, pointing hand, grab hands, crosshair, not-allowed, and resize arrows
- Flashes a ring on every click (two rings for a right click), so viewers see where you clicked
- Shows up only while someone is screen sharing, so you don't see two pointers at the Mac
- Works across all Spaces, full-screen apps and multiple displays
- No Dock icon, just a menu bar item for size, color, when to show, and launch at login
- One Swift file, no dependencies

## Requirements

macOS 12 or later and the Xcode command line tools:

```sh
xcode-select --install
```

## Build and run

```sh
git clone https://github.com/logicberry/CursorBeacon.git
cd CursorBeacon
swift build -c release
.build/release/CursorBeacon
```

Or without SwiftPM:

```sh
swiftc Sources/CursorBeacon/main.swift -o CursorBeacon
./CursorBeacon
```

## Menu bar

Click the pointer icon in the menu bar to change:

- **Show Pointer**: Always, Only While Screen Sharing, or Off
- **Size**: Small, Medium, Large or Huge
- **Color**
- **Match Cursor Shape**: turn off to always draw the arrow
- **Show Clicks**: the ring on each click (on by default)
- **Hide When Idle**: fade the pointer out after 3 seconds without mouse activity; it comes back as soon as you move or click (off by default)
- **Launch at Login**

Your choices are remembered between launches.

## Options

The same settings can be given on the command line. Options apply to that run only and win over the menu choices.

```sh
CursorBeacon --size 56 --color red
CursorBeacon --color "#00E5FF" --show always
```

| Option    | Default | Notes                                                   |
|-----------|---------|---------------------------------------------------------|
| `--size`  | 40      | 12 to 200 points                                        |
| `--color` | yellow  | yellow, red, green, blue, pink, orange, white, or hex   |
| `--show`  | sharing | `sharing`, `always` or `off` (see below)                |
| `--no-shapes` | off | Always draw the arrow instead of matching the cursor shape |
| `--no-clicks` | off | Don't show a ring on clicks |
| `--hide-when-idle` | off | Fade the pointer out after 3 seconds without mouse activity |
| `--debug` | off     | Prints how many milliseconds each mouse move takes      |

## When the pointer shows

By default the pointer appears only while someone is connected with macOS Screen Sharing or a VNC server that accepts direct connections on port 5900 (like RealVNC Server). It hides again when they disconnect. Change this from the menu bar under **Show Pointer**: Always, Only While Screen Sharing, or Off.

Press **Control-Option-Command-B** anywhere to show or hide the pointer right away. That lasts until you change the mode or a sharing session starts or ends.

Connections relayed through a cloud service (for example RealVNC's cloud connectivity) don't use port 5900 and aren't detected. Use **Always** or the shortcut for those.

## Start at login

Turn on **Launch at Login** in the menu. CursorBeacon adds a small login item at `~/Library/LaunchAgents/me.malikrasaq.cursorbeacon.plist` that starts the copy you turned it on from. If you move or rebuild CursorBeacon, launching the new copy once updates it. Turn the option off to remove it.

## How it works

Each screen gets a transparent window that sits above everything and ignores mouse events. Each shape is drawn once, then moved inside that window on every mouse event, with a check on each display refresh to catch moves that don't send events. Whenever the mouse pauses, it compares the real cursor's silhouette with the standard macOS cursors to pick the matching shape. Since it's a normal window, it's part of the captured screen, unlike the real cursor, which some VNC setups leave out.

## Limitations

- While someone is connected you'll see two pointers at the Mac itself.
- CursorBeacon itself adds only a few milliseconds (check with `--debug`). Most visible lag on a phone comes from the VNC stream; lowering the viewer's picture quality helps.
- Custom cursors that apps draw themselves (for example a paint brush) show as the arrow. The shape switches when the mouse pauses, not while it is moving.

## License

MIT
