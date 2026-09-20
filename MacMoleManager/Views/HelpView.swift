//
//  HelpView.swift
//  MacStorageManager
//
//  Replaces the default "Help isn't available" Help-menu behavior with a
//  plain SwiftUI window. Opened via the Help menu's "MacMoleManager Help"
//  command — see MacStorageManagerApp.swift.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MacMoleManager Help")
                    .font(.title2).bold()

                Text("MacMoleManager is a native front end for Mole, a Mac storage and maintenance tool. Each tab below covers one thing Mole can do. Most tabs work the same way: Preview first to see what Mole found without changing anything, then apply the action once you're happy with the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 16) {
                    HelpSection(
                        systemImage: "gauge.with.dots.needle.50percent",
                        title: "System Status",
                        description: "A quick snapshot of the Mac: free disk space, memory pressure, and uptime, at a glance when you open the app."
                    )
                    HelpSection(
                        systemImage: "chart.pie",
                        title: "Analyze Disk Usage",
                        description: "Browse any folder to see what's using space inside it, largest first. Tap a folder to look inside it; use Back to step out again."
                    )
                    HelpSection(
                        systemImage: "trash",
                        title: "Uninstall an App",
                        description: "Pick an installed app to see its leftover files — caches, preferences, containers, and saved state — alongside the app itself. Choose which ones to remove and they all go to the Trash together, so nothing is deleted permanently without a chance to recover it."
                    )
                    HelpSection(
                        systemImage: "sparkles",
                        title: "Clean My Mac",
                        description: "Finds common cache and temporary files that are safe to remove, grouped by category with sizes. Preview shows exactly what would be cleaned; Clean Now removes it."
                    )
                    HelpSection(
                        systemImage: "gauge.with.dots.needle.67percent",
                        title: "Optimize",
                        description: "Looks for small performance issues — stale DNS/Spotlight caches, broken login items, apps worth closing to free up memory — and lists what it would fix. Items that need your attention are marked with a warning icon."
                    )
                    HelpSection(
                        systemImage: "flame",
                        title: "Deep Purge",
                        description: "A more thorough pass than Clean My Mac, reaching further into logs and developer build artifacts. Review the list carefully before purging — it goes deeper than the regular clean."
                    )
                    HelpSection(
                        systemImage: "shippingbox",
                        title: "Installer Cleanup",
                        description: "Looks in Downloads, Desktop, and Documents for leftover .dmg and .pkg installer files you likely don't need anymore, and lets you pick which ones to send to the Trash."
                    )
                    HelpSection(
                        systemImage: "clock.arrow.circlepath",
                        title: "History",
                        description: "A log of Mole's past clean, optimize, uninstall, and purge runs, plus every individual file that's actually been deleted along the way."
                    )
                    HelpSection(
                        systemImage: "waveform.path.ecg",
                        title: "Live Stats",
                        description: "The same health, CPU, memory, and disk numbers as System Status, but refreshed automatically every few seconds instead of once — plus top processes, battery, network, and uptime."
                    )
                    HelpSection(
                        systemImage: "gearshape",
                        title: "Settings",
                        description: "Pick which caches Clean My Mac is never allowed to remove, and which project folders Deep Purge should treat as its own."
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("About Full Disk Access")
                        .font(.headline)
                    Text("Some scans are incomplete without it. If you see a Full Disk Access banner, use its Open Settings button to grant access, then Re-check.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("For details on Mole itself and who built the pieces MacMoleManager is made from, see About MacMoleManager.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480, height: 520)
    }
}

private struct HelpSection: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout).bold()
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    HelpView()
}
