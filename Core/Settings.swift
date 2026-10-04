import Foundation
import Security

enum NavigationMapApp: String, CaseIterable {
    case system, amap, google
    var label: String { switch self { case .system: "系统地图"; case .amap: "高德地图"; case .google: "Google 地图" } }
}

@MainActor final class Settings: ObservableObject {
    @Published private(set) var baseURL: String
    @Published private(set) var token: String
    var amapKey: String { AppConfiguration.amapKey }
    @Published private(set) var privacyAccepted: Bool
    @Published var planning: Bool { didSet { UserDefaults.standard.set(planning, forKey: "planning") } }
    @Published var mode: TravelMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "travelMode") } }
    @Published var navigationMapApp: NavigationMapApp {
        didSet { UserDefaults.standard.set(navigationMapApp.rawValue, forKey: "navigationMapApp") }
    }
    @Published var mapRenderer: MapRendererKind { didSet { UserDefaults.standard.set(mapRenderer.rawValue, forKey: "mapRenderer") } }
    @Published var hideAIChatIcon: Bool { didSet { UserDefaults.standard.set(hideAIChatIcon, forKey: "hideAIChatIcon") } }
    @Published var revision = UUID()
    var configured: Bool { !baseURL.isEmpty }
    init() {
        let renderer = MapRendererKind(rawValue: UserDefaults.standard.string(forKey: "mapRenderer") ?? "apple") ?? .apple
        mapRenderer = renderer
        hideAIChatIcon = UserDefaults.standard.bool(forKey: "hideAIChatIcon")
        navigationMapApp = NavigationMapApp(rawValue: UserDefaults.standard.string(forKey: "navigationMapApp") ?? "system") ?? .system
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""
        token = Keychain.read("api-token")
        privacyAccepted = UserDefaults.standard.bool(forKey: "amapPrivacy")
        planning = UserDefaults.standard.bool(forKey: "planning")
        mode = TravelMode(rawValue: UserDefaults.standard.string(forKey: "travelMode") ?? "walking") ?? .walking
    }
    func save(url: String, token: String) throws {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : try Self.normalizedURL(url)
        try Keychain.write(token.trimmingCharacters(in: .whitespacesAndNewlines), key: "api-token")
        baseURL = normalized; self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(baseURL, forKey: "baseURL"); revision = UUID()
    }
    static func normalizedURL(_ url: String) throws -> String {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parsed = URLComponents(string: cleaned), ["https", "http"].contains(parsed.scheme ?? ""),
              parsed.host != nil, parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else {
            throw AppError.message("请输入完整服务地址，例如 https://map.example.com；不包含 /api、token 或查询参数")
        }
        return cleaned.hasSuffix("/api") ? String(cleaned.dropLast(4)) : cleaned

    }
    func setPrivacyAccepted(_ accepted: Bool) {
        privacyAccepted = accepted; UserDefaults.standard.set(accepted, forKey: "amapPrivacy"); revision = UUID()
    }
}
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MapAnNai", kSecAttrAccount as String: key]
    }
    static func read(_ key: String) -> String {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ value: String, key: String) throws {
        let q = query(key)
        if value.isEmpty { SecItemDelete(q as CFDictionary); return }
        let update = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q; insert[kSecValueData as String] = Data(value.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.message("无法保存凭据到系统钥匙串（\(status)）") }
    }
}
