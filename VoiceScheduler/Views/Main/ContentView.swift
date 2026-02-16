// ContentView.swift
// 앱의 메인 화면입니다. 로그인 여부에 따라 다른 화면을 보여줍니다.

import SwiftUI

struct ContentView: View {

    // EnvironmentObject: 앱 전체에서 공유되는 데이터에 접근합니다
    // VoiceSchedulerApp에서 전달한 authManager를 여기서 받아 사용합니다
    @EnvironmentObject var authManager: GoogleAuthManager

    var body: some View {
        // Group: 여러 뷰를 하나로 묶어주는 컨테이너입니다
        Group {
            // if-else: 조건에 따라 다른 화면을 보여줍니다
            if authManager.isSignedIn {
                // 로그인이 되어있으면 → 메인 인터페이스(음성 입력 화면)를 보여줍니다
                MainVoiceView()
            } else {
                // 로그인이 안 되어있으면 → 로그인 화면을 보여줍니다
                LoginView()
            }
        }
    }
}

// Preview: Xcode에서 화면을 미리 볼 수 있게 해주는 코드입니다
// 실제 앱 동작에는 영향을 주지 않습니다
#Preview {
    ContentView()
        .environmentObject(GoogleAuthManager())
}
