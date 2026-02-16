// SecretsManager.swift
// API 키와 Client ID 등 민감한 정보를 안전하게 관리합니다.
// Secrets.plist 파일에서 값을 읽어옵니다.
//
// ⚠️ 중요: Secrets.plist 파일은 .gitignore에 추가하여
// Git 저장소에 커밋되지 않도록 하세요!

import Foundation

// ============================================================
// MARK: - Secrets Manager
// ============================================================

class SecretsManager {

    // Singleton 패턴
    static let shared = SecretsManager()

    // 캐시된 secrets 딕셔너리
    private var secrets: [String: Any] = [:]

    private init() {
        loadSecrets()
    }

    // --------------------------------------------------------
    // MARK: - Secrets 로드
    // --------------------------------------------------------

    private func loadSecrets() {
        // Secrets.plist 파일 경로 찾기
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            #if DEBUG
            print("⚠️ Secrets.plist 파일을 찾을 수 없습니다.")
            print("📝 Secrets.plist.template을 복사하여 Secrets.plist를 만들고 실제 값을 입력하세요.")
            #endif
            return
        }

        secrets = dict
    }

    // --------------------------------------------------------
    // MARK: - API Keys
    // --------------------------------------------------------

    /// Gemini API 키
    var geminiAPIKey: String {
        guard let key = secrets["GEMINI_API_KEY"] as? String, !key.isEmpty else {
            #if DEBUG
            print("❌ GEMINI_API_KEY가 Secrets.plist에 설정되지 않았습니다.")
            #endif
            return ""
        }
        return key
    }

    /// Google OAuth Client ID
    var googleClientID: String {
        guard let id = secrets["GOOGLE_CLIENT_ID"] as? String, !id.isEmpty else {
            #if DEBUG
            print("❌ GOOGLE_CLIENT_ID가 Secrets.plist에 설정되지 않았습니다.")
            #endif
            return ""
        }
        return id
    }

    /// Google OAuth Redirect URI
    var googleRedirectURI: String {
        guard let uri = secrets["GOOGLE_REDIRECT_URI"] as? String, !uri.isEmpty else {
            // Client ID에서 자동 생성
            let clientIDPrefix = googleClientID.components(separatedBy: ".").first ?? ""
            return "com.googleusercontent.apps.\(clientIDPrefix):/oauth2redirect"
        }
        return uri
    }

    // --------------------------------------------------------
    // MARK: - 유효성 검사
    // --------------------------------------------------------

    /// 모든 필수 시크릿이 설정되어 있는지 확인
    var isConfigured: Bool {
        return secrets["GEMINI_API_KEY"] != nil &&
               secrets["GOOGLE_CLIENT_ID"] != nil
    }
}
