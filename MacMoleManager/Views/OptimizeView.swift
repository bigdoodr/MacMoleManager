//
//  OptimizeView.swift
//  MacStorageManager
//
//  "Optimize" mode — modeled on CleanView's dry-run-then-confirm shape and
//  now the same MoleUI-style grouped sections via the shared
//  MoleReportView. Confirmed live: Optimize's output uses the same
//  "➤ Category / → item" convention Clean does, just with mostly sizeless,
//  pass/fail-style items ("DNS cache flushed", "Broken login item: Ice (app
//  not found)") instead of Clean's item counts and byte sizes — and a "◎ "
//  glyph in place of "→ " for anything that needs the user's attention,
//  which MoleReportParser surfaces as a warning-styled item. Covers Mole's
//  memory/launch-agent/login-item optimization pass.
//
//  Read-only grouping, not partial selection — same caveat as Clean:
//  "Optimize Now" still runs the full `mole optimize` the dry run previewed.
//

import SwiftUI

struct OptimizeView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false
    @State private var showRawOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Optimize").font(.title2).bold()
                Spacer()
                Button {
                    Task { await vm.runOptimizeDryRun() }
                } label: {
                    Label("Preview (dry run)", systemImage: "eye")
                }
            }

            if vm.optimizeDryRunOutput != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MoleReportView(report: vm.optimizeReport, applyActionLabel: "Optimize Now")

                        if let raw = vm.optimizeDryRunOutput {
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
                    Label("Optimize Now", systemImage: "gauge.with.dots.needle.67percent")
                }
                .confirmationDialog(
                    "This applies the matched optimizations. Continue?",
                    isPresented: $showConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Optimize", role: .destructive) {
                        Task { await vm.confirmOptimize() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
            } else if let result = vm.optimizeResultOutput {
                Label("Optimize complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                ScrollView {
                    Text(result)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else if !vm.optimizeLiveOutput.isEmpty {
                Label("Scanning…", systemImage: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(vm.optimizeLiveOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("bottom")
                    }
                    .onChange(of: vm.optimizeLiveOutput) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "gauge.with.dots.needle.67percent",
                    description: Text("Tap Preview to see what would be optimized before applying anything.")
                )
            }

            Spacer()
        }
        .padding(24)
    }
}
