//
//  LoadingStateManager.swift
//  InkSlate
//
//  Created by UI Overhaul on 9/29/25.
//

import SwiftUI
import Combine
import CoreData

// MARK: - Loading State Manager
class LoadingStateManager: ObservableObject {
    @Published var isLoading = false
    @Published var loadingMessage = ""
    
    func startLoading(message: String = "Loading...") {
        DispatchQueue.main.async { [weak self] in
            self?.loadingMessage = message
            self?.isLoading = true
        }
    }
    
    func stopLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
            self?.loadingMessage = ""
        }
    }
}

// MARK: - Auto Save Manager
class AutoSaveManager: ObservableObject {
    private var saveTimer: Timer?
    private let debounceInterval: TimeInterval = 15.0 
    private var pendingSave = false
    private var lastSaveTime = Date()
    private var managedObjectContext: NSManagedObjectContext?
    
    @Published var isSaving = false
    @Published var lastSaveStatus = "Ready"
    
    func setManagedObjectContext(_ context: NSManagedObjectContext) {
        self.managedObjectContext = context
    }
    
    func scheduleSave() {
        pendingSave = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.performSave()
        }
    }
    
    private func performSave() {
        guard pendingSave, let context = managedObjectContext else { return }
        pendingSave = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSaving = true
            self.lastSaveStatus = "Saving..."
        }

        context.perform { [weak self] in
            guard let self = self else { return }
            do {
                try PerformanceLogger.measure(log: PerformanceMetrics.persistence, name: "AutoSaveSave") {
                    if context.hasChanges {
                        try context.save()
                    }
                }
                let now = Date()
                DispatchQueue.main.async {
                    self.lastSaveTime = now
                    self.isSaving = false
                    self.lastSaveStatus = "Saved at \(DateFormatter.timeFormatter.string(from: now))"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.lastSaveStatus = "Save failed"
                }
            }
        }
    }
    
    func forceSave() {
        saveTimer?.invalidate()
        pendingSave = true
        performSave()
    }
    
    
    deinit {
        saveTimer?.invalidate()
        saveTimer = nil
        
    }
}

// MARK: - Date Formatter Extension
extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Model Context Extensions
extension NSManagedObjectContext {
    func saveWithDebounce(using autoSaveManager: AutoSaveManager) {
        autoSaveManager.setManagedObjectContext(self)
        autoSaveManager.scheduleSave()
    }
    
    func forceSave() {
        do {
            try self.save()
        } catch {
            
        }
    }
    
    
    func performBatch(_ operation: () throws -> Void) throws {
        try operation()
        if hasChanges {
            try save()
        }
    }
    
    
    func performBatchAsync(_ operation: @escaping () throws -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try operation()
                    if self.hasChanges {
                        try self.save()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    func performBatchWithDebounce(_ operation: @escaping () throws -> Void, debounceTime: TimeInterval = 2.0) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + debounceTime) {
            do {
                try operation()
                if self.hasChanges {
                    try self.save()
                }
            } catch {
                // Handle batch operation error silently
            }
        }
    }
}

// MARK: - Loading Overlay View Modifier
struct LoadingOverlayModifier: ViewModifier {
    @ObservedObject var loadingManager: LoadingStateManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if loadingManager.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.accent))
                    
                    if !loadingManager.loadingMessage.isEmpty {
                        Text(loadingManager.loadingMessage)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .padding(DesignSystem.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.surface)
                        .shadow(color: DesignSystem.Shadows.medium, radius: 8, x: 0, y: 4)
                )
            }
        }
    }
}

extension View {
    func loadingOverlay(loadingManager: LoadingStateManager) -> some View {
        modifier(LoadingOverlayModifier(loadingManager: loadingManager))
    }
}
