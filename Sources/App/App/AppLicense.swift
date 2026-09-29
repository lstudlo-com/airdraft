import AirdraftCore
import Foundation

@MainActor enum AppLicense {
    static func make(bundle: Bundle = .main, isolated: Bool = false) -> LicenseStore {
        let info = bundle.infoDictionary ?? [:]
        let channel = info["AirdraftDistribution"] as? String ?? "community"
        // An unknown channel is a broken official build, never a free fallback.
        let distribution: LicenseStore.Distribution = isolated || channel == "community" ? .community : .official
        // Never choose the environment from a launch argument or an editable
        // preference. Debug cannot contact production; Release cannot use test keys.
        #if DEBUG
        let environment = PolarEnvironment.sandbox
        #else
        let environment = PolarEnvironment.production
        #endif
        let config = PolarConfiguration.from(info: info, environment: environment)
        return LicenseStore(distribution: distribution, configuration: config,
            storage: KeychainLicenseStorage(bundleID: bundle.bundleIdentifier ?? AppIdentity.bundleID,
                                            environment: environment))
    }
}
