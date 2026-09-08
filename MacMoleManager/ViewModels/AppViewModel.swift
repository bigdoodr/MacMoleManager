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
    /// What the busy overlay says while `isBusy` — set per action rather
    /// than derived from `selectedMode`, since e.g. Clean's dry run and its
    /// real run are both on the Clean tab but take very different messages.
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

    // Status
    @Published var status: MoleStatus?

    // Analyze
    @Published var analysis: MoleAnalysis?
    @Published var analyzeTargetPath = NSHomeDirectory()
    /// Previously-scanned levels, so navigating back doesn't need a rescan.
    /// `mole analyze` only reports one directory level per call, so drilling
    /// into a subfolder always costs a fresh scan going forward — but going
    /// back can just replay what we already have.
    @Published private(set) var analyzeHistory: [(path: String, analysis: MoleAnalysis)] = []

    var canNavigateAnalysisBack: Bool { !analyzeHistory.isEmpty }

    // Uninstall
    @Published var installedApps: [MoleAppEntry] = []
    @Published var selectedApp: MoleAppEntry?
    /// AppCleaner-style per-file leftover breakdown for the selected app —
    /// found natively via AppLeftoverScanner rather than mole's `uninstall`
    /// preview. Confirmed live (both `--dry-run` output and `--help`) that
    /// mole only ever prints a one-line "Matched N app(s)" summary with no
    /// way to list individual matched paths, so getting AppCleaner's
    /// granular per-file checklist means finding those files ourselves —
    /// see AppLeftoverScanner.swift.
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
    /// `cleanDryRunOutput` parsed into MoleUI-style collapsible sections —
    /// see MoleReportParser.swift. Read-only grouping; mole has no per-item
    /// clean flag, so "Clean Now" still runs everything the dry run found.
    @Published var cleanReport: MoleReportSummary = .empty
    /// mole's raw stdout for the *in-progress* dry-run scan, updated a few
    /// times a second while it runs — see `runCleanDryRun()`. The scan can
    /// take several minutes on a full disk, so this lets CleanView show
    /// mole's own output scrolling by instead of a bare spinner the whole
    /// time. Cleared once the scan finishes (the finished, parsed result
    /// lives in `cleanReport`/`cleanDryRunOutput` from that point on).
    @Published var cleanLiveOutput = ""

    // Optimize
    @Published var optimizeDryRunOutput: String?
    @Published var optimizeResultOutput: String?
    /// Same grouped-sections treatment as `cleanReport` — see
    /// MoleReportParser.swift.
    @Published var optimizeReport: MoleReportSummary = .empty
    /// Same live-while-scanning treatment as `cleanLiveOutput`.
    @Published var optimizeLiveOutput = ""

    // Purge
    @Published var purgeDryRunOutput: String?
    @Published var purgeResultOutput: String?

    // Installer cleanup — a native FileManager scan (InstallerScanner), not
    // a wrapped mole subcommand. `mole installer` turned out to be a real
    // interactive terminal UI rather than a plain-text preview, so it can't
    // be captured through Process/Pipe — see InstallerScanner.swift.
    @Published var installerLeftovers: [InstallerLeftover] = []
    @Published var installerHasScanned = false
    @Published var selectedInstallerLeftoverIDs: Set<UUID> = []
    @Published var installerCleanupResultMessage: String?

    // History
    @Published var moleHistory: MoleHistory?

    // Live Stats — a continuously-refreshing `mole status --json`, distinct
    // from the one-shot `status` above so a slow/failing poll here can't
    // stomp on the System Status tab's own state (or trigger the app-wide
    // busy overlay/error banner every few seconds while this tab is open).
    @Published var liveStatus: MoleStatus?
    @Published var isLiveStatsRunning = false
    @Published var liveStatsErrorMessage: String?
    @Published var liveStatsLastUpdated: Date?

    // Settings — native editing of Mole's own on-disk whitelist and
    // purge_paths config files, not a wrapped mole subcommand. Both
    // `mole clean --whitelist` and `mole purge --paths` are genuine
    // interactive-only experiences (confirmed live: a raw-terminal
    // checklist, and dropping into vim) — see MoleConfigStore.swift.
    @Published var whitelistSelectedPatterns: Set<String> = []
    /// Anything already in the saved whitelist file that isn't one of the
    /// catalog rows in MoleWhitelistCatalog — either a path the user (or
    /// Mole's own interactive manager) added by hand, or one of the a
    /// handful of DEFAULT_WHITELIST_PATTERNS entries that don't map onto a
    /// single catalog row (a broader glob than any one item covers).
    /// Preserved verbatim rather than dropped, so saving from Settings
    /// never silently un-protects something.
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
        }
    }

    func refreshMoleVersion() async {
        moleVersion = try? await runner.version()
    }

    /// Runs Mole's own installer (not a vendored binary) so the app tracks
    /// Mole's release cadence. On success, immediately loads status so the
    /// rest of the UI has something to show right away.
    ///
    /// Primary path is `runner.install()` — a plain, promptless run that
    /// works whenever install.sh never needs to elevate. Confirmed live: on
    /// a Mac that's never had `/usr/local/bin` created (no prior Homebrew or
    /// Xcode Command Line Tools install), install.sh decides it needs sudo
    /// and its lock-reauthentication step reads/writes `/dev/tty` directly —
    /// something a Process/Pipe child has none of, so it fails outright with
    /// "/dev/tty: Device not configured" rather than a permission error. If
    /// that happens, fall back to `performElevatedInstall()`, the same
    /// real-pty-plus-native-dialog approach `updateMole()` already uses for
    /// its own /dev/tty problem.
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
            errorMessage = error.localizedDescription
        }
    }

    /// Pre-authenticates via `sudo -A -v` through AskPassHelper's native
    /// dialog (Touch ID first, if configured), then runs Mole's install
    /// script in that same real pty session — install.sh's own internal
    /// sudo calls (`needs_sudo`/`maybe_sudo`/its lock reauthentication step)
    /// then find an already-warm ticket and never need to prompt, or touch
    /// `/dev/tty`, again. Mirrors `performElevatedUpdate()` below exactly,
    /// just running the installer instead of `mole update`.
    private func performElevatedInstall() async throws -> String {
        let scriptPath = try AskPassHelper.write(reason: .install)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }
        let command = "export SUDO_ASKPASS=\(scriptPath.shellEscaped); sudo -A -v && \(MoleRunner.installScriptCommand)"
        return try await PTYRunner().run(command: command)
    }

    /// `mo update` — moves an already-installed Mole forward to the latest
    /// stable release, same cadence the standalone CLI itself would use.
    ///
    /// Primary path (being live-tested): `performElevatedUpdate()`, which
    /// runs `sudo -A -v && mole update` inside one real pty session via
    /// PTYRunner/AskPassHelper — see the doc comments on those two files.
    /// If that throws, and the install turns out to be Homebrew-managed,
    /// fall back to `runner.updateViaHomebrew()` (already confirmed working
    /// standalone) rather than surfacing a regression for the one case
    /// that was already fixed. The old SecureField/`sudo -S` admin-password
    /// flow below (`submitAdminPassword`, `update(withAdminPassword:)`,
    /// `needsAdminPasswordPrompt`/`friendlyAdminError`) is intentionally
    /// left in place, just unreached from here — an easy revert if the PTY
    /// path doesn't pan out on first live test.
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
                    errorMessage = error.localizedDescription
                    return
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    /// `sudo -A -v` validates admin credentials via AskPassHelper's native
    /// password dialog (Touch ID first, if configured) and caches a sudo
    /// ticket — it does NOT run `mole` itself as root. `mole update` then
    /// runs unprivileged in that same pty session, so any admin-requiring
    /// sub-operation it performs internally (including a Homebrew-managed
    /// `brew upgrade`) uses that already-warmed ticket itself, rather than
    /// this app running mole (or brew) as root directly.
    private func performElevatedUpdate() async throws -> String {
        let scriptPath = try AskPassHelper.write(reason: .update)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }
        let binaryPath = try await runner.resolveBinaryPath()
        let command = "export SUDO_ASKPASS=\(scriptPath.shellEscaped); sudo -A -v && \(binaryPath.shellEscaped) update"
        return try await PTYRunner().run(command: command)
    }

    /// Called from the admin password sheet. Runs `sudo mole update`
    /// directly with the entered password rather than trying to pre-warm
    /// sudo's cache in a separate process — see the doc comment on
    /// `MoleRunner.update(withAdminPassword:)` for why. Stays open with a
    /// specific error (wrong password vs. not an admin account) on failure
    /// instead of just dismissing and re-prompting.
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

    /// sudo's own wording for these two failure modes is unambiguous enough
    /// to translate directly, so the sheet can tell "wrong password" apart
    /// from "this account isn't an admin" instead of just re-prompting blind.
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
    /// whatever's in `analyzeTargetPath` as a fresh root, discarding any
    /// drill-down history from a previous browse.
    func runAnalysis() async {
        analyzeHistory = []
        await performAnalysis(path: analyzeTargetPath)
    }

    /// Drills into a folder row from the current scan. Mole has no notion of
    /// a recursive tree in one call, so this is a genuine new `mole analyze`
    /// invocation — but the current level gets pushed onto history first so
    /// `navigateAnalysisBack()` can return to it without rescanning.
    func navigateAnalysisInto(_ entry: MoleAnalysisEntry) async {
        guard entry.isDir == true, let path = entry.path else { return }
        if let currentAnalysis = analysis {
            analyzeHistory.append((path: analyzeTargetPath, analysis: currentAnalysis))
        }
        analyzeTargetPath = path
        await performAnalysis(path: path)
    }

    /// Pops the last level off history and restores it directly — no rescan,
    /// since we already have that level's results.
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
            // Pre-check everything found, matching AppCleaner's default —
            // the user unchecks anything they'd rather keep instead of
            // having to hunt down and check every item themselves.
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

    /// Trashes exactly the checked items — the .app bundle itself included,
    /// if it's still checked — entirely natively (no mole subcommand
    /// involved), so what's shown selected in the UI is exactly what gets
    /// removed.
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
        // mole prints its whole report to stdout as it scans — MoleRunner
        // already drains that continuously to avoid the pipe-buffer deadlock
        // (see its doc comments), so mirroring the same chunks into a second
        // buffer here costs nothing extra and lets the view show mole's
        // output live instead of a bare spinner for however long a full-disk
        // scan takes. Polled rather than pushed: `ProcessOutputBuffer` is a
        // plain thread-safe buffer, not a publisher, so this Task just reads
        // its current text a few times a second while the scan is in flight.
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

    /// Runs until the calling `.task` is cancelled by SwiftUI — i.e. for as
    /// long as the Live Stats tab stays selected. Every cycle shells out to
    /// `mole status --json` again; there's no "watch" flag Mole supports for
    /// this, so polling a few seconds apart is the only way to get a
    /// refreshing dashboard rather than a one-shot snapshot.
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

    /// Loads both config files fresh from disk. Safe to call more than once
    /// (e.g. re-entering the Settings tab) — always reflects whatever is
    /// currently on disk rather than stale in-memory state, since Terminal
    /// `mole` or MoleUI could have changed either file since MMM last read it.
    func loadSettings() {
        let savedWhitelist = Set(MoleConfigStore.loadWhitelistPatterns())
        // No file yet means Mole is running on its own built-in defaults —
        // show those as already protected rather than an empty, misleading
        // checklist.
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

    /// Writes both config files. Plain synchronous FileManager calls (no
    /// `mole` subprocess involved), so unlike the rest of this view model
    /// there's no need to route this through `runTask`'s busy overlay.
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

    /// Shared wrapper: sets isBusy/busyMessage, clears/reports errorMessage,
    /// keeps each call site down to one line instead of repeating do/catch
    /// everywhere.
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
