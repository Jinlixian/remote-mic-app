import Foundation
import Testing
@testable import RemoteMic

@Suite("Host application scheme fallback")
struct ApplicationSchemeFallbackTests {
    private func defaults() -> UserDefaults {
        let suite = "ApplicationSchemeFallbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func hostSchemePersistsAndResolvesBindings() {
        let defaults = defaults()
        let settings = AppSettings(defaults: defaults)
        let binding = UnifiedButtonBinding(
            remoteProfileID: nil,
            button: .ok,
            trigger: .singleClick,
            configured: ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
        )
        let id = settings.createHostApplicationScheme(
            name: "APP 方案",
            bindings: [binding],
            deviceProfileID: nil
        )
        #expect(id != nil)
        #expect(settings.hostApplicationSchemeProfiles(device: nil).count == 1)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: id!,
            device: nil,
            button: .ok,
            trigger: .singleClick
        )?.action == .commandCopy)

        let restored = AppSettings(defaults: defaults)
        #expect(restored.hostApplicationSchemeProfiles(device: nil).count == 1)
        #expect(restored.hostApplicationSchemeBinding(
            mappingProfileID: id!,
            device: nil,
            button: .ok,
            trigger: .singleClick
        )?.action == .commandCopy)
    }

    @Test func hostSchemeIsFilteredByDevice() {
        let defaults = defaults()
        let settings = AppSettings(defaults: defaults)
        let device = UUID()
        let other = UUID()
        _ = settings.createHostApplicationScheme(
            name: "设备方案",
            bindings: [],
            deviceProfileID: device
        )
        #expect(settings.hostApplicationSchemeProfiles(device: device).count == 1)
        #expect(settings.hostApplicationSchemeProfiles(device: other).isEmpty)
        #expect(settings.hostApplicationSchemeProfiles(device: nil).count == 1)
    }

    @Test func macroFeatureUsesHostSchemeWithoutGlobalProfilePollution() {
        let feature = MacroFeatureIntegration()
        let id = UUID()
        let action = ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
        feature.configureHostApplicationSchemes(
            profiles: { _ in [ButtonMappingProfile(id: id, name: "APP 方案")] },
            binding: { _, _, _, _ in action },
            create: { _, _, _ in id },
            reload: { true }
        )
        #expect(feature.usesHostApplicationSchemes)
        #expect(feature.applicationSchemeProfiles(device: nil).map(\.id) == [id])
        #expect(feature.mappingProfiles(device: nil).isEmpty)
        #expect(feature.isMappingProfileApplicable(id, device: nil))
        #expect(feature.assignedApplicationBinding(
            mappingProfileID: id,
            device: nil,
            button: .ok,
            trigger: .singleClick
        ) == action)
    }

    @Test @MainActor func bridgeMaterializesLegacyAppsIntoHostSchemes() throws {
        let suite = "ApplicationSchemeFallbackTests.bridge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        let copy = ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
        let paste = ConfiguredButtonAction(action: .commandPaste, shortcut: nil)
        let appA = CustomApplicationProfile(
            displayName: "A",
            bundleIdentifier: "test.a",
            applicationPath: "/Applications/A.app",
            buttonBindings: [ApplicationButtonBinding(button: .ok, trigger: .singleClick, configured: copy)]
        )
        let appB = CustomApplicationProfile(
            displayName: "B",
            bundleIdentifier: "test.b",
            applicationPath: "/Applications/B.app",
            buttonBindings: [ApplicationButtonBinding(button: .ok, trigger: .singleClick, configured: copy)]
        )
        let appC = CustomApplicationProfile(
            displayName: "C",
            bundleIdentifier: "test.c",
            applicationPath: "/Applications/C.app",
            buttonBindings: [ApplicationButtonBinding(button: .ok, trigger: .singleClick, configured: paste)]
        )
        settings.addCustomApplicationProfile(appA)
        settings.addCustomApplicationProfile(appB)
        settings.addCustomApplicationProfile(appC)

        let model = BridgeAppModel(settings: settings)
        #expect(model.macroFeature.usesHostApplicationSchemes)
        #expect(settings.hostApplicationSchemes.count == 2)
        let assigned = settings.customApplicationProfiles.compactMap(\.mappingProfileID)
        #expect(assigned.count == 3)
        #expect(assigned[0] == assigned[1])
        #expect(assigned[2] != assigned[0])
        #expect(settings.customApplicationProfile(id: appA.id)?.buttonBindings == nil)
        #expect(settings.hostApplicationSchemeProfiles(device: nil).count == 2)
        let owners = Set(settings.applicationSchemeOwners.values)
        #expect(owners == Set([appA.id.uuidString, appC.id.uuidString]))
    }

    @Test @MainActor func nonOwnerEditCopiesIntoSelfAndLeavesSourceIndependent() throws {
        let suite = "ApplicationSchemeFallbackTests.copy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        let copy = ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
        let paste = ConfiguredButtonAction(action: .commandPaste, shortcut: nil)
        let cut = ConfiguredButtonAction(action: .commandCut, shortcut: nil)
        let appA = CustomApplicationProfile(
            displayName: "A", bundleIdentifier: "test.a", applicationPath: "/Applications/A.app"
        )
        let appB = CustomApplicationProfile(
            displayName: "B", bundleIdentifier: "test.b", applicationPath: "/Applications/B.app"
        )
        let appC = CustomApplicationProfile(
            displayName: "C", bundleIdentifier: "test.c", applicationPath: "/Applications/C.app"
        )
        settings.addCustomApplicationProfile(appA)
        settings.addCustomApplicationProfile(appB)
        settings.addCustomApplicationProfile(appC)
        let schemeB = try #require(settings.createHostApplicationScheme(
            name: "B 方案",
            bindings: [UnifiedButtonBinding(
                remoteProfileID: nil, button: .ok, trigger: .singleClick, configured: copy
            )],
            deviceProfileID: nil
        ))
        let schemeA = try #require(settings.createHostApplicationScheme(
            name: "A 方案",
            bindings: [UnifiedButtonBinding(
                remoteProfileID: nil, button: .ok, trigger: .singleClick, configured: cut
            )],
            deviceProfileID: nil
        ))
        settings.setApplicationSchemeOwner(schemeB, applicationProfileID: appB.id)
        settings.setApplicationSchemeOwner(schemeA, applicationProfileID: appA.id)
        #expect(settings.setApplicationMappingProfileID(schemeB, applicationProfileID: appA.id))
        #expect(settings.setApplicationMappingProfileID(schemeB, applicationProfileID: appB.id))
        #expect(settings.setApplicationMappingProfileID(schemeA, applicationProfileID: appC.id))

        let model = BridgeAppModel(settings: settings)
        #expect(model.macroFeature.usesHostApplicationSchemes)
        #expect(settings.setApplicationButtonOverride(
            paste,
            applicationProfileID: appA.id,
            button: .up,
            trigger: .singleClick
        ) == .wrote)

        #expect(settings.customApplicationProfile(id: appA.id)?.mappingProfileID == schemeA)
        #expect(settings.applicationSchemeOwner(schemeA) == appA.id)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeB, device: nil, button: .up, trigger: .singleClick
        ) == nil)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeA, device: nil, button: .ok, trigger: .singleClick
        )?.action == .commandCopy)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeA, device: nil, button: .up, trigger: .singleClick
        )?.action == .commandPaste)
        #expect(settings.configuredAction(
            for: .up, trigger: .singleClick, profileID: nil,
            applicationBundleIdentifier: appC.bundleIdentifier
        ).action == .commandPaste)

        #expect(settings.setApplicationButtonOverride(
            cut,
            applicationProfileID: appC.id,
            button: .down,
            trigger: .singleClick
        ) == .wrote)

        let schemeC = try #require(settings.customApplicationProfile(id: appC.id)?.mappingProfileID)
        #expect(schemeC != schemeA)
        #expect(settings.applicationSchemeOwner(schemeC) == appC.id)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeA, device: nil, button: .down, trigger: .singleClick
        )?.action == .arrowDown)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeC, device: nil, button: .down, trigger: .singleClick
        )?.action == .commandCut)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeC, device: nil, button: .up, trigger: .singleClick
        )?.action == .commandPaste)
    }

    @Test @MainActor func ownerEditUpdatesOwnedSchemeAndReferencingAppsFollow() throws {
        let suite = "ApplicationSchemeFallbackTests.shared.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        let copy = ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
        let paste = ConfiguredButtonAction(action: .commandPaste, shortcut: nil)
        let cut = ConfiguredButtonAction(action: .commandCut, shortcut: nil)
        let appA = CustomApplicationProfile(
            displayName: "A",
            bundleIdentifier: "test.a",
            applicationPath: "/Applications/A.app",
            buttonBindings: [ApplicationButtonBinding(
                button: .down, trigger: .singleClick, configured: cut
            )]
        )
        let appC = CustomApplicationProfile(
            displayName: "C", bundleIdentifier: "test.c", applicationPath: "/Applications/C.app"
        )
        settings.addCustomApplicationProfile(appA)
        settings.addCustomApplicationProfile(appC)
        let schemeA = try #require(settings.createHostApplicationScheme(
            name: "A 方案",
            bindings: [UnifiedButtonBinding(
                remoteProfileID: nil, button: .ok, trigger: .singleClick, configured: copy
            )],
            deviceProfileID: nil
        ))
        settings.setApplicationSchemeOwner(schemeA, applicationProfileID: appA.id)
        #expect(settings.setApplicationMappingProfileID(schemeA, applicationProfileID: appA.id))
        #expect(settings.setApplicationMappingProfileID(schemeA, applicationProfileID: appC.id))

        let model = BridgeAppModel(settings: settings)
        #expect(model.macroFeature.usesHostApplicationSchemes)
        #expect(settings.setApplicationButtonOverride(
            paste,
            applicationProfileID: appA.id,
            button: .ok,
            trigger: .singleClick
        ) == .wrote)

        #expect(settings.hostApplicationSchemes.count == 1)
        #expect(settings.applicationSchemeOwner(schemeA) == appA.id)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeA, device: nil, button: .ok, trigger: .singleClick
        )?.action == .commandPaste)
        #expect(settings.customApplicationProfile(id: appA.id)?.buttonBindings == nil)
        #expect(settings.hostApplicationSchemeBinding(
            mappingProfileID: schemeA, device: nil, button: .down, trigger: .singleClick
        )?.action == .commandCut)
        #expect(settings.applicationProfilesSharingMappingProfile(schemeA) == 2)
        #expect(settings.customMappingEnabled)
        #expect(settings.activeAssignedMappingProfileID(bundleIdentifier: appC.bundleIdentifier) == schemeA)
        #expect(model.macroFeature.isMappingProfileApplicable(schemeA, device: nil))
        #expect(model.macroFeature.assignedApplicationBinding(
            mappingProfileID: schemeA, device: nil, button: .ok, trigger: .singleClick
        )?.action == .commandPaste)
        #expect(settings.customApplicationProfile(id: appC.id)?.mappingProfileID == schemeA)
        #expect(settings.configuredAction(
            for: .ok, trigger: .singleClick, profileID: nil,
            applicationBundleIdentifier: appC.bundleIdentifier
        ).action == .commandPaste)
    }
    @Test func deletingApplicationClearsOwnershipButKeepsScheme() throws {
        let defaults = defaults()
        let settings = AppSettings(defaults: defaults)
        let app = CustomApplicationProfile(
            displayName: "A", bundleIdentifier: "test.a", applicationPath: "/Applications/A.app"
        )
        settings.addCustomApplicationProfile(app)
        let scheme = try #require(settings.createHostApplicationScheme(
            name: "A 方案", bindings: [], deviceProfileID: nil
        ))
        settings.setApplicationSchemeOwner(scheme, applicationProfileID: app.id)
        #expect(settings.applicationSchemeOwner(scheme) == app.id)
        settings.removeCustomApplicationProfile(id: app.id)
        #expect(settings.applicationSchemeOwner(scheme) == nil)
        #expect(settings.hostApplicationSchemeProfiles(device: nil).map(\.id) == [scheme])
    }

    @Test func legacyOwnerReconcilesForSharedSchemeByDefaultName() throws {
        let defaults = defaults()
        let settings = AppSettings(defaults: defaults)
        let appA = CustomApplicationProfile(
            displayName: "A", bundleIdentifier: "test.a", applicationPath: "/Applications/A.app"
        )
        let appB = CustomApplicationProfile(
            displayName: "B", bundleIdentifier: "test.b", applicationPath: "/Applications/B.app"
        )
        settings.addCustomApplicationProfile(appA)
        settings.addCustomApplicationProfile(appB)
        let scheme = try #require(settings.createHostApplicationScheme(
            name: "A 方案", bindings: [], deviceProfileID: nil
        ))
        #expect(settings.setApplicationMappingProfileID(scheme, applicationProfileID: appA.id))
        #expect(settings.setApplicationMappingProfileID(scheme, applicationProfileID: appB.id))
        settings.reconcileHostApplicationSchemeOwners { application in
            "\(application.displayName) 方案"
        }
        #expect(settings.applicationSchemeOwner(scheme) == appA.id)
    }

}
