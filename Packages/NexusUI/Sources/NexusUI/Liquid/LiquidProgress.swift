import SwiftUI

/// Progress track color — `docs/03_COMPONENTS.md` §ProgressBar/§CircularProgress: "track: white 12%".
/// Starter ships 0.10; kept as ported (visually calibrated against the reference).
private let progressTrack = Color.white.opacity(0.10)

/// Thin capsule progress bar per `docs/03_COMPONENTS.md` §ProgressBar.
///
/// `value` is clamped to 0...1.
public struct LiquidProgressLine: View {

    public let value: Double
    public let color: Color

    public init(value: Double, color: Color = DS.ColorToken.accentPrimary) {
        self.value = value
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(progressTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: 5)
    }
}

/// Circular progress ring with a centered label, per
/// `docs/03_COMPONENTS.md` §CircularProgress (meeting load, project health,
/// focus timer). `value` is clamped to 0...1.
public struct LiquidCircularProgress: View {

    public let value: Double
    public let title: String
    public let size: CGFloat
    public let color: Color

    public init(value: Double, title: String, size: CGFloat = 66, color: Color = DS.ColorToken.accentPrimary) {
        self.value = value
        self.title = title
        self.size = size
        self.color = color
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(progressTrack, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 8)
            Text(title)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

/// 1 pt hairline divider in `strokeHairline`.
public struct LiquidDividerLine: View {

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(DS.ColorToken.strokeHairline)
            .frame(height: 1)
    }
}
