import SwiftUI
import CadenceCore

enum Atelier {
    static let blue = Color(red: 0.15, green: 0.46, blue: 0.97)
    static let revision = Color(red: 0.46, green: 0.41, blue: 0.96)
    static func color(for kind: SessionKind) -> Color { kind == .course ? blue : revision }
    static func duration(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(min(seconds, Double(Int.max / 2)))) : 0
        return value >= 3600 ? "\(value / 3600) h \(String(format: "%02d", value / 60 % 60))" : "\(value / 60) min"
    }
    static func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(min(seconds, Double(Int.max / 2)))) : 0
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    static func day(_ date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .day, for: date)!
    }
    static func subject(_ id: UUID?, in state: CadenceState) -> Subject? {
        state.subjects.first { $0.id == id }
    }
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
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AtelierPage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: 920).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            if #available(iOS 26.0, *), !reduceTransparency {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }.tint(tint).controlSize(.large)
    }
    private var button: some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity).frame(minHeight: 28) }
    }
}

struct SecondaryAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                button.buttonStyle(.glass)
            } else {
                button.buttonStyle(.bordered)
            }
        }.controlSize(.large)
    }
    private var button: some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity).frame(minHeight: 28) }
    }
}

struct SubjectMark: View {
    let subject: Subject?
    var body: some View {
        Image(systemName: subject?.symbol ?? "book.closed")
            .font(.title3).frame(width: 44, height: 44)
            .foregroundStyle(Color(cadenceHex: subject?.colorHex ?? "#2776F8"))
            .background(Color(cadenceHex: subject?.colorHex ?? "#2776F8").opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let title: String
    var color: Color = .secondary
    var body: some View {
        Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(color).background(color.opacity(0.12), in: Capsule())
    }
}

struct MetricRow: View {
    let title: String
    let seconds: Double
    var color: Color = Atelier.blue
    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            Text(Atelier.duration(seconds)).fontWeight(.semibold).monospacedDigit()
        }.font(.subheadline)
    }
}

struct EmptyCard: View {
    let title: String
    let symbol: String
    let description: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(description))
            .frame(maxWidth: .infinity)
    }
}
