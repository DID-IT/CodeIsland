import XCTest
@testable import CodeIslandCore

/// Replays a recorded Claude Code orchestrator run (OrchestratorFixture)
/// through `reduceEvent`, the same path live hooks take.
final class OrchestratorReplayTests: XCTestCase {
    private func replay(first count: Int = OrchestratorFixture.lines.count) throws -> SessionSnapshot {
        var sessions: [String: SessionSnapshot] = [:]
        for line in OrchestratorFixture.lines.prefix(count) {
            let event = try XCTUnwrap(HookEvent(from: Data(line.utf8)), line)
            _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 20)
        }
        return try XCTUnwrap(sessions["orch-1"])
    }

    private func reduce(_ session: SessionSnapshot, _ json: [String: Any]) throws -> SessionSnapshot {
        var sessions = ["orch-1": session]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 20)
        return try XCTUnwrap(sessions["orch-1"])
    }

    func testEachSubagentGetsTheTaskTheOrchestratorGaveIt() throws {
        let session = try replay(first: 11) // all three launched
        XCTAssertEqual(session.subagents["agent-1"]?.taskDescription, "Find Sparkle usage")
        XCTAssertEqual(session.subagents["agent-2"]?.taskDescription, "Find push channels")
        XCTAssertEqual(session.subagents["agent-3"]?.taskDescription, "Count Swift files")
        XCTAssertEqual(session.subagents["agent-3"]?.isBackground, true)
        XCTAssertEqual(session.subagents["agent-1"]?.isBackground, false)
        XCTAssertEqual(session.subagents["agent-1"]?.model, "claude-sonnet-5-5")
    }

    func testTheTaskIsKnownAsSoonAsTheSubagentStarts() throws {
        let session = try replay(first: 4) // PreToolUse Agent, SubagentStart
        XCTAssertEqual(session.subagents["agent-1"]?.taskDescription, "Find Sparkle usage")
    }

    func testAFinishedSubagentStaysOnTheCardWithItsResult() throws {
        let session = try replay(first: 14) // agent-2 stopped
        XCTAssertEqual(Set(session.subagents.keys), ["agent-1", "agent-3"])
        let finished = try XCTUnwrap(session.finishedSubagents.first)
        XCTAssertEqual(finished.agentId, "agent-2")
        XCTAssertEqual(finished.taskDescription, "Find push channels")
        XCTAssertEqual(finished.toolCount, 1)
        XCTAssertNotNil(finished.finishedAt)
        XCTAssertEqual(finished.status, .idle)
        XCTAssertTrue(finished.resultSummary?.contains("PushChannelKind") == true)
        XCTAssertEqual(session.subagentTimeline.map(\.agentId).count, 3)
    }

    func testTaskNotificationsAreNotShownAsTheUsersPrompt() throws {
        let session = try replay()
        XCTAssertEqual(session.lastUserPrompt, "Spawn three subagents and report back.")
        XCTAssertFalse(session.recentMessages.contains { $0.isUser && $0.text.contains("task-notification") })
    }

    func testTheWholeRunEndsWithThreeFinishedAndNoneRunning() throws {
        let session = try replay()
        XCTAssertTrue(session.subagents.isEmpty)
        XCTAssertEqual(session.finishedSubagents.map(\.agentId), ["agent-2", "agent-3", "agent-1"])
        XCTAssertEqual(session.finishedSubagents.first { $0.agentId == "agent-3" }?.resultSummary, "148")
        XCTAssertEqual(session.status, .idle)
    }

    func testTheNextRealPromptClearsLastTurnsSubagents() throws {
        var session = try replay()
        session = try reduce(session, [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "orch-1",
            "prompt": "Now fix it.",
        ])
        XCTAssertTrue(session.finishedSubagents.isEmpty)
        XCTAssertEqual(session.lastUserPrompt, "Now fix it.")
    }

    func testFinishedListIsCapped() {
        var session = SessionSnapshot()
        for i in 0..<(SessionSnapshot.maxFinishedSubagents + 3) {
            session.recordFinishedSubagent(SubagentState(agentId: "a\(i)", agentType: "Explore"))
        }
        XCTAssertEqual(session.finishedSubagents.count, SessionSnapshot.maxFinishedSubagents)
        XCTAssertEqual(session.finishedSubagents.first?.agentId, "a3")
    }

    func testTaskNotificationDetection() {
        XCTAssertTrue(isTaskNotificationPrompt("  <task-notification>\n<task-id>x</task-id>"))
        XCTAssertFalse(isTaskNotificationPrompt("explain <task-notification> tags"))
    }
}
