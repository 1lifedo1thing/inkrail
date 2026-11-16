// Native type-check-only fixture. No view lifecycle or runtime assertions.
import SwiftUI

@MainActor
private struct StateCompatibilityProbe: View {
    @InkrailState private var search = ""
    @InkrailState private var hovered = false
    @InkrailState private var items: [String] = []
    @InkrailState private var pending: String?
    @InkrailState private var sequence = 0

    init(initialSearch: String = "") {
        _search = InkrailState(initialValue: initialSearch)
    }

    var body: some View {
        VStack {
            TextField("Search", text: $search)
            Toggle("Hover", isOn: $hovered)
            Button("Change state") { advance() }
        }
        .onHover { hovered = $0 }
        .alert("Pending", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            Button("Clear") { pending = nil }
        }
    }

    private func advance() {
        sequence += 1
        items.append(search)
        pending = search
    }
}
