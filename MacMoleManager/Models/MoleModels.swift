//
//  MoleModels.swift
//  MacStorageManager
//
//  Decodable shapes for `mole`'s --json output, reconciled against real
//  output from `mole status --json`, `mole analyze --json <path>`, and
//  `mole uninstall --list` (all confirmed working as invoked in
//  MoleRunner.swift). Every field stays optional so an unexpected schema
//  drift in a future Mole release shows "—" instead of crashing.
//

import Foundation

// Every Decodable model in this file is explicitly `nonisolated`. The
// project's default-actor-isolation setting (MainActor) otherwise applies
// to plain struct declarations too, and Decodable's `init(from:)`
// requirement is itself a nonisolated protocol requirement — a
// MainActor-isolated conformance can't satisfy it, which is exactly what
// surfaced as "Main actor-isolated conformance of 'MoleStatus' to
// 'Decodable' cannot be used in actor-isolated context" once these types
// got decoded from MoleRunner's actor-isolated methods. These are pure
// data models with no reason to be actor-isolated in the first place, so
// opting the whole type out (rather than patching individual members, as
// done elsewhere in this codebase for methods that must interoperate with
// nonisolated callers) is the cleanest fix here.

nonisolated struct MoleStatus: Decodable {
    let diskUsedBytes: Int64?
    let diskFreeBytes: Int64?
    let diskTotalBytes: Int64?
    let cpuUsagePercent: Double?
    let memoryUsagePercent: Double?
    let healthScore: Int?
    let healthScoreMessage: String?

    private nonisolated struct Disk: Decodable {
        let mount: String?
        let used: Int64?
        let total: Int64?
    }

    private nonisolated struct CPU: Decodable {
        let usage: Double?
    }

    private nonisolated struct Memory: Decodable {
        let usedPercent: Double?

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case disks, cpu, memory
        case healthScore = "health_score"
        case healthScoreMessage = "health_score_msg"
    }

    // `status --json` reports one entry per mounted volume rather than a
    // single disk total, so the primary ("/") volume is picked out here to
    // keep the flat diskUsed/Free/Total properties the rest of the app expects.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let disks = try container.decodeIfPresent([Disk].self, forKey: .disks) ?? []
        let primary = disks.first(where: { $0.mount == "/" }) ?? disks.first

        diskUsedBytes = primary?.used
        diskTotalBytes = primary?.total
        if let used = primary?.used, let total = primary?.total {
            diskFreeBytes = total - used
        } else {
            diskFreeBytes = nil
        }

        cpuUsagePercent = try container.decodeIfPresent(CPU.self, forKey: .cpu)?.usage
        memoryUsagePercent = try container.decodeIfPresent(Memory.self, forKey: .memory)?.usedPercent
        healthScore = try container.decodeIfPresent(Int.self, forKey: .healthScore)
        healthScoreMessage = try container.decodeIfPresent(String.self, forKey: .healthScoreMessage)
    }
}

nonisolated struct MoleAnalysis: Decodable {
    let path: String?
    let totalSizeBytes: Int64?
    let entries: [MoleAnalysisEntry]?

    private enum CodingKeys: String, CodingKey {
        case path, entries
        case totalSizeBytes = "total_size"
    }
}

nonisolated struct MoleAnalysisEntry: Decodable, Identifiable {
    var id: String { path ?? UUID().uuidString }
    let name: String?
    let path: String?
    let sizeBytes: Int64?
    let isDir: Bool?

    var kind: String? {
        guard let isDir else { return nil }
        return isDir ? "Folder" : "File"
    }

    private enum CodingKeys: String, CodingKey {
        case name, path
        case sizeBytes = "size"
        case isDir = "is_dir"
    }
}

nonisolated struct MoleAppEntry: Decodable, Identifiable {
    var id: String { bundleIdentifier ?? name ?? UUID().uuidString }
    let name: String?
    let bundleIdentifier: String?
    /// The exact name `mole uninstall` expects as its argument — not
    /// guaranteed to match `name` (e.g. apps with punctuation in their
    /// display name), so this is what gets passed back into the CLI.
    let uninstallName: String?
    let path: String?
    /// Already a human-readable string (e.g. "7.2MB") straight from Mole,
    /// not raw bytes — `mole uninstall --list` doesn't report a byte count.
    let sizeDisplay: String?

    private enum CodingKeys: String, CodingKey {
        case name, path
        case bundleIdentifier = "bundle_id"
        case uninstallName = "uninstall_name"
        case sizeDisplay = "size"
    }

    /// Parses Mole's formatted string (e.g. "725KB", "7.2MB") back into bytes
    /// so sorting by size is numeric rather than alphabetical — otherwise
    /// "725KB" would sort ahead of "7.2MB". Falls back to 0 for anything
    /// unparseable so a bad entry sinks to the bottom rather than crashing.
    var sizeBytesForSorting: Double {
        guard let sizeDisplay else { return 0 }
        let numberPart = sizeDisplay.prefix { $0.isNumber || $0 == "." }
        let unitPart = sizeDisplay[numberPart.endIndex...].trimmingCharacters(in: .whitespaces).uppercased()
        guard let value = Double(numberPart) else { return 0 }

        switch unitPart {
        case "B", "BYTES": return value
        case "KB": return value * 1_024
        case "MB": return value * 1_024 * 1_024
        case "GB": return value * 1_024 * 1_024 * 1_024
        case "TB": return value * 1_024 * 1_024 * 1_024 * 1_024
        default: return value
        }
    }
}

extension Int64 {
    /// Human-readable byte formatting, matching macOS's own Finder-style units.
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
