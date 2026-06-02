import SwiftUI

// MARK: - Modern Homescreen Views
struct ItemsListView: View {
    var body: some View {
        VStack(spacing: 0) {
            ModernHomeHeader()

            ModernHomeMainView()
        }
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Modern Home Header
struct ModernHomeHeader: View {
    @State private var showingProfileCustomization = false
    @EnvironmentObject private var profileService: ProfileService
    @StateObject private var dailyQuoteService = DailyQuoteService()

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if let quote = dailyQuoteService.currentQuote {
                let leadingOffset: CGFloat = 60
                let trailingInset: CGFloat = DesignSystem.Spacing.lg
                HStack {
                    Spacer()
                    ModernDailyQuoteCard(
                        quote: quote,
                        userName: profileService.userName,
                        userIcon: profileService.userIcon,
                        userImage: profileService.userImage,
                        onOpenProfileCustomization: { showingProfileCustomization = true }
                    )
                    .frame(maxWidth: max(0, platformScreenWidth - leadingOffset - trailingInset))
                }
                .padding(.leading, leadingOffset)
                .padding(.trailing, trailingInset)
            }
        }
        .padding(.top, 40)
        .sheet(isPresented: $showingProfileCustomization) {
            ProfileCustomizationView(profileService: profileService)
        }
    }
}

// MARK: - Modern Daily Quote Card (Homescreen)
private struct ModernDailyQuoteCard: View {
    let quote: DailyQuote
    let userName: String
    let userIcon: String
    let userImage: PlatformImage?
    let onOpenProfileCustomization: () -> Void

    @State private var borderPhase: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(userName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)

                        Text("Daily thought")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .textCase(.uppercase)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("“\(quote.text)”")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textPrimary.opacity(0.9))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)

                        Text("— \(quote.author)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .italic()
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .padding(.leading, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(DesignSystem.Colors.surface)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.accent.opacity(0.55),
                                DesignSystem.Colors.accent.opacity(0.12),
                                DesignSystem.Colors.accent.opacity(0.45)
                            ],
                            startPoint: UnitPoint(x: borderPhase, y: 0),
                            endPoint: UnitPoint(x: borderPhase + 0.6, y: 1)
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.10), radius: 14, x: 0, y: 8)
            .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.06), radius: 4, x: 0, y: 2)

            Button(action: onOpenProfileCustomization) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.16), radius: 10, x: 0, y: 5)

                    if let userImage {
                        Image(platformImage: userImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: userIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textInverse)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize profile")
            .offset(x: -16, y: -16)
        }
        .onAppear {
            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) {
                borderPhase = 1
            }
        }
    }

    private var accessibilitySummary: String {
        "Daily thought for \(userName). \(quote.text) — \(quote.author)"
    }
}

// MARK: - Modern Home Main View
struct ModernHomeMainView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                ModernBottomTimeDisplay(currentTime: context.date)
            }
        }
    }
}

// MARK: - Modern Bottom Time Display
struct ModernBottomTimeDisplay: View {
    let currentTime: Date

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text(Self.timeFormatter.string(from: currentTime))
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text(Self.dateFormatter.string(from: currentTime))
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.xl)
    }
}
