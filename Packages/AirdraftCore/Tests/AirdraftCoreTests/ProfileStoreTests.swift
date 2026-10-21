import XCTest
@testable import AirdraftCore

@MainActor
final class ProfileStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stt-profiles-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testDefaultsAndActive() {
        let store = ProfileStore(directory: tempDir())
        XCTAssertEqual(store.profiles.map(\.name), ["Clean", "Concise", "Summary", "Verbatim"])
        XCTAssertEqual(store.activeProfile.id, RefinementProfile.cleanID)
        XCTAssertTrue(store.baseRulesAreDefault)
    }

    func testEditPersistsAndResetRestores() {
        let dir = tempDir()
        let store = ProfileStore(directory: dir)
        var concise = store.profiles[1]
        concise.instructions = "Shorter."
        store.update(concise)
        store.setBaseRules("custom base")
        store.setActive(RefinementProfile.summaryID)

        let reloaded = ProfileStore(directory: dir)
        XCTAssertEqual(reloaded.profiles[1].instructions, "Shorter.")
        XCTAssertEqual(reloaded.baseRules, "custom base")
        XCTAssertEqual(reloaded.activeProfileID, RefinementProfile.summaryID)
        XCTAssertFalse(reloaded.isDefault(reloaded.profiles[1]))

        reloaded.resetProfile(id: RefinementProfile.conciseID)
        XCTAssertTrue(reloaded.isDefault(reloaded.profiles[1]))
        reloaded.resetBaseRules()
        XCTAssertTrue(reloaded.baseRulesAreDefault)
    }

    func testUserProfilesCanBeAddedAndRemovedButBuiltInsCannot() {
        let store = ProfileStore(directory: tempDir())
        let custom = store.add(RefinementProfile(name: "Email", instructions: "Write an email."))
        XCTAssertEqual(store.profiles.count, 5)
        XCTAssertFalse(custom.isBuiltIn)
        store.setActive(custom.id)
        store.remove(id: custom.id)
        XCTAssertEqual(store.profiles.count, 4)
        XCTAssertEqual(store.activeProfileID, RefinementProfile.cleanID)
        store.remove(id: RefinementProfile.cleanID)
        XCTAssertEqual(store.profiles.count, 4)
    }

    func testResetAllRemovesUserProfilesAndRestoresDefaults() {
        let store = ProfileStore(directory: tempDir())
        store.add(RefinementProfile(name: "X", instructions: "x"))
        var clean = store.profiles[0]
        clean.name = "Renamed"
        store.update(clean)
        store.resetAll()
        XCTAssertEqual(store.profiles, RefinementProfile.defaults)
        XCTAssertEqual(store.activeProfileID, RefinementProfile.cleanID)
    }

    func testDuplicateUsesSelectedProfileAndPreservesRawBehaviorAfterReload() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        var source = store.profiles[3]
        source.task = "Remembered task"
        source.instructions = "Remembered instructions"
        source.symbol = "doc.text"
        store.update(source)

        let copy = try XCTUnwrap(store.duplicate(id: source.id))
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertFalse(copy.usesLLM)
        XCTAssertEqual(copy.task, source.task)
        XCTAssertEqual(copy.instructions, source.instructions)
        XCTAssertEqual(copy.symbol, source.symbol)
        XCTAssertEqual(copy.name, "Verbatim copy")
        XCTAssertEqual(store.duplicate(id: source.id)?.name, "Verbatim copy 2")
        XCTAssertEqual(store.activeProfileID, RefinementProfile.cleanID)
        XCTAssertEqual(ProfileStore(directory: dir).profiles.first { $0.id == copy.id }, copy)
        XCTAssertNil(store.duplicate(id: UUID()))
    }
}

extension ProfileStoreTests {
    func testLegacyProfilesInheritAppDefaultWithoutLosingEdits() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        var profile = store.activeProfile
        profile.name = "My cleanup"
        profile.instructions = "Keep my wording."
        store.update(profile)
        let url = dir.appendingPathComponent("profiles.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        for index in profiles.indices { profiles[index].removeValue(forKey: "speechModel") }
        json["profiles"] = profiles
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let restored = ProfileStore(directory: dir)
        XCTAssertNil(restored.persistenceError)
        XCTAssertEqual(restored.activeProfile, profile)
        let appDefault = ASRConfig(kind: .senseVoice, language: "zh")
        XCTAssertEqual(restored.activeProfile.speechConfig(default: appDefault), appDefault)
    }

