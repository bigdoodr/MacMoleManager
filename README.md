# MacMoleManager

A native macOS app that wraps [Mole](https://github.com/tw93/Mole) — the open-source `mole` CLI for cleaning, uninstalling, analyzing, and monitoring a Mac — in a SwiftUI interface. Built for admins who want Mole's functionality without dropping to Terminal, and originally developed to replace a swiftDialog-based shell script for exactly that purpose.

## Features

- **System Status** — disk, CPU, memory, and Mole's own health score, read live from `mole status --json`.
- **Analyze Disk Usage** — browse folder sizes from any starting path, drilling in and out via `mole analyze --json`.
- **Uninstall an App** — pick an installed app to see its leftover files — caches, preferences, containers, saved state — found natively alongside the app itself; choose which to remove and they all go to the Trash together.
- **Clean My Mac** — dry-run preview of everything Mole's clean pass would delete, then confirm.
- **Optimize** — finds smaller performance issues (stale DNS/Spotlight caches, broken login items, memory-heavy apps worth closing) and previews them before applying.
- **Deep Purge** — a more thorough pass than Clean My Mac, reaching further into logs and developer build artifacts.
- **Installer Cleanup** — finds leftover `.dmg`/`.pkg` installers in Downloads, Desktop, and Documents and lets you pick which to send to the Trash.
- **History** — a log of Mole's past clean/optimize/uninstall/purge runs, plus every individual file that's actually been deleted.
- **Live Stats** — a continuously-refreshing dashboard: per-core CPU, memory (used/available/cached/swap), every disk volume, top processes, battery, network, and uptime.
- **Settings** — choose which caches Clean My Mac may never remove (Mole's own ~70-item whitelist catalog, plus anything custom) and which folders Deep Purge should treat as project directories — edits Mole's own config files directly, since both of Mole's own equivalents (`mole clean --whitelist`, `mole purge --paths`) turn out to be interactive-only commands with no scriptable equivalent.
- Installs Mole automatically if it isn't already on the Mac (runs Mole's own official install script), and updates it in place afterward, whether it ended up installed via that installer or via Homebrew.

## Requirements

- macOS. [Mole](https://github.com/tw93/Mole) itself is **not** a prerequisite — if MacMoleManager doesn't find it already installed, it shows a banner offering to install it for you, running Mole's own official install script. See [How it works](#how-it-works).
- Xcode 16 or later to build from source.
- Full Disk Access granted to MacMoleManager (System Settings → Privacy & Security → Full Disk Access) for complete scan results.

## Building

1. Clone this repo and open `MacMoleManager.xcodeproj` in Xcode.
2. Set your own signing team under Signing & Capabilities.
3. Build and run (⌘R).

App Sandbox is intentionally off — MacMoleManager shells out to an external CLI and needs broad filesystem access under Full Disk Access, which isn't compatible with the sandbox's container model. This is why the app is distributed outside the Mac App Store, via direct download / your own Developer ID signing.

## How it works

For most features, MacMoleManager doesn't reimplement any of Mole's scanning, cleaning, or analysis logic — it runs the `mole` binary as a separate process (`status --json`, `analyze --json`, `history --json`, `clean`, `optimize`, `purge`, `uninstall --list`) and renders whatever Mole reports. All of that real work — deciding what's safe to clean, what a stale cache looks like, how to size a directory tree — is Mole's.

If Mole isn't installed yet, MacMoleManager runs Mole's own install script (the same one at [mole.fit](https://mole.fit)) rather than vendoring a copy, so it stays on Mole's own release cadence going forward.

A handful of features are deliberately **not** wrapped `mole` subcommands, because the interactive command they'd otherwise map to turned out (confirmed live) to need a real terminal MacMoleManager can't give it — a raw-terminal checklist UI, or dropping straight into `vim` — rather than a plain preview it could capture:

- **Uninstall's per-file leftovers** and **Installer Cleanup** scan the filesystem directly (`Services/AppLeftoverScanner.swift`, `Services/InstallerScanner.swift`) instead of parsing `mole uninstall`/`mole installer`, which only ever print a one-line summary with no way to list individual files.
- **Settings** reads and writes Mole's own `~/.config/mole/whitelist` and `~/.config/mole/purge_paths` config files directly (`Services/MoleConfigStore.swift`), instead of driving `mole clean --whitelist` or `mole purge --paths`, both of which launch a genuinely interactive experience with no `--help`-respecting scriptable form.

Either way, the files on disk are the same ones Mole itself reads, so changes made in MacMoleManager, Terminal, and MoleUI all stay in sync.

## Credits & inspiration

This app exists because of work other people in the Mac admin community did first:

- **[Mole](https://github.com/tw93/Mole)** by [tw93](https://github.com/tw93) — the CLI this app is a GUI for. All cleaning, analysis, and uninstall logic belongs to that project.
- **[MoleUI](https://github.com/tw93/Mole)** — tw93's own GUI for Mole, a reference point for how this app groups and presents Mole's results (the tile layout in System Status/Live Stats, the collapsible sections in Clean/Optimize).
- **["Discovering Mole: A Command-Line Utility for Mac Cleaning"](https://jonbrown.org/blog/discovering-mole-a-command-line-utility-for-mac-cleaning/)** by Jon Brown — the writeup that introduced Mole as a tool worth building around.
- **[Dan's Disk Management script](https://github.com/dan-snelson/dialog-scripts/tree/main/Disk%20Usage)** by Dan K. Snelson — the original bash-based tool for WKU's fleet that MacMoleManager grew out of and replaces. See also his writeup, **["Disk Usage with swiftDialog"](https://snelson.us/2022/11/disk-usage-with-swiftdialog-0-0-2/)**.
- **[swiftDialog](https://github.com/swiftDialog/swiftDialog)** by Bart Reardon — the native dialog toolkit that powered Dan's script's UI. Its **[Preset 6 (Inspect Mode "Guidance")](https://swiftdialog.app/advanced/inspect/preset6/)** documentation shaped the UI pattern (a navigable results screen instead of a single static dialog) this app's views are organized around, even though the final implementation moved to native SwiftUI instead of swiftDialog.

## License

MacMoleManager is licensed under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)), matching the license of [Mole](https://github.com/tw93/Mole/blob/main/LICENSE) that it wraps.

Mole itself is not bundled with this app — MacMoleManager invokes whatever `mole` binary is already installed on your Mac as a separate process, and does not include or link against any of Mole's source code. Mole remains fully owned and licensed by its own authors under GPLv3; this app is simply a GUI client for it, licensed the same way as a courtesy and to keep everything downstream unambiguous.
