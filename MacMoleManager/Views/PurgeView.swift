//
//  PurgeView.swift
//  MacStorageManager
//
//  "Deep Purge" mode — modeled directly on CleanView's dry-run-then-confirm
//  shape. Covers Mole's deeper cache/log/derived-data purge pass, which goes
//  further than the regular Clean My Mac scan.
//

import SwiftUI

struct PurgeView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Deep Purge").font(.title2).bold()
                Spacer()
                Button {
                    Task { await vm.runPurgeDryRun() }
                } label: {
                    Label("Preview (dry run)", systemImage: "eye")
                }
            }

            if let dryRun = vm.purgeDryRunOutput {
                ScrollView {
                    Text(dryRun)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Label("Purge Now", systemImage: "flame")
                }
                .confirmationDialog(
                    "This permanently deletes the matched caches/logs/derived data. Continue?",
                    isPresented: $showConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Purge", role: .destructive) {
                        Task { await vm.confirmPurge() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
            } else if let result = vm.purgeResultOutput {
                Label("Purge complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                ScrollView {
                    Text(result)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "flame",
                    description: Text("Tap Preview to see what can be purged before deleting anything.\nThis goes deeper than Clean My Mac, so review the list carefully.")
                )
            }

            Spacer()
        }
        .padding(24)
    }
}
