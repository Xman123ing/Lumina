import Foundation
import SQLite3

@MainActor
final class SQLiteDictionaryStore {
    static let shared = SQLiteDictionaryStore()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent("Lumina/dictionaries", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        dbPath = dir.appendingPathComponent("ecdict.sqlite3").path
        installBundledDatabaseIfNeeded()
        openDatabase()
        createSchemaIfNeeded()
    }

    var databasePath: String { dbPath }

    func entryCount() -> Int {
        let sql = "SELECT COUNT(*) FROM entries;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    func lookup(term: String) -> DictionaryEntry? {
        let key = normalize(term)
        guard !key.isEmpty else { return nil }

        let sql = """
        SELECT word, phonetic_us, phonetic_uk, definition
        FROM entries
        WHERE lower(word) = ?
        LIMIT 1
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readEntry(stmt: stmt)
    }

    func search(term: String, limit: Int = 10) -> [DictionaryEntry] {
        let key = normalize(term)
        guard !key.isEmpty else { return [] }

        let sql = """
        SELECT word, phonetic_us, phonetic_uk, definition
        FROM entries
        WHERE lower(word) LIKE ? OR lower(word) LIKE ?
        ORDER BY
            CASE WHEN lower(word) LIKE ? THEN 0 ELSE 1 END,
            length(word),
            word
        LIMIT ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        let prefix = "\(key)%"
        let contains = "%\(key)%"
        sqlite3_bind_text(stmt, 1, prefix, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, contains, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, prefix, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(limit))

        var rows: [DictionaryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = readEntry(stmt: stmt) {
                rows.append(row)
            }
        }
        return rows
    }

    func importFromTSV(fileURL: URL) throws {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }

        let insert = "INSERT OR REPLACE INTO entries(word, phonetic_us, phonetic_uk, definition) VALUES(?, ?, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        for line in lines {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { continue }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, parts[0], -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, parts[1], -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, parts[2], -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, parts[3], -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func createSchemaIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS entries(
            word TEXT PRIMARY KEY,
            phonetic_us TEXT NOT NULL DEFAULT '',
            phonetic_uk TEXT NOT NULL DEFAULT '',
            definition TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_entries_word ON entries(word);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func installBundledDatabaseIfNeeded() {
        let fm = FileManager.default
        guard let bundledURL = Bundle.module.url(forResource: "builtin_dictionary", withExtension: "sqlite3") else {
            return
        }

        let localExists = fm.fileExists(atPath: dbPath)
        if !localExists {
            try? fm.copyItem(at: bundledURL, to: URL(fileURLWithPath: dbPath))
            return
        }

        let localCount = countEntries(atPath: dbPath)
        // Replace old/small local DB with bundled large dictionary.
        if localCount < 50_000 {
            let tmpBackup = dbPath + ".backup"
            try? fm.removeItem(atPath: tmpBackup)
            try? fm.copyItem(atPath: dbPath, toPath: tmpBackup)
            try? fm.removeItem(atPath: dbPath)
            do {
                try fm.copyItem(at: bundledURL, to: URL(fileURLWithPath: dbPath))
            } catch {
                // Restore on failure.
                try? fm.removeItem(atPath: dbPath)
                try? fm.copyItem(atPath: tmpBackup, toPath: dbPath)
            }
            try? fm.removeItem(atPath: tmpBackup)
        }
    }

