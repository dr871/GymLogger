import SwiftUI
import UIKit

enum Haptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Numeric entry that doesn't fight the typist.
///
/// Deriving the text straight from the model breaks decimal entry: typing "62."
/// parses to 62, which reformats the field back to "62" and eats the point. So
/// the text is local state, and the model only pushes back in when it changes
/// from somewhere else (for instance "Keep 60" resetting the prefill).
struct WeightField: View {
    @Binding var value: Double?
    var placeholder = "kg"

    @State private var text: String

    init(value: Binding<Double?>, placeholder: String = "kg") {
        _value = value
        self.placeholder = placeholder
        _text = State(initialValue: WeightField.format(value.wrappedValue))
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 18, weight: .regular, design: .rounded))
            .monospacedDigit()
            .onChange(of: text) { _, newText in
                value = WeightField.parse(newText)
            }
            .onChange(of: value) { _, newValue in
                guard WeightField.parse(text) != newValue else { return }
                text = WeightField.format(newValue)
            }
            .fieldChrome()
    }

    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(value)
    }
}

struct RepsField: View {
    @Binding var value: Int?
    var placeholder = "reps"

    @State private var text: String

    init(value: Binding<Int?>, placeholder: String = "reps") {
        _value = value
        self.placeholder = placeholder
        _text = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 18, weight: .regular, design: .rounded))
            .monospacedDigit()
            .onChange(of: text) { _, newText in
                value = Int(newText)
            }
            .onChange(of: value) { _, newValue in
                guard Int(text) != newValue else { return }
                text = newValue.map(String.init) ?? ""
            }
            .fieldChrome()
    }
}

private struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 6)
            .frame(minHeight: Metrics.tap)
            .background(Palette.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }
}

private extension View {
    func fieldChrome() -> some View { modifier(FieldChrome()) }
}

/// A labelled row wrapping a text field, used throughout the editors.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 8)
            content
                .frame(maxWidth: 150)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .kerning(1.1)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 2)
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

/// Screen chrome. The bars are left to the system so they render with the
/// platform's own material; only the content ground is ours.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Palette.bg.ignoresSafeArea())
    }
}

extension View {
    func screen() -> some View { modifier(ScreenBackground()) }
}

enum Format {
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func weight(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value == value.rounded() ? "\(Int(value))" : "\(value)"
    }

    /// "60kg × 12", or "— × 40" for bodyweight work.
    static func lastSet(_ set: SetEntry?) -> String {
        guard let set else { return "—" }
        let weight = set.weight.map { "\(Format.weight($0))kg" } ?? "—"
        let reps = set.reps.map(String.init) ?? "—"
        return "\(weight) × \(reps)"
    }
}

/// Dismisses the keyboard from anywhere. The decimal pad has no return key, so
/// every screen with a numeric field needs an explicit way out.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
}
