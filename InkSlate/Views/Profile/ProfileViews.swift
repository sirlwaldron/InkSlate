//
//  ProfileViews.swift
//  InkSlate
//
//  Created by UI Overhaul on 9/29/25.
//

import SwiftUI

// MARK: - Profile Main View
struct ProfileMainView: View {
    @State private var showingAbout = false
    @State private var showingCustomization = false
    @StateObject private var profileService = ProfileService()
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Profile Header
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Profile Image
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    if let userImage = profileService.userImage {
                        Image(uiImage: userImage)
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
                
                // Profile Info
                Text(profileService.userName)
                    .font(DesignSystem.Typography.title1)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            // Profile Actions
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
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingCustomization) {
            ProfileCustomizationView(profileService: profileService)
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // App Icon and Info
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
                        
                        Text("Version 1.0.0")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                
                // App Description
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("About InkSlate")
                        .font(DesignSystem.Typography.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("InkSlate is your personal productivity companion, designed to help you organize your thoughts, manage your tasks, and keep track of your life in a beautiful, minimalist interface. All data is stored locally on your device.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Credits
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Made with ❤️")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("© 2024 InkSlate. All rights reserved.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.background)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Profile Customization View
struct ProfileCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileService: ProfileService
    
    @State private var tempUserName: String = ""
    @State private var tempUserIcon: String = ""
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // Header
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
                    
                    // Current Profile Preview
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Text("Preview")
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 12) {
                            // Profile Avatar Preview
                            ZStack {
                                Circle()
                                    .fill(DesignSystem.Colors.accent)
                                    .frame(width: 50, height: 50)
                                
                                if let selectedImage = selectedImage {
                                    Image(uiImage: selectedImage)
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
                            
                            // Profile Info Preview
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
                    
                    // Customization Form
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        // Name Field
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
                        
                        // Photo Selection
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
                        }
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ProfileImagePicker(selectedImage: $selectedImage)
        }
        .onAppear {
            tempUserName = profileService.userName
            tempUserIcon = profileService.userIcon
        }
    }
    
    private func saveChanges() {
        // Save the selected image if one was chosen
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

// MARK: - Profile Image Picker
struct ProfileImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileImagePicker
        
        init(_ parent: ProfileImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}