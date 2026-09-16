import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profile Main View
struct ProfileMainView: View {
    @State private var showingAbout = false
    @State private var showingCustomization = false
    @EnvironmentObject private var profileService: ProfileService
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            VStack(spacing: DesignSystem.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    if let userImage = profileService.userImage {
                        Image(platformImage: userImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: profileService.userIcon)
                            .font(.system(size: 60))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
                
                Text(profileService.userName)
                    .font(DesignSystem.Typography.title1)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            VStack(spacing: DesignSystem.Spacing.md) {
                Button(action: { showingCustomization = true }) {
                    HStack {
                        Image(systemName: "person.circle")
                            .font(.system(size: 16, weight: .medium))
                        Text("Customize Profile")
                            .font(DesignSystem.Typography.body)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .minimalistCard(.outlined)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { showingAbout = true }) {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .medium))
                        Text("About")
                            .font(DesignSystem.Typography.body)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .minimalistCard(.outlined)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.Colors.background)
        .navigationTitle("Profile")
        .inlineNavigationTitle()
        .inkSlateSheet(isPresented: $showingAbout) {
            AboutView()
        }
        .inkSlateSheet(isPresented: $showingCustomization) {
            ProfileCustomizationView(profileService: profileService)
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        if let build, !build.isEmpty { return "\(short) (\(build))" }
        return short
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "app.fill")
                            .font(.system(size: 40))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text("InkSlate")
                            .font(DesignSystem.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Version \(appVersion)")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("About InkSlate")
                        .font(DesignSystem.Typography.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("InkSlate is your personal productivity companion for notes, tasks, journals, budgets, and more. Your content is stored in Core Data on this device, and when you are signed into iCloud with CloudKit enabled for InkSlate, selected data can sync across your Apple devices.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Made with ❤️")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("© 2026 InkSlate. All rights reserved.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.background)
            .navigationTitle("About")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .inkSlateFormContainer()
        }
    }
}

// MARK: - Profile Customization View
struct ProfileCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileService: ProfileService
    
    @State private var tempUserName: String = ""
    @State private var tempUserIcon: String = ""
    @State private var selectedImage: PlatformImage?
    @State private var showingImagePicker = false
    @State private var showingHomeBackgroundPicker = false
    @State private var pendingHomeBackgroundImage: PlatformImage?
    @State private var homeBackgroundEditSession: HomeBackgroundEditSession?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Customize Profile")
                            .font(DesignSystem.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Personalize your InkSlate experience")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Text("Preview")
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(DesignSystem.Colors.accent)
                                    .frame(width: 50, height: 50)
                                
                                if let selectedImage = selectedImage {
                                    Image(platformImage: selectedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: tempUserIcon.isEmpty ? profileService.userIcon : tempUserIcon)
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textInverse)
                                }
                            }
                            
                            Text(tempUserName.isEmpty ? profileService.userName : tempUserName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Spacer()
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                .fill(DesignSystem.Colors.surface)
                                .shadow(color: DesignSystem.Shadows.medium, radius: 4, x: 0, y: 2)
                        )
                    }
                    
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Name")
                                .font(DesignSystem.Typography.callout)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            TextField("Enter your name", text: $tempUserName)
                                .font(DesignSystem.Typography.body)
                                .padding(DesignSystem.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .fill(DesignSystem.Colors.backgroundTertiary)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Icon")
                                .font(DesignSystem.Typography.callout)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                ForEach(profileService.availableIcons, id: \.self) { icon in
                                    Button {
                                        tempUserIcon = icon
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(DesignSystem.Colors.backgroundTertiary)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    Circle()
                                                        .stroke(
                                                            (tempUserIcon.isEmpty ? profileService.userIcon : tempUserIcon) == icon
                                                                ? DesignSystem.Colors.accent
                                                                : DesignSystem.Colors.border,
                                                            lineWidth: 2
                                                        )
                                                )
                                            Image(systemName: icon)
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(DesignSystem.Colors.accent)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Profile Photo")
                                .font(DesignSystem.Typography.callout)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                HStack {
                                    Image(systemName: "photo")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.accent)
                                    
                                    Text(selectedImage == nil ? "Choose Photo" : "Change Photo")
                                        .font(DesignSystem.Typography.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                .padding(DesignSystem.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .fill(DesignSystem.Colors.backgroundTertiary)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(role: .destructive) {
                                selectedImage = nil
                                profileService.removeProfileImage()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.red)
                                    
                                    Text("Remove Photo")
                                        .font(DesignSystem.Typography.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                    
                                    Spacer()
                                }
                                .padding(DesignSystem.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .fill(Color.red.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(profileService.userImage == nil && selectedImage == nil)
                        }

                        homeBackgroundSection
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.background)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .inkSlateFormContainer()
        }
        .inkSlateSheet(isPresented: $showingImagePicker) {
            ProfileImagePicker(selectedImage: $selectedImage, allowsEditing: true)
        }
        .inkSlateSheet(isPresented: $showingHomeBackgroundPicker) {
            ProfileImagePicker(
                selectedImage: Binding(
                    get: { pendingHomeBackgroundImage },
                    set: { newValue in
                        guard let newValue else {
                            pendingHomeBackgroundImage = nil
                            return
                        }
                        pendingHomeBackgroundImage = newValue
                        // Wait for the photo picker sheet to finish dismissing before
                        // presenting the editor (nested sheets blank out on iOS).
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            homeBackgroundEditSession = HomeBackgroundEditSession(
                                image: newValue,
                                isNewPick: true,
                                initialScale: 1,
                                initialOffset: .zero
                            )
                        }
                    }
                ),
                allowsEditing: false
            )
        }
        .fullScreenCoverIfAvailable(item: $homeBackgroundEditSession) { session in
            HomeBackgroundEditorView(
                image: session.image,
                initialScale: session.initialScale,
                initialOffset: session.initialOffset
            ) { scale, offset in
                if session.isNewPick {
                    profileService.updateHomeBackgroundImage(session.image)
                }
                profileService.updateHomeBackgroundTransform(
                    scale: scale,
                    offsetX: offset.width,
                    offsetY: offset.height
                )
            }
        }
        .onAppear {
            tempUserName = profileService.userName
            tempUserIcon = profileService.userIcon
            selectedImage = profileService.userImage
        }
    }

    private var homeBackgroundSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Home Background")
                .font(DesignSystem.Typography.callout)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Only applies to the Home screen")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            if let background = profileService.homeBackgroundImage {
                HomeBackgroundPreviewCard(
                    image: background,
                    scale: profileService.homeBackgroundScale,
                    offsetX: profileService.homeBackgroundOffsetX,
                    offsetY: profileService.homeBackgroundOffsetY
                )
            }

