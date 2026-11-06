import SwiftUI

/// Plain board structure on the app's shared pieces. The server owns the ask order.
struct BoardScreen: View {
    let board: BoardStore
    let openSettings: () -> Void
    @State private var ownAnswer: BoardItem?
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
                        ForEach(board.asks) { item in
                            askCard(item)
                                .contextMenu {
                                    Button("Not needed", systemImage: "xmark") { board.perform(.drop, on: item) }
                                    if let url = item.claudeURL {
                                        Button("Ask in Claude", systemImage: "arrow.up.forward.app") { openURL(url) }
                                    }
                                }
                        }
                        if !waiting.answered.isEmpty {
                            SectionTitle(text: String(localized: "Answered")).padding(.top, 12)
                            answeredCard(waiting.answered)
                            quiet(String(localized: "Each session gets its answer the next time it runs."))
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
        .refreshable { await board.refresh() }
        .background { ProvinceWall(accent: .aresus) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $ownAnswer) { item in
            BoardOwnAnswerSheet(item: item) { answer in board.perform(.answer(answer), on: item) }
        }
        #if DEBUG
        .task(id: board.waiting != nil) {
            guard ownAnswer == nil, let id = LaunchArguments.value("-openOwnAnswer").flatMap(Int.init),
                  let item = board.asks.first(where: { $0.id == id }) else { return }
            ownAnswer = item
        }
        #endif
    }

    /// One ask: the question, why, how long it waited; the answers (two or three short ones side by side, the first
    /// filled, the others outlined; else one under the other); then one quiet line of the rarer actions.
    private func askCard(_ item: BoardItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: item.text).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let why = item.why, !why.isEmpty {
                Text(verbatim: why).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            meta(item).padding(.top, 10)
            if board.failed.contains(item.id) {
                Text("Not sent. Try again.").font(AppFont.text(12, weight: .medium))
                    .foregroundStyle(StatusTone.issue.color(.aresus)).padding(.top, 8)
            }
            answers(item).padding(.top, 14)
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
        Button { ownAnswer = item } label: { Text("Own answer…").lineLimit(1).fixedSize() }.foregroundStyle(Ink.muted).frame(minHeight: 40).contentShape(Rectangle())
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
                            .foregroundStyle(Ink.primary).fixedSize(horizontal: false, vertical: true)
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

private struct BoardOwnAnswerSheet: View {
    let item: BoardItem
    let send: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: item.text).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                TextField("Your answer", text: $text, axis: .vertical)
                    .lineLimit(5...12).font(AppFont.text(16)).foregroundStyle(Ink.primary)
                    .padding(14).background(Ink.field, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("board-own-answer")
                Button("Send") {
                    guard let answer = BoardWords.ownAnswer(text) else { return }
                    send(answer)
                    dismiss()
                }
                .buttonStyle(FormButtonStyle(accent: .aresus)).disabled(BoardWords.ownAnswer(text) == nil)
                Spacer(minLength: 0)
            }
            .padding(18)
            .background { ProvinceWall(accent: .aresus) }
            .navigationTitle(Text("Own answer…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
    }
}
