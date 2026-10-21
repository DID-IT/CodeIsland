import Foundation

// MARK: - Orchestrator / subagent task tracking
//
// What Claude Code (2.1.300) actually sends when an orchestrator spawns
// subagents, from a recorded run (Tests/CodeIslandCoreTests/OrchestratorFixture):
//
//   root PreToolUse  Agent  tool_input {description, subagent_type, run_in_background}
//   SubagentStart    agent_id, agent_type            (no description)
//   root PostToolUse Agent  tool_response {agentId, description, resolvedModel, isAsync}
//   … subagent tool hooks carry agent_id …
//   root Stop        background_tasks [{id, type, status, description, agent_type}]
//   root UserPromptSubmit  "<task-notification>…" when a subagent finishes
//   SubagentStop     agent_id, last_assistant_message, background_tasks
//
// So the task description is joined in from the parent's Agent tool response
// (exact, by agent id) and from `background_tasks` (any event that has it).
// Kept in its own file so this fork's changes to SessionSnapshot.swift stay
// a handful of call sites.

extension SessionSnapshot {
    /// Upper bound on `finishedSubagents`; oldest drop first.
    public static let maxFinishedSubagents = 12

    /// Moves a stopped subagent into `finishedSubagents`, replacing an
    /// earlier entry for the same id.
    public mutating func recordFinishedSubagent(_ subagent: SubagentState, at date: Date = Date()) {
        var finished = subagent
        finished.status = .idle
        finished.currentTool = nil
        finished.toolDescription = nil
        finished.finishedAt = date
        finishedSubagents.removeAll { $0.agentId == finished.agentId }
        finishedSubagents.append(finished)
        if finishedSubagents.count > Self.maxFinishedSubagents {
            finishedSubagents.removeFirst(finishedSubagents.count - Self.maxFinishedSubagents)
        }
    }

    /// Running and finished subagents of this turn, in start order.
    public var subagentTimeline: [SubagentState] {
        (Array(subagents.values) + finishedSubagents).sorted { $0.startTime < $1.startTime }
    }
}

/// Joins task descriptions onto subagents from any event that carries them.
/// Never creates a subagent: SubagentStart stays the only way in.
func applySubagentTaskMetadata(
    sessions: inout [String: SessionSnapshot],
    sessionId: String,
    event: HookEvent
) {
    guard sessions[sessionId] != nil else { return }

    if event.agentId == nil,
       let tool = event.rawJSON["tool_name"] as? String, tool == "Agent" || tool == "Task",
       let response = event.rawJSON["tool_response"] as? [String: Any],
       let agentId = nonEmptyString(response["agentId"]) {
        let input = event.rawJSON["tool_input"] as? [String: Any]
        let description = nonEmptyString(response["description"]) ?? nonEmptyString(input?["description"])
        let background = (input?["run_in_background"] as? Bool) == true
        updateSubagent(in: &sessions, sessionId: sessionId, agentId: agentId) { sub in
            if let description { sub.taskDescription = description }
            if background { sub.isBackground = true }
            if sub.model == nil, let model = nonEmptyString(response["resolvedModel"]) { sub.model = model }
        }
    }

    if let tasks = event.rawJSON["background_tasks"] as? [[String: Any]] {
        for task in tasks where (task["type"] as? String ?? "subagent") == "subagent" {
            guard let agentId = nonEmptyString(task["id"]),
                  let description = nonEmptyString(task["description"]) else { continue }
            updateSubagent(in: &sessions, sessionId: sessionId, agentId: agentId) { sub in
                if sub.taskDescription == nil { sub.taskDescription = description }
            }
        }
    }
}

/// The parent's in-flight Agent call names the task a just-started subagent
/// will work on. A best guess only when two Agent calls overlap; the tool
/// response that follows corrects it by id.
func pendingAgentTaskDescription(parent: SessionSnapshot?, agentType: String) -> String? {
    guard let parent, parent.currentTool == "Agent",
          let description = parent.toolDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
          !description.isEmpty, description != agentType else { return nil }
    return description
}

private func updateSubagent(
    in sessions: inout [String: SessionSnapshot],
    sessionId: String,
    agentId: String,
    _ change: (inout SubagentState) -> Void
) {
    if var live = sessions[sessionId]?.subagents[agentId] {
        change(&live)
        sessions[sessionId]?.subagents[agentId] = live
    } else if let index = sessions[sessionId]?.finishedSubagents.firstIndex(where: { $0.agentId == agentId }) {
        change(&sessions[sessionId]!.finishedSubagents[index])
    }
}

private func nonEmptyString(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else { return nil }
    return text
}
