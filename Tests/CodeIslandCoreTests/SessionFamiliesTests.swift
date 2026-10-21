import XCTest
@testable import CodeIslandCore

/// Claude desktop sessions that start other sessions. Payload shapes follow
/// real transcripts (Claude Code 2.1.304); ids and text are made up.
final class SessionFamiliesTests: XCTestCase {
    private func reduce(_ sessions: inout [String: SessionSnapshot], _ json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        _ = reduceEvent(sessions: &sessions, event: try XCTUnwrap(HookEvent(from: data)), maxHistory: 20)
    }

    // MARK: Prompts

    func testHostInjectedPromptsAreNotUserTurns() {
        let sideSession = "<system-reminder>\n[SYSTEM NOTIFICATION]\n</system-reminder>\n<side-sessions-event>\nSession \"X\" ended its turn.\n</side-sessions-event>"
        XCTAssertEqual(classifySubmittedPrompt(sideSession), .injected)
        XCTAssertEqual(classifySubmittedPrompt("<task-notification>\n<task-id>a1</task-id>\n</task-notification>"), .injected)
        XCTAssertEqual(classifySubmittedPrompt("<system-reminder>cut short by the hook"), .injected)
    }

    func testTypedTextSurvivesAnAppendedReminder() {
        XCTAssertEqual(classifySubmittedPrompt("Fix the build\n<system-reminder>files changed</system-reminder>"), .typed("Fix the build"))
        XCTAssertEqual(classifySubmittedPrompt("explain <div> tags"), .typed("explain <div> tags"))
    }

    func testASpawnBriefDropsItsHeader() {
        let brief = "Background (from the session that started this one):\nDider asked for cockpit fixes."
        XCTAssertEqual(classifySubmittedPrompt(brief), .spawnBrief("Dider asked for cockpit fixes."))
    }

    func testReducerKeepsTheUsersPromptOverASideSessionNote() throws {
        var sessions: [String: SessionSnapshot] = [:]
        try reduce(&sessions, ["hook_event_name": "UserPromptSubmit", "session_id": "p", "prompt": "Order cockpit UI fixes"])
        try reduce(&sessions, ["hook_event_name": "UserPromptSubmit", "session_id": "p",
                               "prompt": "<system-reminder>note</system-reminder><side-sessions-event>done</side-sessions-event>"])
        XCTAssertEqual(sessions["p"]?.lastUserPrompt, "Order cockpit UI fixes")
        XCTAssertEqual(sessions["p"]?.recentMessages.filter(\.isUser).count, 1)
    }

    func testReducerMarksASpawnedSessionAndShowsItsBrief() throws {
        var sessions: [String: SessionSnapshot] = [:]
        try reduce(&sessions, ["hook_event_name": "UserPromptSubmit", "session_id": "c",
                               "prompt": "Background (from the session that started this one):\nShow only the buttons that work."])
        XCTAssertEqual(sessions["c"]?.wasSpawnedBySession, true)
        XCTAssertEqual(sessions["c"]?.lastUserPrompt, "Show only the buttons that work.")
    }

    // MARK: Linking

    private func spawn(_ sessions: inout [String: SessionSnapshot], parent: String, title: String, tool: String = "mcp__ccd_session__start_session") throws {
        try reduce(&sessions, [
            "hook_event_name": "PostToolUse", "session_id": parent, "tool_name": tool,
            "tool_input": ["title": title, "initiation": "user_asked", "context": "fresh"],
            "tool_response": [["type": "text", "text": "Started session \"\(title)\" (session_id: local_x)"]],
        ])
    }

    private func child(_ sessions: inout [String: SessionSnapshot], _ id: String, title: String, startedAfter seconds: TimeInterval = 5) {
        var child = SessionSnapshot()
        child.sessionTitle = title
        child.sessionTitleSource = .claudeCustomTitle
        child.startTime = Date().addingTimeInterval(seconds)
        sessions[id] = child
    }

    func testAChildLinksToTheSessionThatStartedIt() throws {
        var sessions: [String: SessionSnapshot] = [:]
        try spawn(&sessions, parent: "mantsu", title: "OC-EXE-25-1 cockpit actions (deliver)")
        child(&sessions, "oc-exe", title: "OC-EXE-25-1 cockpit actions (deliver)")
        child(&sessions, "other", title: "Unrelated work")
        SessionFamilies.link(&sessions)
        XCTAssertEqual(sessions["oc-exe"]?.parentSessionId, "mantsu")
        XCTAssertNil(sessions["other"]?.parentSessionId)
        XCTAssertNil(sessions["mantsu"]?.parentSessionId)
    }

