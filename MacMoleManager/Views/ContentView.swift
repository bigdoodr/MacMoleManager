//
//  ContentView.swift
//  MacStorageManager
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(AppViewModel.Mode.allCases, selection: $vm.selectedMode) { mode in
                Label(mode.rawValue, systemImage: mode.systemImage)
                    .tag(mode)
            }
            .navigationTitle("Mac Storage Manager")
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                if !vm.moleInstalled {
                    MoleMissingBanner()
                }
                if !vm.fullDiskAccessGranted {
                    FullDiskAccessBanner()
                }
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(!vm.moleInstalled)
                if let errorMessage = vm.errorMessage {
                    ErrorBanner(message: errorMessage)
                }
            }
            .overlay {
                if vm.isBusy {
                    ProgressOverlay(message: vm.busyMessage)
                }
            }
        }
        .onAppear { vm.refreshFullDiskAccessState() }
        .task { await vm.refreshMoleInstalledState() }
    }

    @ViewBuilder
    private var detailView: some View {
        switch vm.selectedMode {
        case .status: StatusView()
        case .analyze: DiskUsageView()
        case .uninstall: UninstallView()
        case .clean: CleanView()
        case .optimize: OptimizeView()
        case .purge: PurgeView()
        case .installer: InstallerView()
        case .history: HistoryView()
        case .liveStats: LiveStatsView()
        case .settings: SettingsView()
        }
    }
}

private struct MoleMissingBanner: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            if vm.isInstallingMole {
                Text("Installing Mole (running the official installer from tw93/mole)…")
                    .font(.callout)
                Spacer()
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Mole isn't installed — this app needs it to do anything.")
                    .font(.callout)
                Spacer()
                Button("Install Mole") { Task { await vm.installMole() } }
            }
        }
        .padding(10)
        .background(.red.opacity(0.15))
    }
}

private struct FullDiskAccessBanner: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Full Disk Access isn't granted yet — some scans will be incomplete.")
                .font(.callout)
            Spacer()
            Button("Open Settings") { FullDiskAccess.openSystemSettings() }
            Button("Re-check") { vm.refreshFullDiskAccessState() }
        }
        .padding(10)
        .background(.orange.opacity(0.15))
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(.red.opacity(0.12))
    }
}

private struct ProgressOverlay: View {
    var message: String = "Working…"

    var body: some View {
        ZStack {
            Color.black.opacity(0.05)
            ProgressView(message)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
