// SessionTranscript.swift
//
// Pineapple 🍍
//
// MCP tool: read_session_transcript
//
// Purpose: let Claude Desktop (or any MCP client) peek at a Claude Code
// session's transcript without resuming it. Pairs with the v2.1 primary-
// session pointer model — when the user asks "what's the status of project
// X?", Claude can read the most recent turns of that project's primary
// session and answer using its actual content, not just memory.
//
// Resolution order:
//   1. If `session_id` is given (full UUID or prefix), use it directly.
//   2. Else if `project` is given:
//        a. Walk ~/.claude/projects/* and decode each cwd.
//        b. Fuzzy-match `project` against each cwd's basename.
//        c. Best match → check `<cwd>/.seashell-inbox/primary-session.txt`.
//           If the pointer exists, use that session id.
//           Otherwise pick the largest .jsonl in that project's dir.
//   3. Else: error.
//
// Tier A — read-only, no approval needed.

import Foundation
import MCP
import Logging

// MARK: - Types

private struct TranscriptTurn {
    let timestamp: String
    let role: String        // "user" | "assistant"
    let textParts: [String] // pre-rendered text blobs
    let toolNames: [String] // names of tools used in this turn (assistant only)
    let hadThinking: Bool
}

private struct ResolvedSession {
    let sessionId: String
    let cwd: String
    let label: String
    let jsonlPath: String
    let totalTurns: Int
    let usedPrimaryPointer: Bool
}

// MARK: - Path helpers

private let claudeProjectsRoot: String = {
    NSHomeDirectory() + "/.claude/projects"
}()

/// Decode `~/.claude/projects/<dir>/` to its original cwd.
/// Heuristic: leading '-' dropped, remaining '-' become '/'.
/// Matches the encode used by Claude Code (and our seashell-sessions Python).
private func decodeProjectDir(_ name: String) -> String {
    var s = name
    if s.hasPrefix("-") { s.removeFirst() }
    return "/" + s.replacingOccurrences(of: "-", with: "/")
}

private func listAllProjectDirs() -> [(dir: String, cwd: String)] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: claudeProjectsRoot) else {
        return []
    }
    return entries.compactMap { name in
        let dirPath = claudeProjectsRoot + "/" + name
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return (dirPath, decodeProjectDir(name))
    }
}

private func listJsonls(in dirPath: String) -> [(id: String, path: String, sizeBytes: Int)] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else {
        return []
    }
    return entries.compactMap { name -> (String, String, Int)? in
        guard name.hasSuffix(".jsonl") else { return nil }
        let path = dirPath + "/" + name
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int) ?? 0
        let id = String(name.dropLast(".jsonl".count))
        return (id, path, size)
    }
}

private func readPrimaryPointer(for cwd: String) -> String? {
    let pointerPath = cwd + "/.seashell-inbox/primary-session.txt"
    guard let raw = try? String(contentsOfFile: pointerPath, encoding: .utf8) else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Fuzzy matching (mirrors seashell-sessions Python)

private func fuzzyScore(query: String, label: String, cwd: String) -> Int {
    let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let l = label.lowercased()
    let c = cwd.lowercased()
    if q == l { return 100 }
    if l.replacingOccurrences(of: "-", with: "") == q.replacingOccurrences(of: "-", with: "") { return 90 }
    if l.hasPrefix(q) { return 85 }
    if l.contains(q) { return 75 }
    if c.contains(q) { return 50 }
    return 0
}

// MARK: - Session resolution

/// Resolve project name → session id by:
///  1. Picking the project dir whose basename best fuzzy-matches `query`.
///  2. Reading that project's primary-session pointer if present.
///  3. Else picking the largest .jsonl in that project's dir.
private func resolveByProject(_ query: String) -> ResolvedSession? {
    let dirs = listAllProjectDirs()
    var best: (score: Int, dir: String, cwd: String)? = nil
    for (dir, cwd) in dirs {
        let label = (cwd as NSString).lastPathComponent
        let score = fuzzyScore(query: query, label: label, cwd: cwd)
        if score > 0, score > (best?.score ?? 0) {
            best = (score, dir, cwd)
        }
    }
    guard let pick = best else { return nil }
    let label = (pick.cwd as NSString).lastPathComponent

    // Try primary pointer first
    if let primary = readPrimaryPointer(for: pick.cwd) {
        let candidates = listJsonls(in: pick.dir)
        if let match = candidates.first(where: { $0.id == primary }) {
            let total = countLines(at: match.path)
            return ResolvedSession(
                sessionId: match.id,
                cwd: pick.cwd,
                label: label,
                jsonlPath: match.path,
                totalTurns: total,
                usedPrimaryPointer: true
            )
        }
        // Pointer points to a session not in this project's dir — fall through.
    }

    // Fallback: largest jsonl in this project dir
    let candidates = listJsonls(in: pick.dir).sorted { $0.sizeBytes > $1.sizeBytes }
    guard let largest = candidates.first else { return nil }
    let total = countLines(at: largest.path)
    return ResolvedSession(
        sessionId: largest.id,
        cwd: pick.cwd,
        label: label,
        jsonlPath: largest.path,
        totalTurns: total,
        usedPrimaryPointer: false
    )
}

/// Resolve a session id (full or prefix) by scanning every project dir.
private func resolveById(_ idOrPrefix: String) -> ResolvedSession? {
    for (dir, cwd) in listAllProjectDirs() {
        for j in listJsonls(in: dir) {
            if j.id == idOrPrefix || j.id.hasPrefix(idOrPrefix) {
                let label = (cwd as NSString).lastPathComponent
                let total = countLines(at: j.path)
                return ResolvedSession(
                    sessionId: j.id,
                    cwd: cwd,
                    label: label,
                    jsonlPath: j.path,
                    totalTurns: total,
                    usedPrimaryPointer: false
                )
            }
        }
    }
    return nil
}

private func countLines(at path: String) -> Int {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
    return data.split(separator: "\n", omittingEmptySubsequences: true).count
}

// MARK: - Transcript parsing

private func parseTurns(at path: String, lastN: Int) -> [TranscriptTurn] {
    guard let blob = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let lines = blob.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }

    var turns: [TranscriptTurn] = []
    for line in lines {
        guard let data = line.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            continue
        }
        guard let type = any["type"] as? String, type == "user" || type == "assistant" else {
            continue
        }
        let timestamp = (any["timestamp"] as? String) ?? ""
        guard let message = any["message"] as? [String: Any] else { continue }
        let role = (message["role"] as? String) ?? type

        var textParts: [String] = []
        var toolNames: [String] = []
        var hadThinking = false

        // user content is either a String or [content blocks]; assistant is always [content blocks]
        if let asString = message["content"] as? String {
            textParts.append(asString)
        } else if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                let bType = (block["type"] as? String) ?? ""
                switch bType {
                case "text":
                    if let t = block["text"] as? String, !t.isEmpty { textParts.append(t) }
                case "thinking":
                    hadThinking = true
                case "tool_use":
                    if let name = block["name"] as? String { toolNames.append(name) }
                case "tool_result":
                    // tool results are noise here — skip
                    continue
                default:
                    continue
                }
            }
        }

        // Skip turns that produced nothing useful (e.g. assistant turn that was only tool_result)
        if textParts.isEmpty && toolNames.isEmpty && !hadThinking { continue }

        turns.append(TranscriptTurn(
            timestamp: timestamp,
            role: role,
            textParts: textParts,
            toolNames: toolNames,
            hadThinking: hadThinking
        ))
    }

    if turns.count > lastN {
        return Array(turns.suffix(lastN))
    }
    return turns
}

