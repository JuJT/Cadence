import SwiftUI
import CadenceCore

enum CadenceColors {
    static let blue = Color(cadenceHex: "#2776F8")
    static let ice = Color(cadenceHex: "#82C7FF")
    static let revision = Color(cadenceHex: "#8793EA")
    static let positive = Color(cadenceHex: "#319A73")
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.92, green: 0.95, blue: 1, alpha: 1) : UIColor(red: 0.075, green: 0.12, blue: 0.21, alpha: 1) })
    static let secondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.67, green: 0.74, blue: 0.85, alpha: 1) : UIColor(red: 0.35, green: 0.41, blue: 0.51, alpha: 1) })
}

enum CadenceSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let section: CGFloat = 28
}

enum CadenceRadius {
    static let row: CGFloat = 18
    static let card: CGFloat = 26
    static let hero: CGFloat = 32
}

enum CadenceTheme {
    static let contentWidth: CGFloat = 860
    static let highlight = LinearGradient(colors: [.white.opacity(0.96), .white.opacity(0.24), CadenceColors.ice.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum Atelier {
    static let blue = CadenceColors.blue
    static let revision = CadenceColors.revision
    static let ice = CadenceColors.ice
    static func color(for kind: SessionKind) -> Color { kind == .course ? blue : revision }
    static func duration(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(min(seconds, Double(Int.max / 2)))) : 0
        return value >= 3600 ? "\(value / 3600) h \(String(format: "%02d", value / 60 % 60))" : "\(value / 60) min"
    }
    static func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(min(seconds, Double(Int.max / 2)))) : 0
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    static func day(_ date: Date) -> DateInterval { Calendar.current.dateInterval(of: .day, for: date)! }
    static func subject(_ id: UUID?, in state: CadenceState) -> Subject? { state.subjects.first { $0.id == id } }
}

/// Slow light fields drift along a smooth, non-repeating path without per-frame blurs.
struct CadenceBackground: View {
    var animated = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var motionEnabled: Bool { animated && !reduceMotion && !reduceTransparency && !lowPower }

    var body: some View {
        GeometryReader { geometry in
            if motionEnabled {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isVisible || scenePhase != .active)) { context in
                    lightFields(size: geometry.size, date: context.date)
                }
            } else {
                lightFields(size: geometry.size, date: nil)
            }
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
            .onAppear { isVisible = true; lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .onDisappear { isVisible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }

    private func lightFields(size: CGSize, date: Date?) -> some View {
        let dark = colorScheme == .dark
        let radius = max(size.width, 420)
        return ZStack {
            LinearGradient(colors: dark ? [Color(cadenceHex: "#0B1424"), Color(cadenceHex: "#13243C")] : [Color(cadenceHex: "#F8FAFF"), Color(cadenceHex: "#EAF2FF")], startPoint: .topLeading, endPoint: .bottomTrailing)
            if !reduceTransparency {
                RadialGradient(colors: [CadenceColors.ice.opacity(dark ? 0.13 : 0.43), .clear], center: CadenceAuraMotion.center(x: 0.98, y: 0.26, date: date, seed: 11), startRadius: 0, endRadius: radius * 0.9)
                RadialGradient(colors: [CadenceColors.blue.opacity(dark ? 0.10 : 0.15), .clear], center: CadenceAuraMotion.center(x: 0.02, y: 0.88, date: date, seed: 29), startRadius: 0, endRadius: radius * 0.8)
                RadialGradient(colors: [.white.opacity(dark ? 0.04 : 0.9), .clear], center: CadenceAuraMotion.center(x: 0.16, y: 0.02, date: date, seed: 47), startRadius: 0, endRadius: radius * 0.9)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.6, y: -40))
                    path.addCurve(to: CGPoint(x: size.width * 1.15, y: size.height * 0.48), control1: CGPoint(x: size.width * 0.44, y: size.height * 0.25), control2: CGPoint(x: size.width * 0.8, y: size.height * 0.32))
                }.stroke(.white.opacity(dark ? 0.08 : 0.48), lineWidth: 1)
            }
        }
    }
}

private enum CadenceAuraMotion {
    static func center(x: Double, y: Double, date: Date?, seed: Double) -> UnitPoint {
        guard let date else { return UnitPoint(x: x, y: y) }
        let seconds = date.timeIntervalSinceReferenceDate
        // Independent long segments, joined with zero first/second derivative.
        // There is no repeating animation or automatic reversal.
        let dx = (noise(seconds / 73 + seed, seed: seed) - 0.5) * 0.34
        let dy = (noise(seconds / 97 + seed, seed: seed + 17) - 0.5) * 0.24
        return UnitPoint(x: x + dx, y: y + dy)
    }

    private static func noise(_ position: Double, seed: Double) -> Double {
        let left = floor(position)
        let fraction = position - left
        let blend = fraction * fraction * fraction * (fraction * (fraction * 6 - 15) + 10)
        return random(left, seed: seed) * (1 - blend) + random(left + 1, seed: seed) * blend
    }

