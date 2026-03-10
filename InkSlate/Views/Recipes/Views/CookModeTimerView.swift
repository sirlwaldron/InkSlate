//
//  CookModeTimerView.swift
//  InkSlate
//
//  Timer view component for cook mode
//

import SwiftUI

struct CookModeTimerView: View {
    @EnvironmentObject var viewModel: CookModeViewModel
    let step: RecipeStep
    let minutes: Int
    
    var body: some View {
        VStack(spacing: 16) {
            if let timerState = viewModel.activeTimers[step.id] {
                Text(viewModel.timeString(from: timerState.remainingSeconds))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(timerState.remainingSeconds <= 10 ? .red : .white)
                    .monospacedDigit()
                
                HStack(spacing: 16) {
                    Button(action: { viewModel.toggleTimer(for: step) }) {
                        Image(systemName: timerState.isRunning ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    
                    Button(action: { viewModel.resetTimer(for: step) }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
            } else {
                Button(action: { viewModel.startTimer(for: step, minutes: minutes) }) {
                    VStack {
                        Image(systemName: "timer")
                            .font(.system(size: 40))
                        Text("Start \(minutes)min Timer")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
                }
            }
        }
    }
}

