import Combine
import CoreData
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Stable synthetic step ids

enum RecipeTimerStepID {
    static func cookTime(for recipe: Recipe) -> UUID {
        let base = recipe.id?.uuidString ?? recipe.objectID.uriRepresentation().absoluteString
        let digest = SHA256.hash(data: Data("InkSlate.recipeCookTime.\(base)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return uuidFrom16Bytes(bytes)
    }

    private static func uuidFrom16Bytes(_ bytes: [UInt8]) -> UUID {
        precondition(bytes.count == 16)
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}

// MARK: - Persistent recipe timers (survives leaving recipe detail / cook mode sheet)

@MainActor
final class RecipeTimerController: ObservableObject {
    @Published var activeTimers: [UUID: TimerState] = [:]

    struct TimerState {
        var totalSeconds: Int
        var remainingSeconds: Int
        var isRunning: Bool
    }

    private var timerCancellables: [UUID: AnyCancellable] = [:]
    private var notificationTitles: [UUID: String] = [:]
    private static let persistenceKey = "recipeTimer.activeSnapshots"
    private var backgroundObserver: NSObjectProtocol?

    init() {
        restorePersistedTimers()
        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistActiveTimers() }
        }
        #endif
    }

    func startTimer(for step: RecipeStep, minutes: Int, notificationContextLabel: String? = nil) {
        let totalSeconds = minutes * 60
        let stepID = step.id

        stopTimer(for: stepID)

        notificationTitles[stepID] = notificationContextLabel ?? step.instruction

        activeTimers[stepID] = TimerState(
            totalSeconds: totalSeconds,
            remainingSeconds: totalSeconds,
            isRunning: true
        )

        let timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateTimer(for: stepID)
            }

        timerCancellables[stepID] = timer
        scheduleCookNotificationIfRunning(for: stepID)
        persistActiveTimers()
    }

    func toggleTimer(for step: RecipeStep) {
        let stepID = step.id
        guard var state = activeTimers[stepID] else { return }

        state.isRunning.toggle()
        activeTimers[stepID] = state

        if state.isRunning {
            let timer = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.updateTimer(for: stepID)
                }
            timerCancellables[stepID] = timer
        } else {
            stopTimer(for: stepID)
        }
        scheduleCookNotificationIfRunning(for: stepID)
        persistActiveTimers()
    }

    func resetTimer(for step: RecipeStep) {
        let stepID = step.id
        stopTimer(for: stepID)
        activeTimers.removeValue(forKey: stepID)
        notificationTitles.removeValue(forKey: stepID)
        InkSlateNotificationService.shared.cancelCookTimerNotification(stepID: stepID)
        persistActiveTimers()
    }

    func stopTimer(for stepID: UUID) {
        timerCancellables[stepID]?.cancel()
        timerCancellables.removeValue(forKey: stepID)
    }

    private func updateTimer(for stepID: UUID) {
        guard var state = activeTimers[stepID], state.isRunning else { return }

        state.remainingSeconds -= 1

        if state.remainingSeconds <= 0 {
            state.isRunning = false
            state.remainingSeconds = 0
            stopTimer(for: stepID)
            activeTimers.removeValue(forKey: stepID)
            notificationTitles.removeValue(forKey: stepID)
            InkSlateNotificationService.shared.cancelCookTimerNotification(stepID: stepID)
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #elseif canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            #endif
            return
        }

        activeTimers[stepID] = state
        if state.remainingSeconds % 5 == 0 {
            persistActiveTimers()
        }
    }

    private func scheduleCookNotificationIfRunning(for stepID: UUID) {
        guard let state = activeTimers[stepID], state.isRunning, state.remainingSeconds > 0 else {
            InkSlateNotificationService.shared.cancelCookTimerNotification(stepID: stepID)
            return
        }
        Task { @MainActor in
            guard let latest = self.activeTimers[stepID], latest.isRunning, latest.remainingSeconds > 0 else {
                InkSlateNotificationService.shared.cancelCookTimerNotification(stepID: stepID)
                return
            }
            let line = self.notificationTitles[stepID] ?? "Timer"
            await InkSlateNotificationService.shared.scheduleCookTimerNotificationIfNeeded(
                stepID: stepID,
                remainingSeconds: latest.remainingSeconds,
                title: "Cook timer",
                body: line
            )
        }
    }

    func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        timerCancellables.values.forEach { $0.cancel() }
        timerCancellables.removeAll()
    }

    private struct PersistedTimerSnapshot: Codable {
        var stepID: UUID
        var totalSeconds: Int
        var remainingSeconds: Int
        var isRunning: Bool
        var notificationTitle: String?
        var savedAt: Date
    }

    private func persistActiveTimers() {
        let snapshots = activeTimers.map { id, state in
            PersistedTimerSnapshot(
                stepID: id,
                totalSeconds: state.totalSeconds,
                remainingSeconds: state.remainingSeconds,
                isRunning: state.isRunning,
                notificationTitle: notificationTitles[id],
                savedAt: Date()
            )
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func restorePersistedTimers() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let snapshots = try? JSONDecoder().decode([PersistedTimerSnapshot].self, from: data)
        else { return }

        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        let now = Date()

        for snap in snapshots where snap.remainingSeconds > 0 {
            let elapsed = Int(now.timeIntervalSince(snap.savedAt))
            let remaining = max(0, snap.remainingSeconds - (snap.isRunning ? elapsed : 0))
            guard remaining > 0 else { continue }

            activeTimers[snap.stepID] = TimerState(
                totalSeconds: snap.totalSeconds,
                remainingSeconds: remaining,
                isRunning: snap.isRunning
            )
            if let title = snap.notificationTitle {
                notificationTitles[snap.stepID] = title
            }

            if snap.isRunning {
                let timer = Timer.publish(every: 1.0, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        self.updateTimer(for: snap.stepID)
                    }
                timerCancellables[snap.stepID] = timer
                scheduleCookNotificationIfRunning(for: snap.stepID)
            }
        }
    }

    func activeTimerRows(for recipe: Recipe) -> [RecipeCardTimerRow] {
        var rows: [RecipeCardTimerRow] = []
        let cookId = RecipeTimerStepID.cookTime(for: recipe)
        if let state = activeTimers[cookId] {
            rows.append(
                RecipeCardTimerRow(
                    id: cookId,
                    title: "Cook",
                    remainingSeconds: state.remainingSeconds,
                    isRunning: state.isRunning
                )
            )
        }
        for (index, step) in recipe.recipeSteps.enumerated() {
            guard let state = activeTimers[step.id] else { continue }
            rows.append(
                RecipeCardTimerRow(
                    id: step.id,
                    title: "Step \(index + 1)",
                    remainingSeconds: state.remainingSeconds,
                    isRunning: state.isRunning
                )
            )
        }
        return rows
    }
}

struct RecipeCardTimerRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let remainingSeconds: Int
    let isRunning: Bool
}
