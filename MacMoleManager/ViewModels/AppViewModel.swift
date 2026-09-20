//
//  AppViewModel.swift
//  MacStorageManager
//
//  Central @Published state. Every mode (Status / Analyze / Clean / Uninstall)
//  reads and writes this one object, so the UI updates the moment mole's
//  output is decoded.
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
        case optimize = "Optimize"
        case purge = "Deep Purge"
        case installer = "Installer Cleanup"
        case history = "History"
        case liveStats = "Live Stats"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .status: return "gauge.with.dots.needle.50percent"
            case .analyze: return "chart.pie"
            case .uninstall: return "trash"
            case .clean: return "sparkles"
            case .optimize: return "gauge.with.dots.needle.67percent"
            case .purge: return "flame"
            case .installer: return "shippingbox"
            case .history: return "clock.arrow.circlepath"
            case .liveStats: return "waveform.path.ecg"
            case .settings: return "gearshape"
            }
        }
    }

    @Published var selectedMode: Mode = .status
    @Published var isBusy = false
    /// What the busy overlay says while `isBusy` — set per action, since a tab's
    /// dry-run and real-run steps use very different messages.
    @Published var busyMessage = "Working…"
    @Published var errorMessage: String?
    @Published var fullDiskAccessGranted = FullDiskAccess.isGranted()

    // Mole install/update state
    @Published var moleInstalled = true
    @Published var isInstallingMole = false
    @Published var moleVersion: String?
    @Published var isUpdatingMole = false
    @Published var updateOutput: String?

    // Admin password prompt, shown when mole can't reach its own /dev/tty
    // prompt from inside a GUI app (see MoleRunner.update(withAdminPassword:)).
    @Published var isPromptingForAdminPassword = false
    @Published var isSubmittingAdminPassword = false
    @Published var adminPasswordError: String?

    /// Which elevated action failed because the account has no admin rights at
    /// all (distinct from a wrong password) — drives NeedsAdminAccessView.
    enum PendingElevatedAction: Identifiable, Hashable {
        case install
        case update
        var id: Self { self }
    }
    @Published var pendingElevatedAction: PendingElevatedAction?
    @Published var isRequestingPrivilegesAccess = false
    @Published var privilegesRequestError: String?

    /// Drives OnboardingView — shown automatically the first time Mole is
    /// found missing, and reopenable any time from MoleMissingBanner.
    @Published var showMoleOnboarding = false
    private static let hasShownMoleOnboardingKey = "AppViewModel.hasShownMoleOnboarding"

    // Status
    @Published var status: MoleStatus?

    // Analyze
    @Published var analysis: MoleAnalysis?
    @Published var analyzeTargetPath = NSHomeDirectory()
    /// Previously-scanned levels, so navigating back doesn't need a rescan.
    @Published private(set) var analyzeHistory: [(path: String, analysis: MoleAnalysis)] = []

    var canNavigateAnalysisBack: Bool { !analyzeHistory.isEmpty }

    // Uninstall
    @Published var installedApps: [MoleAppEntry] = []
    @Published var selectedApp: MoleAppEntry?
    /// AppCleaner-style per-file leftover breakdown for the selected app, found
    /// natively via AppLeftoverScanner — mole's own uninstall preview only prints
    /// a one-line summary with no per-file listing.
    @Published var appLeftovers: [AppLeftoverItem] = []
    @Published var hasScannedLeftovers = false
    @Published var selectedLeftoverIDs: Set<UUID> = []

    var selectedLeftoversTotalBytes: Int64 {
        appLeftovers
            .filter { selectedLeftoverIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    // Clean
    @Published var cleanDryRunOutput: String?
    @Published var cleanResultOutput: String?
    /// `cleanDryRunOutput` parsed into collapsible sections — see MoleReportParser.swift.
    @Published var cleanReport: MoleReportSummary = .empty
    /// mole's raw stdout for the in-progress dry-run scan, updated live via `runCleanDryRun()`.
    /// Cleared once the scan finishes and `cleanReport`/`cleanDryRunOutput` take over.
    @Published var cleanLiveOutput = ""

    // Optimize
    @Published var optimizeDryRunOutput: String?
    @Published var optimizeResultOutput: String?
    @Published var optimizeReport: MoleReportSummary = .empty
    @Published var optimizeLiveOutput = ""

    // Purge
    @Published var purgeDryRunOutput: String?
    @Published var purgeResultOutput: String?

    // Installer cleanup — a native FileManager scan (InstallerScanner), since
    // `mole installer` is an interactive terminal UI, not a scriptable preview.
    @Published var installerLeftovers: [InstallerLeftover] = []
    @Published var installerHasScanned = false
    @Published var selectedInstallerLeftoverIDs: Set<UUID> = []
    @Published var installerCleanupResultMessage: String?

    // History
    @Published var moleHistory: MoleHistory?

    // Live Stats — a continuously-refreshing `mole status --json`, distinct
    // from the one-shot `status` above so a slow/failing poll here doesn't
    // affect the System Status tab.
    @Published var liveStatus: MoleStatus?
    @Published var isLiveStatsRunning = false
    @Published var liveStatsErrorMessage: String?
    @Published var liveStatsLastUpdated: Date?

    // Settings — native editing of Mole's own on-disk whitelist and purge_paths
    // config files, since both `mole clean --whitelist` and `mole purge --paths`
    // are interactive-only (raw-terminal checklist / vim) — see MoleConfigStore.swift.
    @Published var whitelistSelectedPatterns: Set<String> = []
    /// Anything in the saved whitelist file that isn't one of the catalog rows in
    /// MoleWhitelistCatalog. Preserved verbatim so saving from Settings never
    /// silently un-protects something the user or Mole itself added by hand.
    @Published var whitelistCustomPatterns: [String] = []
    @Published var purgePaths: [String] = []
    @Published var hasLoadedSettings = false
    @Published var settingsSaveMessage: String?

    private let runner = MoleRunner.shared

    func refreshFullDiskAccessState() {
        fullDiskAccessGranted = FullDiskAccess.isGranted()
    }

    func refreshMoleInstalledState() async {
        moleInstalled = await runner.isBinaryAvailable()
        if moleInstalled {
            await refreshMoleVersion()
        } else if !UserDefaults.standard.bool(forKey: Self.hasShownMoleOnboardingKey) {
            showMoleOnboarding = true
        }
    }

    /// Dismisses OnboardingView. `markSeen` is true for the normal "Not Now"/
    /// successful-install path so it doesn't reappear on every launch.
    func dismissMoleOnboarding(markSeen: Bool = true) {
        showMoleOnboarding = false
        if markSeen {
            UserDefaults.standard.set(true, forKey: Self.hasShownMoleOnboardingKey)
        }
    }

    func refreshMoleVersion() async {
        moleVersion = try? await runner.version()
    }

    /// Runs Mole's own installer (not a vendored binary). If the plain
    /// `runner.install()` fails — e.g. a fresh Mac where install.sh needs sudo
    /// and can't reach /dev/tty from a Process/Pipe child — falls back to
    /// `performElevatedInstall()`.
    func installMole() async {
        isInstallingMole = true
        errorMessage = nil
        defer { isInstallingMole = false }
        do {
            do {
                _ = try await runner.install()
            } catch {
                _ = try await performElevatedInstall()
                try await runner.refreshBinaryPathAfterExternalInstall()
            }
            moleInstalled = true
            await refreshMoleVersion()
            await loadStatus()
        } catch {
            handleElevationFailure(error, action: .install)
        }
    }

    /// Pre-authenticates via `sudo -A -v` through AskPassHelper's native dialog
    /// (Touch ID first, if configured), then runs install.sh in that same real
    /// pty session so its internal sudo calls find an already-warm ticket
    /// instead of needing `/dev/tty`. Mirrors `performElevatedUpdate()` below.
    private func performElevatedInstall() async throws -> String {
        let scriptPath = try AskPassHelper.write(reason: .install)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }
        let command = "export SUDO_ASKPASS=\(scriptPath.shellEscaped); sudo -A -v && \(MoleRunner.installScriptCommand)"
        return try await PTYRunner().run(command: command)
    }

    /// `mo update` — moves an already-installed Mole to the latest release.
    /// Primary path is `performElevatedUpdate()` (sudo -A -v + mole update in
    /// one pty session). If that throws and the install is Homebrew-managed,
    /// falls back to `runner.updateViaHomebrew()` instead.
    func updateMole() async {
        isUpdatingMole = true
        errorMessage = nil
        defer { isUpdatingMole = false }
        do {
            updateOutput = try await performElevatedUpdate()
            await refreshMoleVersion()
        } catch {
            if await runner.installSource() == .homebrew {
                do {
                    updateOutput = try await runner.updateViaHomebrew()
                    await refreshMoleVersion()
                    return
                } catch {
                    handleElevationFailure(error, action: .update)
                    return
                }
            }
            handleElevationFailure(error, action: .update)
        }
    }

    /// Routes "this account has no admin rights at all" to NeedsAdminAccessView
    /// instead of the plain error banner, since retrying a password can't fix it.
    private func handleElevationFailure(_ error: Error, action: PendingElevatedAction) {
        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if AdminAccess.describesMissingAdminRights(description) {
            pendingElevatedAction = action
        } else {
            errorMessage = description
        }
    }

    func dismissPendingElevatedAction() {
        pendingElevatedAction = nil
        privilegesRequestError = nil
    }

    /// Retries whichever action (install/update) triggered NeedsAdminAccessView.
    private func retryPendingElevatedAction() async {
        guard let action = pendingElevatedAction else { return }
        pendingElevatedAction = nil
        switch action {
        case .install: await installMole()
        case .update: await updateMole()
        }
    }

    /// Called from NeedsAdminAccessView's primary button. On success,
    /// automatically retries the original install/update.
    func requestAdminViaPrivileges() async {
        guard let action = pendingElevatedAction else { return }
        isRequestingPrivilegesAccess = true
        privilegesRequestError = nil
        defer { isRequestingPrivilegesAccess = false }
        do {
            try await AdminAccess.requestTemporaryAdmin(
                reason: "MacMoleManager needs administrator rights to \(action.verb)."
            )
            await retryPendingElevatedAction()
        } catch {
            privilegesRequestError = error.localizedDescription
        }
    }

    /// `sudo -A -v` validates admin credentials via AskPassHelper's native dialog
    /// and caches a sudo ticket, without running `mole` itself as root. `mole
    /// update` then runs unprivileged in that same pty session and reuses the ticket.
    private func performElevatedUpdate() async throws -> String {
        let scriptPath = try AskPassHelper.write(reason: .update)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }
        let binaryPath = try await runner.resolveBinaryPath()
        let command = "export SUDO_ASKPASS=\(scriptPath.shellEscaped); sudo -A -v && \(binaryPath.shellEscaped) update"
        return try await PTYRunner().run(command: command)
    }

    /// Called from the admin password sheet. Stays open with a specific error
    /// (wrong password vs. not an admin account) on failure instead of just
    /// dismissing and re-prompting.
    func submitAdminPassword(_ password: String) async {
        isSubmittingAdminPassword = true
        adminPasswordError = nil
        defer { isSubmittingAdminPassword = false }
        do {
            updateOutput = try await runner.update(withAdminPassword: password)
            await refreshMoleVersion()
            isPromptingForAdminPassword = false
        } catch {
            adminPasswordError = Self.friendlyAdminError(for: error)
        }
    }

    func cancelAdminPasswordPrompt() {
        isPromptingForAdminPassword = false
        adminPasswordError = nil
    }

    private static func needsAdminPasswordPrompt(for error: Error) -> Bool {
        guard let description = (error as? LocalizedError)?.errorDescription else { return false }
        return description.contains("admin access denied") || description.contains("/dev/tty")
    }

    /// Translates sudo's own error wording so the sheet can tell "wrong password"
    /// apart from "this account isn't an admin".
    private static func friendlyAdminError(for error: Error) -> String {
        guard let description = (error as? LocalizedError)?.errorDescription else {
            return error.localizedDescription
        }
        if description.localizedCaseInsensitiveContains("incorrect password attempt")
            || description.localizedCaseInsensitiveContains("Sorry, try again") {
            return "That password wasn't accepted. Please try again."
        }
        if description.localizedCaseInsensitiveContains("is not in the sudoers file") {
            return "This account doesn't have administrator privileges."
        }
        if description.localizedCaseInsensitiveContains("a password is required") {
            return "No password was entered."
        }
        return description
    }

    func loadStatus() async {
        await runTask {
            self.status = try await self.runner.status()
        }
    }

    /// Entry point for the "Scan" button / typing a new path — treats
    /// `analyzeTargetPath` as a fresh root, discarding drill-down history.
    func runAnalysis() async {
        analyzeHistory = []
        await performAnalysis(path: analyzeTargetPath)
    }

    /// Drills into a folder row from the current scan (a fresh `mole analyze`
    /// call), pushing the current level onto history first.
    func navigateAnalysisInto(_ entry: MoleAnalysisEntry) async {
        guard entry.isDir == true, let path = entry.path else { return }
        if let currentAnalysis = analysis {
            analyzeHistory.append((path: analyzeTargetPath, analysis: currentAnalysis))
        }
        analyzeTargetPath = path
        await performAnalysis(path: path)
    }

    /// Pops the last level off history and restores it directly, no rescan needed.
    func navigateAnalysisBack() {
        guard let previous = analyzeHistory.popLast() else { return }
        analyzeTargetPath = previous.path
        analysis = previous.analysis
    }

    private func performAnalysis(path: String) async {
        await runTask {
            self.analysis = try await self.runner.analyze(path: path)
        }
    }

    func loadInstalledApps() async {
        await runTask {
            self.installedApps = try await self.runner.uninstallList()
        }
    }

    func selectApp(_ app: MoleAppEntry) async {
        selectedApp = app
        appLeftovers = []
        hasScannedLeftovers = false
        selectedLeftoverIDs = []
        await runTask(message: "Looking for \(app.name ?? "this app")'s leftover files…") {
            let found = AppLeftoverScanner.scan(
                appName: app.name ?? app.uninstallName ?? "",
                bundleIdentifier: app.bundleIdentifier,
                appPath: app.path
            )
            self.appLeftovers = found
            // Pre-check everything found; user unchecks anything they'd rather keep.
            self.selectedLeftoverIDs = Set(found.map(\.id))
            self.hasScannedLeftovers = true
        }
    }

    func toggleLeftoverSelection(_ item: AppLeftoverItem) {
        if selectedLeftoverIDs.contains(item.id) {
            selectedLeftoverIDs.remove(item.id)
        } else {
            selectedLeftoverIDs.insert(item.id)
        }
    }

    func selectAllLeftovers() {
        selectedLeftoverIDs = Set(appLeftovers.map(\.id))
    }

    func deselectAllLeftovers() {
        selectedLeftoverIDs.removeAll()
    }

    /// Trashes exactly the checked items — the .app bundle itself included, if
    /// still checked — natively, with no mole subcommand involved.
    func confirmUninstall(_ app: MoleAppEntry) async {
        let toDelete = appLeftovers.filter { selectedLeftoverIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        await runTask(message: "Moving selected files to the Trash…") {
            try AppLeftoverScanner.moveToTrash(toDelete)
            self.appLeftovers.removeAll { toDelete.contains($0) }
            self.selectedLeftoverIDs.removeAll()
            self.selectedApp = nil
            self.hasScannedLeftovers = false
        }
        await loadInstalledApps()
    }

    func runCleanDryRun() async {
        // ProcessOutputBuffer isn't a publisher, so this Task polls its current
        // text a few times a second to show mole's live output during the scan.
        let liveBuffer = ProcessOutputBuffer()
        let pollTask = Task {
            while !Task.isCancelled {
                self.cleanLiveOutput = liveBuffer.text
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { pollTask.cancel() }

        await runTask(message: "Scanning your Mac for cleanable files — this can take several minutes…") {
            let output = try await self.runner.cleanDryRun(liveOutput: liveBuffer)
            self.cleanDryRunOutput = output
            self.cleanReport = MoleReportParser.parse(output)
        }
        cleanLiveOutput = ""
    }

    func confirmClean() async {
        await runTask(message: "Deleting matched files — this can take a few minutes…") {
            self.cleanResultOutput = try await self.runner.cleanExecute()
            self.cleanDryRunOutput = nil
            self.cleanReport = .empty
        }
    }

    func runOptimizeDryRun() async {
        // Same live-polling pattern as `runCleanDryRun()` — see its comment.
        let liveBuffer = ProcessOutputBuffer()
        let pollTask = Task {
            while !Task.isCancelled {
                self.optimizeLiveOutput = liveBuffer.text
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { pollTask.cancel() }

        await runTask(message: "Scanning for optimizable memory/launch items — this can take a few minutes…") {
            let output = try await self.runner.optimizeDryRun(liveOutput: liveBuffer)
            self.optimizeDryRunOutput = output
            self.optimizeReport = MoleReportParser.parse(output)
        }
        optimizeLiveOutput = ""
    }

    func confirmOptimize() async {
        await runTask(message: "Optimizing…") {
            self.optimizeResultOutput = try await self.runner.optimizeExecute()
            self.optimizeDryRunOutput = nil
            self.optimizeReport = .empty
        }
    }

    func runPurgeDryRun() async {
        await runTask(message: "Scanning caches/logs/derived data for a deep purge — this can take several minutes…") {
            self.purgeDryRunOutput = try await self.runner.purgeDryRun()
        }
    }

    func confirmPurge() async {
        await runTask(message: "Purging…") {
            self.purgeResultOutput = try await self.runner.purgeExecute()
            self.purgeDryRunOutput = nil
        }
    }

    func runInstallerScan() async {
        await runTask(message: "Scanning Downloads, Desktop, and Documents for leftover installer files…") {
            self.installerLeftovers = InstallerScanner.scan()
            self.installerHasScanned = true
            self.selectedInstallerLeftoverIDs = []
            self.installerCleanupResultMessage = nil
        }
    }

    func loadHistory() async {
        await runTask(message: "Loading history…") {
            self.moleHistory = try await self.runner.history()
        }
    }

    /// Runs until cancelled by SwiftUI's `.task`, i.e. while Live Stats stays
    /// selected. Mole has no "watch" flag, so this polls `status --json` every few seconds.
    func runLiveStatsLoop() async {
        isLiveStatsRunning = true
        defer { isLiveStatsRunning = false }
        while !Task.isCancelled {
            do {
                liveStatus = try await runner.status()
                liveStatsErrorMessage = nil
                liveStatsLastUpdated = Date()
            } catch {
                liveStatsErrorMessage = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// Loads both config files fresh from disk — safe to call repeatedly, e.g.
    /// re-entering the Settings tab, in case Terminal `mole` or MoleUI changed either file.
    func loadSettings() {
        let savedWhitelist = Set(MoleConfigStore.loadWhitelistPatterns())
        // No file yet means Mole is running on its built-in defaults — show those
        // as already protected rather than an empty, misleading checklist.
        let effectiveWhitelist = savedWhitelist.isEmpty ? Set(MoleWhitelistCatalog.defaultPatterns) : savedWhitelist
        let catalogPatterns = Set(MoleWhitelistCatalog.items.map(\.expandedPattern))
        whitelistSelectedPatterns = effectiveWhitelist.intersection(catalogPatterns)
            .union(MoleWhitelistCatalog.alwaysProtectedPatterns)
        whitelistCustomPatterns = effectiveWhitelist.subtracting(catalogPatterns).sorted()
        purgePaths = MoleConfigStore.loadPurgePaths()
        hasLoadedSettings = true
        settingsSaveMessage = nil
    }

    func toggleWhitelistItem(_ item: WhitelistCatalogItem) {
        guard !item.isAlwaysProtected else { return }
        if whitelistSelectedPatterns.contains(item.expandedPattern) {
            whitelistSelectedPatterns.remove(item.expandedPattern)
        } else {
            whitelistSelectedPatterns.insert(item.expandedPattern)
        }
        settingsSaveMessage = nil
    }

    func addCustomWhitelistPattern(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !whitelistCustomPatterns.contains(trimmed) else { return }
        whitelistCustomPatterns.append(trimmed)
        settingsSaveMessage = nil
    }

    func removeCustomWhitelistPattern(_ pattern: String) {
        whitelistCustomPatterns.removeAll { $0 == pattern }
        settingsSaveMessage = nil
    }

    func addPurgePath(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !purgePaths.contains(trimmed) else { return }
        purgePaths.append(trimmed)
        settingsSaveMessage = nil
    }

    func removePurgePath(_ path: String) {
        purgePaths.removeAll { $0 == path }
        settingsSaveMessage = nil
    }

    /// Writes both config files synchronously — no subprocess involved, so no
    /// need to route through `runTask`'s busy overlay.
    func saveSettings() {
        do {
            try MoleConfigStore.saveWhitelistPatterns(Array(whitelistSelectedPatterns) + whitelistCustomPatterns)
            try MoleConfigStore.savePurgePaths(purgePaths)
            settingsSaveMessage = "Saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleInstallerSelection(_ item: InstallerLeftover) {
        if selectedInstallerLeftoverIDs.contains(item.id) {
            selectedInstallerLeftoverIDs.remove(item.id)
        } else {
            selectedInstallerLeftoverIDs.insert(item.id)
        }
    }

    func selectAllInstallerLeftovers() {
        selectedInstallerLeftoverIDs = Set(installerLeftovers.map(\.id))
    }

    func deselectAllInstallerLeftovers() {
        selectedInstallerLeftoverIDs.removeAll()
    }

    func confirmInstallerCleanup() async {
        let toDelete = installerLeftovers.filter { selectedInstallerLeftoverIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        await runTask(message: "Moving selected installer files to the Trash…") {
            try InstallerScanner.moveToTrash(toDelete)
            let freedBytes = toDelete.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let count = toDelete.count
            self.installerCleanupResultMessage = "Moved \(count) item\(count == 1 ? "" : "s") to the Trash — \(freedBytes.formattedBytes) freed."
            self.installerLeftovers.removeAll { toDelete.contains($0) }
            self.selectedInstallerLeftoverIDs.removeAll()
        }
    }

    /// Shared wrapper: sets isBusy/busyMessage, clears/reports errorMessage.
    private func runTask(message: String = "Working…", _ work: @escaping () async throws -> Void) async {
        busyMessage = message
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
