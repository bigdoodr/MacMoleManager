//
//  MoleConfigStore.swift
//  MacStorageManager
//
//  Native reader/writer for Mole's own on-disk config files — no `mole`
//  subprocess involved. `mole clean --whitelist` and `mole purge --paths` are
//  both interactive-only (a raw-terminal checklist, and dropping into vim,
//  respectively — the same limitation as `mole installer`, see
//  InstallerScanner.swift), so Settings edits these files directly instead.
//
//  File formats/header text match Mole's own source — lib/manage/whitelist.sh,
//  lib/core/base.sh, bin/clean.sh, commit 650ec4202343542e86b09c451a75bd6c171b5b6e
//  on tw93/Mole.
//

import Foundation

enum MoleConfigStore {

    private static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mole", isDirectory: true)
    }

    private static var whitelistFile: URL { configDirectory.appendingPathComponent("whitelist") }
    private static var purgePathsFile: URL { configDirectory.appendingPathComponent("purge_paths") }

    // MARK: - Whitelist

    /// Mole's own sentinel token for "protect Finder metadata (.DS_Store)" —
    /// not a real path, just a literal string Mole special-cases throughout
    /// lib/core/base.sh and lib/manage/whitelist.sh:
    /// `readonly FINDER_METADATA_SENTINEL="FINDER_METADATA"`.
    static let finderMetadataSentinel = "FINDER_METADATA"

    /// Raw pattern lines from `~/.config/mole/whitelist` — comment (#) and
    /// blank lines skipped, same as `load_mole_whitelist` (lib/core/base.sh).
    /// Empty if the file doesn't exist yet; MoleWhitelistCatalog.defaultPatterns
    /// mirrors Mole's own built-in fallback for that case.
    static func loadWhitelistPatterns() -> [String] {
        loadPatternLines(from: whitelistFile)
    }

    /// Replaces the file's whole pattern list, matching Mole's own
    /// `save_whitelist_patterns` header text and replacement semantics.
    static func saveWhitelistPatterns(_ patterns: [String]) throws {
        let header = """
        # Mole Whitelist - Protected paths won't be deleted
        # Default protections: Playwright browsers, Ollama models, Surge Mac, R renv, Finder metadata
        # Add one pattern per line to keep items safe.
        """
        try savePatternLines(patterns, header: header, to: whitelistFile)
    }

    // MARK: - Purge Paths

    /// `~/.config/mole/purge_paths` — one filesystem path per line, supporting
    /// `~` for home. Left un-expanded (unlike whitelist patterns) so a
    /// round-trip edit stays `~/...` rather than a fully-qualified path.
    static func loadPurgePaths() -> [String] {
        loadPatternLines(from: purgePathsFile)
    }

    static func savePurgePaths(_ paths: [String]) throws {
        let header = """
        # Mole Purge Paths - Auto-discovered project directories
        # Edit this file to customize, or run: mo purge --paths
        # Add one path per line (supports ~ for home directory)
        """
        try savePatternLines(paths, header: header, to: purgePathsFile)
    }

    // MARK: - Shared file I/O

    private static func loadPatternLines(from url: URL) -> [String] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func savePatternLines(_ lines: [String], header: String, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        var content = header + "\n"
        if !lines.isEmpty {
            content += "\n" + lines.joined(separator: "\n") + "\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
