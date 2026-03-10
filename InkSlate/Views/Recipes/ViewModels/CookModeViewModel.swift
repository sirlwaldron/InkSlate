//
//  CookModeViewModel.swift
//  InkSlate
//
//  ViewModel for cook mode with proper timer management
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class CookModeViewModel: ObservableObject {
    @Published var steps: [RecipeStep] = []
    @Published var currentStepIndex = 0
    @Published var activeTimers: [UUID: TimerState] = [:]
    
    struct TimerState {
        var totalSeconds: Int
        var remainingSeconds: Int
        var isRunning: Bool
    }
    
    private var timerCancellables: [UUID: AnyCancellable] = [:]
    
    var currentStep: RecipeStep? {
        guard currentStepIndex >= 0 && currentStepIndex < steps.count else {
            return nil
        }
        return steps[currentStepIndex]
    }
    
    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(currentStepIndex + 1) / Double(steps.count)
    }
    
    var isComplete: Bool {
        currentStepIndex >= steps.count
    }
    
    func loadSteps(from recipeSteps: [RecipeStep]) {
        steps = recipeSteps
        currentStepIndex = 0
        stopAllTimers()
    }
    
    func nextStep() {
        guard currentStepIndex < steps.count - 1 else { return }
        currentStepIndex += 1
    }
    
    func previousStep() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }
    
    func startTimer(for step: RecipeStep, minutes: Int) {
        let totalSeconds = minutes * 60
        let stepID = step.id
        
        // Stop any existing timer for this step
        stopTimer(for: stepID)
        
        activeTimers[stepID] = TimerState(
            totalSeconds: totalSeconds,
            remainingSeconds: totalSeconds,
            isRunning: true
        )
        
        // Use Timer.publish for proper Combine integration
        let timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateTimer(for: stepID)
            }
        
        timerCancellables[stepID] = timer
    }
    
    func toggleTimer(for step: RecipeStep) {
        let stepID = step.id
        guard var state = activeTimers[stepID] else { return }
        
        state.isRunning.toggle()
        activeTimers[stepID] = state
        
        if state.isRunning {
            // Resume timer
            let timer = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.updateTimer(for: stepID)
                }
            timerCancellables[stepID] = timer
        } else {
            // Pause timer
            stopTimer(for: stepID)
        }
    }
    
    func resetTimer(for step: RecipeStep) {
        let stepID = step.id
        stopTimer(for: stepID)
        
        if var state = activeTimers[stepID] {
            state.remainingSeconds = state.totalSeconds
            state.isRunning = false
            activeTimers[stepID] = state
        }
    }
    
    func stopTimer(for stepID: UUID) {
        timerCancellables[stepID]?.cancel()
        timerCancellables.removeValue(forKey: stepID)
    }
    
    func stopAllTimers() {
        timerCancellables.values.forEach { $0.cancel() }
        timerCancellables.removeAll()
    }
    
    private func updateTimer(for stepID: UUID) {
        guard var state = activeTimers[stepID], state.isRunning else { return }
        
        state.remainingSeconds -= 1
        
        if state.remainingSeconds <= 0 {
            state.isRunning = false
            state.remainingSeconds = 0
            stopTimer(for: stepID)
            // Trigger haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        
        activeTimers[stepID] = state
    }
    
    func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    deinit {
        // Clean up timers synchronously to avoid capturing self
        timerCancellables.values.forEach { $0.cancel() }
        timerCancellables.removeAll()
    }
}

