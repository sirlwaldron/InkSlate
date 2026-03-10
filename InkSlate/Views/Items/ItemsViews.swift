//
//  ItemsViews.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI
import CoreData

// MARK: - Modern Homescreen Views
struct ItemsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            VStack(spacing: 0) {
                // Header with time/date and profile
                ModernHomeHeader(currentTime: context.date)
                
                // Main content area
                ModernHomeMainView(currentTime: context.date)
            }
            .background(DesignSystem.Colors.background)
        }
    }
}

// MARK: - Modern Home Header
struct ModernHomeHeader: View {
    let currentTime: Date
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var showingProfileCustomization = false
    @StateObject private var profileService = ProfileService()
    @StateObject private var dailyQuoteService = DailyQuoteService()
    @EnvironmentObject var shared: SharedStateManager
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Minimalistic Welcome & Quote Card
            if let quote = dailyQuoteService.currentQuote {
                HStack {
                    Spacer()
                    
                    ZStack(alignment: .topLeading) {
                        // Modern minimalistic card with animated border
                        VStack(alignment: .trailing, spacing: 4) {
                            // Welcome text - more minimal
                            Text("Welcome back, \(profileService.userName)")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .padding(.top, 12)
                                .padding(.trailing, 16)
                            
                            // Subtle dot separator instead of line
                            Circle()
                                .fill(DesignSystem.Colors.textSecondary.opacity(0.3))
                                .frame(width: 4, height: 4)
                                .padding(.vertical, 1)

                            // Quote - cleaner layout
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\"\(quote.text)\"")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(2)

                                Text("— \(quote.author)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.8))
                                    .italic()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                        .background(
                            ZStack {
                                // Animated border effect
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                DesignSystem.Colors.accent.opacity(0.6),
                                                DesignSystem.Colors.accent.opacity(0.2),
                                                DesignSystem.Colors.accent.opacity(0.6)
                                            ],
                                            startPoint: UnitPoint(x: animationOffset, y: 0),
                                            endPoint: UnitPoint(x: animationOffset + 0.5, y: 1)
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .onAppear {
                                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                                            animationOffset = 1
                                        }
                                    }
                                
                                // Card background
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(DesignSystem.Colors.surface)
                                    .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.1), radius: 12, x: 0, y: 6)
                                    .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                        )

                        // Profile on left side - smaller and more minimalistic
                        Button(action: { showingProfileCustomization = true }) {
                            ZStack {
                                Circle()
                                    .fill(DesignSystem.Colors.accent)
                                    .frame(width: 50, height: 50)
                                    .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.15), radius: 8, x: 0, y: 4)
                                    .shadow(color: DesignSystem.Colors.textSecondary.opacity(0.08), radius: 2, x: 0, y: 1)

                                if let userImage = profileService.userImage {
                                    Image(uiImage: userImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: profileService.userIcon)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textInverse)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .offset(x: -15, y: -15) // overlap effect from left
                    }
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.85) // 85% of screen width - moved more to the right
                }
                .padding(.leading, 60) // Moved card further to the right
                .onTapGesture { showingSettings = true }
            }
        }
        .padding(.top, 40) // Moved card down more
        .sheet(isPresented: $showingProfile) {
            ProfileMainView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingProfileCustomization) {
            ProfileCustomizationView(profileService: profileService)
        }
    }
}

// MARK: - Modern Home Main View
struct ModernHomeMainView: View {
    let currentTime: Date 
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Bottom time and date with modern animations
            ModernBottomTimeDisplay(currentTime: currentTime)
        }
    }
}

// MARK: - Modern Bottom Time Display
struct ModernBottomTimeDisplay: View {
    let currentTime: Date
    @State private var isVisible = false
    
    
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
            // Bottom time
            Text(Self.timeFormatter.string(from: currentTime))
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.black)
            
            // Bottom date
            Text(Self.dateFormatter.string(from: currentTime))
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.xl)
    }
}
