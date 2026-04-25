// InboxHandlers.swift

// Pineapple 🍍
//
// User → Claude inbox tools with per-project routing.
//
// The user runs `seashell-msg "..."` from any Wave Terminal block. The shell
// command walks up from cwd to find the nearest `.seashell-inbox/` directory
// (created by `seashell init`). Notes go to that project's inbox; if no
// project marker is found, they fall back to the global inbox at `~/.seashell/`.
//
// Storage layout:
//   ~/.seashell/
//   ├── inbox.jsonl                  global inbox (no project context)
//   ├── inbox.archive.jsonl          global archive
//   ├── replies.jsonl                global replies
//   └── projects.jsonl               registry of known project paths
//
//   <project_path>/.seashell-inbox/
//   ├── inbox.jsonl                  per-project inbox
//   ├── inbox.archive.jsonl          per-project archive
//   └── replies.jsonl                per-project replies
//
// Read pattern (per inbox):
//   1. Atomically rename inbox.jsonl → inbox.processing.jsonl.
//   2. Parse processing.jsonl line by line.
//   3. Mark each record as read=true and append to archive.jsonl.
//   4. Delete processing.jsonl.
//
// Discovery:
//   read_user_inbox / inbox_count / inbox_history aggregate across
//   the global inbox + every registered project in projects.jsonl.

import Foundation
import MCP
import Logging

// MARK: - Records

struct InboxRecord: Codable {
    let id: String
    let ts: String
    let cwd: String
    let hostname: String?
    let text: String
    var read: Bool
    let attachments: [Attachment]?
    /// Optional reply token — when set, `seashell-ask` is blocking on this.
    /// Claude answering should call `reply_to_user(message_id: id, ...)`.
    let reply_token: String?

    struct Attachment: Codable {
        let type: String   // "file" | "directory"
        let path: String
    }
}

struct ReplyRecord: Codable {
    let message_id: String
    let ts: String
    let text: String
    let hostname: String?
}

struct ProjectRegistryEntry: Codable {
    let path: String
    let name: String
    let added_at: String
}

// MARK: - Inbox path resolution

private struct InboxPaths {
    let inbox: String
    let processing: String
    let archive: String
    let replies: String
    let projectName: String?    // nil for global
    let projectPath: String?    // nil for global

    var label: String { projectName ?? "global" }
}

private let globalInboxDir = NSHomeDirectory() + "/.seashell"
private let projectsRegistryPath = globalInboxDir + "/projects.jsonl"

private func globalInbox() -> InboxPaths {
    InboxPaths(
        inbox:      globalInboxDir + "/inbox.jsonl",
        processing: globalInboxDir + "/inbox.processing.jsonl",
        archive:    globalInboxDir + "/inbox.archive.jsonl",
        replies:    globalInboxDir + "/replies.jsonl",
        projectName: nil,
        projectPath: nil
    )
}

private func resolveProjectInbox(at projectPath: String) -> InboxPaths {
    let dir = projectPath + "/.seashell-inbox"
    let name = (projectPath as NSString).lastPathComponent
    return InboxPaths(
        inbox:      dir + "/inbox.jsonl",
        processing: dir + "/inbox.processing.jsonl",
        archive:    dir + "/inbox.archive.jsonl",
        replies:    dir + "/replies.jsonl",
        projectName: name.isEmpty ? "(unknown)" : name,
        projectPath: projectPath
    )
}

private func ensureDir(_ path: String) {
    try? FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true
    )
}

// MARK: - Project registry

private func loadRegisteredProjects() -> [ProjectRegistryEntry] {
    guard let data = try? String(contentsOfFile: projectsRegistryPath, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    return data.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        guard let lineData = String(line).data(using: .utf8) else { return nil }
        return try? decoder.decode(ProjectRegistryEntry.self, from: lineData)
    }
}

/// All inboxes Claude should consult: global plus every registered project that still exists on disk.
private func discoverInboxes() -> [InboxPaths] {
    var inboxes: [InboxPaths] = [globalInbox()]
    for project in loadRegisteredProjects() {
        // Skip stale entries whose directory no longer exists
        guard FileManager.default.fileExists(atPath: project.path) else { continue }
        inboxes.append(resolveProjectInbox(at: project.path))
    }
    return inboxes
}

// MARK: - I/O helpers

private func parseInboxRecords(from path: String) -> [InboxRecord] {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    return data.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        guard let lineData = String(line).data(using: .utf8) else { return nil }
        return try? decoder.decode(InboxRecord.self, from: lineData)
    }
}

