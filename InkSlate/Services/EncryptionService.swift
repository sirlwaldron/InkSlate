//
//  EncryptionService.swift
//  InkSlate
//

import Foundation
import SwiftUI
import Combine
import CryptoKit
import LocalAuthentication
import Security
import CommonCrypto

// MARK: - Encryption Service
class EncryptionService: ObservableObject {
    static let shared = EncryptionService()
    
    private let keychainService = "co.inkslate.encryption"
    private let biometricKeyIdentifier = "co.inkslate.biometric.key"
    
    private init() {}
    
    
    deinit {
        
    }
    
    // MARK: - Encryption Methods
    
    /// Legacy v1: deterministic salt from note id + PBKDF2 + AES-GCM payload (raw combined bytes, base64).
    private static let encPrefix = "⟪ENC⟫"
    private static let encSuffix = "⟪/ENC⟫"
    /// v2: random salt per encryption, JSON metadata + AES-GCM (still 4-digit PIN at the UI).
    private static let enc2Prefix = "⟪ENC2⟫"
    private static let enc2Suffix = "⟪/ENC2⟫"
    
    private struct NoteEncryptedPayloadV2: Codable {
        var v: Int
        var i: Int
        var s: String
        var c: String
    }
    
    private static let standaloneMagic = Data("INKSB1".utf8)
    
    private func randomSalt(byteCount: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status == errSecSuccess { return Data(bytes) }
        return Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max) })
    }
    
    func encryptNote(_ note: Notes, password: String) -> Bool {
        guard !password.isEmpty else { return false }
        
        do {
            let salt = randomSalt()
            let passwordData = password.data(using: .utf8) ?? Data()
            let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
            let key = SymmetricKey(data: keyData)
            
            let content = note.content ?? ""
            let plaintext = content.data(using: .utf8) ?? Data()
            let ciphertext = try encrypt(data: plaintext, with: key)
            
            let payload = NoteEncryptedPayloadV2(
                v: 2,
                i: 100_000,
                s: salt.base64EncodedString(),
                c: ciphertext.base64EncodedString()
            )
            let json = try JSONEncoder().encode(payload)
            note.content = Self.enc2Prefix + json.base64EncodedString() + Self.enc2Suffix
            note.isEncrypted = true
            note.containerType = "encrypted"
            note.preview = nil
            note.modifiedDate = Date()
            
            return true
        } catch {
            return false
        }
    }
    
    func decryptNote(_ note: Notes, password: String) -> Bool {
        guard note.isEncrypted, !password.isEmpty else { return false }
        
        let content = note.content ?? ""
        
        do {
            let decryptedData: Data
            
            if let v2Payload = Self.extractV2Payload(from: content) {
                let passwordData = password.data(using: .utf8) ?? Data()
                guard let salt = Data(base64Encoded: v2Payload.s) else { return false }
                guard let ciphertext = Data(base64Encoded: v2Payload.c) else { return false }
                let iterations = max(10_000, v2Payload.i)
                let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: iterations, keyLength: 32)
                let key = SymmetricKey(data: keyData)
                decryptedData = try decrypt(data: ciphertext, with: key)
            } else {
                let key = try deriveKey(from: password, note: note)
                
                let base64Payload: String = {
                    guard
                        let prefixRange = content.range(of: Self.encPrefix),
                        let suffixRange = content.range(of: Self.encSuffix, range: prefixRange.upperBound..<content.endIndex)
                    else {
                        return content
                    }
                    return String(content[prefixRange.upperBound..<suffixRange.lowerBound])
                }()
                
                guard let encryptedData = Data(base64Encoded: base64Payload) else { return false }
                decryptedData = try decrypt(data: encryptedData, with: key)
            }
            
            note.content = String(data: decryptedData, encoding: .utf8) ?? ""
            note.isEncrypted = false
            note.containerType = "none"
            note.modifiedDate = Date()
            
            let plain = MarkdownSerialization.plainText(from: note.content ?? "")
            note.preview = plain.isEmpty ? nil : String(plain.prefix(100))
            
            return true
        } catch {
            return false
        }
    }
    
    private static func extractV2Payload(from content: String) -> NoteEncryptedPayloadV2? {
        guard
            let pStart = content.range(of: enc2Prefix),
            let pEnd = content.range(of: enc2Suffix, range: pStart.upperBound..<content.endIndex)
        else { return nil }
        let b64 = String(content[pStart.upperBound..<pEnd.lowerBound])
        guard let json = Data(base64Encoded: b64) else { return nil }
        return try? JSONDecoder().decode(NoteEncryptedPayloadV2.self, from: json)
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
        let salt = randomSalt()
        let passwordData = password.data(using: .utf8) ?? Data()
        let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
        let key = SymmetricKey(data: keyData)
        let ciphertext = try encrypt(data: data, with: key)
        let payload = NoteEncryptedPayloadV2(v: 2, i: 100_000, s: salt.base64EncodedString(), c: ciphertext.base64EncodedString())
        let json = try JSONEncoder().encode(payload)
        var out = Self.standaloneMagic
        out.append(json)
        return out
    }
    
    func decrypt(data: Data, password: String) throws -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        
        if data.count > Self.standaloneMagic.count, data.prefix(Self.standaloneMagic.count) == Self.standaloneMagic {
            let json = data.dropFirst(Self.standaloneMagic.count)
            let payload = try JSONDecoder().decode(NoteEncryptedPayloadV2.self, from: Data(json))
            guard let salt = Data(base64Encoded: payload.s) else { throw EncryptionError.decryptionFailed }
            guard let ciphertext = Data(base64Encoded: payload.c) else { throw EncryptionError.decryptionFailed }
            let iterations = max(10_000, payload.i)
            let keyData = try deriveKeyPBKDF2(password: passwordData, salt: salt, iterations: iterations, keyLength: 32)
            let key = SymmetricKey(data: keyData)
            return try decrypt(data: ciphertext, with: key)
        }
        
        let legacySalt = Data("InkSlateGenericSalt".utf8)
        let keyData = try deriveKeyPBKDF2(password: passwordData, salt: legacySalt, iterations: 100_000, keyLength: 32)
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

