import Foundation
import Testing
@testable import RemoteMic

@Suite("Application button profile selection")
struct ApplicationProfileSelectionTests {
    private func makeSettings(
        frontmostBundleIdentifier: @escaping () -> String? = { nil }
    ) -> (AppSettings, UserDefaults, String) {
        let name = "SayAll.AppProfileSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        settings.frontmostApplicationBundleIdentifier = frontmostBundleIdentifier
        return (settings, defaults, name)
    }

    @Test func assignedProfileWinsOverGlobalProfileButLosesToOverride() {
        let (settings, defaults, name) = makeSettings(frontmostBundleIdentifier: { "com.example.target" })
        defer { defaults.removePersistentDomain(forName: name) }
        let appID = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "Target", bundleIdentifier: "com.example.target", applicationPath: ""
        ))
        let schemeID = UUID()
        settings.assignedMappingProfileApplicable = { $0 == schemeID }
        settings.assignedMappingProfileAction = { _, button, trigger in
            button == .ok && trigger == .singleClick
                ? .init(action: .arrowLeft, shortcut: nil)
                : nil
        }
        settings.configuredActionOverride = { _, _, _ in
            .init(action: .commandPaste, shortcut: nil)
        }
        #expect(settings.setApplicationMappingProfileID(schemeID, applicationProfileID: appID))
        #expect(settings.configuredAction(for: .ok, trigger: .singleClick, profileID: nil).action == .arrowLeft)
        // 方案未覆盖的手势继承基础映射，不回落到别的方案。
        #expect(settings.configuredAction(for: .back, trigger: .singleClick, profileID: nil).action == .commandPaste)

        #expect(settings.setApplicationButtonOverride(
            .init(action: .arrowRight, shortcut: nil),
            applicationProfileID: appID,
            button: .ok,
            trigger: .singleClick
        ) == .wrote)
        #expect(settings.configuredAction(for: .ok, trigger: .singleClick, profileID: nil).action == .arrowRight)
    }

    @Test func inapplicableProfileFallsBackToGlobal() {
        let (settings, defaults, name) = makeSettings(frontmostBundleIdentifier: { "com.example.target" })
        defer { defaults.removePersistentDomain(forName: name) }
        let appID = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "Target", bundleIdentifier: "com.example.target", applicationPath: ""
        ))
        let schemeID = UUID()
        settings.assignedMappingProfileApplicable = { _ in false }
        settings.assignedMappingProfileAction = { _, _, _ in
            .init(action: .arrowLeft, shortcut: nil)
        }
        settings.configuredActionOverride = { _, _, _ in
            .init(action: .commandPaste, shortcut: nil)
        }
        _ = settings.setApplicationMappingProfileID(schemeID, applicationProfileID: appID)
        #expect(settings.activeAssignedMappingProfileID() == nil)
        #expect(settings.configuredAction(for: .ok, trigger: .singleClick, profileID: nil).action == .commandPaste)
    }

    @Test func explicitDisabledInAssignedProfileDoesNotInherit() {
        let (settings, defaults, name) = makeSettings(frontmostBundleIdentifier: { "com.example.target" })
        defer { defaults.removePersistentDomain(forName: name) }
        let appID = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "Target", bundleIdentifier: "com.example.target", applicationPath: ""
        ))
        let schemeID = UUID()
        settings.assignedMappingProfileApplicable = { $0 == schemeID }
        settings.assignedMappingProfileAction = { _, button, trigger in
            button == .ok && trigger == .singleClick ? .disabled : nil
        }
        _ = settings.setApplicationMappingProfileID(schemeID, applicationProfileID: appID)
        #expect(settings.configuredAction(for: .ok, trigger: .singleClick, profileID: nil).action == .disabled)
        #expect(settings.applicationAssignedProfileHasBinding(for: .ok, trigger: .singleClick))
    }

    @Test func profileReferencePersistsAndOldConfigurationDecodesWithoutIt() throws {
        let name = "SayAll.AppProfileSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let schemeID = UUID()
        let settings = AppSettings(defaults: defaults)
        let appID = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "Target",
            bundleIdentifier: "com.example.target",
            applicationPath: "",
            mappingProfileID: schemeID
        ))
        #expect(settings.customApplicationProfile(id: appID)?.mappingProfileID == schemeID)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.customApplicationProfile(id: appID)?.mappingProfileID == schemeID)

        let encoder = JSONEncoder()
        let data = try encoder.encode(CustomApplicationProfile(
            displayName: "Target", bundleIdentifier: "com.example.target", applicationPath: ""
        ))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "mappingProfileID")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CustomApplicationProfile.self, from: legacy)
        #expect(decoded.mappingProfileID == nil)
    }

    @Test func assignedProfileDoesNotChangeButtonsOutsideApplicationScope() {
        let (settings, defaults, name) = makeSettings(frontmostBundleIdentifier: { "com.example.target" })
        defer { defaults.removePersistentDomain(forName: name) }
        let appID = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "Target", bundleIdentifier: "com.example.target", applicationPath: ""
        ))
        let schemeID = UUID()
        settings.assignedMappingProfileApplicable = { $0 == schemeID }
        settings.assignedMappingProfileAction = { _, _, _ in
            .init(action: .arrowLeft, shortcut: nil)
        }
        settings.configuredActionOverride = { _, _, _ in
            .init(action: .commandPaste, shortcut: nil)
        }
        _ = settings.setApplicationMappingProfileID(schemeID, applicationProfileID: appID)
        #expect(!settings.applicationAssignedProfileHasBinding(for: .menu, trigger: .singleClick))
        #expect(settings.configuredAction(for: .menu, trigger: .singleClick, profileID: nil).action == .commandPaste)
    }

    @Test func unavailableReferencesAreClearedAndOverridesKept() {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let valid = UUID()
        let stale = UUID()
        let appA = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "A", bundleIdentifier: "com.example.a", applicationPath: "",
            mappingProfileID: stale
        ))
        let appB = settings.addCustomApplicationProfile(CustomApplicationProfile(
            displayName: "B", bundleIdentifier: "com.example.b", applicationPath: "",
            mappingProfileID: valid
        ))
        _ = settings.setApplicationButtonOverride(
            .init(action: .arrowLeft, shortcut: nil),
            applicationProfileID: appA,
            button: .ok,
            trigger: .singleClick
        )
        let cleared = settings.clearUnavailableApplicationMappingProfileReferences(valid: [valid])
        #expect(cleared == 1)
        #expect(settings.customApplicationProfile(id: appA)?.mappingProfileID == nil)
        #expect(settings.customApplicationProfile(id: appB)?.mappingProfileID == valid)
        #expect(settings.customApplicationProfile(id: appA)?.buttonBindings?.count == 1)
    }
}
