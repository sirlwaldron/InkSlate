import Combine
import Foundation
import SwiftUI

@MainActor
final class CookModeViewModel: ObservableObject {
    @Published var steps: [RecipeStep] = []
    @Published var currentStepIndex = 0

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
    }

    func nextStep() {
        guard currentStepIndex < steps.count else { return }
        currentStepIndex += 1
    }

    func previousStep() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }
}
