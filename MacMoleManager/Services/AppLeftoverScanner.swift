//
//  AppLeftoverScanner.swift
//  MacStorageManager
//
//  AppCleaner-style per-file uninstall breakdown. `mole uninstall` only ever
//  prints a one-line summary with no per-file listing, so this scans the
//  standard macOS leftover locations itself, matched primarily by bundle
//  identifier and falling back to a substring match on the app's full display
//  name. Matching the full name (not a single vendor word) is deliberate —
//  it keeps "Microsoft Outlook" from also flagging a shared "Microsoft"
//  folder that Word/Excel/Teams live in; under-matching is a safer failure
//  mode here than trashing another app's data.
//
//  Deletion goes straight to FileManager.trashItem, no mole subcommand involved.
//

import Foundation

struct AppLeftoverItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let sizeBytes: Int64
    let category: String
}

enum AppLeftoverScanner {
    private static var searchLocations: [(url: URL, category: String)] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return [
            (library.appendingPathComponent("Application Support"), "Application Support"),
            (library.appendingPathComponent("Caches"), "Caches"),
            (library.appendingPathComponent("Preferences"), "Preferences"),
            (library.appendingPathComponent("Containers"), "Containers"),
            (library.appendingPathComponent("Group Containers"), "Group Containers"),
            (library.appendingPathComponent("Saved Application State"), "Saved Application State"),
            (library.appendingPathComponent("Logs"), "Logs"),
            (library.appendingPathComponent("WebKit"), "WebKit"),
            (library.appendingPathComponent("HTTPStorages"), "HTTP Storage"),
        ]
    }

    /// - Parameters:
    ///   - appName: Display name (e.g. "Microsoft Outlook") — used as the
    ///     fallback name-substring match.
    ///   - bundleIdentifier: e.g. "com.microsoft.Outlook" — used as the
    ///     primary match, since most of these folders are named after it.
    ///   - appPath: Path to the .app bundle itself, if still known (it may
    ///     already be gone if this is a re-scan after a partial cleanup).
    static func scan(appName: String, bundleIdentifier: String?, appPath: String?) -> [AppLeftoverItem] {
        let fm = FileManager.default
        var results: [AppLeftoverItem] = []

        if let appPath, fm.fileExists(atPath: appPath) {
            results.append(AppLeftoverItem(
                name: URL(fileURLWithPath: appPath).lastPathComponent,
                path: appPath,
                sizeBytes: sizeOf(appPath),
                category: "Application"
            ))
        }

        let trimmedName = appName.trimmingCharacters(in: .whitespaces)

        for (directory, category) in searchLocations {
            guard let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                let filename = url.lastPathComponent
                let matchesBundleID = bundleIdentifier.map { !$0.isEmpty && filename.localizedCaseInsensitiveContains($0) } ?? false
                let matchesName = !trimmedName.isEmpty && filename.localizedCaseInsensitiveContains(trimmedName)
                guard matchesBundleID || matchesName else { continue }

                results.append(AppLeftoverItem(
                    name: filename,
                    path: url.path,
                    sizeBytes: sizeOf(url.path),
                    category: category
                ))
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Leftover folders (caches, containers) can nest many levels deep, so
    /// this walks the whole tree rather than trusting a single
    /// `.fileSizeKey` read — that key only ever reports non-zero for plain
    /// files, never for a directory itself.
    private static func sizeOf(_ path: String) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let attributes = try? fm.attributesOfItem(atPath: path)
            return Int64((attributes?[.size] as? UInt64) ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func moveToTrash(_ items: [AppLeftoverItem]) throws {
        let fm = FileManager.default
        for item in items {
            try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
    }
}
