import SwiftUI
import TwenCore

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("twen").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Phase", model.engine.phase.rawValue)
                row("Worked", worked)
                row("Saturation", String(format: "%.0f%%", model.engine.saturation * 100))
                if model.engine.phase == .breakRunning {
                    row("Break", "\(Int(model.engine.breakRemaining.rounded(.up)))s left")
                }
            }
            .font(.callout.monospacedDigit())

            Divider()

            Button("Take a break now") { model.requestBreak() }
            Button("Quit twen") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 220)
    }

    private var worked: String {
        let total = Int(model.engine.accrued)
        return "\(total / 60)m \(total % 60)s"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
