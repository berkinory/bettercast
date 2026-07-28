import Foundation

extension Bundle {
    /// The app's channel-aware display name ("Bettercast", "Bettercast Dev", "Bettercast Beta"), driven by CFBundleDisplayName/CFBundleName in the generated Info.plist.
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Bettercast"
    }
}
