import SwiftUI

struct TransactionDetailSheet: View {
    @State var store: TransactionDetailStore
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    @State private var originalExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.isLoading { ProgressView("Loading…").frame(maxWidth: .infinity).padding(30) }
                    if let error = store.loadError {
                        Text(error).foregroundStyle(palette.expense).padding(.vertical)
                        Button("Retry") { Task { await store.load() } }
                    }
                    if let detail = store.detail { record(detail) }
                }.padding(20)
            }
            .background { Wall(palette: palette) }
            .navigationTitle("Transaction").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $store.showsRecategorisation) {
                RecategoriseSheet(store: store, palette: palette)
            }
        }
        .font(AppFont.text(14)).foregroundStyle(palette.ink).tint(palette.balance)
        .preferredColorScheme(palette.dark ? .dark : .light)
        .task {
            if store.detail == nil { await store.load() }
            // Sample-only routing for repeatable simulator screenshots, like the
            // existing -sampleCategory / -sampleMonth launch arguments.
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if store.isSample, let index = arguments.firstIndex(of: "-sampleRecategorise"),
               arguments.indices.contains(index + 1) {
                store.beginRecategorisation()
                store.mode = arguments[index + 1] == "add" ? .add : .switchCategory
            }
            #endif
        }
    }

    @ViewBuilder private func record(_ detail: TransactionDetail) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(detail.place).font(AppFont.text(22, weight: .bold))
            Text(detail.signedAmount).font(AppFont.number(28, weight: .bold))
                .foregroundStyle(detail.amount < 0 ? palette.expense : palette.balance)
            Text(detail.bookingDate).font(AppFont.number(12)).foregroundStyle(palette.muted)
        }.padding(.bottom, 20)
        detailRow("Category") {
            VStack(alignment: .leading, spacing: 8) {
                CategoryChip(name: detail.category, color: detail.categoryColor)
                HStack(spacing: 10) {
                    if let source = detail.categorySource, !source.isEmpty {
                        Text("via \(source)").foregroundStyle(palette.muted)
                    }
                    if !store.choices.isEmpty {
                        Button("Change") { store.beginRecategorisation() }.buttonStyle(.bordered)
                            .controlSize(.small).accessibilityIdentifier("changeCategory")
                    }
                }
            }
        }
        if !detail.tags.isEmpty {
            detailRow("Also in") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detail.tags, id: \.self) { name in
                        CategoryChip(name: name, color: store.categoryColor(for: name))
                    }
                }
            }
        }
        if let account = detail.accountLabel { detailRow("Account") { Text(account) } }
        ForEach(detail.rows) { row in detailRow(row.label) { Text(row.value) } }
        if let rows = detail.originalRows {
            DisclosureGroup("Original \(detail.source) record", isExpanded: $originalExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.label).foregroundStyle(palette.muted)
                            Text(row.value).foregroundStyle(palette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(AppFont.number(11)).padding(.top, 12).textSelection(.enabled)
            }.font(AppFont.text(13)).padding(.top, 20)
        }
    }

    private func detailRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(AppFont.text(12, weight: .semibold)).foregroundStyle(palette.muted)
                .frame(width: 94, alignment: .leading)
            content().font(AppFont.text(13.5)).frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }.padding(.vertical, 10).overlay(alignment: .bottom) { Rectangle().fill(palette.grid).frame(height: 1) }
    }
}

struct CategoryChip: View {
    let name: String
    let color: String
    var body: some View {
        Text(name).font(AppFont.text(12.5, weight: .semibold)).foregroundStyle(Color(hex: color))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(hex: color).opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: color).opacity(0.20)))
    }
}
