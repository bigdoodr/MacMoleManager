//
//  InstallerScanner.swift
//  MacStorageManager
//
//  Native replacement for wrapping `mole installer`, which is a genuine
//  interactive raw-terminal UI (arrow-key/space/enter checklist), not a
//  plain-text preview — `Process`+`Pipe` gives it no real terminal to draw
//  into and it hangs forever. Finding stray .dmg/.pkg installers doesn't
//  need mole at all, so this scans and deletes directly via FileManager.
//

import Foundation

struct InstallerLeftover: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let sizeBytes: Int64
    /// Which of the scanned folders this came from, e.g. "Downloads".
    let location: String
}

enum InstallerScanner {

    private static let matchedExtensions: Set<String> = ["dmg", "pkg"]

    private static var searchLocations: [(url: URL, label: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (home.appendingPathComponent("Downloads"), "Downloads"),
            (home.appendingPathComponent("Desktop"), "Desktop"),
            (home.appendingPathComponent("Documents"), "Documents"),
        ]
    }

    /// Synchronous — a top-level directory listing of three folders is fast
    /// enough not to need its own background queue hop.
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

    /// Moves to the Trash rather than deleting outright, so a selection that
    /// turns out to include something still needed is recoverable.
    static func moveToTrash(_ items: [InstallerLeftover]) throws {
        let fm = FileManager.default
        for item in items {
            try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
    }
}
