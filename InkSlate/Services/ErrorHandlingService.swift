//
//  ErrorHandlingService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/18/25.
//  Comprehensive error handling service for the notes feature
//

import Foundation
import SwiftUI

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

// MARK: - Error Handling Service
class ErrorHandlingService: ObservableObject {
    static let shared = ErrorHandlingService()
    
    @Published var currentError: NotesError?
    @Published var showingError = false
    
    private init() {}
    
    func handleError(_ error: Error, context: String = "") {
        let notesError: NotesError
        
        if let notesErr = error as? NotesError {
            notesError = notesErr
        } else {
            notesError = .unknown("\(context.isEmpty ? "" : "\(context): ")\(error.localizedDescription)")
        }
        
        DispatchQueue.main.async {
            self.currentError = notesError
            self.showingError = true
        }
        
    }
    
    func clearError() {
        currentError = nil
        showingError = false
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
                if let error = errorService.currentError,
                   let _ = error.recoverySuggestion {
                    Button("Retry") {
                        // Implement retry logic based on error type
                        errorService.clearError()
                    }
                }
            } message: {
                if let error = errorService.currentError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.errorDescription ?? "An unknown error occurred")
                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
