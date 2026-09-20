//
//  SettingsView.swift
//  MacStorageManager
//
//  Editor for the two Mole config files otherwise only reachable through
//  `mole clean --whitelist` (a raw-terminal checklist) or `mole purge --paths`
//  (drops into vim) — see MoleConfigStore.swift. Reads/writes
//  ~/.config/mole/whitelist and ~/.config/mole/purge_paths directly.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var newWhitelistPath = ""
    @State private var newPurgePath = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                whitelistSection
                Divider()
                purgePathsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if !vm.hasLoadedSettings { vm.loadSettings() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.title2).bold()
                Text("Controls what Clean My Mac and Deep Purge are allowed to touch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button("Save") { vm.saveSettings() }
                    .keyboardShortcut("s", modifiers: .command)
                if let message = vm.settingsSaveMessage {
                    Text(message).font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Whitelist

    private var whitelistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protected from Clean My Mac")
                .font(.headline)
            Text("Checked items are never removed by Clean My Mac. A few are always protected by Mole itself, so they're checked and can't be turned off.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(WhitelistCategory.allCases, id: \.self) { category in
                let items = MoleWhitelistCatalog.items.filter { $0.category == category }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.displayName)
                            .font(.caption).bold()
                            .foregroundStyle(.secondary)
                        ForEach(items) { item in
                            Toggle(isOn: Binding(
                                get: { vm.whitelistSelectedPatterns.contains(item.expandedPattern) },
                                set: { _ in vm.toggleWhitelistItem(item) }
                            )) {
                                HStack(spacing: 6) {
                                    Text(item.name).font(.callout)
                                    if item.isAlwaysProtected {
                                        Text("Always protected")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(item.isAlwaysProtected)
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }

            customWhitelistPatterns
        }
    }

    private var customWhitelistPatterns: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Other Protected Paths")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
            Text("Anything already in Mole's whitelist file that isn't one of the items above, or a path you add yourself.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ForEach(vm.whitelistCustomPatterns, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        vm.removeCustomWhitelistPattern(pattern)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("/path/to/protect/*", text: $newWhitelistPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWhitelistPath)
                Button("Add", action: addWhitelistPath)
                    .disabled(newWhitelistPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addWhitelistPath() {
        vm.addCustomWhitelistPattern(newWhitelistPath)
        newWhitelistPath = ""
    }

    // MARK: - Purge Paths

    private var purgePathsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deep Purge Project Directories")
                .font(.headline)
            Text("Folders Deep Purge treats as project directories worth cleaning build artifacts from. Supports ~ for your home folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if vm.purgePaths.isEmpty {
                Text("No custom paths — Deep Purge uses its own built-in discovery.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(vm.purgePaths, id: \.self) { path in
                HStack {
                    Text(path)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        vm.removePurgePath(path)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("~/Projects", text: $newPurgePath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPurgePathField)
                Button("Add", action: addPurgePathField)
                    .disabled(newPurgePath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addPurgePathField() {
        vm.addPurgePath(newPurgePath)
        newPurgePath = ""
    }
}
