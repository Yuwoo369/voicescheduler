// GoogleAuthManager.swift
// 구글 로그인(OAuth 2.0)을 관리하는 핵심 파일입니다.
// OAuth 2.0이란? 사용자가 비밀번호를 직접 입력하지 않고도
// 구글 계정으로 안전하게 로그인할 수 있게 해주는 표준 방식입니다.

import Foundation
import SwiftUI

// Combine: 데이터의 변화를 실시간으로 감지하고 전달하는 애플의 프레임워크입니다
import Combine

// ============================================================
// MARK: - 구글 인증 관리자 클래스
// ============================================================

// ObservableObject: 이 클래스의 데이터가 변경되면 화면이 자동으로 업데이트됩니다
// 예: 로그인 상태가 바뀌면 화면도 자동으로 바뀝니다
class GoogleAuthManager: ObservableObject {

    // --------------------------------------------------------
    // MARK: - 저장되는 데이터들 (Published = 변경 시 화면 자동 업데이트)
    // --------------------------------------------------------

    // @Published: 이 값이 바뀌면 이 값을 사용하는 모든 화면이 자동으로 새로고침됩니다
    // isSignedIn: 로그인 되어있는지 여부 (true = 로그인됨, false = 로그인 안됨)
    @Published var isSignedIn: Bool = false

    // 데모 모드 여부 (Google 로그인 없이 앱 체험)
    @Published var isDemoMode: Bool = false

    // Apple 로그인 모드 여부
    @Published var isAppleSignIn: Bool = false

    // 로그인한 사용자의 이메일 주소
    @Published var userEmail: String = ""

    // 로그인한 사용자의 이름
    @Published var userName: String = ""

    // 로그인한 사용자의 프로필 사진 URL
    @Published var userProfileImageURL: URL?

    // 에러 메시지 (로그인 실패 시 사용자에게 보여줄 메시지)
    @Published var errorMessage: String?

    // 로딩 중인지 여부 (로그인 버튼 누른 후 처리 중일 때 true)
    @Published var isLoading: Bool = false

    // --------------------------------------------------------
    // MARK: - 구글 API 접근을 위한 토큰들
    // --------------------------------------------------------

    // Access Token: 구글 API(캘린더 등)에 접근할 때 사용하는 "출입증" 같은 것
    // 유효기간이 짧아서 (보통 1시간) 자주 갱신해야 합니다
    private var accessToken: String?

    // Refresh Token: Access Token이 만료되었을 때 새로 발급받기 위한 토큰
    // 유효기간이 길어서 오래 보관할 수 있습니다
    private var refreshToken: String?

    // --------------------------------------------------------
    // MARK: - 구글 OAuth 설정값들 (SecretsManager에서 안전하게 로드)
    // --------------------------------------------------------

    // Client ID: 구글이 우리 앱을 식별하는 고유 번호
    private var clientID: String {
        return SecretsManager.shared.googleClientID
    }

    // Redirect URI: 로그인 완료 후 돌아올 주소 (앱의 URL Scheme)
    private var redirectURI: String {
        return SecretsManager.shared.googleRedirectURI
    }

    // Scope: 우리 앱이 접근하고 싶은 구글 서비스 목록
    // - userinfo.email: 사용자 이메일 읽기
    // - userinfo.profile: 사용자 이름, 프로필 사진 읽기
    // - calendar.events: 캘린더 이벤트 생성/조회/삭제 (캘린더 자체 관리 권한 없음, 최소 권한)
    private let scopes = [
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/calendar.events"
    ]

    // --------------------------------------------------------
    // MARK: - 초기화 함수
    // --------------------------------------------------------

    init() {
        // 앱이 시작될 때 이전에 저장된 로그인 정보가 있는지 확인합니다
        loadSavedTokens()

        // Google 토큰이 없으면 Apple 로그인 복원 시도
        if accessToken == nil {
            restoreAppleSignIn()
        }
    }

    // --------------------------------------------------------
    // MARK: - 데모 모드
    // --------------------------------------------------------

    /// 데모 모드 진입 (Google 로그인 없이 앱 체험)
    func enterDemoMode() {
        isDemoMode = true
        isSignedIn = true
        userName = "Demo User"
        userEmail = "demo@voicescheduler.app"
        userProfileImageURL = nil
    }

    // --------------------------------------------------------
    // MARK: - Apple 로그인
    // --------------------------------------------------------

