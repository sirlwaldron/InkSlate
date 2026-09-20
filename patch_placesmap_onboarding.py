import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

# 1. Add AppStorage and State to PlacesMapView
old_states = """    @State private var selectedFeature: MapFeature?
    @State private var resolvedItem: MKMapItem?
    @State private var isResolvingFeature = false
    @StateObject private var locationManager = LocationManager.shared

    init() {"""
new_states = """    @State private var selectedFeature: MapFeature?
    @State private var resolvedItem: MKMapItem?
    @State private var isResolvingFeature = false
    @StateObject private var locationManager = LocationManager.shared
    
    @AppStorage("hasSeenLocationOnboarding") private var hasSeenLocationOnboarding = false
    @State private var showLocationOnboarding = false

    init() {"""
content = content.replace(old_states, new_states)

# 2. Modify onAppear to check AppStorage
old_onappear = """            .onAppear {
                locationManager.requestAuthorization()
            }"""
new_onappear = """            .onAppear {
                if !hasSeenLocationOnboarding {
                    showLocationOnboarding = true
                } else {
                    locationManager.requestAuthorization()
                }
            }
            .inkSlateSheet(isPresented: $showLocationOnboarding) {
                LocationOnboardingView {
                    hasSeenLocationOnboarding = true
                    showLocationOnboarding = false
                    locationManager.requestAuthorization()
                }
            }"""
content = content.replace(old_onappear, new_onappear)

# 3. Append LocationOnboardingView at the end of the file
onboarding_view = """
// MARK: - Location Onboarding View

struct LocationOnboardingView: View {
    var onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            Spacer(minLength: 0)
            
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.10))
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(DesignSystem.Colors.accent.opacity(0.18), lineWidth: 0.5)
                    .frame(width: 132, height: 132)
                Image(systemName: "location.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
            }
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                Text("Explore Nearby")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("InkSlate uses your location to show you on the map, helping you find and save nearby restaurants, parks, and activities directly to your lists.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            
            Spacer(minLength: 0)
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(DesignSystem.Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                }
                .minimalistButton(variant: .primary, size: .large)
                .accessibilityLabel("Continue to allow location access")
            }
        }
        .padding(DesignSystem.Spacing.xxl)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        #if os(macOS)
        .frame(width: 400, height: 500)
        #endif
    }
}
"""

content += onboarding_view

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)
print("Patched PlacesMapView.swift with LocationOnboardingView successfully.")
