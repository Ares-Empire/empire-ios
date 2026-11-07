import SwiftUI

/// Plain board structure on the app's shared pieces. The server owns the ask order.
struct BoardScreen: View {
    let board: BoardStore
    let openSettings: () -> Void
    /// What Patrik typed per ask. Kept until the ask leaves the server's list, so Undo brings it back with the card.
    @State private var drafts: [Int: String] = [:]
    @FocusState private var focused: Int?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AresusHeader(bust: Image("Bust"), title: String(localized: "For you")) {
                    GlassIconButton(symbol: "gearshape", label: String(localized: "Settings"), action: openSettings)
                }
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(text: String(localized: "Waiting on you"))
                    if let notice = board.notice { quiet(notice) }
                    if let error = board.error {
                        if board.waiting != nil { quiet(String(localized: "Not refreshed: \(error)")) }
                        else {
                            CalmMessage(text: error, actionTitle: String(localized: "Try again")) {
                                Task { await board.refresh() }
                            }.padding(.top, 100)
                        }
                    }
                    if let waiting = board.waiting {
                        if board.asks.isEmpty {
                            CalmMessage(text: String(localized: "Nothing waits on you."))
                                .padding(.vertical, waiting.answered.isEmpty && waiting.unowned.count == 0 ? 150 : 40)
                        }
                        ForEach(board.asks) { item in askCard(item) }
                        if !waiting.answered.isEmpty {
                            SectionTitle(text: String(localized: "Answered")).padding(.top, 12)
                            answeredCard(waiting.answered)
                            quiet(String(localized: "Running sessions get their answer right away, the others the next time they run."))
                        }
                        if waiting.unowned.count > 0 { quiet(waiting.unowned.line()).padding(.top, 12) }
                    } else if board.error == nil {
                        CalmLoading().padding(.top, 170)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 90)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await board.refresh() }
        .background { ProvinceWall(accent: .aresus) }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: board.waiting?.asks.map(\.id)) { _, ids in
            let open = Set(ids ?? [])
            drafts = drafts.filter { open.contains($0.key) }
        }
        #if DEBUG
        .task(id: board.waiting != nil) {
            // `-boardOwnWords <text>` fills the first ask's field, for screenshots (the field keeps room for more
            // lines than it shows when filled before its first layout; typed text sizes it exactly).
            guard let text = LaunchArguments.value("-boardOwnWords"), let first = board.asks.first else { return }
            drafts[first.id] = text
        }
        #endif
    }

    /// One ask: "Claude is waiting" when the session stopped for it; the question, why, how long it waited; the
    /// answers (two or three short ones side by side, the first filled, the others outlined; else one under the
    /// other); a field for his own words; then one quiet line of the rarer actions.
    private func askCard(_ item: BoardItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The long-press menu sits on the question, not the whole card: a long press in the field places the
            // cursor or pastes.
            VStack(alignment: .leading, spacing: 0) {
                if item.blocking { waitingLabel.padding(.bottom, 8) }
                Text(verbatim: item.text).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let why = item.why, !why.isEmpty {
                    Text(verbatim: why).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                }
                meta(item).padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Not needed", systemImage: "xmark") { board.perform(.drop, on: item) }
                if let url = item.claudeURL {
                    Button("Ask in Claude", systemImage: "arrow.up.forward.app") { openURL(url) }
                }
            }
            if board.failed.contains(item.id) {
                Text("Not sent. Try again.").font(AppFont.text(12, weight: .medium))
                    .foregroundStyle(StatusTone.issue.color(.aresus)).padding(.top, 8)
            }
            answers(item).padding(.top, 14)
            ownWords(item).padding(.top, 10)
            footer(item).padding(.top, 2)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func meta(_ item: BoardItem) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = board.clock.now(context.date)
            let age = Text(verbatim: item.topic + " · " + BoardWords.age(item.created, now: now)).foregroundStyle(Ink.muted)
            let due = Text(verbatim: item.due.flatMap { BoardWords.due($0) }.map { " · " + $0 } ?? "")
                .foregroundStyle(item.due.map { BoardWords.isDue($0, now: now) } == true
                                 ? StatusTone.issue.color(.aresus) : Ink.muted)
            Text("\(age)\(due)").font(AppFont.text(12))
        }
    }

    @ViewBuilder private func answers(_ item: BoardItem) -> some View {
        if item.options.isEmpty {
            Button("Done") { board.perform(.done, on: item) }.buttonStyle(FormButtonStyle(accent: .aresus))
        } else if item.options.count <= 3 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { optionButtons(item) }
                VStack(spacing: 8) { optionButtons(item) }
            }
        } else {
            VStack(spacing: 8) { optionButtons(item) }
        }
    }

    /// A session that cannot go on without the answer (`board ask --blocking`): small caps styled like the section
    /// headings, in the accent, not the issue red: it asks for attention, nothing is wrong.
    private var waitingLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            Text(verbatim: String(localized: "Claude is waiting").uppercased())
                .font(AppFont.text(11, weight: .semibold)).tracking(1.3)
        }
        .foregroundStyle(AppAccent.aresus.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Claude is waiting"))
    }

    /// Patrik's own words, on every ask (Patrik, 2026-11-07: "a way for me to enter free text"): a field that grows to
    /// five lines; the send arrow shows once there is something to send. It goes the way a tapped answer goes (the undo
    /// bar first), and the session gets the words exactly as typed, trimmed.
    private func ownWords(_ item: BoardItem) -> some View {
        let draft = Binding(get: { drafts[item.id] ?? "" }, set: { drafts[item.id] = $0 })
        let answer = BoardWords.ownAnswer(draft.wrappedValue)
        let length = BoardWords.ownAnswerLength(draft.wrappedValue)
        let field = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                TextField("", text: draft, prompt: Text("Or answer in your own words").foregroundStyle(Ink.muted),
                          axis: .vertical)
                    .lineLimit(1...5)
                    .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                    .focused($focused, equals: item.id)
                    .padding(.vertical, 12)
                    .accessibilityLabel(Text("Your answer"))
                    .accessibilityIdentifier("board-own-answer-\(item.id)")
                if let answer {
                    Button {
                        focused = nil
                        board.perform(.answer(answer), on: item)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                            .foregroundStyle(AppAccent.aresus.color)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Send"))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.leading, 14).padding(.trailing, answer == nil ? 14 : 0)
            .background(Ink.field, in: field)
            .overlay(field.strokeBorder(Ink.line))
            .animation(.easeOut(duration: 0.15), value: answer == nil)
            // Near the server's limit a quiet count, so a missing arrow is never a mystery.
            if length > BoardWords.ownAnswerWarning {
                Text(verbatim: BoardWords.ownAnswerCount(length))
                    .font(AppFont.number(11, weight: .regular))
                    .foregroundStyle(length > BoardWords.ownAnswerLimit ? StatusTone.issue.color(.aresus) : Ink.muted)
            }
        }
    }

    private func optionButtons(_ item: BoardItem) -> some View {
        ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
            Button { board.perform(.answer(option), on: item) } label: { Text(verbatim: option) }
                .buttonStyle(FormButtonStyle(kind: index == 0 ? .primary : .secondary, accent: .aresus))
        }
    }

    /// The rarer actions in one quiet line; Ask in Claude moves under the other two when the line is too narrow.
    private func footer(_ item: BoardItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                footerActions(item)
                Spacer(minLength: 0)
                claudeLink(item)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) { footerActions(item) }
                claudeLink(item)
            }
        }
        .font(AppFont.text(13, weight: .medium)).buttonStyle(.plain)
    }

    @ViewBuilder private func footerActions(_ item: BoardItem) -> some View {
        Button { board.perform(.drop, on: item) } label: { Text("Not needed").lineLimit(1).fixedSize() }
            .foregroundStyle(Ink.muted).frame(minHeight: 40)
            .contentShape(Rectangle())
    }

    @ViewBuilder private func claudeLink(_ item: BoardItem) -> some View {
        if let url = item.claudeURL {
            Button { openURL(url) } label: {
                HStack(spacing: 5) {
                    Text("Ask in Claude").lineLimit(1).fixedSize()
                    Image(systemName: "arrow.up.forward").font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(Ink.secondary).frame(minHeight: 40).contentShape(Rectangle())
        }
    }

    /// Answers on their way to the session that asked: one card, the question quiet and the answer in ink.
    private func answeredCard(_ items: [BoardItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.text).font(AppFont.text(13)).foregroundStyle(Ink.muted).lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.muted)
                        Text(verbatim: item.answer ?? "").font(AppFont.text(15, weight: .medium))
                            .foregroundStyle(Ink.primary).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                if index < items.count - 1 { Rectangle().fill(Ink.line).frame(height: 1) }
            }
        }
        .padding(.horizontal, 16).glassCard()
    }

    private func quiet(_ text: String) -> some View {
        Text(verbatim: text).font(AppFont.text(12)).foregroundStyle(Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
