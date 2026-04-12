import SwiftUI

struct AIStupidLevelPageView: View {
    let benchmarkStore: AIStupidLevelStore
    let onNavigateToProvider: (ProviderConfig) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("AI Benchmark")
                .font(.headline)
            Text("Coming soon...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}