            Button {
                showingHomeBackgroundPicker = true
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)

                    Text(profileService.homeBackgroundImage == nil ? "Choose Background" : "Change Background")
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                )
            }
            .buttonStyle(.plain)

            if let background = profileService.homeBackgroundImage {
                Button {
                    homeBackgroundEditSession = HomeBackgroundEditSession(
                        image: background,
                        isNewPick: false,
                        initialScale: profileService.homeBackgroundScale,
                        initialOffset: CGSize(
                            width: profileService.homeBackgroundOffsetX,
                            height: profileService.homeBackgroundOffsetY
                        )
                    )
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.accent)

                        Text("Resize & Position")
                            .font(DesignSystem.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(DesignSystem.Colors.backgroundTertiary)
                    )
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    profileService.removeHomeBackgroundImage()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)

                        Text("Remove Background")
                            .font(DesignSystem.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(.red)

                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(Color.red.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func saveChanges() {
        if let selectedImage = selectedImage {
            profileService.updateProfileImage(selectedImage)
        }
        
        profileService.updateProfile(
            name: tempUserName.isEmpty ? profileService.userName : tempUserName,
            icon: tempUserIcon.isEmpty ? profileService.userIcon : tempUserIcon
        )
        dismiss()
    }
}

// MARK: - Home Background Edit Session

private struct HomeBackgroundEditSession: Identifiable {
    let id = UUID()
    let image: PlatformImage
    let isNewPick: Bool
    let initialScale: Double
    let initialOffset: CGSize
}

// MARK: - Home Background Preview

private struct HomeBackgroundPreviewCard: View {
    let image: PlatformImage
    let scale: Double
    let offsetX: Double
    let offsetY: Double

    var body: some View {
        GeometryReader { proxy in
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(x: offsetX * 0.15, y: offsetY * 0.15)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Home Background Editor

private struct HomeBackgroundEditorView: View {
    let image: PlatformImage
    let initialScale: Double
    let initialOffset: CGSize
    let onSave: (Double, CGSize) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: Double
    @State private var offset: CGSize
    @State private var dragStart: CGSize = .zero
    @State private var pinchStart: Double = 1
    @State private var displayImage: PlatformImage?

    init(
        image: PlatformImage,
        initialScale: Double,
        initialOffset: CGSize,
        onSave: @escaping (Double, CGSize) -> Void
    ) {
        self.image = image
        self.initialScale = initialScale
        self.initialOffset = initialOffset
        self.onSave = onSave
        let clampedScale = max(1, min(initialScale, 4))
        _scale = State(initialValue: clampedScale)
        _offset = State(initialValue: initialOffset)
        _dragStart = State(initialValue: initialOffset)
        _pinchStart = State(initialValue: clampedScale)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("Pinch to resize · Drag to move")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.top, DesignSystem.Spacing.md)
                        .padding(.bottom, DesignSystem.Spacing.sm)

                    ZStack {
                        Color.black.opacity(0.08)

                        if let displayImage {
                            Image(platformImage: displayImage)
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(scale)
                                .offset(offset)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: dragStart.width + value.translation.width,
                                        height: dragStart.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    dragStart = offset
                                },
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(4, max(1, pinchStart * value))
                                }
                                .onEnded { _ in
                                    pinchStart = scale
                                }
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    Button("Reset") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scale = 1
                            pinchStart = 1
                            offset = .zero
                            dragStart = .zero
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.lg)
                }
            }
            .navigationTitle("Home Background")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(scale, offset)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
        }
        .task(id: ObjectIdentifier(image as AnyObject)) {
            displayImage = await Task.detached(priority: .userInitiated) {
                downsampleHomeBackgroundForEditor(image)
            }.value
        }
    }
}

