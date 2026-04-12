// Sources/BenchmarkViews.swift
import SwiftUI

struct ModelHistorySparkline: View {
    let points: [ModelHistoryPoint]

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
                with: .color(.primary.opacity(0.55)),
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
