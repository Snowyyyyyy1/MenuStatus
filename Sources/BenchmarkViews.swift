// Sources/BenchmarkViews.swift
import SwiftUI

// MARK: - Global Index Bar (top of menu popover)

struct GlobalIndexBar: View {
    let index: GlobalIndex

    private var trendColor: Color {
        switch index.trend {
        case "improving": return .green
        case "declining": return .red
        default: return .secondary
        }
    }

    private var trendSymbol: String {
        switch index.trend {
        case "improving": return "arrow.up"
        case "declining": return "arrow.down"
        default: return "arrow.right"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("AI Index")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text("\(Int(index.current.globalScore.rounded()))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Image(systemName: trendSymbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(trendColor)

            GlobalIndexSparkline(points: index.history.reversed())
                .frame(height: 16)
                .frame(maxWidth: .infinity)

            Text(index.trend.capitalized)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct GlobalIndexSparkline: View {
    let points: [GlobalIndexPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let scores = points.map(\.globalScore)
            let minV = scores.min() ?? 0
            let maxV = scores.max() ?? 100
            let range = max(1, maxV - minV)

            var path = Path()
            for (i, score) in scores.enumerated() {
                let x = CGFloat(i) / CGFloat(scores.count - 1) * size.width
                let y = size.height - CGFloat((score - minV) / range) * size.height
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                path,
                with: .color(.primary.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Benchmark Section (inside a provider tab)

struct BenchmarkSection: View {
    let summary: BenchmarkVendorSummary
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .scaleEffect(isHovered ? 1.2 : 1.0)

                    Text("Model Benchmarks")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(summaryLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.scores) { score in
                        BenchmarkModelRow(score: score)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var summaryLine: String {
        let count = summary.scores.count
        let avg = Int(summary.averageScore.rounded())
        var parts = ["\(count) model\(count == 1 ? "" : "s")", "avg \(avg)"]
        if summary.warningCount > 0 { parts.append("\(summary.warningCount) warn") }
        if summary.criticalCount > 0 { parts.append("\(summary.criticalCount) crit") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Single Model Row

struct BenchmarkModelRow: View {
    let score: BenchmarkScore

    var body: some View {
        HStack(spacing: 8) {
            Text(score.name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)

            ScoreBar(score: score.currentScore, lower: score.confidenceLower, upper: score.confidenceUpper, color: score.status.color)
                .frame(height: 8)
                .frame(maxWidth: .infinity)

            Text("\(Int(score.currentScore.rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 22, alignment: .trailing)

            Image(systemName: score.trend.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(score.trend.color)
                .frame(width: 10)
        }
    }
}

private struct ScoreBar: View {
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
