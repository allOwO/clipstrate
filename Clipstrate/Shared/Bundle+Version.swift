import Foundation

extension Bundle {
    /// `CFBundleShortVersionString`（如 "0.1"）；缺省回退 "0"。
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// `CFBundleVersion`（构建号，如 "1"）；缺省回退 "0"。
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
