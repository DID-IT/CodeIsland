import Foundation

// MARK: - Sessions that start sessions
//
// In the Claude desktop app a session can start other sessions
// (mcp__ccd_session__start_session / hand_off_to_session). Those are full
// Claude Code sessions with their own session id and hooks; nothing in the
// child's hooks or transcript names the parent. What does line up, from real
// transcripts (Claude Code 2.1.304):
//
//   parent PostToolUse  tool_name …start_session, tool_input.title "X",
//                       tool_response "Started session … (session_id: local_…)"
//   child hooks         _claude_desktop_session "local_…" (CLAUDE_CODE_HOST_SESSION_ID)
//   child transcript    custom-title "X"  → SessionSnapshot.sessionTitle
//   child first prompt  "Background (from the session that started this one): …"
//
// So a child is linked by its desktop id when the parent's tool result named
// it, else to the parent that most recently started a session with its exact
// title shortly before the child appeared.

/// How the island should treat a submitted prompt.
public enum SubmittedPrompt: Equatable {
    /// Text the user typed (wrapped blocks already removed).
    case typed(String)
    /// Another session's brief for this one, header line removed.
    case spawnBrief(String)
    /// Only blocks the host injected: task notifications, side-session
    /// events, system reminders. Not a user turn to show.
    case injected
}

/// Tags the Claude hosts wrap around text the user did not type.
let injectedPromptTags = ["task-notification", "side-sessions-event", "system-reminder", "ci-monitor-event"]

private let spawnBriefHeader = "Background (from the session that started this one):"

public func classifySubmittedPrompt(_ prompt: String) -> SubmittedPrompt {
    var text = prompt
    // Strip whole injected blocks wherever they sit; keep everything else.
    for tag in injectedPromptTags {
        while let open = text.range(of: "<\(tag)"),
              let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // A lone opening tag (block cut short by the hook) is still injected.
    if text.isEmpty || injectedPromptTags.contains(where: { text.hasPrefix("<\($0)") }) {
        return .injected
    }
    if text.hasPrefix(spawnBriefHeader) {
        let brief = text.dropFirst(spawnBriefHeader.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return .spawnBrief(brief.isEmpty ? text : brief)
    }
    return .typed(text)
}

/// Kept for callers that only care about task notifications.
public func isTaskNotificationPrompt(_ prompt: String) -> Bool {
    prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<task-notification>")
}

/// Records a session start by this (parent) session from its PostToolUse.
func recordSessionSpawn(sessions: inout [String: SessionSnapshot], sessionId: String, event: HookEvent, now: Date = Date()) {
    guard event.agentId == nil,
          let tool = event.rawJSON["tool_name"] as? String,
          tool.hasSuffix("__start_session") || tool.hasSuffix("__hand_off_to_session"),
          let input = event.rawJSON["tool_input"] as? [String: Any],
          let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !title.isEmpty else { return }
    sessions[sessionId]?.spawnedSessionTitles[title] = now
    let own = sessions[sessionId]?.claudeDesktopSessionId
    for hostId in desktopSessionIds(in: event.rawJSON["tool_response"]) where hostId != own {
        sessions[sessionId]?.spawnedDesktopSessionIds[hostId] = now
    }
}

/// Every `local_…` id in a tool result, whatever its shape (text blocks,
/// a string, a dictionary).
func desktopSessionIds(in value: Any?) -> [String] {
    var texts: [String] = []
    func collect(_ v: Any?) {
        switch v {
        case let s as String: texts.append(s)
        case let a as [Any]: a.forEach(collect)
        case let d as [String: Any]: d.values.forEach(collect)
        default: break
        }
    }
    collect(value)
    var ids: [String] = []
    for text in texts {
        var rest = text[...]
        while let r = rest.range(of: "local_") {
            let tail = rest[r.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            let id = "local_" + tail
            if ClaudeDesktopCodeSession.isValidHostSessionId(id), !ids.contains(id) { ids.append(id) }
            rest = rest[r.upperBound...]
        }
    }
    return ids
}

public enum SessionFamilies {
    /// A child must appear within this window after its parent started it.
    public static let linkWindow: TimeInterval = 15 * 60
    /// Clock slack: the child's first hook can land just before the
    /// parent's PostToolUse.
    public static let linkSlack: TimeInterval = 60

    /// Links unlinked sessions to the session that started them. Links are
    /// kept once made (a later rename does not unlink).
    public static func link(_ sessions: inout [String: SessionSnapshot]) {
        let parents = sessions.filter {
            !$0.value.spawnedSessionTitles.isEmpty || !$0.value.spawnedDesktopSessionIds.isEmpty
        }
        guard !parents.isEmpty else { return }
        for (childId, child) in sessions where child.parentSessionId == nil {
            if let hostId = child.claudeDesktopSessionId,
               let parentId = parents.first(where: { $0.key != childId && $0.value.spawnedDesktopSessionIds[hostId] != nil })?.key {
                sessions[childId]?.parentSessionId = parentId
                continue
            }
            guard let title = child.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let candidates = parents.compactMap { parentId, parent -> (String, Date)? in
                guard parentId != childId, let spawnedAt = parent.spawnedSessionTitles[title] else { return nil }
                let lag = child.startTime.timeIntervalSince(spawnedAt)
                guard lag >= -linkSlack, lag <= linkWindow else { return nil }
                return (parentId, spawnedAt)
            }
            if let best = candidates.max(by: { $0.1 < $1.1 }) {
                sessions[childId]?.parentSessionId = best.0
            }
        }
    }

    /// Sessions below `id` (children, grandchildren, …) that are not idle.
    /// A parent whose own turn ended is still busy while these run.
    public static func activeDescendants(of id: String, in sessions: [String: SessionSnapshot]) -> Int {
        var count = 0
        var seen: Set<String> = [id]
        var frontier = [id]
        while let current = frontier.popLast() {
            for (childId, child) in sessions where child.parentSessionId == current && seen.insert(childId).inserted {
                if child.status != .idle { count += 1 }
                frontier.append(childId)
            }
        }
        return count
    }

    /// The list order with every child moved right under its parent
    /// (depth 1), recursively. A family takes the slot of its first member
    /// in `orderedIds`, so a child that needs you still pulls its family up.
    /// A child whose parent is not in `orderedIds` stays where it is.
    public static func nest(_ orderedIds: [String], sessions: [String: SessionSnapshot]) -> [(id: String, depth: Int)] {
        let present = Set(orderedIds)
        func parent(of id: String) -> String? {
            guard let p = sessions[id]?.parentSessionId, p != id, present.contains(p) else { return nil }
            return p
        }
        func root(of id: String) -> String {
            var current = id
            var seen: Set<String> = [id]
            while let p = parent(of: current), seen.insert(p).inserted { current = p }
            return current
        }
        var children: [String: [String]] = [:]
        for id in orderedIds { if let p = parent(of: id) { children[p, default: []].append(id) } }

        var result: [(String, Int)] = []
        var placed = Set<String>()
        func place(_ id: String, depth: Int) {
            guard placed.insert(id).inserted else { return }
            result.append((id, depth))
            for child in children[id] ?? [] { place(child, depth: depth + 1) }
        }
        for id in orderedIds { place(root(of: id), depth: 0) }
        return result
    }
}