#if canImport(UIKit)
private func downsampleHomeBackgroundForEditor(_ image: UIImage) -> UIImage {
    let maxDimension: CGFloat = 1200
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
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
}
#elseif canImport(AppKit)
private func downsampleHomeBackgroundForEditor(_ image: NSImage) -> NSImage {
    let maxDimension: CGFloat = 1200
    let longest = max(image.size.width, image.size.height)
    guard longest > maxDimension else { return image }
    let scale = maxDimension / longest
    let target = NSSize(
        width: max(1, floor(image.size.width * scale)),
        height: max(1, floor(image.size.height * scale))
    )
    let output = NSImage(size: target)
    output.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
    output.unlockFocus()
    return output
}
#endif

// MARK: - Profile Image Picker
#if canImport(UIKit)
struct ProfileImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: PlatformImage?
    var allowsEditing: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = allowsEditing
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileImagePicker
        init(_ parent: ProfileImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if parent.allowsEditing, let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#elseif canImport(AppKit)
import AppKit
struct ProfileImagePicker: View {
    @Binding var selectedImage: PlatformImage?
    var allowsEditing: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text(allowsEditing ? "Choose a profile image" : "Choose a home background")
            Button("Choose Image…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url,
                   let data = try? Data(contentsOf: url),
                   let image = platformImage(from: data) {
                    selectedImage = image
                }
                dismiss()
            }
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 280, minHeight: 120)
    }
}
#endif