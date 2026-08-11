import SwiftUI
import TwenCore

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = SettingsStore.shared

    private var engine: TwenEngine { model.engine }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            phaseContent

            if model.isSuppressed {
                Text(suppressionLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            actions
        }
        .padding(14)
        .frame(width: 250)
    }

    // MARK: - Per-phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch engine.phase {
        case .waiting, .working:
            VStack(alignment: .leading, spacing: 6) {
                Text(nextBreakLine)
                    .font(.body.monospacedDigit())
                ProgressView(value: min(engine.accrued, engine.config.workInterval),
                             total: engine.config.workInterval)
                    .controlSize(.small)
                workedLine
            }

        case .paused:
            VStack(alignment: .leading, spacing: 4) {
                Text("Paused — you're away")
                    .foregroundStyle(.secondary)
                workedLine
            }

        case .ramping:
            VStack(alignment: .leading, spacing: 4) {
                Text("Time to look away")
                Text("The screen is slowly fading to gray.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                workedLine
            }

        case .gray:
            VStack(alignment: .leading, spacing: 4) {
                Text("Screen's waiting — take your break")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Look 20 feet away for \(breakSeconds) seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                workedLine
            }

        case .breakRunning:
            breakCountdown

        case .breakSatisfied:
            Text("Break taken — color returns when you're back.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .snoozed:
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders are paused")
                    .foregroundStyle(.secondary)
                Text("The timer starts fresh when you resume.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Big smooth 1s countdown. The engine only ticks every 2s, so this reads
    /// the wall clock against `breakEndEstimate` instead of `breakRemaining`.
    private var breakCountdown: some View {
        TimelineView(.animation) { context in
            let remaining = breakRemaining(at: context.date)
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: remaining / max(engine.config.breakLength, 1))
                        .stroke(.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 32, weight: .light).monospacedDigit())
                }
                .frame(width: 88, height: 88)
                Text("Look 20 feet away")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    /// Seconds left in the break at `now`, clamped to 0...breakLength so the
    /// display never goes negative or overshoots when the estimate is stale.
    private func breakRemaining(at now: Date) -> TimeInterval {
        let length = engine.config.breakLength
        guard let end = model.breakEndEstimate else {
            return min(max(engine.breakRemaining, 0), length)
        }
        return min(max(end.timeIntervalSince(now), 0), length)
    }

    // MARK: - Lines

    private var nextBreakLine: String {
        let remaining = engine.config.workInterval - engine.accrued
        guard remaining > 0 else { return "Break coming up" }
        return "Next break in ~\(Int((remaining / 60).rounded(.up)))m"
    }

    @ViewBuilder
    private var workedLine: some View {
        let minutes = Int(engine.accrued / 60)
        if minutes >= 1 {
            Text("Worked \(minutes)m")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var breakSeconds: Int {
        Int(engine.config.breakLength.rounded())
    }

    private var suppressionLine: String {
        if let signal = model.suppressionSignals.first {
            return "on hold — \(signal)"
        }
        return "on hold — video or presentation detected"
    }

    /// "Paused until 14:30" / "Paused until tomorrow" / "Paused while on battery" / "Paused".
    private var pausedLine: String {
        switch model.pauseReason {
        case .battery:
            return "Paused while on battery"
        case .manual(let until?):
            if Calendar.current.isDateInToday(until) {
                return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "Paused until tomorrow"
        case .manual(nil), nil:
            return "Paused"
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                breakButton
                Text(settings.comboDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            pauseControls
            HStack(spacing: 12) {
                SettingsOpenButton()
                Button("Quit twen") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// A subtle Pause menu normally; a Resume button plus status line while snoozed.
    @ViewBuilder
    private var pauseControls: some View {
        if engine.phase == .snoozed {
            HStack(spacing: 8) {
                Button("Resume") { model.resume() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text(pausedLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Menu("Pause") {
                Button("For 1 hour") { model.pause(for: 60 * 60) }
                Button("Until tomorrow") { model.pauseUntilTomorrow() }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var breakButton: some View {
        let nudging = engine.phase == .ramping || engine.phase == .gray
        let button = Button("Take a break now") { model.requestBreak() }
            .disabled(engine.phase == .breakRunning)
        if nudging {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
