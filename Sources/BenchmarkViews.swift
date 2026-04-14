// Sources/BenchmarkViews.swift
import SwiftUI

enum BenchmarkHoverStyle {
    static let tooltipWidth: CGFloat = 250
}

struct BenchmarkRowHoverInfo {
    let score: BenchmarkScore
    let anchorX: CGFloat
    let rowMinY: CGFloat
    let rowMaxY: CGFloat
}

struct ModelHistorySparkline: View {
    let points: [ModelHistoryPoint]
    var lineColor: Color = .primary.opacity(0.55)

    private var values: [Double] {
        points.compactMap { $0.stupidScore ?? $0.displayScore }
    }

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 100
            let range = max(1, maxV - minV)

            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
                let y = size.height - CGFloat((value - minV) / range) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(
                path,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct ScoreBar: View {
    let score: Double
    let lower: Double?
    let upper: Double?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let clampedScore = min(100, max(0, score))
            let scoreWidth = w * clampedScore / 100

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                if let lower, let upper {
                    let lowerClamped = min(100, max(0, lower))
                    let upperClamped = min(100, max(0, upper))
                    let ciStart = w * lowerClamped / 100
                    let ciEnd = w * upperClamped / 100
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.25))
                        .frame(width: max(0, ciEnd - ciStart))
                        .offset(x: ciStart)
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .frame(width: scoreWidth)
            }
        }
    }
}

struct BenchmarkModelHoverCard: View {
    let score: BenchmarkScore
    let detail: BenchmarkModelDetail?
    let stats: BenchmarkModelStats?
    let history: ModelHistoryPayload?
    @Environment(\.colorScheme) private var colorScheme

    private static let timestampFormatter = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var displayName: String {
        detail?.displayName?.nilIfBlank ?? score.name
    }

    private var metadataLines: [String] {
        [detail?.version?.nilIfBlank, detail?.notes?.nilIfBlank].compactMap { $0 }
    }

    private var freshnessLabel: String {
        guard let raw = score.lastUpdated ?? detail?.latestScore?.ts else {
            return "Update time unavailable"
        }
        guard let date = Self.timestampFormatter.date(from: raw) else {
            return raw
        }

        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
        if score.isStale == true {
            return "Stale • \(relative)"
        }
        return "Updated \(relative)"
    }

    private var sparklinePoints: [ModelHistoryPoint] {
        guard let history else { return [] }
        return Array(history.history.prefix(32))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    ForEach(metadataLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(HoverSurfaceStyle.secondaryTextOpacity(for: colorScheme)))
                            .lineLimit(2)
                    }

                    Text(freshnessLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.primary.opacity(HoverSurfaceStyle.tertiaryTextOpacity(for: colorScheme)))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    VendorChip(vendor: detail?.vendor ?? score.provider)

                    HStack(spacing: 4) {
                        Image(systemName: score.trend.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(score.trend.color)

                        Text("\(Int(score.currentScore.rounded()))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(score.status.color)
                    }
                }
            }

            ScoreBar(
                score: score.currentScore,
                lower: score.confidenceLower,
                upper: score.confidenceUpper,
                color: score.status.color
            )
            .frame(height: 8)

            if detail?.usesReasoningEffort == true || detail?.supportsToolCalling == true {
                HStack(spacing: 6) {
                    if detail?.usesReasoningEffort == true {
                        BenchmarkBadge(label: "Reasoning", color: .blue)
                    }
                    if detail?.supportsToolCalling == true {
                        BenchmarkBadge(label: "Tools", color: .purple)
                    }
                }
            }

            if let stats {
                HStack(spacing: 10) {
                    BenchmarkStatItem(title: "Runs", value: stats.totalRuns.map(String.init) ?? "--")
                    BenchmarkStatItem(title: "Success", value: formatPercent(stats.successRate))
                    BenchmarkStatItem(title: "Latency", value: formatLatency(stats.averageLatency))
                    BenchmarkStatItem(title: "Correct", value: formatFraction(stats.averageCorrectness))
                }
            }

            if sparklinePoints.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECENT TREND")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)

                    ModelHistorySparkline(points: sparklinePoints, lineColor: score.status.color.opacity(0.9))
                        .frame(height: 28)
                }
            }
        }
        .frame(width: BenchmarkHoverStyle.tooltipWidth)
        .readableHoverSurface()
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    private func formatLatency(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))ms"
    }

    private func formatFraction(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }
}

private struct BenchmarkStatItem: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.primary.opacity(HoverSurfaceStyle.tertiaryTextOpacity(for: colorScheme)))

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BenchmarkBadge: View {
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(colorScheme == .dark ? 0.20 : 0.12))
            )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
