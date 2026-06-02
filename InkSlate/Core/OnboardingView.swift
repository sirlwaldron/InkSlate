import SwiftUI

// MARK: - Onboarding Page Model
struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let highlights: [Highlight]
    
    struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    let onFinish: () -> Void
    
    @State private var currentPage: Int = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 12
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "pencil",
            title: "Welcome to InkSlate",
            subtitle: "A calm, private home for your notes, plans, and everyday inspirations.",
            highlights: []
        ),
        OnboardingPage(
            icon: "brain.head.profile",
            title: "Your second brain",
            subtitle: "Capture ideas in Notes, connect them in Mind Maps, and reflect in your Journal.",
            highlights: [
                .init(icon: "note.text", label: "Notes"),
                .init(icon: "brain.head.profile", label: "Mind Maps"),
                .init(icon: "book.closed", label: "Journal")
            ]
        ),
        OnboardingPage(
            icon: "checklist",
            title: "Stay organized",
            subtitle: "Plan your days, track your spending, and keep the things that matter close.",
            highlights: [
                .init(icon: "checklist", label: "To-Do"),
                .init(icon: "calendar", label: "Calendar"),
                .init(icon: "chart.pie.fill", label: "Budget"),
                .init(icon: "house.fill", label: "Home")
            ]
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "Create & enjoy",
            subtitle: "Cook from your recipe book, save places you love, and never lose a great quote or film.",
            highlights: [
                .init(icon: "fork.knife", label: "Recipes"),
                .init(icon: "mappin.and.ellipse", label: "Places"),
                .init(icon: "quote.bubble", label: "Quotes"),
                .init(icon: "tv", label: "Watchlist")
            ]
        ),
        OnboardingPage(
            icon: "lock.shield",
            title: "Private & yours",
            subtitle: "Your library lives on your device and syncs securely across your Apple devices with iCloud.",
            highlights: [
                .init(icon: "icloud", label: "iCloud sync"),
                .init(icon: "paintpalette", label: "Themes"),
                .init(icon: "hand.raised", label: "Private")
            ]
        )
    ]
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                footer
            }
        }
        .onAppear {
            animateIn()
        }
    }
    
    // MARK: - Header (Skip)
    private var header: some View {
        HStack {
            Spacer()
            Button {
                lightHaptic()
                complete()
            } label: {
                Text("Skip")
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip onboarding")
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.md)
    }
    
    // MARK: - Page Content
    private var pageContent: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                pageView(for: page)
                    .tag(index)
                    .padding(.horizontal, DesignSystem.Spacing.xxl)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .opacity(contentOpacity)
        .offset(y: contentOffset)
        .animation(.easeInOut(duration: 0.35), value: currentPage)
    }
    
    private func pageView(for page: OnboardingPage) -> some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            Spacer(minLength: 0)
            
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.10))
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(DesignSystem.Colors.accent.opacity(0.18), lineWidth: 0.5)
                    .frame(width: 132, height: 132)
                Image(systemName: page.icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
            }
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                Text(page.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            
            if !page.highlights.isEmpty {
                highlightsGrid(page.highlights)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private func highlightsGrid(_ highlights: [OnboardingPage.Highlight]) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 96), spacing: DesignSystem.Spacing.lg)
        ]
        return LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.lg) {
            ForEach(highlights) { item in
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(DesignSystem.Colors.backgroundSecondary)
                        )
                    Text(item.label)
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
    
    // MARK: - Footer (Indicator + Continue/Get Started)
    private var footer: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            indicator
            
            Button {
                handlePrimaryTap()
            } label: {
                Text(isLastPage ? "Get Started" : "Continue")
                    .font(DesignSystem.Typography.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.lg)
            }
            .minimalistButton(variant: .primary, size: .large)
            .padding(.horizontal, DesignSystem.Spacing.xxl)
            .accessibilityLabel(isLastPage ? "Get Started" : "Continue to next page")
        }
        .padding(.bottom, DesignSystem.Spacing.xxl)
        .opacity(contentOpacity)
    }
    
    private var indicator: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == currentPage
                        ? DesignSystem.Colors.accent
                        : DesignSystem.Colors.border
                    )
                    .frame(width: index == currentPage ? 22 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: currentPage)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
    }
    
    // MARK: - Helpers
    private var isLastPage: Bool {
        currentPage >= pages.count - 1
    }
    
    private func handlePrimaryTap() {
        lightHaptic()
        if isLastPage {
            complete()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                currentPage += 1
            }
        }
    }
    
    private func complete() {
        withAnimation(.easeOut(duration: 0.25)) {
            contentOpacity = 0
            contentOffset = -8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onFinish()
        }
    }
    
    private func animateIn() {
        contentOpacity = 0
        contentOffset = 12
        withAnimation(.easeOut(duration: 0.4).delay(0.05)) {
            contentOpacity = 1
            contentOffset = 0
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environmentObject(ThemeService.shared)
}