    private static func random(_ index: Double, seed: Double) -> Double {
        let value = sin(index * 12.9898 + seed * 78.233) * 43758.5453
        return value - floor(value)
    }
}

/// A short entrance changes presentation only; the tab's navigation state stays intact.
struct CadenceTabEntrance: ViewModifier {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(0.8 + 0.2 * progress)
            .offset(y: reduceMotion ? 0 : (1 - progress) * 6)
            .task(id: isSelected) {
                guard isSelected, !reduceMotion, scenePhase == .active,
                      !ProcessInfo.processInfo.isLowPowerModeEnabled else { progress = 1; return }
                progress = 0
                do { try await Task.sleep(nanoseconds: 20_000_000) }
                catch { progress = 1; return }
                guard !Task.isCancelled else { progress = 1; return }
                withAnimation(.easeOut(duration: 0.24)) { progress = 1 }
            }
            .onChange(of: reduceMotion) { _, reduced in if reduced { progress = 1 } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { progress = 1 } }
    }
}

struct CadenceGlassStyle: ViewModifier {
    var radius: CGFloat = CadenceRadius.card
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency || contrast == .increased {
                    shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    ZStack {
                        shape.fill(.thinMaterial)
                        shape.fill(colorScheme == .dark ? Color(cadenceHex: "#1B304B").opacity(0.34) : Color.white.opacity(0.52))
                        shape.fill(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.05 : 0.25), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay { shape.strokeBorder(CadenceTheme.highlight, lineWidth: 1).opacity(colorScheme == .dark ? 0.22 : 0.85).allowsHitTesting(false) }
            .shadow(color: Color(cadenceHex: "#234773").opacity(colorScheme == .dark ? 0.13 : 0.075), radius: 16, x: 0, y: 7)
    }
}

extension View {
    func cadenceSurface(radius: CGFloat = CadenceRadius.card) -> some View { modifier(CadenceGlassStyle(radius: radius)) }
    func cadenceListStyle() -> some View { scrollContentBackground(.hidden).background(CadenceBackground()).tint(CadenceColors.blue) }
    func cadenceSegmentedStyle() -> some View { padding(5).cadenceSurface(radius: 22).tint(CadenceColors.blue) }
}

extension Date {
    func cadenceFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: Locale(identifier: "fr_FR")))
    }
}

extension Color {
    init(cadenceHex: String) {
        let clean = cadenceHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(clean, radix: 16) ?? 0x2776F8
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct AtelierCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: CadenceSpacing.medium) { content }
            .padding(CadenceSpacing.large).frame(maxWidth: .infinity, alignment: .leading).cadenceSurface()
    }
}

struct AtelierPage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: CadenceTheme.contentWidth).frame(maxWidth: .infinity)
        }.background(CadenceBackground())
    }
}

struct CadenceSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(CadenceColors.ink)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(CadenceColors.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProminentAction: View {
    let title: String
    let symbol: String
    var tint: Color = Atelier.blue
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency { button.buttonStyle(.glassProminent) }
            else { button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
        }
        .tint(tint).controlSize(.large)
        .overlay { Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false) }
        .shadow(color: tint.opacity(0.24), radius: 12, x: 0, y: 5)
    }
    private var button: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).frame(minHeight: 30).padding(.vertical, 2) }
    }
}

struct SecondaryAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency { button.buttonStyle(.glass) }
            else { button.buttonStyle(.bordered).buttonBorderShape(.capsule) }
        }.controlSize(.large).tint(Atelier.blue)
    }
    private var button: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).frame(minHeight: 30).padding(.vertical, 2) }
    }
}

struct SubjectMark: View {
    let subject: Subject?
    var body: some View {
        Image(systemName: subject?.symbol ?? "book.closed")
            .font(.title3.weight(.medium)).frame(width: 44, height: 44)
            .foregroundStyle(Color(cadenceHex: subject?.colorHex ?? "#2776F8"))
            .background(Color(cadenceHex: subject?.colorHex ?? "#2776F8").opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.4), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let title: String
    var color: Color = .secondary
    var body: some View {
        Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(color).background(color.opacity(0.1), in: Capsule()).fixedSize(horizontal: false, vertical: true)
    }
}

struct MetricRow: View {
    let title: String
    let seconds: Double
    var color: Color = Atelier.blue
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .top, endPoint: .bottom)).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(title).foregroundStyle(CadenceColors.secondary)
            Spacer(minLength: 8)
            Text(Atelier.duration(seconds)).fontWeight(.semibold).monospacedDigit().foregroundStyle(CadenceColors.ink)
        }.font(.subheadline)
    }
}

struct EmptyCard: View {
    let title: String
    let symbol: String
    let description: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Atelier.blue)
                .frame(width: 60, height: 60).cadenceSurface(radius: 20).accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(CadenceColors.ink)
            Text(description).font(.subheadline).foregroundStyle(CadenceColors.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth: .infinity).cadenceSurface()
    }
}
