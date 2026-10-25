# Changelog

## 0.1.0

First release. CursorBeacon draws a big, bright pointer that shows up in VNC and screen-sharing streams that hide the Mac's cursor.

- **Download and run.** `CursorBeacon.app` runs natively on both Apple Silicon and Intel Macs, macOS 12 or later.
- **Low lag.** The pointer reacts to every mouse event within a few milliseconds (check with `--debug`) and appears on the next screen refresh, at any refresh rate.
- **Shows up only while screen sharing.** By default the pointer appears when someone connects with macOS Screen Sharing or a VNC server on port 5900, and hides when they leave, so you don't see two pointers while using the Mac yourself.
- **Show/hide shortcut.** Press Control-Option-Command-B anywhere.
- **Matches the cursor shape.** Text beam, pointing hand, grab hands, crosshair, not-allowed and resize arrows, all in your chosen color.
- **Click rings.** A ring flashes on every click (two for a right click), so viewers can see where you clicked.
- **Hide When Idle.** Optionally fades the pointer out after 3 seconds without mouse activity.
- **Menu bar settings.** Size, color, when to show, shape matching, click rings, hide when idle, and launch at login. All of them are remembered.
- **Launch at Login** from the menu, with no manual setup.
- **Works everywhere.** All Spaces, full-screen apps and multiple displays, including screens added or removed while it runs.
- **No permissions needed**, and clicks pass straight through the pointer.
- Command-line options: `--size`, `--color`, `--show`, `--no-shapes`, `--no-clicks`, `--hide-when-idle`, `--debug`, `--version`.
