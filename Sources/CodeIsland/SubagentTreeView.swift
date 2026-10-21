import SwiftUI
import CodeIslandCore

/// Session-card rows for an orchestrator's subagents: one line per subagent
/// this turn, with the task the orchestrator gave it, what it is doing now,
/// how long it has run and its model. Finished ones stay, dimmed, until the
/// next real user prompt. Click the header to fold the list.
///
/// Lives in its own file so this fork's change to NotchPanelView.swift is a
/// single call site.
struct SubagentTreeView: View {
    let session: SessionSnapshot
    let fontSize: CGFloat
    let showModel: Bool
    /// Subagents with a permission request or question queued on this card.
    let waitingAgentIds: Set<String>

    @State private var expanded = true

    static let agentColor = Color(red: 0.65, green: 0.55, blue: 0.95)
    static let waitingColor = Color(red: 1.0, green: 0.6, blue: 0.25)
    /// Rows per group before the rest fold into "+N more".
    static let maxRunningRows = 6
    static let maxFinishedRows = 4

    private var smallSize: CGFloat { max(9, fontSize - 1) }
    private var running: [SubagentState] {
        session.subagents.values.sorted { $0.startTime < $1.startTime }
    }
    private var finished: [SubagentState] { session.finishedSubagents }

    var body: some View {
        if !running.isEmpty || !finished.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    withAnimation(NotchAnimation.micro) { expanded.toggle() }
                } label: {
                    header
                }
                .buttonStyle(.plain)

                if expanded {
                    // Ticks once a second only while something runs.
                    TimelineView(.periodic(from: .now, by: running.isEmpty ? 3600 : 1)) { context in
                        rows(now: context.date)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.leading, 4)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: smallSize - 1, weight: .semibold))
                .foregroundStyle(Self.agentColor)
            Text(summary)
                .font(.system(size: smallSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        var parts: [String] = []
        if !running.isEmpty { parts.append(String(format: L10n.shared["subagents_running_format"], running.count)) }
        if !finished.isEmpty { parts.append(String(format: L10n.shared["subagents_done_format"], finished.count)) }
        return parts.joined(separator: " · ")
    }

    private func rows(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(running.prefix(Self.maxRunningRows), id: \.agentId) { sub in
                row(sub, now: now)
            }
            if running.count > Self.maxRunningRows {
                moreRow(running.count - Self.maxRunningRows)
            }
            // Newest finished first: what just came back matters most.
            ForEach(finished.reversed().prefix(Self.maxFinishedRows), id: \.agentId) { sub in
                row(sub, now: now)
            }
            if finished.count > Self.maxFinishedRows {
                moreRow(finished.count - Self.maxFinishedRows)
            }
        }
        .padding(.leading, 2)
    }

    /// A narrow card drops the model label before it squeezes the task.
    private func row(_ sub: SubagentState, now: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            rowContent(sub, now: now, includeModel: showModel)
            rowContent(sub, now: now, includeModel: false)
        }
        .help(tooltip(sub))
    }

    private func rowContent(_ sub: SubagentState, now: Date, includeModel: Bool) -> some View {
        let isDone = sub.finishedAt != nil
        let isWaiting = !isDone && waitingAgentIds.contains(sub.agentId)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(glyph(isDone: isDone, isWaiting: isWaiting))
                .foregroundStyle(glyphColor(isDone: isDone, isWaiting: isWaiting))
                .fixedSize()
            Text(sub.agentType)
                .fontWeight(.semibold)
                .foregroundStyle(Self.agentColor.opacity(isDone ? 0.6 : 1))
                .lineLimit(1)
                .fixedSize()
            if let task = sub.taskDescription {
                Text(task)
                    .foregroundStyle(.white.opacity(isDone ? 0.45 : 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            if sub.isBackground {
                Image(systemName: "moon.fill")
                    .font(.system(size: smallSize - 2))
                    .foregroundStyle(.white.opacity(0.4))
                    .help(L10n.shared["subagent_background"])
            }
            Spacer(minLength: 4)
            if isWaiting {
                Text(L10n.shared["subagent_waiting"])
                    .foregroundStyle(Self.waitingColor)
                    .lineLimit(1)
                    .fixedSize()
            } else if !isDone, let tool = sub.currentTool {
                Text(tool)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
            if includeModel, let model = ModelLabel.label(model: sub.model, effort: sub.reasoningEffort) {
                Text(model)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(Self.elapsed(from: sub.startTime, to: sub.finishedAt ?? now))
                .foregroundStyle(.white.opacity(isDone ? 0.4 : 0.6))
                .monospacedDigit()
                .fixedSize()
        }
        .font(.system(size: smallSize, design: .monospaced))
    }

    private func moreRow(_ count: Int) -> some View {
        Text(String(format: L10n.shared["task_progress_more"], count))
            .font(.system(size: smallSize, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
    }

    /// U+FE0E keeps ▶ and ⏸ in text presentation instead of emoji.
    private func glyph(isDone: Bool, isWaiting: Bool) -> String {
        if isDone { return "✓" }
        return isWaiting ? "⏸\u{FE0E}" : "▶\u{FE0E}"
    }

    private func glyphColor(isDone: Bool, isWaiting: Bool) -> Color {
        if isDone { return AgentTaskProgressView.doneColor }
        return isWaiting ? Self.waitingColor : AgentTaskProgressView.activeColor
    }

    private func tooltip(_ sub: SubagentState) -> String {
        var lines = [sub.agentType + (sub.taskDescription.map { ": \($0)" } ?? "")]
        if sub.finishedAt == nil, let tool = sub.currentTool {
            lines.append(tool + (sub.toolDescription.map { " · \($0)" } ?? ""))
        }
        if let result = sub.resultSummary {
            lines.append(String(result.prefix(300)))
        }
        return lines.joined(separator: "\n")
    }

    /// "0:42", "12:05", "1:02:10".
    static func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// "↳ Explore · Find Sparkle usage" above an approval or question that a
/// subagent raised, so the orchestrator's card says who is asking.
struct SubagentRequestOrigin: View {
    let subagent: SubagentState
    let fontSize: CGFloat

    /// The subagent behind a queued request, if it came from one.
    static func subagent(for event: HookEvent, in session: SessionSnapshot?) -> SubagentState? {
        guard let agentId = event.agentId else { return nil }
        return session?.subagents[agentId]
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: fontSize - 2, weight: .semibold))
            Text(subagent.agentType)
                .fontWeight(.semibold)
            if let task = subagent.taskDescription {
                Text("· \(task)")
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .foregroundStyle(SubagentTreeView.agentColor)
    }
}
