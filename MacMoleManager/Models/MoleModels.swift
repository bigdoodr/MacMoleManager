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

struct MoleStatus: Decodable {
    let diskUsedBytes: Int64?
    let diskFreeBytes: Int64?
    let diskTotalBytes: Int64?
    let cpuUsagePercent: Double?
    let memoryUsagePercent: Double?
    let healthScore: Int?
    let healthScoreMessage: String?

    private struct Disk: Decodable {
        let mount: String?
        let used: Int64?
        let total: Int64?
    }

    private struct CPU: Decodable {
        let usage: Double?
    }

    private struct Memory: Decodable {
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

struct MoleAnalysis: Decodable {
    let path: String?
    let totalSizeBytes: Int64?
    let entries: [MoleAnalysisEntry]?

    private enum CodingKeys: String, CodingKey {
        case path, entries
        case totalSizeBytes = "total_size"
    }
}

struct MoleAnalysisEntry: Decodable, Identifiable {
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

struct MoleAppEntry: Decodable, Identifiable {
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
}

extension Int64 {
    /// Human-readable byte formatting, matching macOS's own Finder-style units.
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
