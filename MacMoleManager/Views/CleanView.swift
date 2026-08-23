//
//  CleanView.swift
//  MacStorageManager
//
//  Replaces "Clean My Mac" mode — the one that rendered "Ready to Clean"
//  with `?`/blank placeholders instead of real scan numbers in the shell
//  version. Same dry-run-then-confirm shape, driven by plain @Published
//  strings instead of a JXA-built markdown blob handed to swiftDialog.
//

import SwiftUI

struct CleanView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false

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

            if let dryRun = vm.cleanDryRunOutput {
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
            } else {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "sparkles",
                    description: Text("Tap Preview to run `mole clean --dry-run` before deleting anything.")
                )
            }

            Spacer()
        }
        .padding(24)
    }
}
