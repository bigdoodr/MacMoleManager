//
//  StatusView.swift
//  MacStorageManager
//
//  Replaces MacStorageCheckBeta.sh's "System Status" mode. That mode's
//  bug ("No status data returned — check the log for details.") was a
//  symptom of `mole status --json` output surviving a temp-file round
//  trip through a backgrounded subshell; here it goes straight from
//  Process stdout into @Published state.
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("System Status")
                    .font(.title2).bold()
                if let moleVersion = vm.moleVersion {
                    Text(moleVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isUpdatingMole {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await vm.updateMole() }
                    } label: {
                        Label("Check for Mole Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Button {
                    Task { await vm.loadStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if let updateOutput = vm.updateOutput {
                Text(updateOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = vm.status {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                    StatTile(title: "Disk Used", value: status.diskUsedBytes?.formattedBytes ?? "—")
                    StatTile(title: "Disk Free", value: status.diskFreeBytes?.formattedBytes ?? "—")
                    StatTile(title: "Disk Total", value: status.diskTotalBytes?.formattedBytes ?? "—")
                    StatTile(title: "CPU Usage", value: status.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—")
                    StatTile(title: "Memory Usage", value: status.memoryUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—")
                    StatTile(title: "Health Score", value: status.healthScore.map { score in
                        status.healthScoreMessage.map { "\(score) · \($0)" } ?? "\(score)"
                    } ?? "—")
                }
            } else {
                ContentUnavailableView(
                    "No status loaded yet",
                    systemImage: "gauge.with.dots.needle.50percent",
                    description: Text("Tap Refresh to run `mole status --json`.")
                )
            }

            Spacer()
        }
        .padding(24)
        .task { if vm.status == nil { await vm.loadStatus() } }
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