    private func countEntries(atPath path: String) -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM entries;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func readEntry(stmt: OpaquePointer?) -> DictionaryEntry? {
        guard
            let wordC = sqlite3_column_text(stmt, 0),
            let defC = sqlite3_column_text(stmt, 3)
        else { return nil }

        let word = String(cString: wordC)
        let us = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let uk = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        let parsed = parseDefinitions(String(cString: defC))

        return DictionaryEntry(
            term: word,
            phoneticUS: us,
            phoneticUK: uk,
            definitions: parsed.primary,
            englishDefinitions: parsed.english
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDefinitions(_ raw: String) -> (primary: [String], english: [String]) {
        // Normalize separators from ECDICT fields.
        let replaced = raw
            .replacingOccurrences(of: "|", with: "\n")
            .replacingOccurrences(of: "/", with: "\n")
            .replacingOccurrences(of: "；", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")

        let lines = replaced
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var primary: [String] = []
        var english: [String] = []

        for line in lines {
            let expanded = expandCommaMeanings(line)
            for piece in expanded {
                let cleaned = cleanDefinition(piece)
                guard !cleaned.isEmpty else { continue }
                let splitLines = splitMixedPartOfSpeechLine(cleaned)
                for splitLine in splitLines {
                    if containsCJK(splitLine) {
                        primary.append(splitLine)
                    } else {
                        english.append(splitLine)
                    }
                }
            }
        }

        primary = mergeByPartOfSpeech(deduplicate(primary))
        english = mergeByPartOfSpeech(deduplicate(english))
        primary = sortByPartOfSpeechPriority(primary)
        english = sortByPartOfSpeechPriority(english)

        return (Array(primary.prefix(10)), Array(english.prefix(10)))
    }

    private func cleanDefinition(_ line: String) -> String {
        var out = line
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while out.contains("  ") {
            out = out.replacingOccurrences(of: "  ", with: " ")
        }
        if out.count > 140 {
            out = String(out.prefix(140)) + "..."
        }
        return out
    }

    private func containsCJK(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private var partOfSpeechPrefixes: [String] {
        [
            "n.", "v.", "vt.", "vi.", "adj.", "a.", "adv.", "ad.", "prep.", "pron.", "conj.", "interj.",
            "aux.", "modal.", "det.", "num.", "abbr.", "phr."
        ]
    }

    private func extractPOS(_ line: String) -> String? {
        let lower = line.lowercased()
        return partOfSpeechPrefixes.first { lower.hasPrefix($0) }
    }

    private func sortByPartOfSpeechPriority(_ lines: [String]) -> [String] {
        let priority: [String: Int] = [
            "n.": 0, "v.": 1, "vt.": 1, "vi.": 1, "adj.": 2, "a.": 2, "adv.": 3, "ad.": 3, "prep.": 4,
            "pron.": 5, "conj.": 6, "interj.": 7, "aux.": 8, "modal.": 9, "det.": 10,
            "num.": 11, "abbr.": 12, "phr.": 13
        ]
        return lines.sorted { lhs, rhs in
            let lp = extractPOS(lhs).flatMap { priority[$0] } ?? 999
            let rp = extractPOS(rhs).flatMap { priority[$0] } ?? 999
            if lp == rp { return lhs < rhs }
            return lp < rp
        }
    }

    private func expandCommaMeanings(_ line: String) -> [String] {
        guard let pos = extractPOS(line) else { return [line] }
        let body = line.dropFirst(pos.count)
        let parts = body
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return [line] }
        return parts.map { "\(pos) \($0)" }
    }

    private func deduplicate(_ lines: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for line in lines {
            let key = normalize(line)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(line)
        }
        return out
    }

    private func mergeByPartOfSpeech(_ lines: [String]) -> [String] {
        var grouped: [String: [String]] = [:]
        var orderedPOS: [String] = []
        var passthrough: [String] = []

        for line in lines {
            guard let pos = extractPOS(line) else {
                passthrough.append(line)
                continue
            }

            let body = line.dropFirst(pos.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            if grouped[pos] == nil {
                grouped[pos] = []
                orderedPOS.append(pos)
            }
            grouped[pos]?.append(body)
        }

        var merged: [String] = orderedPOS.compactMap { pos in
            guard let items = grouped[pos], !items.isEmpty else { return nil }
            let unique = deduplicatePhrases(items)
            return "\(pos) \(unique.joined(separator: "; "))"
        }
        merged.append(contentsOf: passthrough)
        return merged
    }

    private func deduplicatePhrases(_ items: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for item in items {
            let key = normalize(item)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(item)
        }
        return out
    }

    private func splitMixedPartOfSpeechLine(_ line: String) -> [String] {
        let markers = partOfSpeechPrefixes
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let markerPattern = "(?:^|[\\s,，;；/|])(\(markers))"
        guard let regex = try? NSRegularExpression(pattern: markerPattern, options: [.caseInsensitive]) else {
            return [line]
        }

        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range)
        guard matches.count > 1 else { return [line] }

        var ranges: [Range<String.Index>] = []
        for index in 0..<matches.count {
            let startLocation = matches[index].range.location
            let endLocation = index + 1 < matches.count ? matches[index + 1].range.location : line.utf16.count
            let start = String.Index(utf16Offset: startLocation, in: line)
            let end = String.Index(utf16Offset: endLocation, in: line)
            guard start < end else { continue }
            ranges.append(start..<end)
        }

        let parts = ranges
            .map { String(line[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? [line] : parts
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
