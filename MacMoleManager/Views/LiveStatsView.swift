//
//  LiveStatsView.swift
//  MacStorageManager
//
//  "Live Stats" mode — the same `mole status --json` System Status already
//  shows, but refreshed continuously instead of once, and surfacing the
//  fuller set of fields Terminal Mole's own dashboard and MoleUI display
//  (per-core CPU, memory cache/available, one tile per real disk volume,
//  top processes, battery, network) rather than just the six System Status
//  tiles. Reconciled against a real `mole status --json` sample.
//
//  Uses its own state (AppViewModel.liveStatus, not .status) and polls via
//  a plain `while !Task.isCancelled` loop tied to this view's `.task` — see
//  AppViewModel.runLiveStatsLoop(). SwiftUI cancels that task automatically
//  when the user navigates away, which stops the polling without any
//  explicit start/stop wiring here.
//

import SwiftUI

struct LiveStatsView: View {
    @EnvironmentObject var vm: AppViewModel

    // Uptime has its own tile below (Casey's call — it balances the grid
    // better than cramming it into this line), so the header line sticks to
    // the static hardware facts that don't change tile-to-tile.
    private var subtitleLine: String? {
        guard let status = vm.liveStatus else { return nil }
        let parts = [status.hostModel, status.cpuModel, status.osVersion].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Live Stats").font(.title2).bold()
                        if vm.isLiveStatsRunning {
                            HStack(spacing: 5) {
                                Circle().fill(Color.green).frame(width: 7, height: 7)
                                Text("Live").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let subtitleLine {
                        Text(subtitleLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let lastUpdated = vm.liveStatsLastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let liveStatsErrorMessage = vm.liveStatsErrorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(liveStatsErrorMessage)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let status = vm.liveStatus {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Health/Uptime/CPU/Memory/Power/Network — a fixed
                        // set of six — share one grid so it divides evenly
                        // into clean rows with nothing left dangling alone.
                        // Order matters here as much as membership: a
                        // LazyVGrid row is only as tall as its tallest cell,
                        // so a short tile (Health, Uptime) next to a tall one
                        // (CPU, Memory) leaves visible empty space — pairing
                        // short-with-short and tall-with-tall keeps rows even.
                        //
                        // Disks and Top Processes sit outside this grid: the
                        // disk count varies (1 on most Macs, more with an
                        // external drive attached), which would leave an odd
                        // tile stranded alone in the grid — a single
                        // full-width card avoids that regardless of count,
                        // and reads closer to MoleUI's own combined disk box.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                            StatTile(title: "Health", value: status.healthScore.map { score in
                                status.healthScoreMessage.map { "\(score) · \($0)" } ?? "\(score)"
                            } ?? "—")
                            UptimeTile(status: status)

                            CPUTile(status: status)
                            MemoryTile(status: status)

                            if let battery = status.batteries.first {
                                PowerTile(battery: battery)
                            }
                            NetworkTile(status: status)
                        }

                        if !status.displayDisks.isEmpty {
                            DisksTile(disks: status.displayDisks)
                        }

                        if !status.topProcesses.isEmpty {
                            TopProcessesTile(processes: status.topProcesses, totalProcessCount: status.processCount)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "Connecting…",
                    systemImage: "waveform.path.ecg",
                    description: Text("Fetching Mole's live status.")
                )
            }

            Spacer()
        }
        .padding(24)
        .task { await vm.runLiveStatsLoop() }
    }
}

/// Shared "titled card" shape for every Live Stats tile fancier than a
/// plain StatTile — same background/corner treatment, but built for a
/// multi-line VStack of detail rows instead of one big value.
private struct DetailTile<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

private struct UptimeTile: View {
    let status: MoleStatus

    var body: some View {
        DetailTile(title: "Uptime") {
            Text(status.uptimeDisplay ?? "—")
                .font(.title3.monospacedDigit())
                .bold()
        }
    }
}

private struct CPUTile: View {
    let status: MoleStatus

