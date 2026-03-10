//
//  SplashScreenView.swift
//  InkSlate
//
//  Created by UI Enhancement on 9/30/25.
//

import SwiftUI

// MARK: - Splash Screen View
struct SplashScreenView: View {
    @State private var isVisible = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Pen Icon
                Image(systemName: "pencil")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .scaleEffect(scale)
                    .opacity(opacity)
                
                // App Name
                Text("InkSlate")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .opacity(opacity)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Initial state
        isVisible = true
        
        // Animate in
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }
        
        // Hold for a moment, then fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 0.0
                scale = 1.1
            }
            
            // Complete after fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
}

#Preview {
    SplashScreenView {
        // Splash screen completed
    }
}
