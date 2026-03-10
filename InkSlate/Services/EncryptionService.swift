//
//  EncryptionService.swift
//  InkSlate
//

import Foundation
import SwiftUI
import CryptoKit
import LocalAuthentication
import Security

// MARK: - Encryption Service
class EncryptionService: ObservableObject {
    static let shared = EncryptionService()
    
    private let keychainService = "co.inkslate.encryption"
    private let biometricKeyIdentifier = "co.inkslate.biometric.key"
    
    private init() {}
    
    
    deinit {
        
    }
    
    // MARK: - Encryption Methods
    
    func encryptNote(_ note: Notes, password: String) -> Bool {
        guard !password.isEmpty else { return false }
        
        do {
            let key = try deriveKey(from: password, note: note)
            let content = note.content ?? ""
            let encryptedData = try encrypt(data: content.data(using: .utf8) ?? Data(), with: key)
            
            // Store encrypted content
            note.content = encryptedData.base64EncodedString()
            note.isEncrypted = true
            note.containerType = "encrypted"
            
            return true
        } catch {
            // Encryption failed
            return false
        }
    }
    
    func decryptNote(_ note: Notes, password: String) -> Bool {
        guard note.isEncrypted, !password.isEmpty else { return false }
        
        do {
            let key = try deriveKey(from: password, note: note)
            let content = note.content ?? ""
            guard let encryptedData = Data(base64Encoded: content) else { return false }
            
            let decryptedData = try decrypt(data: encryptedData, with: key)
            note.content = String(data: decryptedData, encoding: .utf8) ?? ""
            note.isEncrypted = false
            note.containerType = "none"
            
            return true
        } catch {
            // Decryption failed
            return false
        }
    }
    
    // MARK: - Biometric Authentication
    
    func authenticateWithBiometrics(for noteId: String, completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Authenticate to access encrypted notes"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        // Retrieve stored password from keychain
                        if let password = self.retrieveBiometricPassword(for: noteId) {
                            completion(true, password)
                        } else {
                            completion(false, nil)
                        }
                    } else {
                        completion(false, nil)
                    }
                }
            }
        } else {
            completion(false, nil)
        }
    }
    
    func storeBiometricPassword(_ password: String, for noteId: String) -> Bool {
        let passwordData = password.data(using: .utf8) ?? Data()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: noteId,
            kSecValueData as String: passwordData,
            kSecAttrAccessControl as String: createAccessControl()
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func retrieveBiometricPassword(for noteId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: noteId,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    private func createAccessControl() -> SecAccessControl {
        var error: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        )
        
        if error != nil {
            // Access control creation error
        }
        
        return access!
    }
    
    // MARK: - Private Methods
    
    private func deriveKey(from password: String, note: Notes) throws -> SymmetricKey {
        let passwordData = password.data(using: .utf8) ?? Data()
        
        // Generate unique salt for each note using note ID
        let saltString = "InkSlate-\(note.id?.uuidString ?? UUID().uuidString)"
        let salt = Data(saltString.utf8)
        
        // Use PBKDF2 with proper iteration count (100,000+ is recommended)
        let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
        
        return SymmetricKey(data: keyData)
    }
    
    private func deriveKeyPBKDF2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        var derivedKeyData = Data(count: keyLength)
        
        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        
        if derivationStatus != kCCSuccess {
            throw EncryptionError.keyDerivationFailed
        }
        
        return derivedKeyData
    }
    
    private func encrypt(data: Data, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }
    
    private func decrypt(data: Data, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    // MARK: - Public Encryption Methods for Notes
    
    func encrypt(data: Data, password: String) throws -> Data {
        // For standalone encryption without note context
        let passwordData = password.data(using: .utf8) ?? Data()
        let salt = Data("InkSlateGenericSalt".utf8)
        let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
        let key = SymmetricKey(data: keyData)
        return try encrypt(data: data, with: key)
    }
    
    func decrypt(data: Data, password: String) throws -> Data {
        // For standalone decryption without note context
        let passwordData = password.data(using: .utf8) ?? Data()
        let salt = Data("InkSlateGenericSalt".utf8)
        let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
        let key = SymmetricKey(data: keyData)
        return try decrypt(data: data, with: key)
    }
}

// MARK: - Encryption Errors
enum EncryptionError: Error {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
}

// Need to import CommonCrypto
import CommonCrypto

// MARK: - Encryption View
struct EncryptionView: View {
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var useBiometrics: Bool = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    let note: Notes
    let onComplete: (Bool) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Encrypt Note")
                        .font(.headline)
                    
                    Text("This note will be encrypted and protected with a password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 16) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    if password != confirmPassword && !confirmPassword.isEmpty {
                        Text("Passwords do not match")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Toggle("Enable Biometric Unlock", isOn: $useBiometrics)
                        .padding(.top, 8)
                }
                
                Button("Encrypt Note") {
                    encryptNote()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || password != confirmPassword)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Encrypt Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onComplete(false)
                    }
                }
            }
            .alert("Encryption", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("success") {
                        onComplete(true)
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func encryptNote() {
        guard password == confirmPassword else {
            alertMessage = "Passwords do not match"
            showingAlert = true
            return
        }
        
        let success = EncryptionService.shared.encryptNote(note, password: password)
        if success {
            // Store password for biometric unlock if enabled
            if useBiometrics, let noteId = note.id?.uuidString {
                _ = EncryptionService.shared.storeBiometricPassword(password, for: noteId)
            }
            
            alertMessage = "Note encrypted successfully"
        } else {
            alertMessage = "Failed to encrypt note"
        }
        showingAlert = true
    }
}

// MARK: - Decryption View
struct DecryptionView: View {
    @State private var password: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var canUseBiometrics = false
    let note: Notes
    let onComplete: (Bool) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Decrypt Note")
                        .font(.headline)
                    
                    Text("Enter the password to decrypt this note.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Decrypt Note") {
                    decryptNote()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                
                if canUseBiometrics {
                    Button("Use Biometric Authentication") {
                        authenticateWithBiometrics()
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Decrypt Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onComplete(false)
                    }
                }
            }
            .alert("Decryption", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("success") {
                        onComplete(true)
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                checkBiometricAvailability()
            }
        }
    }
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        canUseBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    private func decryptNote() {
        let success = EncryptionService.shared.decryptNote(note, password: password)
        if success {
            alertMessage = "Note decrypted successfully"
        } else {
            alertMessage = "Failed to decrypt note. Check your password."
        }
        showingAlert = true
    }
    
    private func authenticateWithBiometrics() {
        guard let noteId = note.id?.uuidString else {
            alertMessage = "Cannot use biometric authentication for this note"
            showingAlert = true
            return
        }
        
        EncryptionService.shared.authenticateWithBiometrics(for: noteId) { success, password in
            if success, let password = password {
                let decryptSuccess = EncryptionService.shared.decryptNote(note, password: password)
                if decryptSuccess {
                    alertMessage = "Note decrypted successfully"
                    showingAlert = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        onComplete(true)
                    }
                } else {
                    alertMessage = "Failed to decrypt note"
                    showingAlert = true
                }
            } else {
                alertMessage = "Biometric authentication failed"
                showingAlert = true
            }
        }
    }
}