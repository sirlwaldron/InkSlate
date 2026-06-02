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
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                Image(systemName: "pencil")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .scaleEffect(scale)
                    .opacity(opacity)
                
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
        isVisible = true
        
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 0.0
                scale = 1.1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
}

#Preview {
    SplashScreenView {
    }
}
