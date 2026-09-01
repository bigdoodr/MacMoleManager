//
//  MoleConfigStore.swift
//  MacStorageManager
//
//  Native reader/writer for Mole's own on-disk config files — no `mole`
//  subprocess involved. `mole clean --whitelist` and `mole purge --paths`
//  both turned out (confirmed live) to be genuine interactive-only
//  experiences — a raw-terminal checklist, and dropping straight into vim,
//  respectively — the same category of limitation as `mole installer` (see
//  InstallerScanner.swift's doc comment for that story). Settings edits
//  these two files directly instead of trying to drive either interactive
//  command through Process/Pipe.
//
//  File formats and header text below are confirmed against Casey's real
//  ~/.config/mole/whitelist and ~/.config/mole/purge_paths samples, and
//  against Mole's own source — lib/manage/whitelist.sh, lib/core/base.sh,
//  bin/clean.sh, at commit 650ec4202343542e86b09c451a75bd6c171b5b6e on
//  tw93/Mole — not guessed.
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
    /// blank lines skipped, the same parsing Mole's own `load_mole_whitelist`
    /// (lib/core/base.sh) does. Empty if the file doesn't exist yet — Mole
    /// falls back to its own built-in defaults in that case, mirrored here
    /// by MoleWhitelistCatalog.defaultPatterns.
    static func loadWhitelistPatterns() -> [String] {
        loadPatternLines(from: whitelistFile)
    }

    /// Writes the whitelist file with the exact header text Mole's own
    /// `save_whitelist_patterns` (lib/manage/whitelist.sh) writes for clean
    /// mode, so a file MMM saves reads identically to one Mole's own
    /// interactive manager would have produced. Replaces the file's whole
    /// pattern list — matches Mole's own "replacement semantics," not an
    /// append.
    static func saveWhitelistPatterns(_ patterns: [String]) throws {
        let header = """
        # Mole Whitelist - Protected paths won't be deleted
        # Default protections: Playwright browsers, Ollama models, Surge Mac, R renv, Finder metadata
        # Add one pattern per line to keep items safe.
        """
        try savePatternLines(patterns, header: header, to: whitelistFile)
    }

    // MARK: - Purge Paths

    /// `~/.config/mole/purge_paths` — one filesystem path per line,
    /// supporting `~` for the home directory. Left un-expanded here (unlike
    /// whitelist patterns) so a round-trip edit looks exactly like Casey's
    /// real sample did (`~/Library/CloudStorage`), not a fully-qualified path.
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