private func appendInboxRecords(_ records: [InboxRecord], to path: String) {
    guard !records.isEmpty else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let lines = records.compactMap { record -> String? in
        guard let data = try? encoder.encode(record) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    let blob = lines.joined(separator: "\n") + "\n"
    appendString(blob, to: path)
}

private func appendString(_ blob: String, to path: String) {
    ensureDir(path)
    guard let blobData = blob.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: blobData)
        }
    } else {
        try? blob.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Drain (atomic rename → process → archive)

/// Drains unread records from a single inbox. Returns the records that were read.
private func drainInbox(_ inbox: InboxPaths, logger: Logger) -> [InboxRecord] {
    ensureDir(inbox.inbox)

    // Recovery: a previous interrupted drain may have left processing.jsonl behind.
    var recovered: [InboxRecord] = []
    if FileManager.default.fileExists(atPath: inbox.processing) {
        recovered = parseInboxRecords(from: inbox.processing)
        if !recovered.isEmpty {
            logger.info("[\(inbox.label)] recovered \(recovered.count) records from prior processing.jsonl")
        }
    }

    // Atomic rename: any concurrent seashell-msg appends after this point go to a fresh inbox.jsonl.
    if FileManager.default.fileExists(atPath: inbox.inbox) {
        try? FileManager.default.moveItem(atPath: inbox.inbox, toPath: inbox.processing)
    }

    let fresh = parseInboxRecords(from: inbox.processing)
    let allRecords = recovered + fresh
    let unread = allRecords.filter { !$0.read }

    if unread.isEmpty {
        try? FileManager.default.removeItem(atPath: inbox.processing)
        return []
    }

    let archived = unread.map { r -> InboxRecord in
        var copy = r
        copy.read = true
        return copy
    }
    appendInboxRecords(archived, to: inbox.archive)
    try? FileManager.default.removeItem(atPath: inbox.processing)
    return unread
}

private func peekUnread(_ inbox: InboxPaths) -> [InboxRecord] {
    let pending = parseInboxRecords(from: inbox.inbox).filter { !$0.read }
    let recovering = FileManager.default.fileExists(atPath: inbox.processing)
        ? parseInboxRecords(from: inbox.processing).filter { !$0.read }
        : []
    return pending + recovering
}

// MARK: - Formatting

private func formatTimestamp(_ iso: String) -> String {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: iso) {
        let display = DateFormatter()
        display.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        display.timeZone = TimeZone(identifier: "UTC")
        return display.string(from: date)
    }
    return iso
}

private func ageMinutes(_ iso: String) -> Int? {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso) else { return nil }
    return Int(Date().timeIntervalSince(date) / 60.0)
}

private func renderRecord(_ record: InboxRecord, projectLabel: String, index: Int) -> String {
    var lines: [String] = []
    lines.append("[\(index)] \(formatTimestamp(record.ts)) — \(projectLabel) (cwd: \(record.cwd))")
    let indented = record.text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "    \($0)" }
        .joined(separator: "\n")
    lines.append(indented)
    if let attachments = record.attachments, !attachments.isEmpty {
        for att in attachments {
            lines.append("    📎 attachment: \(att.type) at \(att.path)")
        }
    }
    if let token = record.reply_token {
        lines.append("    🔁 awaiting reply (call reply_to_user with message_id=\(record.id), reply_token=\(token))")
    }
    return lines.joined(separator: "\n")
}

// MARK: - Tool: read_user_inbox

/// Drain unread messages across the global inbox + every registered project, archive them.
/// Tier A — safe.
func handleReadUserInbox(
    params: CallTool.Parameters,
    logger: Logger
) async -> CallTool.Result {
    let inboxes = discoverInboxes()
    var hits: [(label: String, record: InboxRecord)] = []

    for inbox in inboxes {
        let drained = drainInbox(inbox, logger: logger)
        for record in drained {
            hits.append((inbox.label, record))
        }
    }

    if hits.isEmpty {
        return CallTool.Result(content: [.text("📭 Inbox empty.")], isError: false)
    }

    var output = "📨 You have \(hits.count) unread note\(hits.count == 1 ? "" : "s"):\n\n"
    output += hits.enumerated()
        .map { renderRecord($1.record, projectLabel: $1.label, index: $0 + 1) }
        .joined(separator: "\n\n")
    return CallTool.Result(content: [.text(output)], isError: false)
}

// MARK: - Tool: inbox_count

