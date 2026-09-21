import XCTest
@testable import AirdraftCore

final class EngineFactoryTests: XCTestCase {
    /// The UI looks up load state by `ASRConfig.engineID`; it must match the id
    /// of the transcriber the factory actually builds.
    @MainActor
    func testEngineIDMatchesTranscriberID() async {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil })
        for kind in ASRProviderKind.allCases {
            let config = ASRConfig(kind: kind)
            let engine = await factory.transcriber(for: config)
            XCTAssertEqual(engine.id, config.engineID, "\(kind)")
        }
    }

    @MainActor
    func testLocalEnginesAreCachedPerModel() async {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil })
        let a = await factory.transcriber(for: ASRConfig(kind: .qwen3, qwen3Model: "org/a"))
        let a2 = await factory.transcriber(for: ASRConfig(kind: .qwen3, qwen3Model: "org/a"))
        let b = await factory.transcriber(for: ASRConfig(kind: .qwen3, qwen3Model: "org/b"))
        XCTAssertTrue((a as AnyObject) === (a2 as AnyObject))
        XCTAssertFalse((a as AnyObject) === (b as AnyObject))
    }
}