// MARK: - Rendering

private func formatTimestamp(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    if let date = parser.date(from: iso) {
        let display = DateFormatter()
        display.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        display.timeZone = TimeZone(identifier: "UTC")
        return display.string(from: date)
    }
    return iso
}

private func renderTurn(_ turn: TranscriptTurn, maxBodyChars: Int) -> String {
    var lines: [String] = []
    let ts = formatTimestamp(turn.timestamp)
    lines.append("[\(ts)] \(turn.role):")

    if turn.hadThinking {
        lines.append("    [thought]")
    }

    for part in turn.textParts {
        var body = part
        if body.count > maxBodyChars {
            let prefix = body.prefix(maxBodyChars)
            body = String(prefix) + "… (truncated, \(part.count - maxBodyChars) more chars)"
        }
        let indented = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
        lines.append(indented)
    }

    if !turn.toolNames.isEmpty {
        let unique = Array(Set(turn.toolNames)).sorted()
        lines.append("    [used: \(unique.joined(separator: ", "))]")
    }

    return lines.joined(separator: "\n")
}

// MARK: - Tool entry point

/// Read the most recent N turns of a Claude Code session transcript.
/// Tier A — read-only.
func handleReadSessionTranscript(
    params: CallTool.Parameters,
    logger: Logger
) async -> CallTool.Result {
    var lastN = 30
    var maxBodyChars = 800
    var projectQuery: String? = nil
    var sessionId: String? = nil

    if let arguments = params.arguments {
        if case .string(let s)? = arguments["project"], !s.isEmpty { projectQuery = s }
        if case .string(let s)? = arguments["session_id"], !s.isEmpty { sessionId = s }
        if let v = arguments["last_n"], case .int(let n) = v {
            lastN = max(1, min(n, 200))
        } else if let v = arguments["last_n"], case .string(let s) = v, let n = Int(s) {
            lastN = max(1, min(n, 200))
        }
        if let v = arguments["max_body_chars"], case .int(let n) = v {
            maxBodyChars = max(80, min(n, 5000))
        } else if let v = arguments["max_body_chars"], case .string(let s) = v, let n = Int(s) {
            maxBodyChars = max(80, min(n, 5000))
        }
    }

    // Resolve target session
    let resolved: ResolvedSession?
    if let sid = sessionId {
        resolved = resolveById(sid)
    } else if let q = projectQuery {
        resolved = resolveByProject(q)
    } else {
        return CallTool.Result(
            content: [.text("Missing required parameter: provide either `project` (project name) or `session_id`.")],
            isError: true
        )
    }

    guard let session = resolved else {
        let target = sessionId ?? projectQuery ?? "(none)"
        return CallTool.Result(
            content: [.text("✗ No session matched '\(target)'. Try `seashell-sessions list` in a terminal to see what's available.")],
            isError: true
        )
    }

    let turns = parseTurns(at: session.jsonlPath, lastN: lastN)
    if turns.isEmpty {
        return CallTool.Result(
            content: [.text("📜 Session \(session.sessionId.prefix(8)) — \(session.label)\n   No user/assistant turns found in transcript.")],
            isError: false
        )
    }

    var output = "📜 Session \(session.sessionId.prefix(8)) — \(session.label) (cwd: \(session.cwd))\n"
    output += "Showing last \(turns.count) turn\(turns.count == 1 ? "" : "s")"
    if session.totalTurns > turns.count {
        output += " (of \(session.totalTurns) total messages in jsonl)"
    }
    if session.usedPrimaryPointer {
        output += "  ★ resolved via primary-session pointer"
    }
    output += "\n" + String(repeating: "─", count: 60) + "\n\n"
    output += turns.map { renderTurn($0, maxBodyChars: maxBodyChars) }.joined(separator: "\n\n")

    return CallTool.Result(content: [.text(output)], isError: false)
}
