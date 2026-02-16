// LoginView.swift
// 구글 로그인 화면입니다.
// 앱을 처음 실행하거나 로그아웃 상태일 때 이 화면이 보입니다.

import SwiftUI

struct LoginView: View {

    // 구글 인증 관리자에 접근
    @EnvironmentObject var authManager: GoogleAuthManager

    var body: some View {
        // ZStack: 뷰를 겹쳐서 배치합니다 (아래에서 위로 쌓임)
        ZStack {
            // ============================================
            // 배경 그라데이션
            // ============================================
            LinearGradient(
                // 그라데이션 색상들
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),  // 진한 남색
                    Color(red: 0.2, green: 0.1, blue: 0.3)   // 보라색 톤
                ]),
                startPoint: .topLeading,    // 시작점: 왼쪽 위
                endPoint: .bottomTrailing   // 끝점: 오른쪽 아래
            )
            .ignoresSafeArea() // 화면 가장자리(노치, 홈바 영역)까지 채움

            // ============================================
            // 메인 컨텐츠
            // ============================================
            VStack(spacing: 40) {
                // Spacer: 빈 공간을 만들어 아래 내용을 화면 중앙으로 밀어줌
                Spacer()

                // ----------------------------------------
                // 앱 아이콘 및 제목
                // ----------------------------------------
                VStack(spacing: 20) {
                    // 마이크 아이콘 (SF Symbols 사용)
                    // SF Symbols: 애플이 제공하는 무료 아이콘 모음
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 100))  // 아이콘 크기
                        .foregroundStyle(          // 그라데이션 색상
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.5), radius: 20)  // 그림자 효과

                    // 앱 제목
                    Text(L10n.appName)
                        .font(.system(size: 36, weight: .bold))  // 크고 굵은 글씨
                        .foregroundColor(.white)

                    // 앱 설명
                    Text(L10n.appTagline)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))  // 약간 투명한 흰색
                        .multilineTextAlignment(.center)       // 가운데 정렬
                }

                Spacer()

                // ----------------------------------------
                // 구글 로그인 버튼
                // ----------------------------------------
                VStack(spacing: 16) {
                    // 로그인 버튼
                    Button(action: {
                        // 버튼 클릭 시 구글 로그인 시작
                        authManager.signIn()
                    }) {
                        // 버튼 내부 디자인
                        HStack(spacing: 12) {
                            // 구글 로고 (실제 앱에서는 구글 로고 이미지 사용 권장)
                            Image(systemName: "g.circle.fill")
                                .font(.title2)

                            Text(L10n.loginGoogle)
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)       // 버튼 가로 최대 크기
                        .padding(.vertical, 16)           // 위아래 여백
                        .background(Color.white)          // 흰색 배경
                        .cornerRadius(12)                 // 둥근 모서리
                        .shadow(color: .black.opacity(0.2), radius: 10)  // 그림자
                    }
                    .disabled(authManager.isLoading)  // 로딩 중이면 버튼 비활성화
                    .opacity(authManager.isLoading ? 0.6 : 1)  // 비활성화 시 흐리게

                    // 로딩 중일 때 표시
                    if authManager.isLoading {
                        ProgressView()  // 로딩 스피너
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }

                    // 에러 메시지 표시
                    if let errorMessage = authManager.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // 권한 안내 문구
                    Text(L10n.loginPermissionNotice)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 32)  // 좌우 여백

                Spacer()
                    .frame(height: 50)  // 아래쪽 여백
            }
        }
        // ============================================
        // URL 스킴 처리 (구글 로그인 완료 후 앱으로 돌아올 때)
        // ============================================
        .onOpenURL { url in
            // 구글 로그인 후 돌아온 URL을 처리
            authManager.handleCallback(url: url)
        }
    }
}

// 미리보기
#Preview {
    LoginView()
        .environmentObject(GoogleAuthManager())
}
