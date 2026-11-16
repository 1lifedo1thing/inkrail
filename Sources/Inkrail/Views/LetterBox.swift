import SwiftUI
import InkrailCore

private struct LetterMonth: Identifiable {
    let date: Date
    let pages: [Page]
    var id: Date { date }
}

@MainActor
struct LetterBox: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @InkrailState private var search = ""
    @InkrailState private var showDeleted = false
    @InkrailState private var deleted: [Page] = []
    @InkrailState private var pageToDelete: Page?

    private var groups: [LetterMonth] {
        let source = showDeleted ? deleted : model.pages
        let filtered = source.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { page in
            calendar.date(from: calendar.dateComponents([.year, .month], from: page.modifiedAt)) ?? page.modifiedAt
        }
        return grouped.keys.sorted(by: >).map { date in
            LetterMonth(date: date, pages: (grouped[date] ?? []).sorted { $0.modifiedAt > $1.modifiedAt })
        }
    }

    var body: some View {
        ZStack {
            DeskPalette.paper
            Image("paper-grain", bundle: InkrailResources.bundle).resizable(resizingMode: .tile).opacity(0.25)
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(showDeleted ? "Recently deleted." : "Your letter box.")
                            .font(.custom("Courier", size: 24))
                        Text(showDeleted ? "Restorable for 30 days, then permanently deleted." : "Everything you left on the page.")
                            .font(.custom("Courier", size: 11)).foregroundColor(DeskPalette.mutedInk)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                }
                HStack {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(DeskPalette.mutedInk)
                    TextField("Find a word, find a letter…", text: $search)
                        .textFieldStyle(.plain).font(.custom("Courier", size: 13))
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Rectangle().fill(DeskPalette.ink.opacity(0.2)).frame(height: 0.5) }
                if showDeleted, let warning = model.trashMaintenanceWarning {
                    Text(warning).font(.system(size: 11))
                        .foregroundColor(DeskPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        if groups.isEmpty {
                            Text(showDeleted ? "No recently deleted letters." : "No letters found.")
                                .font(.custom("Courier", size: 13)).foregroundColor(DeskPalette.mutedInk)
                                .padding(.vertical, 36)
                        }
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.date.formatted(.dateTime.month(.wide).year()).uppercased())
                                    .font(.custom("Courier", size: 10)).tracking(1.4)
                                    .foregroundColor(DeskPalette.mutedInk).padding(.bottom, 8)
                                ForEach(group.pages) { page in row(page) }
                            }
                        }
                    }
                }
                HStack {
                    Button(showDeleted ? "Back to letters" : "Recently deleted") {
                        showDeleted.toggle()
                        if showDeleted { deleted = model.deletedPages() }
                    }
                    .buttonStyle(.plain).font(.custom("Courier", size: 11))
                    Spacer()
                    if !showDeleted {
                        Button("Import") { model.importText() }.buttonStyle(.plain)
                        Button("+ New letter") { model.createPage() }
                            .buttonStyle(.plain).padding(.leading, 16)
                    }
                }
                .font(.custom("Courier", size: 12))
            }
            .padding(32)
        }
        .foregroundColor(DeskPalette.ink)
        .frame(width: 640, height: 690)
        .preferredColorScheme(.light)
        .onChange(of: model.trashRevision) { _ in
            if showDeleted { deleted = model.deletedPages() }
        }
        .alert("Move this letter to Recently Deleted?", isPresented: Binding(
            get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pageToDelete = nil }
            Button("Move Letter", role: .destructive) {
                if let pageToDelete { model.moveToTrash(pageToDelete.id) }
                pageToDelete = nil
            }
        } message: { Text("You can restore it from the letter box for 30 days. After that, it will be permanently deleted.") }
    }

    private func row(_ page: Page) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                if !showDeleted { model.select(page.id) }
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(page.title).font(.custom("Courier", size: 14)).lineLimit(1)
                        Spacer()
                        Text(page.modifiedAt.formatted(.dateTime.day()))
                            .font(.custom("Courier", size: 11)).foregroundColor(DeskPalette.mutedInk)
                    }
                    Text(page.preview.isEmpty ? "An unwritten page." : page.preview)
                        .font(.custom("Courier", size: 11)).lineSpacing(3)
                        .foregroundColor(DeskPalette.mutedInk).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(page.title)")
            if showDeleted {
                Button("Restore") {
                    model.restore(page.id)
                    deleted = model.deletedPages()
                }.buttonStyle(.plain).font(.custom("Courier", size: 11))
            } else {
                Button { pageToDelete = page } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundColor(DeskPalette.mutedInk.opacity(0.6))
                }
                .buttonStyle(.plain).help("Move to Recently Deleted").accessibilityLabel("Delete \(page.title)")
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 3).fill(page.id == model.selectedID && !showDeleted ? Color.black.opacity(0.035) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(DeskPalette.ink.opacity(0.10)).frame(height: 0.5) }
    }
}
