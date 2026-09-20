//
//  CleanView.swift
//  MacStorageManager
//
//  "Clean My Mac" mode: mole's dry-run output grouped into collapsible
//  sections via MoleReportParser + the shared MoleReportView. Read-only
//  grouping, not partial selection — mole has no flag to clean just one
//  category or item, so "Clean Now" still runs the full `mole clean`.
//

import SwiftUI

struct CleanView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false
    @State private var showRawOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Clean My Mac").font(.title2).bold()
                Spacer()
                Button {
                    Task { await vm.runCleanDryRun() }
                } label: {
                    Label("Preview (dry run)", systemImage: "eye")
                }
            }

            if vm.cleanDryRunOutput != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MoleReportView(report: vm.cleanReport, applyActionLabel: "Clean Now")

                        if let raw = vm.cleanDryRunOutput {
                            DisclosureGroup("Raw mole output", isExpanded: $showRawOutput) {
                                Text(raw)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 6)
                            }
                            .font(.callout)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Label("Clean Now", systemImage: "sparkles")
                }
                .confirmationDialog(
                    "This permanently deletes the matched items. Continue?",
                    isPresented: $showConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Clean", role: .destructive) {
                        Task { await vm.confirmClean() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
            } else if let result = vm.cleanResultOutput {
                Label("Clean complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                ScrollView {
                    Text(result)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else if !vm.cleanLiveOutput.isEmpty {
                Label("Scanning…", systemImage: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(vm.cleanLiveOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("bottom")
                    }
                    // Keeps the tail of mole's output in view as it streams in.
                    .onChange(of: vm.cleanLiveOutput) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "sparkles",
                    description: Text("Tap Preview to see what can be cleaned before deleting anything.\nScanning your whole Mac can take several minutes, especially the first time — it's not stuck.")
                )
            }

            Spacer()
        }
        .padding(24)
    }
}
