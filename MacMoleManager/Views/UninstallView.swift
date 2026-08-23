//
//  UninstallView.swift
//  MacStorageManager
//
//  Replaces "Uninstall an App" mode — the one MacStorageCheckBeta.sh
//  actually got working end-to-end most reliably. Same two-step flow
//  (list → select → preview → confirm) survives the port unchanged;
//  it's just backed by SwiftUI state instead of a second dialog window.
//

import SwiftUI

struct UninstallView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Installed Apps").font(.title2).bold()
                    Spacer()
                    Button {
                        Task { await vm.loadInstalledApps() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                List(vm.installedApps, selection: $vm.selectedApp) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.name ?? "Unknown").bold()
                            if let bundleID = app.bundleIdentifier {
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(app.sizeDisplay ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    .tag(app)
                    .onTapGesture {
                        Task { await vm.previewUninstall(app) }
                    }
                }
            }
            .padding(16)
            .frame(minWidth: 320)

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview").font(.title2).bold()

                if let selected = vm.selectedApp {
                    Text("Selected: \(selected.name ?? "—")")
                        .font(.headline)

                    ScrollView {
                        Text(vm.uninstallPreviewOutput ?? "Loading preview…")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        Label("Uninstall \(selected.name ?? "App")…", systemImage: "trash")
                    }
                    .disabled(vm.uninstallPreviewOutput == nil)
                    .confirmationDialog(
                        "Permanently remove \(selected.name ?? "this app") and its related files?",
                        isPresented: $showConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Uninstall", role: .destructive) {
                            Task { await vm.confirmUninstall(selected) }
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                } else {
                    ContentUnavailableView(
                        "No app selected",
                        systemImage: "trash",
                        description: Text("Pick an app on the left to preview what Mole would remove.")
                    )
                }

                Spacer()
            }
            .padding(16)
            .frame(minWidth: 360)
        }
        .task { if vm.installedApps.isEmpty { await vm.loadInstalledApps() } }
    }
}

extension MoleAppEntry: Hashable {
    static func == (lhs: MoleAppEntry, rhs: MoleAppEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
