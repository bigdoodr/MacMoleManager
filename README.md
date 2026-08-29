# MacMoleManager

A native macOS app that wraps [Mole](https://github.com/tw93/Mole) — the open-source `mole` CLI for cleaning, uninstalling, analyzing, and monitoring a Mac — in a SwiftUI interface. Built for admins who want Mole's functionality without dropping to Terminal, and originally developed to replace a swiftDialog-based shell script for exactly that purpose.

## Features

- **System Status** — disk, CPU, memory, and Mole's own health score, read live from `mole status --json`.
- **Analyze Disk Usage** — browse folder sizes from any starting path, drilling in and out via `mole analyze --json`.
- **Uninstall an App** — pick an installed app, preview exactly what Mole would remove, then confirm.
- **Clean My Mac** — dry-run preview of everything Mole's clean pass would delete, then confirm.
- Update Mole itself in place, whether it was installed via Mole's own installer or via Homebrew.

## Requirements

- macOS with [Mole](https://github.com/tw93/Mole) installed (`/usr/local/bin/mole` or a Homebrew install under `/opt/homebrew` or `/usr/local`).
- Xcode 16 or later to build from source.
- Full Disk Access granted to MacMoleManager (System Settings → Privacy & Security → Full Disk Access) for complete scan results.

## Building

1. Clone this repo and open `MacMoleManager.xcodeproj` in Xcode.
2. Set your own signing team under Signing & Capabilities.
3. Build and run (⌘R).

App Sandbox is intentionally off — MacMoleManager shells out to an external CLI and needs broad filesystem access under Full Disk Access, which isn't compatible with the sandbox's container model. This is why the app is distributed outside the Mac App Store, via direct download / your own Developer ID signing.

## How it works

MacMoleManager doesn't reimplement any of Mole's scanning, cleaning, or analysis logic. It runs the `mole` binary as a separate process for every action (`status --json`, `analyze --json`, `clean`, `uninstall`) and renders whatever Mole reports. All the real work — deciding what's safe to clean, what a stale cache looks like, how to size a directory tree — is Mole's.

## Credits & inspiration

This app exists because of work other people in the Mac admin community did first:

- **[Mole](https://github.com/tw93/Mole)** by [tw93](https://github.com/tw93) — the CLI this app is a GUI for. All cleaning, analysis, and uninstall logic belongs to that project.
- **["Discovering Mole: A Command-Line Utility for Mac Cleaning"](https://jonbrown.org/blog/discovering-mole-a-command-line-utility-for-mac-cleaning/)** by Jon Brown — the writeup that introduced Mole as a tool worth building around.
- **["Disk Usage with swiftDialog"](https://snelson.us/2022/11/disk-usage-with-swiftdialog-0-0-2/)** by Dan K. Snelson — the swiftDialog-based disk usage concept this project's predecessor script was originally modeled on.
- **[swiftDialog's Preset 6 (Inspect Mode "Guidance")](https://swiftdialog.app/advanced/inspect/preset6/)** documentation — the UI pattern (a navigable results screen instead of a single static dialog) that shaped how this app's Status/Analyze/Uninstall/Clean views are organized, even though the final implementation moved to native SwiftUI instead of swiftDialog.

## License

MacMoleManager is licensed under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)), matching the license of [Mole](https://github.com/tw93/Mole/blob/main/LICENSE) that it wraps.

Mole itself is not bundled with this app — MacMoleManager invokes whatever `mole` binary is already installed on your Mac as a separate process, and does not include or link against any of Mole's source code. Mole remains fully owned and licensed by its own authors under GPLv3; this app is simply a GUI client for it, licensed the same way as a courtesy and to keep everything downstream unambiguous.
