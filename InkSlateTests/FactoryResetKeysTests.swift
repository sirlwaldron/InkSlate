import Testing
@testable import InkSlate

struct FactoryResetKeysTests {
    @Test func factoryReset_userDefaultsKeys_areScoped() async throws {
        // If this grows unexpectedly, it’s a signal that Factory Reset may be wiping too broadly.
        #expect(InkSlateUserDefaultsKeys.all.contains("MenuOrder"))
        #expect(InkSlateUserDefaultsKeys.all.contains("HiddenMenuItems"))
        #expect(InkSlateUserDefaultsKeys.all.contains("profileUserName"))
        
        // Sanity: we should never be clearing the entire defaults domain.
        #expect(!InkSlateUserDefaultsKeys.all.contains("AppleLanguages"))
        #expect(!InkSlateUserDefaultsKeys.all.contains("NSLanguages"))
    }
}

