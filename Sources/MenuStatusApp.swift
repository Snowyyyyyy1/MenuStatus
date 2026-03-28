import SwiftUI

@main
struct MenuStatusApp: App {
    @State private var store = StatusStore()

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