/// Cheap peek across all inboxes. Returns count + oldest age + per-project breakdown.
/// Tier A — safe.
func handleInboxCount(
    params: CallTool.Parameters,
    logger: Logger
) async -> CallTool.Result {
    let inboxes = discoverInboxes()
    var perBucket: [(label: String, count: Int)] = []
    var allRecords: [InboxRecord] = []

    for inbox in inboxes {
        let unread = peekUnread(inbox)
        if !unread.isEmpty {
            perBucket.append((inbox.label, unread.count))
            allRecords.append(contentsOf: unread)
        }
    }

    if allRecords.isEmpty {
        return CallTool.Result(content: [.text("📭 No unread messages.")], isError: false)
    }

    let ages = allRecords.compactMap { ageMinutes($0.ts) }
    let oldest = ages.max() ?? 0
    let agePhrase: String
    if oldest < 1 { agePhrase = "just now" }
    else if oldest < 60 { agePhrase = "\(oldest) min ago" }
    else if oldest < 1440 { agePhrase = "\(oldest / 60)h \(oldest % 60)m ago" }
    else { agePhrase = "\(oldest / 1440)d ago" }

    let plural = allRecords.count == 1 ? "" : "s"
    var output = "📨 \(allRecords.count) unread message\(plural) (oldest: \(agePhrase))"
    if perBucket.count > 1 {
        let breakdown = perBucket.map { "\($0.label): \($0.count)" }.joined(separator: ", ")
        output += "\n   By project: \(breakdown)"
    } else if let only = perBucket.first {
        output += "  [\(only.label)]"
    }
    return CallTool.Result(content: [.text(output)], isError: false)
}

// MARK: - Tool: inbox_history

/// Browse the archive of read messages across all inboxes.
/// Args: limit (default 20, max 100), search (optional substring filter), project (optional project name filter).
/// Tier A — safe.
func handleInboxHistory(
    params: CallTool.Parameters,
    logger: Logger
) async -> CallTool.Result {
    var limit = 20
    var searchTerm: String? = nil
    var projectFilter: String? = nil

    if let arguments = params.arguments {
        if let v = arguments["limit"], case .string(let s) = v, let n = Int(s) {
            limit = max(1, min(n, 100))
        } else if let v = arguments["limit"], case .int(let n) = v {
            limit = max(1, min(n, 100))
        }
        if let v = arguments["search"], case .string(let s) = v, !s.isEmpty {
            searchTerm = s
        }
        if let v = arguments["project"], case .string(let s) = v, !s.isEmpty {
            projectFilter = s
        }
    }

    let inboxes = discoverInboxes()
    var combined: [(label: String, record: InboxRecord)] = []
    for inbox in inboxes {
        if let pf = projectFilter, inbox.label != pf { continue }
        let records = parseInboxRecords(from: inbox.archive)
        for record in records {
            combined.append((inbox.label, record))
        }
    }

    if let term = searchTerm {
        let needle = term.lowercased()
        combined = combined.filter { $0.record.text.lowercased().contains(needle) }
    }

    // Sort by timestamp descending (most recent first)
    combined.sort { $0.record.ts > $1.record.ts }
    combined = Array(combined.prefix(limit))

    if combined.isEmpty {
        var suffix = ""
        if let term = searchTerm { suffix += " matching \"\(term)\"" }
        if let pf = projectFilter { suffix += " in project \(pf)" }
        return CallTool.Result(content: [.text("📜 No archived messages\(suffix).")], isError: false)
    }

    var output = "📜 Inbox history (\(combined.count) most recent"
    if let term = searchTerm { output += " matching \"\(term)\"" }
    if let pf = projectFilter { output += " in \(pf)" }
    output += "):\n\n"
    output += combined.enumerated()
        .map { renderRecord($1.record, projectLabel: $1.label, index: $0 + 1) }
        .joined(separator: "\n\n")
    return CallTool.Result(content: [.text(output)], isError: false)
}

// MARK: - Tool: reply_to_user

