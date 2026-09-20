//
//  DiskUsageView.swift
//  MacStorageManager
//
//  "Analyze Disk Usage" mode — a native Table renders whatever
//  `analysis.entries` currently holds.
//

import SwiftUI
import AppKit

struct DiskUsageView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Analyze Disk Usage")
                    .font(.title2).bold()
                Spacer()
                TextField("Path", text: $vm.analyzeTargetPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                    .onSubmit { Task { await vm.runAnalysis() } }
                Button("Choose…") { chooseFolder() }
                Button {
                    Task { await vm.runAnalysis() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
            }

            if let analysis = vm.analysis, let entries = analysis.entries, !entries.isEmpty {
                HStack(spacing: 12) {
                    if vm.canNavigateAnalysisBack {
                        Button {
                            vm.navigateAnalysisBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                    Text("Total: \(analysis.totalSizeBytes?.formattedBytes ?? "—")")
                        .foregroundStyle(.secondary)
                }

                Table(entries.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }) {
                    TableColumn("Name") { entry in
                        if entry.isDir == true {
                            Button {
                                Task { await vm.navigateAnalysisInto(entry) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(entry.name ?? entry.path ?? "—")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(entry.name ?? entry.path ?? "—")
                        }
                    }
                    TableColumn("Kind") { entry in Text(entry.kind ?? "—") }
                    TableColumn("Size") { entry in Text(entry.sizeBytes?.formattedBytes ?? "—") }
                        .width(120)
                }
            } else {
                ContentUnavailableView(
                    "No scan yet",
                    systemImage: "chart.pie",
                    description: Text("Pick a path and tap Scan to see what's using space inside it.")
                )
            }

            Spacer()
        }
        .padding(24)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: vm.analyzeTargetPath)
        if panel.runModal() == .OK, let url = panel.url {
            vm.analyzeTargetPath = url.path
        }
    }
}
