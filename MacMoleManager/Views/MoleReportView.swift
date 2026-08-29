//
//  MoleReportView.swift
//  MacStorageManager
//
//  Shared MoleUI-style collapsible rendering for any MoleReportSummary —
//  originally built for Clean, factored out here so Optimize (and Purge,
//  eventually) get the same grouped presentation without duplicating this
//  layout. Each mode's own View embeds this for its parsed report and adds
//  only what's specific to it (its own action button, its own live-output
//  view while scanning, its own raw-output disclosure).
//

import SwiftUI

struct MoleReportView: View {
    let report: MoleReportSummary
    /// The mode's own action button label ("Clean Now", "Optimize Now") —
    /// shown as "Press <label> to apply these changes" in place of mole's
    /// own "Run without --dry-run…" line, which MoleReportParser strips
    /// since it's a Terminal instruction that doesn't apply to a GUI app.
    /// Pass nil to skip this line entirely (e.g. a mode with no apply step).
    var applyActionLabel: String? = nil
    @State private var collapsedCategoryIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryHeader

            ForEach(report.categories) { category in
                categorySection(category)
            }
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if report.potentialSpaceDisplay != nil || report.itemCount != nil {
                HStack(spacing: 16) {
                    if let space = report.potentialSpaceDisplay {
                        Label(space + " potential", systemImage: "arrow.down.circle")
                            .font(.headline)
                    }
                    if let items = report.itemCount {
                        Text("\(items) item\(items == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    if let cats = report.categoryCount {
                        Text("\(cats) categor\(cats == 1 ? "y" : "ies")")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Optimize's footer has no "Potential space:"-style structured
            // line at all — just prose ("Would apply 3 optimizations", "12
            // unchanged | 3 skipped | …") — shown here verbatim instead.
            ForEach(report.footerNotes, id: \.self) { note in
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let applyActionLabel, !report.categories.isEmpty {
                Text("Press \(applyActionLabel) to apply these changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let note = report.partialPreviewNote {
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if !report.headerNotes.isEmpty {
                DisclosureGroup("Scan details") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(report.headerNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: MoleReportCategory) -> some View {
        let isCollapsed = collapsedCategoryIDs.contains(category.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isCollapsed {
                    collapsedCategoryIDs.remove(category.id)
                } else {
                    collapsedCategoryIDs.insert(category.id)
                }
            } label: {
                HStack {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(category.name)
                        .font(.headline)
                    if category.hasWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if category.totalSizeBytes > 0 {
                        Text(category.totalSizeBytes.formattedBytes)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(category.items) { item in
                        itemRow(item)
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, 6)
            }

            Divider()
        }
    }

    @ViewBuilder
    private func itemRow(_ item: MoleReportItem) -> some View {
        if item.subDetails.isEmpty {
            itemRowLabel(item)
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.subDetails, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } label: {
                itemRowLabel(item)
            }
        }
    }

    @ViewBuilder
    private func itemRowLabel(_ item: MoleReportItem) -> some View {
        HStack(alignment: .top) {
            if item.isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .foregroundStyle(item.isWarning ? .orange : .primary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.sizeBytes > 0 {
                Text(item.sizeBytes.formattedBytes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