/// Post a reply to a user message. Used to unblock `seashell-ask`.
/// Args: message_id (required), text (required), project_path (optional — auto-detected if absent).
/// Tier A — safe.
func handleReplyToUser(
    params: CallTool.Parameters,
    logger: Logger
) async -> CallTool.Result {
    guard let arguments = params.arguments,
          case .string(let messageId)? = arguments["message_id"],
          case .string(let text)? = arguments["text"] else {
        return CallTool.Result(
            content: [.text("Missing required parameters: 'message_id' and 'text'")],
            isError: true
        )
    }

    // If project_path wasn't supplied, look up the message in archives to find its origin
    var explicitProjectPath: String? = nil
    if case .string(let p)? = arguments["project_path"], !p.isEmpty {
        explicitProjectPath = p
    }

    let targetInbox: InboxPaths
    if let projectPath = explicitProjectPath {
        targetInbox = resolveProjectInbox(at: projectPath)
    } else if let found = locateInboxForMessage(messageId, logger: logger) {
        targetInbox = found
    } else {
        targetInbox = globalInbox()
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let nowIso = formatter.string(from: Date())

    let reply = ReplyRecord(
        message_id: messageId,
        ts: nowIso,
        text: text,
        hostname: ProcessInfo.processInfo.hostName
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(reply),
          let line = String(data: data, encoding: .utf8) else {
        return CallTool.Result(content: [.text("Failed to encode reply record.")], isError: true)
    }
    appendString(line + "\n", to: targetInbox.replies)

    return CallTool.Result(
        content: [.text("✓ Reply posted to \(targetInbox.label) (\(targetInbox.replies))\nA `seashell-ask` waiting on message_id \(messageId) will pick it up within ~1 second.")],
        isError: false
    )
}

/// Search archives across all known inboxes for the message_id, return the inbox that owns it.
private func locateInboxForMessage(_ id: String, logger: Logger) -> InboxPaths? {
    for inbox in discoverInboxes() {
        let archived = parseInboxRecords(from: inbox.archive)
        if archived.contains(where: { $0.id == id }) {
            return inbox
        }
        // Also check the still-pending inbox (e.g., ask hasn't drained yet)
        let pending = parseInboxRecords(from: inbox.inbox)
        if pending.contains(where: { $0.id == id }) {
            return inbox
        }
    }
    return nil
}

// MARK: - Tool: read_my_replies

private func parseReplies(from path: String) -> [ReplyRecord] {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    return data.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        guard let lineData = String(line).data(using: .utf8) else { return nil }
        return try? decoder.decode(ReplyRecord.self, from: lineData)
    }
}

private func renderReply(_ reply: ReplyRecord, projectLabel: String, index: Int) -> String {
    var lines: [String] = []
    lines.append("[\(index)] \(formatTimestamp(reply.ts)) — \(projectLabel) (in reply to msg \(reply.message_id.prefix(8)))")
    let indented = reply.text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "    \($0)" }
        .joined(separator: "\n")
    lines.append(indented)
    return lines.joined(separator: "\n")
}

/// Browse Claude's past replies (the OUTBOUND side, sibling to inbox_history).
/// Aggregates across the global inbox + every registered project's replies.jsonl.
/// Args: limit (default 10, max 100), search (substring filter), project (label filter).
/// Tier A — safe.
func handleReadMyReplies(
    params: CallTool.Parameters,
    logger: Logger
) async -> CallTool.Result {
    var limit = 10
    var searchTerm: String? = nil
    var projectFilter: String? = nil

    if let arguments = params.arguments {
        if let v = arguments["limit"], case .string(let s) = v, let n = Int(s) {
            limit = max(1, min(n, 100))
        } else if let v = arguments["limit"], case .int(let n) = v {
            limit = max(1, min(n, 100))
        }
        if let v = arguments["search"], case .string(let s) = v, !s.isEmpty {
            searchTerm = s
        }
        if let v = arguments["project"], case .string(let s) = v, !s.isEmpty {
            projectFilter = s
        }
    }

    let inboxes = discoverInboxes()
    var combined: [(label: String, reply: ReplyRecord)] = []
    for inbox in inboxes {
        if let pf = projectFilter, inbox.label != pf { continue }
        let replies = parseReplies(from: inbox.replies)
        for reply in replies {
            combined.append((inbox.label, reply))
        }
    }

    if let term = searchTerm {
        let needle = term.lowercased()
        combined = combined.filter { $0.reply.text.lowercased().contains(needle) }
    }

    // Most recent first
    combined.sort { $0.reply.ts > $1.reply.ts }
    combined = Array(combined.prefix(limit))

    if combined.isEmpty {
        var suffix = ""
        if let term = searchTerm { suffix += " matching \"\(term)\"" }
        if let pf = projectFilter { suffix += " in project \(pf)" }
        return CallTool.Result(content: [.text("📜 No replies recorded\(suffix).")], isError: false)
    }

    var output = "📜 Your past replies (\(combined.count) most recent"
    if let term = searchTerm { output += " matching \"\(term)\"" }
    if let pf = projectFilter { output += " in \(pf)" }
    output += "):\n\n"
    output += combined.enumerated()
        .map { renderReply($1.reply, projectLabel: $1.label, index: $0 + 1) }
        .joined(separator: "\n\n")
    return CallTool.Result(content: [.text(output)], isError: false)
}