// MARK: - Passcode field (encryption sheets)
private struct PasscodeField: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: text) { _, newValue in
                    text = String(newValue.filter(\.isNumber).prefix(4))
                }
        }
    }
}

// MARK: - Encryption View
struct EncryptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var useBiometrics: Bool = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    let note: Notes
    let onComplete: (Bool) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Encrypt note")
                                .font(DesignSystem.Typography.title1)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Text("This note will be encrypted and protected with a 4-digit passcode.")
                                .font(DesignSystem.Typography.callout)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.xl)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            PasscodeField(label: "4-digit passcode", text: $pin)
                            PasscodeField(label: "Confirm passcode", text: $confirmPin)
                            
                            if pin != confirmPin && !confirmPin.isEmpty {
                                Text("Passcodes do not match")
                                    .foregroundColor(DesignSystem.Colors.error)
                                    .font(DesignSystem.Typography.caption)
                            }
                            
                            Toggle("Enable biometric unlock", isOn: $useBiometrics)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .tint(DesignSystem.Colors.accent)
                                .padding(.top, DesignSystem.Spacing.sm)
                        }
                        .padding(DesignSystem.Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        
                        Button("Encrypt note") {
                            encryptNote()
                        }
                        .frame(maxWidth: .infinity)
                        .minimalistButton(variant: .primary, size: .large)
                        .disabled(pin.count != 4 || pin != confirmPin)
                    }
                    .padding(DesignSystem.Spacing.xl)
                }
            }
            .navigationTitle("Encrypt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete(false)
                        dismiss()
                    }
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Encryption", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("success") {
                        onComplete(true)
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func encryptNote() {
        guard pin == confirmPin else {
            alertMessage = "Passcodes do not match"
            showingAlert = true
            return
        }
        guard pin.count == 4 else {
            alertMessage = "Passcode must be 4 digits"
            showingAlert = true
            return
        }
        
        let success = EncryptionService.shared.encryptNote(note, password: pin)
        if success {
            // Store password for biometric unlock if enabled
            if useBiometrics, let noteId = note.id?.uuidString {
                _ = EncryptionService.shared.storeBiometricPassword(pin, for: noteId)
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
    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var canUseBiometrics = false
    let note: Notes
    let onComplete: (Bool) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Decrypt note")
                                .font(DesignSystem.Typography.title1)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Text("Enter the 4-digit passcode to decrypt this note.")
                                .font(DesignSystem.Typography.callout)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.xl)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            PasscodeField(label: "Passcode", text: $pin)
                        }
                        .padding(DesignSystem.Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        
                        Button("Decrypt note") {
                            decryptNote()
                        }
                        .frame(maxWidth: .infinity)
                        .minimalistButton(variant: .primary, size: .large)
                        .disabled(pin.count != 4)
                        
                        if canUseBiometrics {
                            Button("Unlock with biometrics") {
                                authenticateWithBiometrics()
                            }
                            .frame(maxWidth: .infinity)
                            .minimalistButton(variant: .secondary, size: .large)
                        }
                    }
                    .padding(DesignSystem.Spacing.xl)
                }
            }
            .navigationTitle("Decrypt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete(false)
                        dismiss()
                    }
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Decryption", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("success") {
                        onComplete(true)
                        dismiss()
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
        let success = EncryptionService.shared.decryptNote(note, password: pin)
        if success {
            alertMessage = "Note decrypted successfully"
        } else {
            alertMessage = "Failed to decrypt note. Check your passcode."
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