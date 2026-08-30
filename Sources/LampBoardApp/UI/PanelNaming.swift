import LampBoardCore
import AppKit

/// Opening a project, and the three levels of name.
///
/// Split out of `PanelController` when it reached the 800-line ceiling, and this
/// is the seam that was already there: what stays in that file is the panel as a
/// window, where it sits and how tall it is and what it draws, while these four
/// are about what a person calls things and what they choose to see.
///
/// Three levels of name, and only two survive a restart, because only two can. A
/// folder is durable and an agent inside a folder is durable; a session id dies
/// with its process, so a name stored against one lives exactly as long as the
/// conversation it names. That is the honest bargain, and the menu says it rather
/// than letting somebody find out.
extension PanelController {

    /// "Rename…": the name the row shows, by folder, and nothing else changes.
    ///
    /// A blank answer puts the original back — the field is prefilled with the
    /// current name, so clearing it is the gesture for "undo".
    func rename(_ row: ColumnRow) {
        guard let answer = Alerts.ask(
            title: "Rename “\(row.displayName)”",
            message: "Only what the panel shows changes. The session, its window and its "
                + "folder (\(row.workspace.path)) keep their names. Leave it empty to go back to the original.",
            initialValue: row.alias ?? "",
            placeholder: row.workspace.name,
            confirmTitle: "Rename"
        ) else { return }
        // The row is the project, so this names the project. A conversation is
        // named from the extended window, where the lines are conversations, and
        // an agent's lane from the entry beside this one.
        preferences.rowNames = RowNames.renaming(
            row.workspace.path, to: answer, in: preferences.rowNames
        )
        store.republish()
        rebuildContent()
    }

    /// Opens or closes a project's conversations, and remembers it.
    ///
    /// Remembered across launches on purpose. Opening is a statement about the
    /// project, "I want to see inside this one", and one that evaporated at quit
    /// would have to be made again every morning. It also stays when the project
    /// falls back to a single conversation: it is not a statement about how many
    /// there are right now, and a setting that undid itself would not come back
    /// when a second one started.
    func toggleExpansion(_ row: ColumnRow) {
        preferences.expandedRows = Preferences.toggling(row.id, in: preferences.expandedRows)
        rebuildContent()
        resizeToFit(store.state)
    }

    /// Raises one conversation and clears **only** that one.
    ///
    /// Strictly better than what a click on a group used to do, which cleared
    /// every session sharing the most urgent state: opening a project could take
    /// an unread answer with it.
    func activate(session member: RowSession) {
        store.markSeen(sessionId: member.id)
        let row = ColumnRow(
            id: member.id,
            workspace: member.session.workspace,
            sessions: [member.session],
            alias: member.name
        )
        activate(row, markSeen: false)
    }

    /// Moves one conversation up or down inside its project.
    ///
    /// A menu entry rather than a drag, and deliberately: the column's drag
    /// already reorders projects, and a second drag nested inside a block would be
    /// two gestures a few points apart doing different things. The entry says what
    /// it does and cannot be started by accident.
    ///
    /// The order is stored by session id, so it lasts as long as the conversation
    /// and no longer. That is said on the menu rather than discovered: a
    /// conversation has no identity that outlives its process, and inventing one
    /// would mean a place that pointed at nothing after the next restart.
    func move(_ member: RowSession, in row: ColumnRow, by offset: Int) {
        let shown = row.members.map(\.id)
        let current = preferences.conversationOrder[row.id] ?? shown
        var next = preferences.conversationOrder
        next[row.id] = RowOrder.moving(member.id, by: offset, among: shown, in: current)
        preferences.conversationOrder = next
        store.republish()
        rebuildContent()
    }

    /// Names one conversation, and nothing else.
    func rename(session member: RowSession) {
        guard let answer = Alerts.ask(
            title: "Rename \u{201C}\(member.name)\u{201D}",
            message: "Only this conversation. Its project keeps its own name, and so "
                + "does every other conversation in it. Leave it empty to go back to "
                + "the original.",
            initialValue: RowNames.name(ofSession: member.id, in: preferences.rowNames) ?? "",
            placeholder: member.session.title ?? "#\(member.ordinal)",
            confirmTitle: "Rename"
        ) else { return }
        preferences.rowNames = RowNames.renaming(session: member.id, to: answer, in: preferences.rowNames)
        store.republish()
        rebuildContent()
    }

    /// Names this agent's lane in this project.
    ///
    /// A lane and not a conversation, and the menu says so: a second Codex
    /// session opened here tomorrow will carry this name too. That is what a name
    /// per agent means, and it is the only per-agent name that can be kept, since
    /// a conversation's own id dies with its process.
    func renameLane(of member: RowSession) {
        let harness = member.session.harness
        let path = member.session.workspace.path
        guard let answer = Alerts.ask(
            title: "Rename the \(harness.displayName) lane",
            message: "Every \(harness.displayName) conversation in this project that has no "
                + "name of its own will be called this, including ones opened later. "
                + "Leave it empty to go back to the project's own name.",
            initialValue: RowNames.name(of: path, harness: harness, in: preferences.rowNames) ?? "",
            placeholder: RowNames.name(of: path, in: preferences.rowNames) ?? member.session.workspace.name,
            confirmTitle: "Rename"
        ) else { return }
        preferences.rowNames = RowNames.renaming(
            path, harness: harness, to: answer, in: preferences.rowNames
        )
        store.republish()
        rebuildContent()
    }

}
