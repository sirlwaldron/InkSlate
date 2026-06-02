import SwiftUI


struct CookModeTimerView: View {
    @EnvironmentObject private var recipeTimers: RecipeTimerController
    let step: RecipeStep
    let minutes: Int
    var recipeName: String? = nil

    var body: some View {
        Group {
            if let timerState = recipeTimers.activeTimers[step.id] {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(recipeTimers.timeString(from: timerState.remainingSeconds))
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundColor(timerState.remainingSeconds <= 10 ? DesignSystem.Colors.error : DesignSystem.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Button(action: { recipeTimers.toggleTimer(for: step); lightHaptic() }) {
                        Image(systemName: timerState.isRunning ? "pause.fill" : "play.fill")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.accent)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    Button(action: { recipeTimers.resetTimer(for: step); lightHaptic() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    Button(action: {
                        recipeTimers.startTimer(
                            for: step,
                            minutes: minutes,
                            notificationContextLabel: notificationLabelForTimer()
                        )
                        lightHaptic()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(DesignSystem.Typography.caption)
                            Text("\(minutes)m")
                                .font(DesignSystem.Typography.body)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(.plain)

                    Text("Tap to start")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
    }

    private func notificationLabelForTimer() -> String {
        let trimmed = recipeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return step.instruction
        }
        return "\(trimmed): \(step.instruction)"
    }
}

