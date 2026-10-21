import Foundation

// MARK: - Background tasks
//
// A Claude Code turn can end while work it started keeps going: a Bash
// command run with run_in_background, a Monitor, a background subagent.
// From a recorded run (Claude Code 2.1.300):
//
//   PostToolUse Bash  tool_input {description, run_in_background: true}
//                     tool_response {backgroundTaskId: "b3v3iuxzw"}
//   Stop              background_tasks [{id, type: "shell", status: "running",
//                                        description, command}]
//   UserPromptSubmit  "<task-notification>…" when it finishes
//   Stop              background_tasks []
//
// `background_tasks` is the session's whole list, so each event that carries
// it replaces what we had.

public struct BackgroundTask: Equatable, Sendable, Identifiable {
    public let id: String
    /// "shell", "subagent", "monitor", …
    public var type: String
    public var status: String
    public var description: String?
    public var command: String?
    /// When the island first saw it.
    public var startedAt: Date

    public init(id: String, type: String, status: String, description: String?, command: String?, startedAt: Date) {
        self.id = id
        self.type = type
        self.status = status
        self.description = description
        self.command = command
        self.startedAt = startedAt
    }

    public var isRunning: Bool { status == "running" || status == "pending" }
}

extension SessionSnapshot {
    /// Running background work other than subagents (those already keep the
    /// card working and show in the subagent tree).
    public var runningBackgroundTasks: [BackgroundTask] {
        backgroundTasks.filter { $0.isRunning && $0.type != "subagent" }
    }
}

func applyBackgroundTasks(sessions: inout [String: SessionSnapshot], sessionId: String, eventName: String, event: HookEvent, now: Date = Date()) {
    guard sessions[sessionId] != nil else { return }
    if eventName == "SessionEnd", event.agentId == nil {
        sessions[sessionId]?.backgroundTasks = []
        return
    }

    let previous = Dictionary(uniqueKeysWithValues: (sessions[sessionId]?.backgroundTasks ?? []).map { ($0.id, $0) })

    if let list = event.rawJSON["background_tasks"] as? [[String: Any]] {
        sessions[sessionId]?.backgroundTasks = list.compactMap { raw in
            guard let id = raw["id"] as? String, !id.isEmpty else { return nil }
            return BackgroundTask(
                id: id,
                type: raw["type"] as? String ?? "shell",
                status: raw["status"] as? String ?? "running",
                description: (raw["description"] as? String) ?? previous[id]?.description,
                command: (raw["command"] as? String) ?? previous[id]?.command,
                startedAt: previous[id]?.startedAt ?? now
            )
        }
        return
    }

    // A background Bash call is known before the turn's Stop lists it.
    if eventName == "PostToolUse", event.agentId == nil,
       let response = event.rawJSON["tool_response"] as? [String: Any],
       let id = response["backgroundTaskId"] as? String, !id.isEmpty, previous[id] == nil {
        let input = event.rawJSON["tool_input"] as? [String: Any]
        sessions[sessionId]?.backgroundTasks.append(BackgroundTask(
            id: id,
            type: "shell",
            status: "running",
            description: input?["description"] as? String,
            command: input?["command"] as? String,
            startedAt: now
        ))
    }
}