    private var coreSummary: String? {
        guard let total = status.cpuCoreCount else { return nil }
        if let p = status.cpuPerformanceCoreCount, let e = status.cpuEfficiencyCoreCount, p > 0 || e > 0 {
            return "\(total) cores (\(p)P+\(e)E)"
        }
        return "\(total) cores"
    }

    var body: some View {
        DetailTile(title: "CPU Usage") {
            Text(status.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.title3.monospacedDigit())
                .bold()
            if let coreSummary {
                Text(coreSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let load1 = status.load1 {
                DetailRow(label: "Load (1 min)", value: String(format: "%.2f", load1))
            }
            if let load5 = status.load5 {
                DetailRow(label: "Load (5 min)", value: String(format: "%.2f", load5))
            }
            if let load15 = status.load15 {
                DetailRow(label: "Load (15 min)", value: String(format: "%.2f", load15))
            }
        }
    }
}

private struct MemoryTile: View {
    let status: MoleStatus

    var body: some View {
        DetailTile(title: "Memory") {
            Text(status.memoryUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.title3.monospacedDigit())
                .bold()
            if let used = status.memoryUsedBytes, let total = status.memoryTotalBytes {
                Text("\(used.formattedBytes) / \(total.formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let available = status.memoryAvailableBytes {
                DetailRow(label: "Available", value: available.formattedBytes)
            }
            if let cached = status.memoryCachedBytes, cached > 0 {
                DetailRow(label: "Cache", value: cached.formattedBytes)
            }
            if let swapTotal = status.swapTotalBytes, swapTotal > 0, let swapUsed = status.swapUsedBytes {
                DetailRow(label: "Swap", value: "\(swapUsed.formattedBytes) / \(swapTotal.formattedBytes)")
            }
        }
    }
}

/// One combined card for every non-CoreSimulator disk, full width — closer
/// to MoleUI's own single disk box than a grid of narrow per-volume tiles,
/// and sidesteps the grid-parity problem a variable disk count would cause
/// (1 on most Macs, 2+ with an external drive attached).
private struct DisksTile: View {
    let disks: [MoleDiskVolume]

    var body: some View {
        DetailTile(title: "Disks") {
            VStack(spacing: 10) {
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(disk.isExternal == true ? "\(disk.displayName) (External)" : disk.displayName)
                                .font(.callout)
                            Spacer()
                            Text(disk.usedPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                                .font(.callout.monospacedDigit())
                                .bold()
                        }
                        if let used = disk.usedBytes, let total = disk.totalBytes {
                            Text("\(used.formattedBytes) / \(total.formattedBytes)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct TopProcessesTile: View {
    let processes: [MoleTopProcess]
    /// Mole's total system-wide process count (`procs`) — shown here rather
    /// than on the Uptime tile, since it's a fact about processes, not time.
    let totalProcessCount: Int?

    var body: some View {
        DetailTile(title: "Top Processes") {
            if let totalProcessCount {
                Text("\(totalProcessCount) processes total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(processes.prefix(5)) { process in
                    HStack {
                        Text(process.name ?? "—")
                            .font(.callout)
                        Spacer()
                        Text(process.cpuPercent.map { String(format: "%.1f%% CPU", $0) } ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(process.memoryBytes?.formattedBytes ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct PowerTile: View {
    let battery: MoleBattery

    var body: some View {
        DetailTile(title: "Power") {
            Text(battery.percent.map { "\($0)%" } ?? "—")
                .font(.title3.monospacedDigit())
                .bold()
            if let status = battery.status {
                DetailRow(label: "Status", value: status.capitalized)
            }
            if let timeLeft = battery.timeLeft, !timeLeft.isEmpty {
                DetailRow(label: "Time Left", value: timeLeft)
            }
            if let health = battery.health {
                DetailRow(label: "Health", value: battery.cycleCount.map { "\(health) · \($0) cycles" } ?? health)
            }
        }
    }
}

private struct NetworkTile: View {
    let status: MoleStatus

    var body: some View {
        DetailTile(title: "Network") {
            DetailRow(label: "Down", value: String(format: "%.1f MB/s", status.totalDownMBs))
            DetailRow(label: "Up", value: String(format: "%.1f MB/s", status.totalUpMBs))
        }
    }
}
