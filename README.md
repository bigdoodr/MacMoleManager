# MacMoleManager

A native macOS app that wraps [Mole](https://github.com/tw93/Mole) — the open-source `mole` CLI for cleaning, uninstalling, analyzing, and monitoring a Mac — in a SwiftUI interface.

## Features

- **System Status** — disk, CPU, memory, and Mole's own health score, read live from `mole status --json`.
- **Analyze Disk Usage** — browse folder sizes from any starting path, drilling in and out via `mole analyze --json`.
- **Uninstall an App** — pick an installed app to see its leftover files (caches, preferences, containers, saved state) alongside the app itself; choose which to remove and they all go to the Trash together.
- **Clean My Mac** — dry-run preview of everything Mole's clean pass would delete, then confirm.
- **Optimize** — finds smaller performance issues (stale DNS/Spotlight caches, broken login items, memory-heavy apps worth closing) and previews them before applying.
- **Deep Purge** — a more thorough pass than Clean My Mac, reaching further into logs and developer build artifacts.
- **Installer Cleanup** — finds leftover `.dmg`/`.pkg` installers in Downloads, Desktop, and Documents and lets you pick which to send to the Trash.
- **History** — a log of Mole's past clean/optimize/uninstall/purge runs, plus every individual file that's actually been deleted.
- **Live Stats** — a continuously-refreshing dashboard: per-core CPU, memory, every disk volume, top processes, battery, network, and uptime.
- **Settings** — choose which caches Clean My Mac may never remove and which folders Deep Purge should treat as project directories, editing Mole's own config files directly.
- Installs Mole automatically if it isn't already on the Mac, and updates it in place afterward.

## Requirements

- macOS.
- Full Disk Access granted to MacMoleManager (System Settings → Privacy & Security → Full Disk Access) for complete scan results.

## Building

1. Clone this repo and open `MacMoleManager.xcodeproj` in Xcode.
2. Set your own signing team under Signing & Capabilities.
3. Build and run (⌘R).

For a distributable, fleet-deployable `.pkg` (with Mole pre-installed via a postinstall script, and an optional PPPC profile for zero-prompt Full Disk Access / Finder automation on managed Macs), see [`Packaging/README.md`](Packaging/README.md).

App Sandbox is intentionally off, since MacMoleManager shells out to an external CLI and needs Full Disk Access. This is why the app is distributed outside the Mac App Store, via direct download / your own Developer ID signing.

## How it works

MacMoleManager mostly runs the `mole` binary as a separate process (`status --json`, `analyze --json`, `history --json`, `clean`, `optimize`, `purge`, `uninstall --list`) and renders whatever Mole reports. If Mole isn't installed, it runs Mole's own install script from [mole.fit](https://mole.fit).

A few features aren't wrapped `mole` subcommands, because those commands require real terminal interaction:

- **Uninstall's per-file leftovers** and **Installer Cleanup** scan the filesystem directly (`Services/AppLeftoverScanner.swift`, `Services/InstallerScanner.swift`) instead of parsing `mole uninstall`/`mole installer`, which only print a one-line summary with no per-file listing.
- **Settings** reads and writes Mole's own `~/.config/mole/whitelist` and `~/.config/mole/purge_paths` files directly (`Services/MoleConfigStore.swift`) instead of driving `mole clean --whitelist` or `mole purge --paths`, which are interactive-only.

Either way, the files on disk are the same ones Mole itself reads, so changes made in MacMoleManager, Terminal, and MoleUI all stay in sync.

## Credits & inspiration

- **[Mole](https://github.com/tw93/Mole)** by [tw93](https://github.com/tw93) — the CLI this app is a GUI for.
- **[Privileges](https://github.com/SAP/macOS-enterprise-privileges)** by SAP — the self-service temporary-admin tool this app's admin-access flow drives directly when installed (see `Services/AdminAccess.swift`).
- **[MoleUI](https://github.com/Zhili1004/MoleUI)** — Zhili1004's GUI for Mole, a reference point for how this app groups and presents Mole's results.
- **["Discovering Mole: A Command-Line Utility for Mac Cleaning"](https://jonbrown.org/blog/discovering-mole-a-command-line-utility-for-mac-cleaning/)** by Jon Brown — the writeup that introduced Mole as a tool worth building around.
- **[Dan Snelson's Disk Usage script](https://github.com/dan-snelson/dialog-scripts/tree/main/Disk%20Usage)** — the original bash-based tool this app replaces. See also his writeup, **["Disk Usage with swiftDialog"](https://snelson.us/2022/11/disk-usage-with-swiftdialog-0-0-2/)**.
- **[swiftDialog](https://github.com/swiftDialog/swiftDialog)** by Bart Reardon — the native dialog toolkit that powered Dan's script's UI, whose **[Preset 6 (Inspect Mode "Guidance")](https://swiftdialog.app/advanced/inspect/preset6/)** shaped this app's navigable-results UI pattern.

## License

MacMoleManager is licensed under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)), matching [Mole](https://github.com/tw93/Mole/blob/main/LICENSE)'s license.

Mole itself is not bundled with this app — MacMoleManager invokes whatever `mole` binary is already installed on your Mac as a separate process and does not link against Mole's source code.
