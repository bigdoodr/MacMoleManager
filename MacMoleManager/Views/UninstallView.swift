//
//  UninstallView.swift
//  MacStorageManager
//
//  "Uninstall an App" mode: list apps, select one, preview leftovers, confirm.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UninstallView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showConfirm = false
    @State private var searchText = ""
    @State private var sortOption: SortOption = .name
    /// Meaning depends on `sortOption` — see `sortDirectionLabel` — and resets
    /// to that field's natural default whenever the field changes.
    @State private var sortAscending = true
    /// Mole's `uninstall --list` has no install-date field, so this is read
    /// straight off the filesystem (matches Finder's "Date Added" column).
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
        // Plain HStack + Divider, not HSplitView — nesting an AppKit NSSplitView
        // inside NavigationSplitView's own NSSplitView-backed detail pane made
        // the two fight over column geometry on resize and collapse the sidebar.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Without layoutPriority, the Picker + two Buttons take their natural
                // width first and SwiftUI compresses "Installed Apps" character-by-character.
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
                // React to selection change rather than a tap gesture — List's own
                // click handling consumes the tap before a row-level gesture sees it.
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

                    // Discovered natively by AppLeftoverScanner (Caches, Preferences,
                    // Containers, Logs, etc.) — mole's own uninstall preview is just a
                    // one-line summary with no per-file detail.
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
                                    FinderRevealHelper.reveal(URL(fileURLWithPath: item.path))
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
/// same icon Finder shows for that bundle. `icon(forFile:)` never returns nil;
/// a bad path just falls back to the generic document icon.
private struct AppIconView: View {
    let path: String?
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable()
            .frame(width: size, height: size)
    }
}
