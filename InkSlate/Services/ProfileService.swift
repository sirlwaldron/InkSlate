import SwiftUI
import Foundation
import Combine

// MARK: - Profile Service
@MainActor
class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published var userName: String = "User"
    @Published var userIcon: String = "person.circle.fill"
    @Published var userImage: PlatformImage?

    @Published var homeBackgroundImage: PlatformImage?
    @Published var homeBackgroundScale: Double = 1.0
    @Published var homeBackgroundOffsetX: Double = 0
    @Published var homeBackgroundOffsetY: Double = 0

    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let userNameKey = "profileUserName"
    private let userIconKey = "profileUserIcon"
    private let userImageKey = "profileUserImage"
    private let homeBackgroundScaleKey = "homeBackgroundScale"
    private let homeBackgroundOffsetXKey = "homeBackgroundOffsetX"
    private let homeBackgroundOffsetYKey = "homeBackgroundOffsetY"
    private let imageFileName = "profile-user-image.jpg"
    private let homeBackgroundFileName = "home-background.jpg"
    /// Keep profile JPEG well under NSUbiquitousKeyValueStore per-key limits.
    private let maxCloudProfileImageBytes = 700_000
    private var cloudStoreObserver: NSObjectProtocol?

    let availableIcons = [
        "person.circle.fill",
        "person.crop.circle.fill",
        "person.2.circle.fill",
        "person.3.circle.fill",
        "star.circle.fill",
        "heart.circle.fill",
        "flame.circle.fill",
        "leaf.circle.fill",
        "moon.circle.fill",
        "sun.max.circle.fill",
        "cloud.circle.fill",
        "bolt.circle.fill",
        "sparkles.circle.fill",
        "crown.circle.fill",
        "diamond.circle.fill"
    ]

    init() {
        setupCloudStoreObserver()
        loadProfile()
    }

    deinit {
        if let cloudStoreObserver {
            NotificationCenter.default.removeObserver(cloudStoreObserver)
        }
    }

    private func setupCloudStoreObserver() {
        cloudStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadProfile()
            }
        }
    }

    func loadProfile() {
        if let cloudName = cloudStore.string(forKey: userNameKey), !cloudName.isEmpty {
            userName = cloudName
        } else if let localName = userDefaults.string(forKey: userNameKey), !localName.isEmpty {
            userName = localName
            cloudStore.set(localName, forKey: userNameKey)
        } else {
            userName = "User"
        }

        if let cloudIcon = cloudStore.string(forKey: userIconKey), !cloudIcon.isEmpty {
            userIcon = cloudIcon
        } else if let localIcon = userDefaults.string(forKey: userIconKey), !localIcon.isEmpty {
            userIcon = localIcon
            cloudStore.set(localIcon, forKey: userIconKey)
        } else {
            userIcon = "person.circle.fill"
        }

        loadHomeBackgroundTransform()

        Task {
            await loadProfileImage()
            await loadHomeBackgroundImage()
        }

        cloudStore.synchronize()
    }

    func updateProfile(name: String, icon: String) {
        userName = name
        userIcon = icon

        cloudStore.set(name, forKey: userNameKey)
        cloudStore.set(icon, forKey: userIconKey)
        cloudStore.synchronize()

        userDefaults.set(name, forKey: userNameKey)
        userDefaults.set(icon, forKey: userIconKey)
    }

    func updateProfileImage(_ image: PlatformImage) {
        let processed = processProfileImageForStorage(image)
        userImage = processed
        guard let imageData = jpegDataFittingCloudLimit(for: processed) else { return }
        saveImageToDisk(imageData, fileName: imageFileName)
        cloudStore.set(imageData, forKey: userImageKey)
        cloudStore.synchronize()
        userDefaults.set(imageData, forKey: userImageKey)
    }

    func removeProfileImage() {
        userImage = nil
        removeStoredImage(fileName: imageFileName)
        cloudStore.removeObject(forKey: userImageKey)
        cloudStore.synchronize()
        userDefaults.removeObject(forKey: userImageKey)
    }

    func updateHomeBackgroundImage(_ image: PlatformImage) {
        let processed = processHomeBackgroundImageForStorage(image)
        homeBackgroundImage = processed
        homeBackgroundScale = 1.0
        homeBackgroundOffsetX = 0
        homeBackgroundOffsetY = 0
        persistHomeBackgroundTransform()

        if let imageData = processed.jpegData(compressionQuality: 0.82)
            ?? processed.inkSlateJPEGDataFitting(maxBytes: 2_500_000) {
            saveImageToDisk(imageData, fileName: homeBackgroundFileName)
        }
    }

    func updateHomeBackgroundTransform(scale: Double, offsetX: Double, offsetY: Double) {
        homeBackgroundScale = max(1.0, min(scale, 4.0))
        homeBackgroundOffsetX = offsetX
        homeBackgroundOffsetY = offsetY
        persistHomeBackgroundTransform()
    }

    func removeHomeBackgroundImage() {
        homeBackgroundImage = nil
        homeBackgroundScale = 1.0
        homeBackgroundOffsetX = 0
        homeBackgroundOffsetY = 0
        removeStoredImage(fileName: homeBackgroundFileName)
        persistHomeBackgroundTransform()
    }

    func resetToDefaults() {
        updateProfile(
            name: "User",
            icon: "person.circle.fill"
        )
        removeProfileImage()
        removeHomeBackgroundImage()
    }

    // MARK: - Load Helpers

    private func loadProfileImage() async {
        if let cloudData = cloudStore.data(forKey: userImageKey),
           let image = platformImage(from: cloudData) {
            userImage = image
            saveImageToDisk(cloudData, fileName: imageFileName)
            userDefaults.set(cloudData, forKey: userImageKey)
            return
        }

        if let localData = userDefaults.data(forKey: userImageKey),
           let image = platformImage(from: localData) {
            userImage = image
            saveImageToDisk(localData, fileName: imageFileName)
            cloudStore.set(localData, forKey: userImageKey)
            cloudStore.synchronize()
            return
        }

        if let storedImage = await loadImageFromDiskAsync(fileName: imageFileName) {
            userImage = storedImage
            if let imageData = jpegDataFittingCloudLimit(for: storedImage) {
                cloudStore.set(imageData, forKey: userImageKey)
                cloudStore.synchronize()
                userDefaults.set(imageData, forKey: userImageKey)
            }
            return
        }

        userImage = nil
    }

    private func loadHomeBackgroundImage() async {
        if let storedImage = await loadImageFromDiskAsync(fileName: homeBackgroundFileName) {
            homeBackgroundImage = storedImage
        } else {
            homeBackgroundImage = nil
        }
    }

    private func loadHomeBackgroundTransform() {
        let scale = cloudStore.object(forKey: homeBackgroundScaleKey) as? Double
            ?? userDefaults.object(forKey: homeBackgroundScaleKey) as? Double
            ?? 1.0
        let offsetX = cloudStore.object(forKey: homeBackgroundOffsetXKey) as? Double
            ?? userDefaults.object(forKey: homeBackgroundOffsetXKey) as? Double
            ?? 0
        let offsetY = cloudStore.object(forKey: homeBackgroundOffsetYKey) as? Double
            ?? userDefaults.object(forKey: homeBackgroundOffsetYKey) as? Double
            ?? 0

        homeBackgroundScale = max(1.0, min(scale, 4.0))
        homeBackgroundOffsetX = offsetX
        homeBackgroundOffsetY = offsetY

        // Seed cloud from local when needed so transforms stay in sync.
        if cloudStore.object(forKey: homeBackgroundScaleKey) == nil {
            persistHomeBackgroundTransform()
        }
    }

    private func persistHomeBackgroundTransform() {
        cloudStore.set(homeBackgroundScale, forKey: homeBackgroundScaleKey)
        cloudStore.set(homeBackgroundOffsetX, forKey: homeBackgroundOffsetXKey)
        cloudStore.set(homeBackgroundOffsetY, forKey: homeBackgroundOffsetYKey)
        cloudStore.synchronize()

        userDefaults.set(homeBackgroundScale, forKey: homeBackgroundScaleKey)
        userDefaults.set(homeBackgroundOffsetX, forKey: homeBackgroundOffsetXKey)
        userDefaults.set(homeBackgroundOffsetY, forKey: homeBackgroundOffsetYKey)
    }

    // MARK: - Image Persistence Helpers

    private func imageFileURL(fileName: String) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func saveImageToDisk(_ data: Data, fileName: String) {
        guard let url = imageFileURL(fileName: fileName) else { return }
        do {
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes(
                [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
        }
    }

    private func loadImageFromDiskAsync(fileName: String) async -> PlatformImage? {
        guard let url = imageFileURL(fileName: fileName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }

        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let image = platformImage(from: data) else { return nil }
            return image
        }.value
    }

    private func removeStoredImage(fileName: String) {
        guard let url = imageFileURL(fileName: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func jpegDataFittingCloudLimit(for image: PlatformImage) -> Data? {
        if let data = image.jpegData(compressionQuality: 0.7),
           data.count <= maxCloudProfileImageBytes {
            return data
        }
        return image.inkSlateJPEGDataFitting(maxBytes: maxCloudProfileImageBytes)
    }

    // MARK: - Image downsampling / compression

    private func processProfileImageForStorage(_ image: PlatformImage) -> PlatformImage {
        #if canImport(UIKit)
        let target = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (target.width - scaledSize.width) / 2, y: (target.height - scaledSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
        #elseif canImport(AppKit)
        let target = CGSize(width: 200, height: 200)
        let newImage = NSImage(size: target)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - scaledSize.width) / 2, y: (target.height - scaledSize.height) / 2)
        image.draw(in: CGRect(origin: origin, size: scaledSize), from: .zero, operation: .sourceOver, fraction: 1.0)
        return newImage
        #else
        return image
        #endif
    }

    private func processHomeBackgroundImageForStorage(_ image: PlatformImage) -> PlatformImage {
        #if canImport(UIKit)
        let maxDimension: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        #elseif canImport(AppKit)
        let maxDimension: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = NSSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let newImage = NSImage(size: target)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        return newImage
        #else
        return image
        #endif
    }
}
