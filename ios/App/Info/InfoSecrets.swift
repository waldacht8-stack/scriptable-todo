import Foundation
import Security

/// API キーなどの秘密の値を、端末の Keychain にだけ保存する（ファイル・ログ・バックアップには出さない）
/// 使う側：Steam の Web API キー（SteamStore）、相談の Gemini API キー（ConsultStore）
enum InfoSecrets {
    private static let service = "com.todoapp.TodoApp.secrets"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// 空や nil を渡すと消す
    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func has(_ key: String) -> Bool { get(key) != nil }
}