    /// Sign in with Apple을 시작합니다
    func signInWithApple() {
        isLoading = true
        errorMessage = nil

        let appleAuth = AppleAuthManager.shared
        appleAuth.onSignInComplete = { [weak self] userID, name, email in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.isAppleSignIn = true
                self?.userName = name
                self?.userEmail = email ?? "private@appleid.com"
                self?.userProfileImageURL = nil
                self?.isSignedIn = true

                #if DEBUG
                print("✅ Apple Sign In 완료: \(name), \(email ?? "no email")")
                #endif
            }
        }
        appleAuth.signIn()
    }

    /// 저장된 Apple 로그인 상태를 복원합니다
    private func restoreAppleSignIn() {
        guard let userID = KeychainManager.shared.read(forKey: KeychainManager.Keys.appleUserID) else {
            return
        }

        AppleAuthManager.shared.checkCredentialState(userID: userID) { [weak self] authorized in
            if authorized {
                self?.isAppleSignIn = true
                self?.userName = KeychainManager.shared.read(forKey: KeychainManager.Keys.appleUserName) ?? "Apple User"
                self?.userEmail = KeychainManager.shared.read(forKey: KeychainManager.Keys.appleUserEmail) ?? "private@appleid.com"
                self?.isSignedIn = true
            }
        }
    }

    // --------------------------------------------------------
    // MARK: - 구글 로그인 시작하기
    // --------------------------------------------------------

    /// 구글 로그인을 시작하는 함수입니다
    /// 이 함수를 호출하면 구글 로그인 웹페이지가 열립니다
    func signIn() {
        // 로딩 상태 시작 (화면에 로딩 표시를 보여주기 위함)
        isLoading = true
        errorMessage = nil

        // OAuth 2.0 인증 URL 만들기
        // 이 URL을 열면 구글 로그인 페이지가 나타납니다
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            errorMessage = "로그인 URL을 만들 수 없습니다"
            isLoading = false
            return
        }

        // URL에 필요한 정보들을 추가합니다 (쿼리 파라미터)
        components.queryItems = [
            // client_id: 우리 앱의 ID
            URLQueryItem(name: "client_id", value: clientID),
            // redirect_uri: 로그인 후 돌아올 주소
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            // response_type: 우리가 받고 싶은 것 (code = 인증 코드)
            URLQueryItem(name: "response_type", value: "code"),
            // scope: 접근하고 싶은 권한들 (공백으로 구분)
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            // access_type: offline으로 하면 refresh_token도 받을 수 있음
            URLQueryItem(name: "access_type", value: "offline"),
            // prompt: consent로 하면 매번 권한 동의 화면을 보여줌
            URLQueryItem(name: "prompt", value: "consent")
        ]

        // URL이 제대로 만들어졌는지 확인
        guard let url = components.url else {
            errorMessage = "로그인 URL을 만들 수 없습니다"
            isLoading = false
            return
        }

        // 사파리 브라우저에서 구글 로그인 페이지 열기
        // UIApplication.shared.open: iOS에서 URL을 여는 표준 방법
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    // --------------------------------------------------------
    // MARK: - 로그인 완료 처리 (콜백 URL 처리)
    // --------------------------------------------------------

    /// 구글 로그인이 완료되고 앱으로 돌아왔을 때 호출되는 함수
    /// - Parameter url: 구글이 보내준 콜백 URL (인증 코드가 포함되어 있음)
    func handleCallback(url: URL) {
        // URL에서 인증 코드 추출하기
        // 예: com.app:/oauth2redirect?code=ABC123 → "ABC123" 추출
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            errorMessage = "인증 코드를 받지 못했습니다"
            isLoading = false
            return
        }

        // 인증 코드를 Access Token으로 교환하기
        exchangeCodeForTokens(code: code)
    }

    // --------------------------------------------------------
    // MARK: - 인증 코드 → Access Token 교환
    // --------------------------------------------------------

    /// 인증 코드를 Access Token으로 교환하는 함수
    /// Access Token이 있어야 구글 API를 사용할 수 있습니다
    private func exchangeCodeForTokens(code: String) {
        // 토큰 교환 요청을 보낼 URL
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            errorMessage = "토큰 교환 URL을 만들 수 없습니다"
            isLoading = false
            return
        }

        // HTTP 요청 만들기
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST" // POST 방식으로 요청
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // 요청에 포함할 데이터
        let bodyParams = [
            "code": code,                      // 구글에서 받은 인증 코드
            "client_id": clientID,             // 우리 앱의 ID
            "redirect_uri": redirectURI,       // 콜백 주소
            "grant_type": "authorization_code" // 인증 코드를 토큰으로 교환한다는 의미
        ]

        // 데이터를 URL 인코딩 형식으로 변환
        // 예: "code=ABC&client_id=XYZ" 형태로 만듦
        let bodyString = bodyParams.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        // 네트워크 요청 보내기
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // 메인 스레드에서 UI 업데이트 (iOS 규칙)
            DispatchQueue.main.async {
                self?.isLoading = false

                // 에러 체크
                if let error = error {
                    self?.errorMessage = "토큰 교환 실패: \(error.localizedDescription)"
                    return
                }

                // 응답 데이터 파싱
                guard let data = data else {
                    self?.errorMessage = "토큰 응답 데이터가 없습니다"
                    return
                }

                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Token exchange response: \(responseString)")
                }
                #endif

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self?.errorMessage = "토큰 응답을 파싱할 수 없습니다"
                    return
                }

                // Google에서 에러를 반환한 경우
                if let errorDesc = json["error_description"] as? String {
                    self?.errorMessage = "토큰 교환 실패: \(errorDesc)"
                    return
                }

                guard let accessToken = json["access_token"] as? String else {
                    self?.errorMessage = "토큰 응답에 access_token이 없습니다"
                    return
                }

                // 토큰 저장
                self?.accessToken = accessToken
                self?.refreshToken = json["refresh_token"] as? String

                // 안전한 저장소에 토큰 저장 (앱을 껐다 켜도 유지되도록)
                self?.saveTokens()

                // 사용자 정보 가져오기
                self?.fetchUserInfo()
            }
        }.resume() // 네트워크 요청 실행
    }

    // --------------------------------------------------------
    // MARK: - 사용자 정보 가져오기
    // --------------------------------------------------------

    /// 로그인한 사용자의 정보(이름, 이메일, 프로필 사진)를 가져오는 함수
    private func fetchUserInfo() {
        guard let accessToken = accessToken else { return }

        // 구글 사용자 정보 API
        guard let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return }

        var request = URLRequest(url: userInfoURL)
        // Authorization 헤더: API 요청 시 "나 로그인했어요" 증명서
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                // HTTP 상태 코드 확인 - 401이면 토큰 만료
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 401 {
                    #if DEBUG
                    print("⏰ fetchUserInfo: Access Token 만료됨, 갱신 시도...")
                    #endif
                    self?.refreshAccessToken { newToken in
                        if newToken != nil {
                            // 갱신 성공 → 새 토큰으로 다시 사용자 정보 가져오기
                            self?.fetchUserInfo()
                        } else {
                            // 갱신 실패 → 재로그인 필요
                            self?.isSignedIn = false
                            self?.errorMessage = "로그인이 만료되었습니다. 다시 로그인해 주세요."
                        }
                    }
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let email = json["email"] as? String else {
                    self?.errorMessage = "사용자 정보를 가져올 수 없습니다"
                    return
                }

                // 사용자 정보 저장
                self?.userEmail = email
                self?.userName = json["name"] as? String ?? ""

                if let pictureURLString = json["picture"] as? String {
                    self?.userProfileImageURL = URL(string: pictureURLString)
                }

                // 로그인 완료!
                self?.isSignedIn = true
            }
        }.resume()
    }

    // --------------------------------------------------------
    // MARK: - 로그아웃
    // --------------------------------------------------------

    /// 로그아웃 함수 - 저장된 모든 정보를 삭제합니다
    func signOut() {
        // 모든 상태 초기화
        isDemoMode = false
        isAppleSignIn = false
        isSignedIn = false
        userEmail = ""
        userName = ""
        userProfileImageURL = nil
        accessToken = nil
        refreshToken = nil

        // Keychain에서 토큰 삭제
        KeychainManager.shared.delete(forKey: KeychainManager.Keys.accessToken)
        KeychainManager.shared.delete(forKey: KeychainManager.Keys.refreshToken)
        KeychainManager.shared.delete(forKey: KeychainManager.Keys.appleUserID)
        KeychainManager.shared.delete(forKey: KeychainManager.Keys.appleUserName)
        KeychainManager.shared.delete(forKey: KeychainManager.Keys.appleUserEmail)
    }

    // --------------------------------------------------------
    // MARK: - 토큰 저장/불러오기 (Keychain 사용)
    // --------------------------------------------------------

    /// 토큰을 Keychain에 안전하게 저장하는 함수
    private func saveTokens() {
        if let token = accessToken {
            KeychainManager.shared.save(token, forKey: KeychainManager.Keys.accessToken)
        }
        if let token = refreshToken {
            KeychainManager.shared.save(token, forKey: KeychainManager.Keys.refreshToken)
        }
    }

    /// Keychain에서 저장된 토큰을 불러오는 함수
    private func loadSavedTokens() {
        accessToken = KeychainManager.shared.read(forKey: KeychainManager.Keys.accessToken)
        refreshToken = KeychainManager.shared.read(forKey: KeychainManager.Keys.refreshToken)

        // 토큰이 있으면 사용자 정보를 다시 가져옵니다
        if accessToken != nil {
            fetchUserInfo()
        }
    }

    // --------------------------------------------------------
    // MARK: - Access Token 가져오기 (외부에서 사용)
    // --------------------------------------------------------

    /// 다른 곳에서 구글 API를 호출할 때 사용할 Access Token을 반환합니다
    func getAccessToken() -> String? {
        if isDemoMode || isAppleSignIn { return "demo_token" }
        return accessToken
    }

    // --------------------------------------------------------
    // MARK: - Access Token 갱신하기
    // --------------------------------------------------------

    /// Refresh Token을 사용해서 새로운 Access Token을 발급받습니다
    /// - Parameter completion: 갱신 완료 후 호출될 콜백 (성공 시 새 토큰, 실패 시 nil)
    func refreshAccessToken(completion: @escaping (String?) -> Void) {
        #if DEBUG
        print("🔄 refreshAccessToken 호출됨")
        #endif

        guard let refreshToken = refreshToken else {
            #if DEBUG
            print("❌ Refresh Token이 없습니다. 다시 로그인해주세요.")
            #endif
            completion(nil)
            return
        }

        #if DEBUG
        print("🔑 Refresh Token 존재함, 갱신 요청 시작...")
        #endif

        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: tokenURL)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    #if DEBUG
                    print("❌ 토큰 갱신 네트워크 실패: \(error.localizedDescription)")
                    #endif
                    completion(nil)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    #if DEBUG
                    print("📡 토큰 갱신 응답 코드: \(httpResponse.statusCode)")
                    #endif
                }

                guard let data = data else {
                    #if DEBUG
                    print("❌ 토큰 갱신 응답 데이터 없음")
                    #endif
                    completion(nil)
                    return
                }

                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 토큰 갱신 응답: \(responseString)")
                }
                #endif

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String else {
                    #if DEBUG
                    print("❌ 토큰 갱신 응답 파싱 실패")
                    #endif
                    completion(nil)
                    return
                }

                // 새 토큰 저장
                self?.accessToken = newAccessToken
                self?.saveTokens()

                #if DEBUG
                print("✅ Access Token 갱신 완료")
                #endif
                completion(newAccessToken)
            }
        }.resume()
    }

    /// Access Token이 유효한지 확인하고, 필요하면 갱신합니다
    /// - Parameter completion: 유효한 토큰 반환 (실패 시 nil)
    func getValidAccessToken(completion: @escaping (String?) -> Void) {
        // 데모 모드 또는 Apple 로그인에서는 즉시 demo_token 반환
        if isDemoMode || isAppleSignIn {
            completion("demo_token")
            return
        }

        #if DEBUG
        print("🔍 getValidAccessToken 호출됨")
        #endif

        guard let token = accessToken else {
            #if DEBUG
            print("❌ accessToken이 nil입니다")
            #endif
            completion(nil)
            return
        }

        #if DEBUG
        print("🔑 현재 토큰 존재함, 유효성 검사 시작...")
        #endif

        // 토큰 유효성 검사 (Authorization 헤더 사용)
        guard let testURL = URL(string: "https://www.googleapis.com/oauth2/v1/tokeninfo") else {
            completion(token)
            return
        }

        var request = URLRequest(url: testURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    #if DEBUG
                    print("⚠️ 토큰 검사 네트워크 오류: \(error.localizedDescription)")
                    #endif
                    // 네트워크 오류 시에도 기존 토큰 시도
                    completion(token)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    #if DEBUG
                    print("📡 토큰 검사 응답 코드: \(httpResponse.statusCode)")
                    #endif

                    if httpResponse.statusCode == 200 {
                        // 토큰이 유효함
                        #if DEBUG
                        print("✅ 토큰 유효함")
                        #endif
                        completion(token)
                    } else {
                        // 토큰이 만료됨 - 갱신 시도
                        #if DEBUG
                        print("⏰ Access Token 만료됨 (status: \(httpResponse.statusCode)), 갱신 시도...")
                        #endif
                        self?.refreshAccessToken(completion: completion)
                    }
                } else {
                    #if DEBUG
                    print("⚠️ HTTPURLResponse 변환 실패")
                    #endif
                    // 네트워크 오류 - 기존 토큰 반환
                    completion(token)
                }
            }
        }.resume()
    }
}
