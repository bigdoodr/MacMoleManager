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
import AppKit
import UniformTypeIdentifiers

struct UninstallView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false
    @State private var searchText = ""
    @State private var sortOption: SortOption = .name
    /// Direction of the current sort. Meaning depends on `sortOption` — see
    /// `sortDirectionLabel` — and resets to that field's natural default
    /// (A→Z, largest-first, newest-first) whenever the field changes.
    @State private var sortAscending = true
    /// Mole's `uninstall --list` has no install-date field at all, so this
    /// is read straight off the filesystem (the date each .app bundle was
    /// added to its containing folder — matches Finder's "Date Added"
    /// column) rather than anything Mole reports.
    @State private var installDates: [String: Date] = [:]

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case size = "Size"
        case installDate = "Install Date"
        var id: String { rawValue }
    }

    private var sortDirectionLabel: String {
        switch sortOption {
        case .name: return sortAscending ? "A → Z" : "Z → A"
        case .size: return sortAscending ? "Smallest First" : "Largest First"
        case .installDate: return sortAscending ? "Oldest First" : "Newest First"
        }
    }

    private var visibleApps: [MoleAppEntry] {
        let filtered: [MoleAppEntry]
        if searchText.isEmpty {
            filtered = vm.installedApps
        } else {
            filtered = vm.installedApps.filter { app in
                (app.name ?? "").localizedCaseInsensitiveContains(searchText)
                    || (app.bundleIdentifier ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOption {
        case .name:
            return filtered.sorted {
                let result = ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "")
                return sortAscending ? result == .orderedAscending : result == .orderedDescending
            }
        case .size:
            return filtered.sorted {
                sortAscending
                    ? $0.sizeBytesForSorting < $1.sizeBytesForSorting
                    : $0.sizeBytesForSorting > $1.sizeBytesForSorting
            }
        case .installDate:
            return filtered.sorted {
                let lhs = installDates[$0.id] ?? .distantPast
                let rhs = installDates[$1.id] ?? .distantPast
                return sortAscending ? lhs < rhs : lhs > rhs
            }
        }
    }

    var body: some View {
        // A plain HStack + Divider, not HSplitView. HSplitView is backed by
        // an AppKit NSSplitView, and this view already sits inside
        // NavigationSplitView's detail pane — itself NSSplitView-backed.
        // Nesting one NSSplitView inside another caused exactly the bug
        // Casey hit live: the two fought over column/divider geometry once
        // real content forced a resize (selecting an app populates the
        // preview pane, which has different intrinsic sizing than the
        // "No app selected" placeholder), and the whole window layout
        // collapsed, shoving the sidebar almost entirely off-screen. A
        // fixed-ratio HStack has no independent resize behavior to
        // conflict with the outer split view, so it can't reproduce this.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Under the old HSplitView, this pane's width was negotiated
                // by AppKit's split view and always had room to spare. The
                // new HStack pane has a narrower idealWidth (340pt), and
                // without any hints every child in this row shares shrink
                // priority equally — so once the Picker + two Buttons ask for
                // their natural width, SwiftUI compresses the "Installed
                // Apps" Text to make room, wrapping it character-by-character
                // instead of eliding. `.fixedSize()` opts the title out of
                // being compressed (it always renders at its ideal size), and
                // `.layoutPriority(1)` tells SwiftUI to shrink everything
                // else in this row first if space is still tight.
                HStack {
                    Text("Installed Apps")
                        .font(.title2)
                        .bold()
                        .fixedSize()
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    .onChange(of: sortOption) { _, newValue in
                        // Each field's natural default: alphabetical goes
                        // A→Z, but size/date default to the more useful
                        // "biggest thing to look at first" direction.
                        sortAscending = (newValue == .name)
                    }
                    Button {
                        sortAscending.toggle()
                    } label: {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    }
                    .help(sortDirectionLabel)
                    Button {
                        Task { await vm.loadInstalledApps() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search installed apps", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                List(visibleApps, selection: $vm.selectedApp) { app in
                    HStack(spacing: 10) {
                        AppIconView(path: app.path)
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
                }
                // `List`'s own click handling consumes the tap for its
                // selection binding before an `.onTapGesture` on the row
                // ever sees it, so fetching the preview from a tap gesture
                // never actually ran — react to the selection changing
                // instead, which fires reliably for both clicks and
                // keyboard arrow-key navigation.
                .onChange(of: vm.selectedApp) { _, newApp in
                    guard let newApp else { return }
                    Task { await vm.selectApp(newApp) }
                }
            }
            .padding(16)
            .frame(minWidth: 280, idealWidth: 340)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview").font(.title2).bold()

                if let selected = vm.selectedApp {
                    HStack(spacing: 10) {
                        AppIconView(path: selected.path, size: 40)
                        Text("Selected: \(selected.name ?? "—")")
                            .font(.headline)
                    }

                    // Every file found here is discovered natively by
                    // AppLeftoverScanner (Caches, Preferences, Containers,
                    // Saved Application State, Logs, etc.) rather than
                    // parsed from mole's output — mole's own uninstall
                    // preview is just a one-line summary with no per-file
                    // detail. This is the AppCleaner-style breakdown Casey
                    // asked for: every match gets its own checkbox, size,
                    // and reveal-in-Finder button.
                    if !vm.hasScannedLeftovers {
                        ContentUnavailableView {
                            Label("Looking for leftover files…", systemImage: "magnifyingglass")
                        }
                    } else if vm.appLeftovers.isEmpty {
                        ContentUnavailableView(
                            "Nothing found",
                            systemImage: "checkmark.circle",
                            description: Text("No app bundle or leftover files were found for \(selected.name ?? "this app").")
                        )
                    } else {
                        Text("Everything below is pre-selected — uncheck anything you'd like to keep.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Select All") { vm.selectAllLeftovers() }
                            Button("Deselect All") { vm.deselectAllLeftovers() }
                            Spacer()
                            Text("\(vm.selectedLeftoverIDs.count) of \(vm.appLeftovers.count) selected — \(vm.selectedLeftoversTotalBytes.formattedBytes)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        List(vm.appLeftovers) { item in
                            let isSelected = vm.selectedLeftoverIDs.contains(item.id)
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(item.category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.sizeBytes.formattedBytes)
                                    .foregroundStyle(.secondary)
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                                } label: {
                                    Image(systemName: "arrow.up.forward.square")
                                }
                                .buttonStyle(.borderless)
                                .help("Reveal in Finder")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { vm.toggleLeftoverSelection(item) }
                        }
                        .listStyle(.inset)

                        Button(role: .destructive) {
                            showConfirm = true
                        } label: {
                            Label("Move \(vm.selectedLeftoverIDs.count) Item\(vm.selectedLeftoverIDs.count == 1 ? "" : "s") to Trash…", systemImage: "trash")
                        }
                        .disabled(vm.selectedLeftoverIDs.isEmpty)
                        .confirmationDialog(
                            "Move \(vm.selectedLeftoverIDs.count) selected item\(vm.selectedLeftoverIDs.count == 1 ? "" : "s") to the Trash?",
                            isPresented: $showConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Move to Trash", role: .destructive) {
                                Task { await vm.confirmUninstall(selected) }
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No app selected",
                        systemImage: "trash",
                        description: Text("Pick an app on the left to see what would be removed.")
                    )
                }

                Spacer()
            }
            .padding(16)
            .frame(minWidth: 320, maxWidth: .infinity)
        }
        .task {
            if vm.installedApps.isEmpty { await vm.loadInstalledApps() }
            refreshInstallDates(for: vm.installedApps)
        }
        .onChange(of: vm.installedApps) { _, newApps in
            refreshInstallDates(for: newApps)
        }
    }

    private func refreshInstallDates(for apps: [MoleAppEntry]) {
        var dates: [String: Date] = [:]
        for app in apps {
            guard let path = app.path else { continue }
            let values = try? URL(fileURLWithPath: path)
                .resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            dates[app.id] = values?.addedToDirectoryDate ?? values?.creationDate
        }
        installDates = dates
    }
}

extension MoleAppEntry: Hashable {
    static func == (lhs: MoleAppEntry, rhs: MoleAppEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Reads an app's real .icns icon straight off disk via NSWorkspace — the
/// same icon Finder shows for that bundle — rather than a generic SF Symbol
/// placeholder. `NSWorkspace.icon(forFile:)` never returns nil; a bad or
/// missing path just falls back to the generic document icon on its own,
/// so there's no error case to handle here.
private struct AppIconView: View {
    let path: String?
    var size: CGFloat = 28

    var body: some View {
        // `icon(forFileType:)` (the string-based API, e.g. "app") was
        // deprecated in macOS 12 in favor of the UTType-based overload —
        // this only matters for the no-path fallback case, since
        // `icon(forFile:)` (used whenever a real path is known) is untouched.
        Image(nsImage: path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable()
            .frame(width: size, height: size)
    }
}
