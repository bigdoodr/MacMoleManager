//
//  MoleReportParser.swift
//  MacStorageManager
//
//  Clean/Optimize/Purge dry-run output has no `--json` form — it's plain text:
//
//    ➤ Category Name
//      → Item label · detail text (often ending in a size, e.g. "9 items, 408.6MB dry")
//      ◎ Warning-flavored item — same shape, different leading glyph
//        • further-indented lines nested under the item above
//
//    ======================================================================
//    Dry run complete - no changes made
//    Potential space: 1.46GB | Items: 103 | Categories: 5     (Clean only)
//    Would apply 3 optimizations                              (Optimize only)
//    Run without --dry-run to apply these changes
//    ======================================================================
//
//  Optimize's footer has no "key: value" pairs, just prose — footerNotes
//  captures it verbatim minus the "Potential space:" line.
//
//  Display parser only: mole's clean/optimize is all-or-nothing, so the
//  grouped UI here is read-only sectioning, not a partial-selection mechanism.
//

import Foundation

struct MoleReportItem: Identifiable {
    let id = UUID()
    let label: String
    /// Everything after the first " · " on the item's line, e.g.
    /// "9 items, 408.6MB dry" or "would clean" for items with no size at all.
    let detail: String
    var sizeBytes: Int64
    /// True for a "◎ " item (mole's own "needs attention" glyph) rather than
    /// a plain "→ " one — the view shows these with a warning treatment.
    let isWarning: Bool
    /// Further-indented lines under this item, e.g. the per-volume breakdown
    /// under "Xcode runtime volumes". Empty for the common case.
    let subDetails: [String]
}

struct MoleReportCategory: Identifiable {
    let id = UUID()
    let name: String
    var items: [MoleReportItem] // var: a post-parse pass back-fills sizes from nested detail lines
    var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var hasWarning: Bool { items.contains { $0.isWarning } }
}

struct MoleReportSummary {
    /// e.g. "1.46GB" — nil if the footer has no "Potential space:" line (Optimize never does).
    let potentialSpaceDisplay: String?
    let itemCount: Int?
    let categoryCount: Int?
    /// A callout worth surfacing as its own banner, e.g. "System caches need sudo…".
    let partialPreviewNote: String?
    /// Loose text printed before the first category header.
    let headerNotes: [String]
    /// Footer lines other than the structured "Potential space: … | Items: … | Categories: …" one.
    let footerNotes: [String]
    let categories: [MoleReportCategory]

    static let empty = MoleReportSummary(
        potentialSpaceDisplay: nil, itemCount: nil, categoryCount: nil,
        partialPreviewNote: nil, headerNotes: [], footerNotes: [], categories: []
    )
}

