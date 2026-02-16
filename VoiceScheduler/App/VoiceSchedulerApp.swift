import SwiftUI
import GoogleSignIn

@main
struct VoiceSchedulerApp: App {
    // 앱 전체에서 사용할 데이터 관리자 (로그인 상태 관리)
    @StateObject private var authManager = GoogleAuthManager()

    // 위젯에서 녹음 시작 요청을 받았는지 여부
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(appState)
                .onOpenURL { url in
                    // 위젯에서 녹음 시작 요청
                    if url.scheme == "voicescheduler" && url.host == "startRecording" {
                        appState.shouldStartRecording = true
                    } else {
                        // 구글 로그인 콜백
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
    }
}

// ============================================================
// MARK: - 앱 상태 관리 (위젯 연동용)
// ============================================================

class AppState: ObservableObject {
    @Published var shouldStartRecording: Bool = false
}
