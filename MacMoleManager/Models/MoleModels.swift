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
    // Flat properties System Status has always used — untouched by the
    // richer fields added below for Live Stats, so that tab keeps working
    // exactly as before.
    let diskUsedBytes: Int64?
    let diskFreeBytes: Int64?
    let diskTotalBytes: Int64?
    let cpuUsagePercent: Double?
    let memoryUsagePercent: Double?
    let healthScore: Int?
    let healthScoreMessage: String?

    // Everything below is reconciled against a real `mole status --json`
    // sample (confirmed live, including a real per-core CPU array, a
    // populated `top_processes`/`batteries`/`network`, and two CoreSimulator
    // volumes) for Live Stats.
    let hostModel: String?
    let cpuModel: String?
    let osVersion: String?
    let uptimeDisplay: String?
    let processCount: Int?
    let cpuPerCore: [Double]?
    let cpuCoreCount: Int?
    let cpuPerformanceCoreCount: Int?
    let cpuEfficiencyCoreCount: Int?
    let load1: Double?
    let load5: Double?
    let load15: Double?
    let memoryUsedBytes: Int64?
    let memoryTotalBytes: Int64?
    let memoryAvailableBytes: Int64?
    let memoryCachedBytes: Int64?
    let swapUsedBytes: Int64?
    let swapTotalBytes: Int64?
    let allDisks: [MoleDiskVolume]
    let topProcesses: [MoleTopProcess]
    let batteries: [MoleBattery]
    let networkInterfaces: [MoleNetworkInterface]

    private nonisolated struct Hardware: Decodable {
        let model: String?
        let cpuModel: String?
        let osVersion: String?

        private enum CodingKeys: String, CodingKey {
            case model
            case cpuModel = "cpu_model"
            case osVersion = "os_version"
        }
    }

    private nonisolated struct CPU: Decodable {
        let usage: Double?
        let perCore: [Double]?
        let coreCount: Int?
        let pCoreCount: Int?
        let eCoreCount: Int?
        let load1: Double?
        let load5: Double?
        let load15: Double?

        private enum CodingKeys: String, CodingKey {
            case usage, load1, load5, load15
            case perCore = "per_core"
            case coreCount = "core_count"
            case pCoreCount = "p_core_count"
            case eCoreCount = "e_core_count"
        }
    }

    private nonisolated struct Memory: Decodable {
        let used: Int64?
        let total: Int64?
        let available: Int64?
        let usedPercent: Double?
        let swapUsed: Int64?
        let swapTotal: Int64?
        let cached: Int64?

        private enum CodingKeys: String, CodingKey {
            case used, total, available, cached
            case usedPercent = "used_percent"
            case swapUsed = "swap_used"
            case swapTotal = "swap_total"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case disks, cpu, memory, hardware, uptime, batteries, network
        case healthScore = "health_score"
        case healthScoreMessage = "health_score_msg"
        case topProcesses = "top_processes"
        case processCount = "procs"
    }

    // `status --json` reports one entry per mounted volume rather than a
    // single disk total, so the primary ("/") volume is picked out here to
    // keep the flat diskUsed/Free/Total properties the rest of the app expects.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let disks = try container.decodeIfPresent([MoleDiskVolume].self, forKey: .disks) ?? []
        let primary = disks.first(where: { $0.mount == "/" }) ?? disks.first

        diskUsedBytes = primary?.usedBytes
        diskTotalBytes = primary?.totalBytes
        if let used = primary?.usedBytes, let total = primary?.totalBytes {
            diskFreeBytes = total - used
        } else {
            diskFreeBytes = nil
        }
        allDisks = disks

        let cpu = try container.decodeIfPresent(CPU.self, forKey: .cpu)
        cpuUsagePercent = cpu?.usage
        cpuPerCore = cpu?.perCore
        cpuCoreCount = cpu?.coreCount
        cpuPerformanceCoreCount = cpu?.pCoreCount
        cpuEfficiencyCoreCount = cpu?.eCoreCount
        load1 = cpu?.load1
        load5 = cpu?.load5
        load15 = cpu?.load15

        let memory = try container.decodeIfPresent(Memory.self, forKey: .memory)
        memoryUsagePercent = memory?.usedPercent
        memoryUsedBytes = memory?.used
        memoryTotalBytes = memory?.total
        memoryAvailableBytes = memory?.available
        memoryCachedBytes = memory?.cached
        swapUsedBytes = memory?.swapUsed
        swapTotalBytes = memory?.swapTotal

        let hardware = try container.decodeIfPresent(Hardware.self, forKey: .hardware)
        hostModel = hardware?.model
        cpuModel = hardware?.cpuModel
        osVersion = hardware?.osVersion

        uptimeDisplay = try container.decodeIfPresent(String.self, forKey: .uptime)
        processCount = try container.decodeIfPresent(Int.self, forKey: .processCount)
        healthScore = try container.decodeIfPresent(Int.self, forKey: .healthScore)
        healthScoreMessage = try container.decodeIfPresent(String.self, forKey: .healthScoreMessage)
        topProcesses = try container.decodeIfPresent([MoleTopProcess].self, forKey: .topProcesses) ?? []
        batteries = try container.decodeIfPresent([MoleBattery].self, forKey: .batteries) ?? []
        networkInterfaces = try container.decodeIfPresent([MoleNetworkInterface].self, forKey: .network) ?? []
    }

    /// Non-CoreSimulator disks only, in the order Mole reported them — what
    /// Live Stats actually lists. See MoleDiskVolume.isCoreSimulatorVolume
    /// for why this can't just filter on the `external` flag.
    var displayDisks: [MoleDiskVolume] {
        allDisks.filter { !$0.isCoreSimulatorVolume }
    }

    /// Mole reports one rate per network interface (en0, en4, …) with no
    /// combined figure — Live Stats shows one Down/Up pair the same way
    /// Terminal Mole's own dashboard does, so these sum across interfaces.
    var totalDownMBs: Double { networkInterfaces.reduce(0) { $0 + ($1.rxRateMBs ?? 0) } }
    var totalUpMBs: Double { networkInterfaces.reduce(0) { $0 + ($1.txRateMBs ?? 0) } }
}

