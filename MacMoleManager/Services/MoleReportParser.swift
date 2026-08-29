//
//  MoleReportParser.swift
//  MacStorageManager
//
//  Clean/Optimize/Purge dry-run output has no `--json` form — it's plain
//  text formatted for a terminal. Confirmed live against a real
//  `mole clean --dry-run` run and a real `mole optimize --dry-run` run —
//  the two share the same category convention but differ in the details:
//
//    ➤ Category Name
//      → Item label · detail text (often ending in a size for Clean, e.g.
//        "9 items, 408.6MB dry" — Optimize's items are mostly pass/fail
//        status text with no size at all, e.g. "DNS cache flushed")
//      ◎ Warning-flavored item — same shape as a "→ " item (Optimize uses
//        this for things needing attention, e.g. "Broken login item: Ice
//        (app not found)"), just a different leading glyph
//        • or further-indented lines — extra detail nested under the item
//          above (e.g. Clean's Xcode runtime volumes per-volume breakdown)
//
//    ======================================================================
//    Dry run complete - no changes made                      (Clean's wording)
//    Potential space: 1.46GB | Items: 103 | Categories: 5     (Clean only)
//    Would apply 3 optimizations                              (Optimize only)
//    12 unchanged | 3 skipped | 1 unavailable | 1 need attention | 1 failed
//    Run without --dry-run to apply these changes
//    ======================================================================
//
//  Optimize's footer has no "key: value" pairs at all — just prose lines —
//  so `footerNotes` captures the footer verbatim (minus the "Potential
//  space:" line, which gets its own structured fields) rather than trying
//  to parse a shape that doesn't exist for every command.
//
//  Everything before the first "➤ " category header (whitelist info, the
//  "system caches need sudo" note, free-space/RAM/uptime line) is kept as
//  loose header notes rather than discarded, since some of it — particularly
//  the sudo note — is worth surfacing to explain why a preview might look
//  partial.
//
//  This is a *display* parser only. Mole has no flag to clean/optimize just
//  one category or item — `mole clean`/`mole optimize` is all-or-nothing —
//  so the grouped UI built from this is read-only sectioning to match
//  MoleUI's presentation, not a partial-selection mechanism. (Real per-item
//  selection would need mole's `--whitelist` support wired up, which is a
//  separate, still-pending piece of work.)
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
    // `var`, not `let`: the post-parse pass below back-fills a size for
    // items (like "Xcode runtime volumes") whose only size figure lives in
    // a nested detail line rather than on the item's own line — mutating
    // `categories[ci].items[ii].sizeBytes` needs `items` itself settable.
    var items: [MoleReportItem]
    var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var hasWarning: Bool { items.contains { $0.isWarning } }
}

struct MoleReportSummary {
    /// e.g. "1.46GB" — nil if the footer's "Potential space:" line wasn't
    /// found (Optimize's footer has no such line at all — see the file
    /// comment — so this is nil there by design, not a parse failure).
    let potentialSpaceDisplay: String?
    let itemCount: Int?
    let categoryCount: Int?
    /// A specific callout worth surfacing on its own — e.g. "System caches
    /// need sudo, run sudo -v && mo clean --dry-run for full preview" — so
    /// the UI can show it as a banner rather than burying it in headerNotes.
    let partialPreviewNote: String?
    /// Everything else printed before the first category header (whitelist
    /// pattern list, free-space line) — shown as loose supporting text.
    let headerNotes: [String]
    /// Footer lines that aren't the structured "Potential space: … | Items:
    /// … | Categories: …" line — e.g. Optimize's "Would apply 3
    /// optimizations" and "12 unchanged | 3 skipped | …" summary.
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

        // Moves any nested detail lines collected since the last item onto
        // that item, since they're only known to belong to it once the
        // *next* item (or category) line arrives.
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

        // Shared by "→ " and "◎ " items — same "label · detail" shape,
        // just a different leading glyph and warning flag.
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
                    // Skips mole's own "Run without --dry-run to apply these
                    // changes" line — that's a Terminal instruction, and
                    // this is a GUI app with its own "Clean Now"/"Optimize
                    // Now" button, so surfacing a CLI command here would
                    // just confuse someone who's never touched Terminal.
                    // MoleReportView prints its own "Press <button> to apply
                    // these changes" line in its place instead.
                    footerNotes.append(trimmed)
                }
                continue
            }

            // "➤ " is checked unconditionally, before the "haven't seen a
            // category yet" branch below — checking that branch first was a
            // bug: it swallowed the very first "➤ " line itself into
            // headerNotes (since sawFirstCategory was still false when that
            // line arrived), which meant `sawFirstCategory` never actually
            // flipped true and every single line for the rest of the file —
            // every real category — fell into the header branch forever.
            if trimmed.hasPrefix("➤ ") {
                flushCategory()
                currentCategoryName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                sawFirstCategory = true
                continue
            }

            // Anything else before the first category (whitelist info, the
            // "system caches need sudo" note, Optimize's own "→ DRY RUN
            // MODE, No files will be modified" banner) is kept as loose
            // header text rather than parsed as an item.
            if !sawFirstCategory {
                if trimmed.localizedCaseInsensitiveContains("need sudo") {
                    partialPreviewNote = trimmed
                } else if trimmed != "Clean Your Mac" && trimmed != "Optimize"
                            && !trimmed.hasPrefix("Dry Run Mode") {
                    // Optimize's own banner line arrives as "→ DRY RUN MODE,
                    // No files will be modified" — the "→ " here is just
                    // part of the same generic-bullet convention items use,
                    // not a real item, so strip it before keeping the line
                    // as a header note (stripping "◎ " too, on the off
                    // chance a future command opens with a warning glyph).
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

            // Anything else while inside a category is a nested detail line
            // under whichever item came last (e.g. the Xcode runtime volume
            // breakdown lines).
            currentSubDetails.append(trimmed)
        }
        flushCategory()

        // Items like "Xcode runtime volumes · 3 unused, 16 in use" carry no
        // size on their own line — the real number is in the first nested
        // detail line ("Runtime volumes total: 57KB …") instead.
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
