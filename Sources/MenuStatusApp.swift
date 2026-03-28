import SwiftUI

@main
struct MenuStatusApp: App {
    @State private var store: StatusStore

    init() {
        let store = StatusStore()
        store.startPolling()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuContentView(store: store)
        } label: {
            Label {
                Text("MenuStatus")
            } icon: {
                Image(systemName: store.overallIndicator.sfSymbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(store.overallIndicator.color)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
