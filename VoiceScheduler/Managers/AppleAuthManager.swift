// AppleAuthManager.swift
// Sign in with Apple 인증을 처리하는 매니저입니다.
// App Store 가이드라인 4.8 준수를 위해 Google 로그인 대안으로 제공됩니다.

import Foundation
import AuthenticationServices

// ============================================================
// MARK: - Apple 인증 매니저
// ============================================================

class AppleAuthManager: NSObject, ObservableObject {

    // Singleton
    static let shared = AppleAuthManager()

    // Apple 로그인 완료 시 호출되는 콜백
    var onSignInComplete: ((String, String, String?) -> Void)?

    // --------------------------------------------------------
    // MARK: - Apple 로그인 시작
    // --------------------------------------------------------

    /// Sign in with Apple 요청을 시작합니다
    func signIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // --------------------------------------------------------
    // MARK: - 인증 상태 확인
    // --------------------------------------------------------

    /// 저장된 Apple 사용자 ID의 인증 상태를 확인합니다
    func checkCredentialState(userID: String, completion: @escaping (Bool) -> Void) {
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { state, _ in
            DispatchQueue.main.async {
                completion(state == .authorized)
            }
        }
    }
}

// ============================================================
// MARK: - ASAuthorizationControllerDelegate
// ============================================================

extension AppleAuthManager: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        let userID = credential.user

        // Apple은 최초 로그인 시에만 이름과 이메일을 제공합니다
        // 이후 로그인에서는 nil이므로 저장해두어야 합니다
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        let email = credential.email

        // 사용자 정보 저장 (최초 로그인 시)
        if !fullName.isEmpty {
            KeychainManager.shared.save(fullName, forKey: KeychainManager.Keys.appleUserName)
        }
        if let email = email {
            KeychainManager.shared.save(email, forKey: KeychainManager.Keys.appleUserEmail)
        }
        KeychainManager.shared.save(userID, forKey: KeychainManager.Keys.appleUserID)

        // 저장된 정보 불러오기 (최초가 아닌 경우를 위해)
        let savedName = fullName.isEmpty
            ? (KeychainManager.shared.read(forKey: KeychainManager.Keys.appleUserName) ?? "Apple User")
            : fullName
        let savedEmail = email
            ?? KeychainManager.shared.read(forKey: KeychainManager.Keys.appleUserEmail)
            ?? "\(userID.prefix(8))@privaterelay.appleid.com"

        onSignInComplete?(userID, savedName, savedEmail)
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        #if DEBUG
        print("❌ Apple Sign In 실패: \(error.localizedDescription)")
        #endif
    }
}
