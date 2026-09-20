//
//  InstallerView.swift
//  MacStorageManager
//
//  "Installer Cleanup" mode — a native checklist over InstallerScanner's
//  FileManager-based scan, not a wrapped mole subcommand (`mole installer` is
//  a raw-terminal UI a GUI app's Process/Pipe can't drive — see InstallerScanner.swift).
//

import SwiftUI

struct InstallerView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false

    private var selectedCount: Int { vm.selectedInstallerLeftoverIDs.count }

    private var selectedTotalBytes: Int64 {
        vm.installerLeftovers
            .filter { vm.selectedInstallerLeftoverIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Installer Cleanup").font(.title2).bold()
                Spacer()
                Button {
                    Task { await vm.runInstallerScan() }
                } label: {
                    Label(vm.installerHasScanned ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
            }

            Text("Looks directly in Downloads, Desktop, and Documents for leftover .dmg/.pkg installer files.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let message = vm.installerCleanupResultMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            if !vm.installerHasScanned {
                ContentUnavailableView(
                    "No scan yet",
                    systemImage: "shippingbox",
                    description: Text("Tap Scan to look for leftover .dmg/.pkg installers you likely don't need anymore.")
                )
            } else if vm.installerLeftovers.isEmpty {
                ContentUnavailableView(
                    "Nothing found",
                    systemImage: "checkmark.circle",
                    description: Text("No leftover installer packages or disk images in Downloads, Desktop, or Documents.")
                )
            } else {
                HStack(spacing: 12) {
                    Button("Select All") { vm.selectAllInstallerLeftovers() }
                    Button("Deselect All") { vm.deselectAllInstallerLeftovers() }
                    Spacer()
                    Text("\(selectedCount) selected — \(selectedTotalBytes.formattedBytes)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                List(vm.installerLeftovers) { item in
                    let isSelected = vm.selectedInstallerLeftoverIDs.contains(item.id)
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.sizeBytes.formattedBytes)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { vm.toggleInstallerSelection(item) }
                }
                .listStyle(.inset)

                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Label("Move Selected to Trash", systemImage: "trash")
                }
                .disabled(selectedCount == 0)
                .confirmationDialog(
                    "Move \(selectedCount) selected item\(selectedCount == 1 ? "" : "s") to the Trash?",
                    isPresented: $showConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Move to Trash", role: .destructive) {
                        Task { await vm.confirmInstallerCleanup() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}
