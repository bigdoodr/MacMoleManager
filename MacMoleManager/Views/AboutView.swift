//
//  AboutView.swift
//  MacStorageManager
//
//  Replaces the default macOS "About" panel so we have room for an
//  Acknowledgments section — this app exists because of the open-source
//  `mole` CLI it wraps, and the WKU-built tooling it replaces. Opened via
//  the app's About menu command (see MacStorageManagerApp.swift), which
//  routes to this instead of the standard orderFrontStandardAboutPanel.
//

import SwiftUI

struct AboutView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacMoleManager"
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2).bold()
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A native macOS front end for Mole, built for WKU's Mac fleet — uninstall apps and their leftovers, analyze disk usage, and clean, optimize, and purge storage without the Terminal.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Acknowledgments")
                    .font(.headline)

                CreditRow(
                    title: "Mole",
                    detail: "The open-source CLI this app wraps for scanning, cleaning, and optimizing — by tw93.",
                    link: "https://github.com/tw93/Mole"
                )
                CreditRow(
                    title: "MoleUI",
                    detail: "tw93's own GUI for Mole — a reference point for how this app groups and presents Mole's results."
                )
                CreditRow(
                    title: "Dan's Disk Management script",
                    detail: "The original bash-based tool for WKU's fleet that MacMoleManager grew out of and replaces.",
                    link: "https://github.com/dan-snelson/dialog-scripts/tree/main/Disk%20Usage"
                )
                CreditRow(
                    title: "swiftDialog",
                    detail: "The native dialog toolkit that powered Dan's script's UI — by Bart Reardon.",
                    link: "https://github.com/swiftDialog/swiftDialog"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("MacMoleManager is not affiliated with or endorsed by the Mole project. Mole is licensed under GPL-3.0.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CreditRow: View {
    let title: String
    let detail: String
    var link: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let link, let url = URL(string: link) {
                Link(title, destination: url)
                    .font(.callout).bold()
            } else {
                Text(title)
                    .font(.callout).bold()
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AboutView()
}
