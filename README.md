# CursorBeacon

A tiny macOS helper that draws a big, bright pointer on top of your screen and keeps it on the mouse.

Some VNC and screen-sharing setups don't show the Mac's cursor, so on a phone or tablet you can't tell where you're pointing. CursorBeacon draws the pointer into the screen image itself, so every viewer sees it: RealVNC, Screens, Jump Desktop, TigerVNC, Zoom, or a screen recording.

- No permissions needed
- Clicks pass straight through it
- Shows up only while someone is screen sharing, so you don't see two pointers at the Mac
- Works across all Spaces, full-screen apps and multiple displays
- No Dock icon, just a small menu bar item
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

## Options

```sh
CursorBeacon --size 56 --color red
CursorBeacon --color "#00E5FF" --show always
```

| Option    | Default | Notes                                                   |
|-----------|---------|---------------------------------------------------------|
| `--size`  | 40      | 12 to 200 points                                        |
| `--color` | yellow  | yellow, red, green, blue, pink, orange, white, or hex   |
| `--show`  | sharing | `sharing`, `always` or `off` (see below)                |
| `--debug` | off     | Prints how many milliseconds each mouse move takes      |

## When the pointer shows

By default the pointer appears only while someone is connected with macOS Screen Sharing or a VNC server that accepts direct connections on port 5900 (like RealVNC Server). It hides again when they disconnect. Change this from the menu bar under **Show Pointer**: Always, Only While Screen Sharing, or Off.

Press **Control-Option-Command-B** anywhere to show or hide the pointer right away. That lasts until you change the mode or a sharing session starts or ends.

Connections relayed through a cloud service (for example RealVNC's cloud connectivity) don't use port 5900 and aren't detected. Use **Always** or the shortcut for those.

## Start at login

Copy the binary somewhere stable:

```sh
sudo cp .build/release/CursorBeacon /usr/local/bin/
```

Create `~/Library/LaunchAgents/me.malikrasaq.cursorbeacon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>me.malikrasaq.cursorbeacon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/CursorBeacon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Load it:

```sh
launchctl load ~/Library/LaunchAgents/me.malikrasaq.cursorbeacon.plist
```

To stop it for good, run `launchctl unload` on the same file.

## How it works

Each screen gets a transparent window that sits above everything and ignores mouse events. The arrow is drawn once, then moved inside that window on every mouse event, with a check on each display refresh to catch moves that don't send events. Since it's a normal window, it's part of the captured screen, unlike the real cursor, which some VNC setups leave out.

## Limitations

- While someone is connected you'll see two pointers at the Mac itself.
- CursorBeacon itself adds only a few milliseconds (check with `--debug`). Most visible lag on a phone comes from the VNC stream; lowering the viewer's picture quality helps.
- The pointer is always an arrow; it doesn't change to a text beam or hand.

## License

MIT
