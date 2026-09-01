//
//  HistoryView.swift
//  MacStorageManager
//
//  "History" mode — wraps `mole history --json`, confirmed against a real
//  sample from Casey's Mac. Two independent lists straight from Mole's own
//  JSON: past sessions (one per clean/optimize/uninstall/… run, with
//  counts but no file-level detail) and individual file deletions. Mole
//  doesn't cross-reference the two by id, so neither does this view — they're
//  shown as separate sections rather than joined into one merged timeline.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("History").font(.title2).bold()
                Spacer()
                Button {
                    Task { await vm.loadHistory() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if let history = vm.moleHistory {
                if history.sessions.isEmpty && history.deletions.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Mole hasn't logged any clean, optimize, uninstall, or purge runs yet.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !history.sessions.isEmpty {
                                SectionHeader(title: "Recent Sessions")
                                VStack(spacing: 1) {
                                    ForEach(history.sessions) { session in
                                        SessionRow(session: session)
                                    }
                                }
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                            }

                            if !history.deletions.isEmpty {
                                SectionHeader(title: "Recent Deletions")
                                VStack(spacing: 1) {
                                    ForEach(history.deletions) { deletion in
                                        DeletionRow(deletion: deletion)
                                    }
                                }
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No history loaded yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Tap Refresh to see your recent Mole activity.")
                )
            }

            Spacer()
        }
        .padding(24)
        .task { if vm.moleHistory == nil { await vm.loadHistory() } }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// Maps a session's raw `command` string back to the same title/icon the
/// sidebar uses for that mode, so History reads as "the same six things,
/// just with a timestamp" rather than introducing a second vocabulary.
private func commandDisplay(_ command: String?) -> (title: String, systemImage: String) {
    switch command?.lowercased() {
    case "clean": return ("Clean My Mac", "sparkles")
    case "optimize": return ("Optimize", "gauge.with.dots.needle.67percent")
    case "uninstall": return ("Uninstall an App", "trash")
    case "purge": return ("Deep Purge", "flame")
    case "installer": return ("Installer Cleanup", "shippingbox")
    case "analyze", "analyse": return ("Analyze Disk Usage", "chart.pie")
    case "status": return ("System Status", "gauge.with.dots.needle.50percent")
    default: return (command?.capitalized ?? "Unknown", "questionmark.circle")
    }
}

private struct SessionRow: View {
    let session: MoleHistorySession

    private static let dateStyle = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()

    private var display: (title: String, systemImage: String) { commandDisplay(session.command) }

    /// Nonzero action counts only — most sessions are dry-run previews where
    /// everything is 0, so this stays quiet unless something actually happened.
    private var actionSummary: String? {
        guard let actions = session.actions else { return nil }
        let parts: [(String, Int?)] = [
            ("removed", actions.removed), ("trashed", actions.trashed),
            ("skipped", actions.skipped), ("failed", actions.failed),
            ("rebuilt", actions.rebuilt), ("other", actions.other),
        ]
        let nonzero = parts.compactMap { label, count -> String? in
            guard let count, count > 0 else { return nil }
            return "\(count) \(label)"
        }
        return nonzero.isEmpty ? nil : nonzero.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: display.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(display.title)
                        .font(.callout).bold()
                    if let failedTasks = session.failedTasks, failedTasks > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .help("\(failedTasks) task\(failedTasks == 1 ? "" : "s") failed")
                    }
                }
                HStack(spacing: 6) {
                    if let started = session.startedDate {
                        Text(started, format: Self.dateStyle)
                    } else {
                        Text(session.startedAt ?? "—")
                    }
                    if let duration = session.durationDisplay {
                        Text("· \(duration)")
                    }
                    if let items = session.items, items > 0 {
                        Text("· \(items) item\(items == 1 ? "" : "s")")
                    }
                    if let size = session.sizeDisplay, size != "0B" {
                        Text("· \(size)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let actionSummary {
                    Text(actionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(.background.opacity(0.4))
    }
}

private struct DeletionRow: View {
    let deletion: MoleDeletionEntry

    private static let dateStyle = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()

    private var isFailed: Bool { deletion.status?.lowercased() != "ok" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isFailed ? .red : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(deletion.path ?? "—")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let timestamp = deletion.timestampDate {
                        Text(timestamp, format: Self.dateStyle)
                    } else {
                        Text(deletion.timestamp ?? "—")
                    }
                    if let mode = deletion.mode {
                        Text("· \(mode == "trash" ? "Moved to Trash" : mode.capitalized)")
                    }
                    if let size = deletion.sizeBytesDisplay {
                        Text("· \(size)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(.background.opacity(0.4))
    }
}
