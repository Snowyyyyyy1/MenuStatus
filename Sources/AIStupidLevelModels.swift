// Sources/AIStupidLevelModels.swift
import Foundation
import SwiftUI

// MARK: - Raw API Types

private enum BenchmarkLossyNumericDecoder {
    static func decodeOptionalDouble<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Double? {
        guard container.contains(key) else { return nil }

        if try container.decodeNil(forKey: key) {
            return nil
        }

        if let value = try? container.decode(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }

        let rawValue = try container.decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty, rawValue.lowercased() != "unavailable" else { return nil }
        guard let value = Double(rawValue), value.isFinite else { return nil }
        return value
    }
}

/// GET /api/dashboard/scores → { success, data: [BenchmarkScore] }
struct BenchmarkScoresResponse: Codable {
    let success: Bool
    let data: [BenchmarkScore]
}

struct BenchmarkScore: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let currentScore: Double?
    let trend: BenchmarkTrend
    let status: BenchmarkStatus
    let confidenceLower: Double?
    let confidenceUpper: Double?
    let standardError: Double?
    let isStale: Bool?
    let lastUpdated: String?

    init(
        id: String,
        name: String,
        provider: String,
        currentScore: Double?,
        trend: BenchmarkTrend,
        status: BenchmarkStatus,
        confidenceLower: Double?,
        confidenceUpper: Double?,
        standardError: Double?,
        isStale: Bool?,
        lastUpdated: String?
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.currentScore = currentScore
        self.trend = trend
        self.status = status
        self.confidenceLower = confidenceLower
        self.confidenceUpper = confidenceUpper
        self.standardError = standardError
        self.isStale = isStale
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(String.self, forKey: .provider)
        currentScore = try BenchmarkLossyNumericDecoder.decodeOptionalDouble(from: container, forKey: .currentScore)
        trend = try container.decode(BenchmarkTrend.self, forKey: .trend)
        status = try container.decode(BenchmarkStatus.self, forKey: .status)
        confidenceLower = try container.decodeIfPresent(Double.self, forKey: .confidenceLower)
        confidenceUpper = try container.decodeIfPresent(Double.self, forKey: .confidenceUpper)
        standardError = try container.decodeIfPresent(Double.self, forKey: .standardError)
        isStale = try container.decodeIfPresent(Bool.self, forKey: .isStale)
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, currentScore, trend, status
        case confidenceLower, confidenceUpper, standardError, isStale, lastUpdated
    }
}

enum BenchmarkTrend: String, Codable {
    case up, down, stable

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BenchmarkTrend(rawValue: raw) ?? .stable
    }

    var symbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .stable: "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: .green
        case .down: .red
        case .stable: .secondary
        }
    }
}

enum BenchmarkStatus: String, Codable {
    case good, warning, critical, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BenchmarkStatus(rawValue: raw) ?? .unknown
    }

    var color: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        case .unknown: .secondary
        }
    }
}

/// GET /api/dashboard/global-index → { success, data: { current, history, trend, ... } }
struct GlobalIndexResponse: Codable {
    let success: Bool
    let data: GlobalIndex
}

struct GlobalIndex: Codable {
    let current: GlobalIndexPoint
    let history: [GlobalIndexPoint]
    let trend: String
    let performingWell: Int?
    let totalModels: Int?
    let lastUpdated: String?
}

struct GlobalIndexPoint: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let label: String
    let globalScore: Double?
    let modelsCount: Int?
    let hoursAgo: Int

    init(
        timestamp: String,
        label: String,
        globalScore: Double?,
        modelsCount: Int?,
        hoursAgo: Int
    ) {
        self.timestamp = timestamp
        self.label = label
        self.globalScore = globalScore
        self.modelsCount = modelsCount
        self.hoursAgo = hoursAgo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        label = try container.decode(String.self, forKey: .label)
        globalScore = try BenchmarkLossyNumericDecoder.decodeOptionalDouble(from: container, forKey: .globalScore)
        modelsCount = try container.decodeIfPresent(Int.self, forKey: .modelsCount)
        hoursAgo = try container.decode(Int.self, forKey: .hoursAgo)
    }
}