    func testTheDesktopIdInTheToolResultLinksExactly() throws {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["mantsu"] = SessionSnapshot()
        sessions["mantsu"]?.claudeDesktopSessionId = "local_aaaa-1111"
        try spawn(&sessions, parent: "mantsu", title: "Deliver OC-EXE-25-1")
        XCTAssertEqual(sessions["mantsu"]?.spawnedDesktopSessionIds.keys.sorted(), ["local_x"])

        try reduce(&sessions, [
            "hook_event_name": "PostToolUse", "session_id": "mantsu", "tool_name": "mcp__ccd_session__start_session",
            "tool_input": ["title": "Second task"],
            "tool_response": [["type": "text", "text": "Started session \"Second task\" (session_id: local_c0bc55c7-34ad, name: second). Parent is local_aaaa-1111."]],
        ])
        XCTAssertNotNil(sessions["mantsu"]?.spawnedDesktopSessionIds["local_c0bc55c7-34ad"])
        XCTAssertNil(sessions["mantsu"]?.spawnedDesktopSessionIds["local_aaaa-1111"], "never its own id")

        // Renamed and started late: the id still matches.
        child(&sessions, "oc-exe", title: "Something else", startedAfter: 3 * 3600)
        sessions["oc-exe"]?.claudeDesktopSessionId = "local_c0bc55c7-34ad"
        SessionFamilies.link(&sessions)
        XCTAssertEqual(sessions["oc-exe"]?.parentSessionId, "mantsu")
    }

    func testDesktopIdsAreFoundInAnyResultShape() {
        XCTAssertEqual(desktopSessionIds(in: "session_id: local_ab-12."), ["local_ab-12"])
        XCTAssertEqual(desktopSessionIds(in: ["text": ["local_x1", "and local_x1"]]), ["local_x1"])
        XCTAssertEqual(desktopSessionIds(in: "no ids, just local_"), [])
    }

    func testHandOffAlsoLinks() throws {
        var sessions: [String: SessionSnapshot] = [:]
        try spawn(&sessions, parent: "p", title: "Moved task", tool: "mcp__ccd_session__hand_off_to_session")
        child(&sessions, "c", title: "Moved task")
        SessionFamilies.link(&sessions)
        XCTAssertEqual(sessions["c"]?.parentSessionId, "p")
    }

    func testAChildFromLongBeforeTheSpawnIsNotLinked() throws {
        var sessions: [String: SessionSnapshot] = [:]
        try spawn(&sessions, parent: "p", title: "Same name")
        child(&sessions, "old", title: "Same name", startedAfter: -3600)
        child(&sessions, "late", title: "Same name", startedAfter: SessionFamilies.linkWindow + 60)
        SessionFamilies.link(&sessions)
        XCTAssertNil(sessions["old"]?.parentSessionId)
        XCTAssertNil(sessions["late"]?.parentSessionId)
    }

    func testTheLatestSpawnWinsAndLinksStick() throws {
        var sessions: [String: SessionSnapshot] = [:]
        try spawn(&sessions, parent: "first", title: "Fix tests")
        sessions["first"]?.spawnedSessionTitles["Fix tests"] = Date().addingTimeInterval(-30)
        try spawn(&sessions, parent: "second", title: "Fix tests")
        child(&sessions, "c", title: "Fix tests")
        SessionFamilies.link(&sessions)
        XCTAssertEqual(sessions["c"]?.parentSessionId, "second")

        sessions["c"]?.sessionTitle = "Renamed by the user"
        SessionFamilies.link(&sessions)
        XCTAssertEqual(sessions["c"]?.parentSessionId, "second")
    }

    // MARK: Nesting

    private func family(_ links: [String: String]) -> [String: SessionSnapshot] {
        var sessions: [String: SessionSnapshot] = [:]
        for id in ["a", "b", "c", "d", "e"] {
            var s = SessionSnapshot()
            s.parentSessionId = links[id]
            sessions[id] = s
        }
        return sessions
    }

    func testChildrenSitUnderTheirParent() {
        let sessions = family(["c": "a", "e": "c"])
        let rows = SessionFamilies.nest(["a", "b", "c", "d", "e"], sessions: sessions)
        XCTAssertEqual(rows.map(\.id), ["a", "c", "e", "b", "d"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 0, 0])
    }

    func testAChildThatNeedsYouPullsItsFamilyUp() {
        // "c" waits on you and sorts first; its parent "a" was last.
        let sessions = family(["c": "a"])
        let rows = SessionFamilies.nest(["c", "b", "a"], sessions: sessions)
        XCTAssertEqual(rows.map(\.id), ["a", "c", "b"])
    }

    func testAChildWhoseParentIsGoneStaysFlat() {
        let sessions = family(["c": "gone"])
        XCTAssertEqual(SessionFamilies.nest(["a", "c"], sessions: sessions).map(\.depth), [0, 0])
    }

    func testAParentCountsItsBusyDescendants() {
        var sessions = family(["b": "a", "c": "a", "d": "c"])
        sessions["b"]?.status = .running
        sessions["c"]?.status = .idle
        sessions["d"]?.status = .waitingApproval
        XCTAssertEqual(SessionFamilies.activeDescendants(of: "a", in: sessions), 2, "b, and grandchild d")
        XCTAssertEqual(SessionFamilies.activeDescendants(of: "c", in: sessions), 1)
        XCTAssertEqual(SessionFamilies.activeDescendants(of: "e", in: sessions), 0)

        var cycle = family(["a": "b", "b": "a"])
        cycle["a"]?.status = .running
        XCTAssertEqual(SessionFamilies.activeDescendants(of: "a", in: cycle), 0, "never counts itself")
        XCTAssertEqual(SessionFamilies.activeDescendants(of: "b", in: cycle), 1)
    }

    func testACycleDoesNotHang() {
        let sessions = family(["a": "b", "b": "a"])
        XCTAssertEqual(Set(SessionFamilies.nest(["a", "b"], sessions: sessions).map(\.id)), ["a", "b"])
    }
}