enum MoleReportParser {
    static func parse(_ raw: String) -> MoleReportSummary {
        let lines = raw.components(separatedBy: "\n")

        var headerNotes: [String] = []
        var footerNotes: [String] = []
        var partialPreviewNote: String?
        var categories: [MoleReportCategory] = []
        var currentCategoryName: String?
        var currentItems: [MoleReportItem] = []
        var currentSubDetails: [String] = []
        var sawFirstCategory = false
        var inFooter = false
        var potentialSpace: String?
        var itemCount: Int?
        var categoryCount: Int?

        // Nested detail lines only belong to an item once the next item/category line arrives.
        func flushPendingSubDetails() {
            guard !currentSubDetails.isEmpty, let last = currentItems.popLast() else {
                currentSubDetails = []
                return
            }
            currentItems.append(MoleReportItem(
                label: last.label, detail: last.detail,
                sizeBytes: last.sizeBytes, isWarning: last.isWarning,
                subDetails: currentSubDetails
            ))
            currentSubDetails = []
        }

        func flushCategory() {
            flushPendingSubDetails()
            if let name = currentCategoryName {
                categories.append(MoleReportCategory(name: name, items: currentItems))
            }
            currentCategoryName = nil
            currentItems = []
        }

        func addItem(from body: String, isWarning: Bool) {
            flushPendingSubDetails()
            let comps = body.components(separatedBy: " · ")
            let label = comps.first?.trimmingCharacters(in: .whitespaces) ?? body
            let detail = comps.count > 1
                ? comps.dropFirst().joined(separator: " · ").trimmingCharacters(in: .whitespaces)
                : ""
            currentItems.append(MoleReportItem(
                label: label, detail: detail,
                sizeBytes: extractSizeBytes(from: detail), isWarning: isWarning,
                subDetails: []
            ))
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("====") {
                inFooter = true
                continue
            }
            if inFooter {
                if trimmed.hasPrefix("Potential space:") {
                    for part in trimmed.components(separatedBy: "|") {
                        let kv = part.components(separatedBy: ":")
                        guard kv.count == 2 else { continue }
                        let key = kv[0].trimmingCharacters(in: .whitespaces)
                        let value = kv[1].trimmingCharacters(in: .whitespaces)
                        switch key {
                        case "Potential space": potentialSpace = value
                        case "Items": itemCount = Int(value)
                        case "Categories": categoryCount = Int(value)
                        default: break
                        }
                    }
                } else if !trimmed.localizedCaseInsensitiveContains("--dry-run") {
                    // Skips mole's "Run without --dry-run…" line; MoleReportView
                    // shows its own "Press <button>" instruction instead.
                    footerNotes.append(trimmed)
                }
                continue
            }

            // Must be checked before the "haven't seen a category yet" branch below,
            // or the first "➤ " line itself gets swallowed into headerNotes and
            // sawFirstCategory never flips true.
            if trimmed.hasPrefix("➤ ") {
                flushCategory()
                currentCategoryName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                sawFirstCategory = true
                continue
            }

            // Anything before the first category is kept as loose header text.
            if !sawFirstCategory {
                if trimmed.localizedCaseInsensitiveContains("need sudo") {
                    partialPreviewNote = trimmed
                } else if trimmed != "Clean Your Mac" && trimmed != "Optimize"
                            && !trimmed.hasPrefix("Dry Run Mode") {
                    // Strip the item-style "→ "/"◎ " bullet Optimize's own banner uses.
                    var note = trimmed
                    for prefix in ["→ ", "◎ "] where note.hasPrefix(prefix) {
                        note = String(note.dropFirst(prefix.count))
                    }
                    if !note.uppercased().hasPrefix("DRY RUN MODE") {
                        headerNotes.append(note)
                    }
                }
                continue
            }

            if trimmed.hasPrefix("→ ") {
                addItem(from: String(trimmed.dropFirst(2)), isWarning: false)
                continue
            }

            if trimmed.hasPrefix("◎ ") {
                addItem(from: String(trimmed.dropFirst(2)), isWarning: true)
                continue
            }

            // Anything else inside a category is a nested detail line under the last item.
            currentSubDetails.append(trimmed)
        }
        flushCategory()

        // Some items carry no size on their own line — it's in the first nested detail line.
        for ci in categories.indices {
            for ii in categories[ci].items.indices {
                if categories[ci].items[ii].sizeBytes == 0,
                   let firstSub = categories[ci].items[ii].subDetails.first {
                    categories[ci].items[ii].sizeBytes = extractSizeBytes(from: firstSub)
                }
            }
        }

        return MoleReportSummary(
            potentialSpaceDisplay: potentialSpace,
            itemCount: itemCount,
            categoryCount: categoryCount,
            partialPreviewNote: partialPreviewNote,
            headerNotes: headerNotes,
            footerNotes: footerNotes,
            categories: categories
        )
    }

    private static func extractSizeBytes(from text: String) -> Int64 {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB|B)\b"#) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numberRange]) else { return 0 }

        switch text[unitRange].uppercased() {
        case "B": return Int64(value)
        case "KB": return Int64(value * 1_024)
        case "MB": return Int64(value * 1_024 * 1_024)
        case "GB": return Int64(value * 1_024 * 1_024 * 1_024)
        case "TB": return Int64(value * 1_024 * 1_024 * 1_024 * 1_024)
        default: return 0
        }
    }
}
