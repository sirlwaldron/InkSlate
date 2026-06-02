import Foundation
import SwiftUI
import Combine
import os

// MARK: - Error Types

enum NotesError: LocalizedError {
    case saveFailed(String)
    case deleteFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case networkError(String)
    case validationError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            return "Failed to save note: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete note: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .saveFailed:
            return "Please try again or check your storage space."
        case .deleteFailed:
            return "Please try again or restart the app."
        case .encryptionFailed:
            return "Please check your password and try again."
        case .decryptionFailed:
            return "Please verify your password is correct."
        case .networkError:
            return "Please check your internet connection."
        case .validationError:
            return "Please check your input and try again."
        case .unknown:
            return "Please restart the app and try again."
        }
    }
}

enum InkSlateAppError: LocalizedError {
    case saveFailed(module: String, detail: String)
    case syncWarning(String)
    case operationFailed(module: String, detail: String)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let module, let detail):
            return "Couldn't save in \(module): \(detail)"
        case .syncWarning(let message):
            return message
        case .operationFailed(let module, let detail):
            return "\(module): \(detail)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .saveFailed:
            return "Your changes may only exist on this device until save succeeds. Check iCloud status in Settings."
        case .syncWarning:
            return "Open Settings → iCloud Sync for troubleshooting. Connect to the internet and ensure you're signed into iCloud."
        case .operationFailed:
            return "Please try again. If the problem continues, check iCloud sync in Settings."
        }
    }
}

// MARK: - Error Handling Service

class ErrorHandlingService: ObservableObject {
    static let shared = ErrorHandlingService()
    private static let log = Logger(subsystem: "com.lucas.InkSlateNew", category: "ErrorHandling")
    
    @Published var currentError: (any LocalizedError)?
    @Published var showingError = false
    private(set) var pendingRetry: (() -> Void)?
    
    private init() {}
    
    func handleError(_ error: Error, context: String = "", retry: (() -> Void)? = nil) {
        let displayError: any LocalizedError
        
        if let notesErr = error as? NotesError {
            displayError = notesErr
        } else if let appErr = error as? InkSlateAppError {
            displayError = appErr
        } else {
            let prefix = context.isEmpty ? "" : "\(context): "
            displayError = InkSlateAppError.operationFailed(module: "InkSlate", detail: "\(prefix)\(error.localizedDescription)")
        }
        
        DispatchQueue.main.async {
            if self.showingError, let existing = self.currentError {
                Self.log.error("Replacing an unacknowledged error alert. Dropped: \(existing.errorDescription ?? "unknown", privacy: .public)")
            }
            self.currentError = displayError
            self.pendingRetry = retry
            self.showingError = true
        }
    }
    
    func reportSaveFailure(_ error: Error, module: String, retry: (() -> Void)? = nil) {
        handleError(InkSlateAppError.saveFailed(module: module, detail: error.localizedDescription), retry: retry)
    }
    
    func reportSyncWarning(_ message: String) {
        handleError(InkSlateAppError.syncWarning(message))
    }
    
    func reportOperationFailure(module: String, detail: String, retry: (() -> Void)? = nil) {
        handleError(InkSlateAppError.operationFailed(module: module, detail: detail), retry: retry)
    }
    
    func clearError() {
        currentError = nil
        showingError = false
        pendingRetry = nil
    }

    func runPendingRetry() {
        let work = pendingRetry
        pendingRetry = nil
        currentError = nil
        showingError = false
        work?()
    }
}

// MARK: - Error Alert View

struct ErrorAlertView: View {
    @ObservedObject var errorService: ErrorHandlingService
    
    var body: some View {
        EmptyView()
            .alert("Error", isPresented: $errorService.showingError) {
                Button("OK") {
                    errorService.clearError()
                }
                if errorService.pendingRetry != nil {
                    Button("Retry") {
                        errorService.runPendingRetry()
                    }
                }
            } message: {
                if let error = errorService.currentError {
                    let description = error.errorDescription ?? "An unknown error occurred"
                    if let suggestion = error.recoverySuggestion, !suggestion.isEmpty {
                        Text("\(description)\n\n\(suggestion)")
                    } else {
                        Text(description)
                    }
                }
            }
    }
}

// MARK: - Error Handling Extensions

extension View {
    func withErrorHandling() -> some View {
        self.background(
            ErrorAlertView(errorService: ErrorHandlingService.shared)
        )
    }
}

// MARK: - Safe Database Operations

extension ErrorHandlingService {
    func safeSave<T>(_ operation: () throws -> T, context: String = "Save operation") -> T? {
        do {
            return try operation()
        } catch {
            handleError(error, context: context)
            return nil
        }
    }
    
    func safeDelete<T>(_ operation: () throws -> T, context: String = "Delete operation") -> T? {
        do {
            return try operation()
        } catch {
            handleError(error, context: context)
            return nil
        }
    }
}
