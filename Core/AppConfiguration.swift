import Foundation

// Client SDK credentials identify this app. They are intentionally bundled and not user-entered secrets.
enum AppConfiguration {
    static var amapKey: String { amapKey(in: Bundle.main.infoDictionary ?? [:]) }
    static func amapKey(in values: [String: Any]) -> String {
        let value = (values["AMapIOSKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value
    }
}