nonisolated struct MoleDiskVolume: Decodable, Identifiable {
    var id: String { mount ?? UUID().uuidString }
    let mount: String?
    let usedBytes: Int64?
    let totalBytes: Int64?
    let usedPercent: Double?
    let isExternal: Bool?

    private enum CodingKeys: String, CodingKey {
        case mount
        case usedBytes = "used"
        case totalBytes = "total"
        case usedPercent = "used_percent"
        case isExternal = "external"
    }

    /// Mole flags Xcode's CoreSimulator disk images as `external: true` too
    /// — they're mounted the same way a real external drive is — so the
    /// `external` field alone can't tell "genuinely plugged in" apart from
    /// "Xcode simulator volume." Path-matching is the only reliable signal.
    var isCoreSimulatorVolume: Bool {
        mount?.contains("CoreSimulator") == true
    }

    /// "Startup Disk" for "/", otherwise the volume's own name (the last
    /// path component of its mount point, e.g. "/Volumes/Backup" → "Backup").
    var displayName: String {
        guard let mount, mount != "/" else { return "Startup Disk" }
        return (mount as NSString).lastPathComponent
    }
}

nonisolated struct MoleTopProcess: Decodable, Identifiable {
    var id: Int { pid ?? -1 }
    let pid: Int?
    let name: String?
    let cpuPercent: Double?
    let memoryPercent: Double?
    let memoryBytes: Int64?

    private enum CodingKeys: String, CodingKey {
        case pid, name
        case cpuPercent = "cpu"
        case memoryPercent = "memory"
        case memoryBytes = "memory_bytes"
    }
}

