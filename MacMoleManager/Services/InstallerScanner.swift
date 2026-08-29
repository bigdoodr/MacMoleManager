//
//  InstallerScanner.swift
//  MacStorageManager
//
//  Native replacement for wrapping `mole installer`. That subcommand turned
//  out (confirmed live) to be a genuine interactive raw-terminal UI — an
//  arrow-key/space/enter checklist, the same category of program as `nano`
//  or `htop` — not a plain-text preview like clean/optimize/purge. A GUI
//  app's `Process`+`Pipe` gives a child no real terminal to draw into, so
//  it just hangs forever waiting for terminal control it will never get;
//  see the doc comment above the (now-removed) installer methods in
//  MoleRunner.swift for the fuller story.
//
//  Since the actual task — find stray .dmg/.pkg installers in the usual
//  drop spots and let the user delete the ones they don't need — doesn't
//  require mole at all, this scans and deletes directly via FileManager.
//  Simpler, fully reliable, and no terminal emulation required.
//

import Foundation

struct InstallerLeftover: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let sizeBytes: Int64
    /// Which of the scanned folders this came from, e.g. "Downloads" —
    /// shown in the UI so a match under Desktop/Documents (which may be
    /// iCloud-synced, per Casey's Mac) doesn't look like a mystery path.
    let location: String
}

enum InstallerScanner {

    /// Leftover installer artifacts, by extension — matches the two file
    /// types MoleUI's own installer picker flagged live (.dmg and .pkg).
    private static let matchedExtensions: Set<String> = ["dmg", "pkg"]

    private static var searchLocations: [(url: URL, label: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (home.appendingPathComponent("Downloads"), "Downloads"),
            (home.appendingPathComponent("Desktop"), "Desktop"),
            (home.appendingPathComponent("Documents"), "Documents"),
        ]
    }

    /// Synchronous — a top-level (non-recursive) directory listing of three
    /// folders is fast enough not to need its own background queue hop;
    /// callers already run this off the main actor via AppViewModel's
    /// `runTask`, which itself just awaits this call from a `Task`.
    static func scan() -> [InstallerLeftover] {
        let fm = FileManager.default
        var results: [InstallerLeftover] = []

        for (directory, label) in searchLocations {
            guard let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where matchedExtensions.contains(url.pathExtension.lowercased()) {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let size = Int64(values?.fileSize ?? 0)
                results.append(InstallerLeftover(name: url.lastPathComponent, path: url.path, sizeBytes: size, location: label))
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Moves the given items to the Trash rather than deleting outright —
    /// recoverable if a selection turns out to include something still
    /// needed, at the cost of nothing (the app already has Full Disk Access
    /// and an unsandboxed entitlements file, so this needs no extra
    /// permission dance).
    static func moveToTrash(_ items: [InstallerLeftover]) throws {
        let fm = FileManager.default
        for item in items {
            try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
    }
}
