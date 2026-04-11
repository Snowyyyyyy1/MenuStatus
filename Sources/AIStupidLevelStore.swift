import Foundation
import Observation

@MainActor
@Observable
final class AIStupidLevelStore {
    var scores: [BenchmarkScore] = []
    var globalIndex: GlobalIndex?
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private(set) var pollInterval: TimeInterval = 300

    func startPolling(interval: TimeInterval) {
        stopPolling()
        pollInterval = max(60, interval)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                do {
                    try await Task.sleep(for: .seconds(self?.pollInterval ?? 300))
                } catch {
                    if Task.isCancelled { break }
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshNow() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let scoresTask = AIStupidLevelClient.fetchScores()
        async let globalTask = AIStupidLevelClient.fetchGlobalIndex()

        do {
            let fetchedScores = try await scoresTask
            self.scores = fetchedScores
        } catch {
            errorMessage = "Benchmark scores: \(error.localizedDescription)"
        }

        do {
            let fetchedIndex = try await globalTask
            self.globalIndex = fetchedIndex
        } catch {
            if errorMessage == nil {
                errorMessage = "Global index: \(error.localizedDescription)"
            }
        }

        lastRefreshed = Date()
        isLoading = false
    }

    func summary(forVendor vendor: String) -> BenchmarkVendorSummary {
        BenchmarkVendorSummary.build(from: scores, vendor: vendor)
    }

    func hasAnyData(forVendors vendors: Set<String>) -> Bool {
        let lowered = Set(vendors.map { $0.lowercased() })
        return scores.contains { lowered.contains($0.provider.lowercased()) }
    }
}
