import XCTest
@testable import CodeIslandCore

/// A turn that ends with a background Bash command still running. Event
/// order and shapes from a recorded Claude Code 2.1.300 run.
final class BackgroundTasksTests: XCTestCase {
    private var sessions: [String: SessionSnapshot] = [:]

    private func send(_ json: [String: Any]) throws {
        var event = json
        event["session_id"] = "s"
        event["cwd"] = "/tmp/bg"
        let data = try JSONSerialization.data(withJSONObject: event)
        _ = reduceEvent(sessions: &sessions, event: try XCTUnwrap(HookEvent(from: data)), maxHistory: 20)
    }

    private var session: SessionSnapshot { sessions["s"] ?? SessionSnapshot() }

    private let running: [String: Any] = [
        "id": "b3v3iuxzw", "type": "shell", "status": "running",
        "description": "Wait for fake deploy", "command": "sleep 25 && echo bg-done",
    ]

    private func startBackgroundCommand() throws {
        try send(["hook_event_name": "UserPromptSubmit", "prompt": "Deploy and wait"])
        try send(["hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "tool_input": ["command": "sleep 25 && echo bg-done", "description": "Wait for fake deploy", "run_in_background": true]])
        try send(["hook_event_name": "PostToolUse", "tool_name": "Bash",
                  "tool_input": ["command": "sleep 25 && echo bg-done", "description": "Wait for fake deploy", "run_in_background": true],
                  "tool_response": ["stdout": "", "stderr": "", "interrupted": false, "backgroundTaskId": "b3v3iuxzw"]])
    }

    func testTheTaskIsKnownAsSoonAsItStarts() throws {
        try startBackgroundCommand()
        XCTAssertEqual(session.runningBackgroundTasks.map(\.id), ["b3v3iuxzw"])
        XCTAssertEqual(session.runningBackgroundTasks.first?.description, "Wait for fake deploy")
    }

    func testAnEndedTurnWithATaskStillRunningKeepsIt() throws {
        try startBackgroundCommand()
        let startedAt = try XCTUnwrap(session.backgroundTasks.first?.startedAt)
        try send(["hook_event_name": "Stop", "background_tasks": [running]])
        XCTAssertEqual(session.status, .idle)
        XCTAssertEqual(session.runningBackgroundTasks.count, 1)
        XCTAssertEqual(session.backgroundTasks.first?.startedAt, startedAt, "the start time survives the Stop's list")
        XCTAssertEqual(session.backgroundTasks.first?.command, "sleep 25 && echo bg-done")
    }

    func testTheNextStopsEmptyListClearsIt() throws {
        try startBackgroundCommand()
        try send(["hook_event_name": "Stop", "background_tasks": [running]])
        try send(["hook_event_name": "UserPromptSubmit",
                  "prompt": "<task-notification>\n<task-id>b3v3iuxzw</task-id>\n</task-notification>"])
        XCTAssertEqual(session.lastUserPrompt, "Deploy and wait")
        try send(["hook_event_name": "Stop", "background_tasks": [] as [Any]])
        XCTAssertTrue(session.runningBackgroundTasks.isEmpty)
    }

    func testSubagentsAndFinishedTasksAreNotCounted() throws {
        try send(["hook_event_name": "Stop", "background_tasks": [
            ["id": "a1", "type": "subagent", "status": "running", "description": "Review", "agent_type": "Explore"],
            ["id": "b1", "type": "shell", "status": "completed", "description": "Build"],
        ]])
        XCTAssertTrue(session.runningBackgroundTasks.isEmpty)
        XCTAssertEqual(session.backgroundTasks.count, 2)
    }

    func testSessionEndForgetsEverything() throws {
        try startBackgroundCommand()
        try send(["hook_event_name": "SessionEnd"])
        XCTAssertTrue(session.backgroundTasks.isEmpty)
    }
}
