//
//  AppViewModel.swift
//  MacStorageManager
//
//  Central @Published state. Every mode (Status / Analyze / Clean / Uninstall)
//  reads and writes this one object, so the UI updates the moment mole's
//  output is decoded — no config file written to /var/tmp for a second
//  process to poll for, no race between "config written" and "dialog reads
//  it," which was the root of the recurring "Configuration Error" bug in
//  MacStorageCheckBeta.sh.
//

import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case status = "System Status"
        case analyze = "Analyze Disk Usage"
        case uninstall = "Uninstall an App"
        case clean = "Clean My Mac"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .status: return "gauge.with.dots.needle.50percent"
            case .analyze: return "chart.pie"
            case .uninstall: return "trash"
            case .clean: return "sparkles"
            }
        }
    }

    @Published var selectedMode: Mode = .status
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var fullDiskAccessGranted = FullDiskAccess.isGranted()

    // Mole install/update state
    @Published var moleInstalled = true
    @Published var isInstallingMole = false
    @Published var moleVersion: String?
    @Published var isUpdatingMole = false
    @Published var updateOutput: String?

    // Status
    @Published var status: MoleStatus?

    // Analyze
    @Published var analysis: MoleAnalysis?
    @Published var analyzeTargetPath = NSHomeDirectory()

    // Uninstall
    @Published var installedApps: [MoleAppEntry] = []
    @Published var selectedApp: MoleAppEntry?
    @Published var uninstallPreviewOutput: String?

    // Clean
    @Published var cleanDryRunOutput: String?
    @Published var cleanResultOutput: String?

    private let runner = MoleRunner.shared

    func refreshFullDiskAccessState() {
        fullDiskAccessGranted = FullDiskAccess.isGranted()
    }

    func refreshMoleInstalledState() async {
        moleInstalled = await runner.isBinaryAvailable()
        if moleInstalled {
            await refreshMoleVersion()
        }
    }

    func refreshMoleVersion() async {
        moleVersion = try? await runner.version()
    }

    /// Runs Mole's own installer (not a vendored binary) so the app tracks
    /// Mole's release cadence. On success, immediately loads status so the
    /// rest of the UI has something to show right away.
    func installMole() async {
        isInstallingMole = true
        errorMessage = nil
        defer { isInstallingMole = false }
        do {
            _ = try await runner.install()
            moleInstalled = true
            await refreshMoleVersion()
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `mo update` — moves an already-installed Mole forward to the latest
    /// stable release, same cadence the standalone CLI itself would use.
    func updateMole() async {
        isUpdatingMole = true
        errorMessage = nil
        defer { isUpdatingMole = false }
        do {
            updateOutput = try await runner.update()
            await refreshMoleVersion()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadStatus() async {
        await runTask {
            self.status = try await self.runner.status()
        }
    }

    func runAnalysis() async {
        await runTask {
            self.analysis = try await self.runner.analyze(path: self.analyzeTargetPath)
        }
    }

    func loadInstalledApps() async {
        await runTask {
            self.installedApps = try await self.runner.uninstallList()
        }
    }

    func previewUninstall(_ app: MoleAppEntry) async {
        selectedApp = app
        await runTask {
            self.uninstallPreviewOutput = try await self.runner.uninstallPreview(appName: app.uninstallName ?? app.name ?? "")
        }
    }

    func confirmUninstall(_ app: MoleAppEntry) async {
        await runTask {
            _ = try await self.runner.uninstallExecute(appName: app.uninstallName ?? app.name ?? "")
            self.uninstallPreviewOutput = nil
            self.selectedApp = nil
        }
        await loadInstalledApps()
    }

    func runCleanDryRun() async {
        await runTask {
            self.cleanDryRunOutput = try await self.runner.cleanDryRun()
        }
    }

    func confirmClean() async {
        await runTask {
            self.cleanResultOutput = try await self.runner.cleanExecute()
            self.cleanDryRunOutput = nil
        }
    }

    /// Shared wrapper: sets isBusy, clears/reports errorMessage, keeps each
    /// call site down to one line instead of repeating do/catch everywhere.
    private func runTask(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