nonisolated struct MoleBattery: Decodable, Identifiable {
    let id = UUID()
    let percent: Int?
    let status: String?
    let timeLeft: String?
    let health: String?
    let cycleCount: Int?

    private enum CodingKeys: String, CodingKey {
        case percent, status, health
        case timeLeft = "time_left"
        case cycleCount = "cycle_count"
    }
}

nonisolated struct MoleNetworkInterface: Decodable {
    let name: String?
    let rxRateMBs: Double?
    let txRateMBs: Double?

    private enum CodingKeys: String, CodingKey {
        case name
        case rxRateMBs = "rx_rate_mbs"
        case txRateMBs = "tx_rate_mbs"
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
    /// `nonisolated` because MoleDeletionEntry.sizeBytesDisplay (a nonisolated
    /// computed property, per this file's actor-isolation note above) calls
    /// it — without this, the project's default MainActor isolation applies
    /// to the extension member too, and that call fails to build.
    nonisolated var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: - History
//
// Reconciled against a real `mole history --json` sample: a top-level
// `sessions` array (one entry per past `clean`/`optimize`/`uninstall`/…
// invocation, with counts but no file-level detail) and a separate
// `deletions` array (one entry per file actually removed, across all
// sessions — the two aren't cross-referenced by id in Mole's own output,
// so this app doesn't try to join them either). `logs`/`limit` in the raw
// JSON are just paths to Mole's own on-disk log files and the page size
// mole applied server-side; nothing here needs them.

nonisolated struct MoleHistory: Decodable {
    let sessions: [MoleHistorySession]
    let deletions: [MoleDeletionEntry]
}

nonisolated struct MoleHistorySession: Decodable, Identifiable {
    let id = UUID()
    let command: String?
    let startedAt: String?
    let endedAt: String?
    let items: Int?
    /// Already a human-readable string (e.g. "27.84GB") straight from Mole,
    /// same convention as MoleAppEntry.sizeDisplay.
    let sizeDisplay: String?
    let operationCount: Int?
    let failedTasks: Int?
    let actions: Actions?

    nonisolated struct Actions: Decodable {
        let removed: Int?
        let trashed: Int?
        let skipped: Int?
        let failed: Int?
        let rebuilt: Int?
        let other: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case command, items, actions
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case sizeDisplay = "size"
        case operationCount = "operation_count"
        case failedTasks = "failed_tasks"
    }

    /// Mole logs these as local-clock "yyyy-MM-dd HH:mm:ss" strings with no
    /// timezone — treated as the Mac's own local time, since that's the
    /// clock Mole itself was reading from when it wrote them.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var startedDate: Date? {
        guard let startedAt, !startedAt.isEmpty else { return nil }
        return Self.dateFormatter.date(from: startedAt)
    }

    private var endedDate: Date? {
        guard let endedAt, !endedAt.isEmpty else { return nil }
        return Self.dateFormatter.date(from: endedAt)
    }

    /// "3m 12s" — nil when Mole never recorded an end time for this session
    /// (seen live: a session killed mid-run logs `ended_at: ""`).
    var durationDisplay: String? {
        guard let start = startedDate, let end = endedDate else { return nil }
        let interval = end.timeIntervalSince(start)
        guard interval >= 0 else { return nil }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

nonisolated struct MoleDeletionEntry: Decodable, Identifiable {
    let id = UUID()
    let timestamp: String?
    let mode: String?
    let status: String?
    let sizeKB: Double?
    let path: String?

    private enum CodingKeys: String, CodingKey {
        case timestamp, mode, status, path
        case sizeKB = "size_kb"
    }

    /// Unlike session timestamps, Mole logs deletions as ISO 8601 with a
    /// numeric (no-colon) offset, e.g. "2026-08-22T21:41:53-0500".
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var timestampDate: Date? {
        guard let timestamp else { return nil }
        return Self.dateFormatter.date(from: timestamp)
    }

    var sizeBytesDisplay: String? {
        guard let sizeKB else { return nil }
        return Int64(sizeKB * 1024).formattedBytes
    }
}
