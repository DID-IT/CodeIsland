import Foundation

/// A real Claude Code run, recorded through every hook and sanitized: an
/// orchestrator spawns two Explore subagents and one background
/// general-purpose agent in one message, then waits for all three.
/// Agent ids, paths, prompts and tool-use ids are replaced; the event
/// order, keys and shapes are exactly what Claude Code 2.1.300 sent.
enum OrchestratorFixture {
    static let jsonl = #"""
{"hook_event_name":"SessionStart","session_id":"orch-1","cwd":"/tmp/orch-project"}
{"hook_event_name":"UserPromptSubmit","session_id":"orch-1","cwd":"/tmp/orch-project","prompt":"Spawn three subagents and report back."}
{"hook_event_name":"PreToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","tool_name":"Agent","tool_use_id":"tu-zEsTbv","tool_input":{"description":"Find Sparkle usage","subagent_type":"Explore"}}
{"hook_event_name":"SubagentStart","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-1","agent_type":"Explore"}
{"hook_event_name":"PostToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","tool_name":"Agent","tool_use_id":"tu-zEsTbv","tool_input":{"description":"Find Sparkle usage","subagent_type":"Explore"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"agent-1","description":"Find Sparkle usage","resolvedModel":"claude-sonnet-5-5"}}
{"hook_event_name":"PreToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","tool_name":"Agent","tool_use_id":"tu-KSUjtH","tool_input":{"description":"Find push channels","subagent_type":"Explore"}}
{"hook_event_name":"SubagentStart","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-2","agent_type":"Explore"}
{"hook_event_name":"PostToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","tool_name":"Agent","tool_use_id":"tu-KSUjtH","tool_input":{"description":"Find push channels","subagent_type":"Explore"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"agent-2","description":"Find push channels","resolvedModel":"claude-sonnet-5-5"}}
{"hook_event_name":"PreToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","tool_name":"Agent","tool_use_id":"tu-sQT6Bj","tool_input":{"description":"Count Swift files","subagent_type":"general-purpose","run_in_background":true}}
{"hook_event_name":"SubagentStart","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-3","agent_type":"general-purpose"}
{"hook_event_name":"PostToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","tool_name":"Agent","tool_use_id":"tu-sQT6Bj","tool_input":{"description":"Count Swift files","subagent_type":"general-purpose","run_in_background":true},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"agent-3","description":"Count Swift files","resolvedModel":"claude-sonnet-5-5"}}
{"hook_event_name":"PreToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-2","agent_type":"Explore","tool_name":"Grep","tool_use_id":"tu-W42jsg","tool_input":{"pattern":"enum\\s+PushChannelKind"}}
{"hook_event_name":"PostToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-2","agent_type":"Explore","tool_name":"Grep","tool_use_id":"tu-W42jsg","tool_input":{"pattern":"enum\\s+PushChannelKind"}}
{"hook_event_name":"SubagentStop","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-2","agent_type":"Explore","background_tasks":[{"id":"agent-1","type":"subagent","status":"running","description":"Find Sparkle usage","agent_type":"Explore"},{"id":"agent-2","type":"subagent","status":"running","description":"Find push channels","agent_type":"Explore"},{"id":"agent-3","type":"subagent","status":"running","description":"Count Swift files","agent_type":"general-purpose"}],"last_assistant_message":"`PushChannelKind` is defined in `/Users/"}
{"hook_event_name":"PreToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-3","agent_type":"general-purpose","tool_name":"Bash","tool_use_id":"tu-2eVBa4","tool_input":{"command":"find Sources -name '*.swift' | wc -l"}}
{"hook_event_name":"Stop","session_id":"orch-1","cwd":"/tmp/orch-project","background_tasks":[{"id":"agent-1","type":"subagent","status":"running","description":"Find Sparkle usage","agent_type":"Explore"},{"id":"agent-3","type":"subagent","status":"running","description":"Count Swift files","agent_type":"general-purpose"}],"last_assistant_message":"All three subagents are running. I'm wai"}
{"hook_event_name":"UserPromptSubmit","session_id":"orch-1","cwd":"/tmp/orch-project","prompt":"<task-notification>\n<task-id>agent-2</task-id>\n<status>completed</status>\n</task-notification>"}
{"hook_event_name":"PostToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-3","agent_type":"general-purpose","tool_name":"Bash","tool_use_id":"tu-2eVBa4","tool_input":{"command":"find Sources -name '*.swift' | wc -l"}}
{"hook_event_name":"PreToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-1","agent_type":"Explore","tool_name":"Grep","tool_use_id":"tu-AcsWbV","tool_input":{"pattern":"^\\s*(@\\w+\\s+)?import\\s+Sparkle\\b"}}
{"hook_event_name":"SubagentStop","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-3","agent_type":"general-purpose","background_tasks":[{"id":"agent-1","type":"subagent","status":"running","description":"Find Sparkle usage","agent_type":"Explore"},{"id":"agent-3","type":"subagent","status":"running","description":"Count Swift files","agent_type":"general-purpose"}],"last_assistant_message":"148"}
{"hook_event_name":"PostToolUse","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-1","agent_type":"Explore","tool_name":"Grep","tool_use_id":"tu-AcsWbV","tool_input":{"pattern":"^\\s*(@\\w+\\s+)?import\\s+Sparkle\\b"}}
{"hook_event_name":"Stop","session_id":"orch-1","cwd":"/tmp/orch-project","background_tasks":[{"id":"agent-1","type":"subagent","status":"running","description":"Find Sparkle usage","agent_type":"Explore"}],"last_assistant_message":"Push channels is done. `PushChannelKind`"}
{"hook_event_name":"UserPromptSubmit","session_id":"orch-1","cwd":"/tmp/orch-project","prompt":"<task-notification>\n<task-id>agent-3</task-id>\n<status>completed</status>\n</task-notification>"}
{"hook_event_name":"SubagentStop","session_id":"orch-1","cwd":"/tmp/orch-project","agent_id":"agent-1","agent_type":"Explore","background_tasks":[{"id":"agent-1","type":"subagent","status":"running","description":"Find Sparkle usage","agent_type":"Explore"}],"last_assistant_message":"Sourc"}
{"hook_event_name":"Stop","session_id":"orch-1","cwd":"/tmp/orch-project","background_tasks":[],"last_assistant_message":"Count Swift files is done: there are 148"}
{"hook_event_name":"UserPromptSubmit","session_id":"orch-1","cwd":"/tmp/orch-project","prompt":"<task-notification>\n<task-id>agent-1</task-id>\n<status>completed</status>\n</task-notification>"}
{"hook_event_name":"Stop","session_id":"orch-1","cwd":"/tmp/orch-project","background_tasks":[],"last_assistant_message":"All three subagents finished.\n\n- **Spark"}
{"hook_event_name":"SessionEnd","session_id":"orch-1","cwd":"/tmp/orch-project"}
"""#

    static var lines: [String] {
        jsonl.split(separator: "\n").map(String.init)
    }
}