    func testBindingPersistsCopiesAndResetsWithoutChangingDefault() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        let appDefault = ASRConfig(kind: .parakeet)
        var profile = store.activeProfile
        profile.speechModel = ProfileSpeechModel(config: ASRConfig(kind: .qwen3, qwen3Model: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"))
        store.update(profile)
        XCTAssertEqual(ProfileStore(directory: dir).activeProfile.speechModel, profile.speechModel)
        XCTAssertEqual(store.duplicate(id: profile.id)?.speechModel, profile.speechModel)
        XCTAssertEqual(store.addNew().speechModel, profile.speechModel)
        XCTAssertEqual(store.activeProfile.speechConfig(default: appDefault).kind, .qwen3)
        store.setActive(RefinementProfile.verbatimID)
        XCTAssertEqual(store.activeProfile.speechConfig(default: appDefault), appDefault)
        store.setActive(profile.id)
        profile.speechModel = nil
        store.update(profile)
        XCTAssertEqual(ProfileStore(directory: dir).activeProfile.speechConfig(default: appDefault), appDefault)
        profile.speechModel = ProfileSpeechModel(config: ASRConfig(kind: .apple))
        store.update(profile)
        store.resetProfile(id: profile.id)
        XCTAssertNil(store.activeProfile.speechModel)
        XCTAssertTrue(store.isDefault(store.activeProfile))
    }

    func testBindingChangesOnlyModelAndProviderNotLanguageOrScript() {
        let binding = ProfileSpeechModel(config: ASRConfig(kind: .qwen3, qwen3Model: "profile-model", language: "en", chineseScript: .simplified))
        let appDefault = ASRConfig(kind: .parakeet, language: "zh", chineseScript: .traditional)
        let effective = binding.applying(to: appDefault)
        XCTAssertEqual(effective.kind, .qwen3)
        XCTAssertEqual(effective.qwen3Model, "profile-model")
        XCTAssertEqual(effective.language, "zh")
        XCTAssertEqual(effective.chineseScript, .traditional)
        XCTAssertEqual(appDefault.kind, .parakeet)
    }

    func testCloudBindingUsesItsProviderEndpointAndSharedCredentialReference() {
        var cloud = ASRConfig()
        cloud.select(.groq)
        let binding = ProfileSpeechModel(config: cloud)
        let effective = binding.applying(to: ASRConfig(kind: .parakeet, baseURL: "http://localhost:1234/v1", apiKeyRef: "custom"))
        XCTAssertEqual(effective.kind, .groq)
        XCTAssertEqual(effective.baseURL, cloud.baseURL)
        XCTAssertEqual(effective.keyRef, cloud.keyRef)
        XCTAssertEqual(effective.speechModelID, cloud.speechModelID)
        XCTAssertNil(binding.unavailableReason)
        XCTAssertNil(binding.apiKeyRef)
    }

    func testCustomServerBindingRetainsEndpointWithoutCopyingCredentials() throws {
        let source = ASRConfig(kind: .openAICompatible, baseURL: "http://localhost:9000/v1", model: "local-speech", apiKeyRef: "asr.my-server")
        let binding = ProfileSpeechModel(config: source)
        let restored = try JSONDecoder().decode(ProfileSpeechModel.self, from: JSONEncoder().encode(binding))
        let effective = restored.applying(to: ASRConfig(kind: .apple, language: "en"))
        XCTAssertEqual(effective.baseURL, source.baseURL)
        XCTAssertEqual(effective.model, source.model)
        XCTAssertEqual(effective.keyRef, source.keyRef)
        XCTAssertEqual(effective.language, "en")
    }

    func testRetiredCloudBindingIsReportedRatherThanReplaced() {
        let binding = ProfileSpeechModel(config: ASRConfig(kind: .groq, model: "retired-speech-model"))
        XCTAssertNotNil(binding.unavailableReason)
        let openRouter = ProfileSpeechModel(config: ASRConfig(kind: .openRouter, model: "custom/new-speech"))
        XCTAssertNil(openRouter.unavailableReason)
        XCTAssertEqual(openRouter.applying(to: ASRConfig()).speechModelID, "custom/new-speech")
    }

    /// Built-in names are shown through the catalog until renamed; stored names, ids,
    /// prompts and history keep the English name.
    func testBuiltInDisplayNamesFollowTheCatalogUntilRenamed() {
        let dir = tempDir()
        let store = ProfileStore(directory: dir)
        let localized = ["Clean": String(localized: "Clean", bundle: .module), "Concise": String(localized: "Concise", bundle: .module),
                         "Summary": String(localized: "Summary", bundle: .module), "Verbatim": String(localized: "Verbatim", bundle: .module)]
        for profile in store.profiles {
            XCTAssertEqual(profile.displayName, localized[profile.name], profile.name)
            XCTAssertEqual(RefinementProfile.displayName(forSavedName: profile.name), localized[profile.name])
        }

        var clean = store.activeProfile
        clean.name = "My clean"
        store.update(clean)
        let reloaded = ProfileStore(directory: dir)
        XCTAssertEqual(reloaded.activeProfile.name, "My clean")
        XCTAssertEqual(reloaded.activeProfile.displayName, "My clean", "A renamed built-in keeps the user's name")
        XCTAssertEqual(reloaded.profiles[1].name, "Concise", "Display mapping never rewrites stored names")

        reloaded.resetProfile(id: RefinementProfile.cleanID)
        XCTAssertEqual(reloaded.activeProfile.displayName, localized["Clean"])

        // A user profile that happens to share a built-in name is shown as typed.
        let custom = RefinementProfile(name: "Clean", instructions: "x")
        XCTAssertEqual(custom.displayName, "Clean")
        XCTAssertEqual(RefinementProfile.displayName(forSavedName: "Notes"), "Notes")

        // Prompts keep the stored English name.
        let request = RefineRequest(transcript: "hi", profile: reloaded.profiles[1], baseRules: reloaded.baseRules,
                                    context: .empty, family: .general, dictionary: [])
        XCTAssertTrue(PromptBuilder.systemPrompt(for: request).contains("PROFILE Concise"))
    }

    /// AD-079: in Traditional Chinese, a built-in can be renamed to its English stored
    /// name and keeps showing it, and no other profile can take a name that one
    /// already shows or stores.
    func testTypedNamesShowAsTypedAndNeverDuplicateAnotherProfile() throws {
        let zh: (UUID) -> String? = {
            [RefinementProfile.cleanID: "整理", RefinementProfile.conciseID: "精簡",
             RefinementProfile.summaryID: "摘要", RefinementProfile.verbatimID: "逐字"][$0]
        }
        let dir = tempDir()
        let store = ProfileStore(directory: dir)
        XCTAssertEqual(store.activeProfile.displayName(localizingBuiltIn: zh), "整理")
        XCTAssertEqual(store.rename(id: RefinementProfile.cleanID, to: "整理", localizingBuiltIn: zh), .unchanged)
        XCTAssertEqual(store.rename(id: RefinementProfile.cleanID, to: "  Clean ", localizingBuiltIn: zh), .renamed)
        XCTAssertEqual(store.activeProfile.name, "Clean", "Prompts and history keep the same stored name")
        XCTAssertEqual(store.activeProfile.displayName(localizingBuiltIn: zh), "Clean", "An explicit name shows as typed")

        let reloaded = ProfileStore(directory: dir)
        XCTAssertTrue(reloaded.activeProfile.nameIsCustom)
        XCTAssertEqual(reloaded.activeProfile.displayName(localizingBuiltIn: zh), "Clean")
        XCTAssertFalse(reloaded.isDefault(reloaded.activeProfile), "Restore Defaults brings the localized name back")

        let custom = reloaded.add(RefinementProfile(name: "Notes", instructions: "x"))
        XCTAssertEqual(reloaded.rename(id: custom.id, to: "精簡", localizingBuiltIn: zh), .duplicate("精簡"),
                       "A custom profile may not look like the built-in Concise")
        XCTAssertEqual(reloaded.rename(id: custom.id, to: "concise", localizingBuiltIn: zh), .duplicate("精簡"),
                       "Nor take its stored name, which English shows")
        XCTAssertEqual(reloaded.rename(id: custom.id, to: "CLEAN", localizingBuiltIn: zh), .duplicate("Clean"))
        XCTAssertEqual(reloaded.rename(id: custom.id, to: "整理", localizingBuiltIn: zh), .renamed,
                       "整理 is free once the built-in shows Clean")
        XCTAssertEqual(reloaded.rename(id: custom.id, to: "   ", localizingBuiltIn: zh), .empty)
        XCTAssertEqual(reloaded.profiles.first { $0.id == custom.id }?.name, "整理")

        reloaded.resetProfile(id: RefinementProfile.cleanID)
        XCTAssertFalse(reloaded.activeProfile.nameIsCustom)
        XCTAssertEqual(reloaded.activeProfile.displayName(localizingBuiltIn: zh), "整理")

        // Files written before the flag existed decode with it off.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RefinementProfile.defaults[0])) as! [String: Any]
        legacy.removeValue(forKey: "nameIsCustom")
        let decoded = try JSONDecoder().decode(RefinementProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, RefinementProfile.defaults[0])
    }
}
