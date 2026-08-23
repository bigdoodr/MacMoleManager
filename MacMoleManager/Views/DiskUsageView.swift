//
//  DiskUsageView.swift
//  MacStorageManager
//
//  Replaces "Analyze Disk Usage (Home Folder)" mode — the one that hit
//  swiftDialog's native "Configuration Error / Configuration file not
//  found" page after a real, multi-minute Mole scan completed. A native
//  List just renders whatever `analysis.entries` currently holds; there's
//  no second window reading a JSON file off disk to go wrong.
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
                Button("Choose…") { chooseFolder() }
                Button {
                    Task { await vm.runAnalysis() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
            }

            if let analysis = vm.analysis, let entries = analysis.entries, !entries.isEmpty {
                Text("Total: \(analysis.totalSizeBytes?.formattedBytes ?? "—")")
                    .foregroundStyle(.secondary)

                Table(entries.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }) {
                    TableColumn("Name") { entry in Text(entry.name ?? entry.path ?? "—") }
                    TableColumn("Kind") { entry in Text(entry.kind ?? "—") }
                    TableColumn("Size") { entry in Text(entry.sizeBytes?.formattedBytes ?? "—") }
                        .width(120)
                }
            } else {
                ContentUnavailableView(
                    "No scan yet",
                    systemImage: "chart.pie",
                    description: Text("Pick a path and tap Scan to run `mole analyze --json`.")
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
