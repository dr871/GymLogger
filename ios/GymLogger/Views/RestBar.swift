import SwiftUI

/// The countdown is rendered straight from the wall clock via TimelineView, so
/// it can't drift or freeze — whatever happened while the app was away, the
/// first frame back shows the truth.
struct RestBar: View {
    @EnvironmentObject var store: Store
    let timer: RestTimerState

    @State private var buzzed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = timer.remaining(at: context.date)
            let done = remaining <= 0

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(done ? "Rest done" : Format.clock(remaining))
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(done ? Palette.accent : Palette.text)
                    if !timer.label.isEmpty {
                        Text(timer.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()

                Button("+30s") { store.addRestTime(30) }
                    .buttonStyle(ChipStyle())

                Button {
                    store.cancelRest()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(ChipStyle())
                .accessibilityLabel("Cancel rest timer")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 66)
            // The elapsed fill sits in a background rather than as a ZStack
            // sibling: GeometryReader is greedy, so alongside the HStack it
            // swelled to fill the whole safe-area inset instead of the bar.
            // In a background it measures what the HStack already resolved to.
            .background(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Palette.accent.opacity(done ? 0.34 : 0.16))
                        .frame(width: geometry.size.width * timer.elapsedFraction(at: context.date))
                }
            }
            .background(Palette.surface2)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            .onChange(of: done) { _, isDone in
                // Haptic only when it finishes with the app in front; the local
                // notification covers every other case.
                if isDone && !buzzed {
                    buzzed = true
                    Haptics.done()
                }
            }
        }
    }
}
