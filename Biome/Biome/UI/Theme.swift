import SwiftUI

enum Theme {
    static let accent = Color(red: 0.42, green: 0.86, blue: 0.62)
    static let accentDeep = Color(red: 0.16, green: 0.55, blue: 0.42)
    static let warm = Color(red: 0.98, green: 0.71, blue: 0.36)
    static let danger = Color(red: 0.98, green: 0.45, blue: 0.38)
    static let ink = Color(red: 0.055, green: 0.075, blue: 0.095)
    static let text = Color(white: 0.94)
    static let dim = Color(white: 0.62)
    static let panel = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.11)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.055, green: 0.085, blue: 0.105),
            Color(red: 0.035, green: 0.055, blue: 0.075),
            Color(red: 0.025, green: 0.035, blue: 0.050)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static func panelBackground(corner: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

struct GlassCard<Content: View>: View {
    var corner: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background(Theme.panelBackground(corner: corner))
    }
}

struct StatChip: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
        )
    }
}

struct EnergyGauge: View {
    let energy: Float
    let maxEnergy: Float

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.warm)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.warm.opacity(0.85), Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geometry.size.width * CGFloat(min(1, energy / maxEnergy))))
                }
            }
            .frame(width: 54, height: 6)
            Text("\(Int(energy))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.30)))
    }
}

struct PopulationChart: View {
    let history: [HistorySample]

    var body: some View {
        Canvas { context, size in
            guard history.count > 1 else { return }
            let maxHerb = history.map { $0.herbivores }.max() ?? 1
            let maxValue = max(10, maxHerb)

            func line(_ value: (HistorySample) -> Float, color: Color, width: CGFloat) {
                var path = Path()
                for (index, sample) in history.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(history.count - 1)
                    let y = size.height * (1 - CGFloat(clampf(value(sample) / maxValue, 0, 1)))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
            }

            var plantPath = Path()
            for (index, sample) in history.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(history.count - 1)
                let y = size.height * (1 - CGFloat(clampf(sample.plants, 0, 1)))
                if index == 0 {
                    plantPath.move(to: CGPoint(x: x, y: y))
                } else {
                    plantPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            plantPath.addLine(to: CGPoint(x: size.width, y: size.height))
            plantPath.addLine(to: CGPoint(x: 0, y: size.height))
            plantPath.closeSubpath()
            context.fill(plantPath, with: .color(Theme.accentDeep.opacity(0.28)))

            line({ $0.herbivores }, color: Theme.accent, width: 1.8)
            line({ $0.carnivores }, color: Theme.danger, width: 1.4)
        }
    }
}

struct GenomeRadar: View {
    let values: [Float]
    var tint: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            guard values.count >= 3 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.40
            let count = values.count

            func point(_ index: Int, _ ratio: CGFloat) -> CGPoint {
                let angle = -CGFloat.pi / 2 + CGFloat(index) / CGFloat(count) * 2 * .pi
                return CGPoint(
                    x: center.x + cos(angle) * radius * ratio,
                    y: center.y + sin(angle) * radius * ratio
                )
            }

            for ring in 1...3 {
                var path = Path()
                let ratio = CGFloat(ring) / 3
                for index in 0..<count {
                    let p = point(index, ratio)
                    if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(Color.white.opacity(0.10)), lineWidth: 0.8)
            }

            var shape = Path()
            for index in 0..<count {
                let p = point(index, CGFloat(clampf(values[index], 0.05, 1)))
                if index == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
            }
            shape.closeSubpath()
            context.fill(shape, with: .color(tint.opacity(0.25)))
            context.stroke(shape, with: .color(tint), lineWidth: 1.3)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.03, green: 0.08, blue: 0.06))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
