import AirdraftCore
import Foundation

@MainActor enum AppLicense {
    static func make(bundle: Bundle = .main, isolated: Bool = false) -> LicenseStore {
        let info = bundle.infoDictionary ?? [:]
        let channel = info["AirdraftDistribution"] as? String ?? "community"
        // An unknown channel is a broken official build, never a free fallback.
        let distribution: LicenseStore.Distribution = isolated || channel == "community" ? .community : .official
        let config: PolarConfiguration?
        if let org = (info["AirdraftPolarOrganization"] as? String).flatMap(UUID.init(uuidString:)),
           let benefit = (info["AirdraftPolarBenefit"] as? String).flatMap(UUID.init(uuidString:)),
           let checkout = (info["AirdraftCheckoutURL"] as? String).flatMap(PolarConfiguration.parseCheckoutURL),
           let portal = (info["AirdraftCustomerPortalURL"] as? String).flatMap(PolarConfiguration.parsePortalURL),
           let days = (info["AirdraftTrialDays"] as? String).flatMap(Int.init), (1...90).contains(days) {
            config = PolarConfiguration(organizationID: org, benefitID: benefit, checkoutURL: checkout, portalURL: portal, trialDays: days)
        } else { config = nil }
        return LicenseStore(distribution: distribution, configuration: config,
            storage: KeychainLicenseStorage(bundleID: bundle.bundleIdentifier ?? AppIdentity.bundleID))
    }
}
