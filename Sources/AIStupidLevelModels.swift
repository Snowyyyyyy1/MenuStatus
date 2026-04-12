// Sources/AIStupidLevelModels.swift
import Foundation
import SwiftUI

// MARK: - Raw API Types

/// GET /api/dashboard/scores → { success, data: [BenchmarkScore] }
struct BenchmarkScoresResponse: Decodable {
    let success: Bool
    let data: [BenchmarkScore]
}

struct BenchmarkScore: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let currentScore: Double
    let trend: BenchmarkTrend
    let status: BenchmarkStatus
    let confidenceLower: Double?
    let confidenceUpper: Double?
    let standardError: Double?
    let isStale: Bool?
    let lastUpdated: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, currentScore, trend, status
        case confidenceLower, confidenceUpper, standardError, isStale, lastUpdated
    }
}

enum BenchmarkTrend: String, Decodable {
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

enum BenchmarkStatus: String, Decodable {
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
struct GlobalIndexResponse: Decodable {
    let success: Bool
    let data: GlobalIndex
}

struct GlobalIndex: Decodable {
    let current: GlobalIndexPoint
    let history: [GlobalIndexPoint]
    let trend: String
    let performingWell: Int?
    let totalModels: Int?
    let lastUpdated: String?
}

struct GlobalIndexPoint: Decodable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let label: String
    let globalScore: Double
    let modelsCount: Int?
    let hoursAgo: Int
}

