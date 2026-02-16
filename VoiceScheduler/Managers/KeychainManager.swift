// KeychainManager.swift
// iOS Keychain을 사용하여 민감한 데이터를 안전하게 저장합니다.
// UserDefaults보다 훨씬 안전한 저장 방식입니다.

import Foundation
import Security

// ============================================================
// MARK: - Keychain Manager
// ============================================================

class KeychainManager {

    // Singleton 패턴
    static let shared = KeychainManager()
    private init() {}

    // 서비스 식별자 (앱 번들 ID 사용)
    private let service = Bundle.main.bundleIdentifier ?? "com.voicescheduler"

    // --------------------------------------------------------
    // MARK: - 저장 (Save)
    // --------------------------------------------------------

    /// Keychain에 문자열 값을 저장합니다
    /// - Parameters:
    ///   - value: 저장할 문자열
    ///   - key: 키 이름
    /// - Returns: 저장 성공 여부
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // 기존 항목 삭제 (업데이트를 위해)
        delete(forKey: key)

        // Keychain 쿼리 구성
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Keychain에 저장
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            #if DEBUG
            print("⚠️ Keychain 저장 실패: \(key), status: \(status)")
            #endif
        }

        return status == errSecSuccess
    }

    // --------------------------------------------------------
    // MARK: - 읽기 (Read)
    // --------------------------------------------------------

    /// Keychain에서 문자열 값을 읽어옵니다
    /// - Parameter key: 키 이름
    /// - Returns: 저장된 문자열 (없으면 nil)
    func read(forKey key: String) -> String? {
        // Keychain 쿼리 구성
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Keychain에서 검색
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    // --------------------------------------------------------
    // MARK: - 삭제 (Delete)
    // --------------------------------------------------------

    /// Keychain에서 값을 삭제합니다
    /// - Parameter key: 키 이름
    /// - Returns: 삭제 성공 여부
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // --------------------------------------------------------
    // MARK: - 모두 삭제 (Delete All)
    // --------------------------------------------------------

    /// 이 앱의 모든 Keychain 항목을 삭제합니다
    func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// ============================================================
// MARK: - Keychain Keys
// ============================================================

extension KeychainManager {
    /// Keychain에서 사용하는 키 이름들
    enum Keys {
        static let accessToken = "google_access_token"
        static let refreshToken = "google_refresh_token"
    }
}
