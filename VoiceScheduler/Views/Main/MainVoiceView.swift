// MainVoiceView.swift
// 앱의 메인 화면입니다.
// 사용자가 음성으로 할 일을 말하고, 결과를 확인하고, 캘린더에 배치하는 화면입니다.

import SwiftUI
import UIKit

// UUID를 Identifiable로 사용하기 위한 Extension
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct MainVoiceView: View {

    // ============================================
    // MARK: - 상태 변수들 (State Variables)
    // ============================================

    // @State: 이 화면에서만 사용하는 데이터. 값이 바뀌면 화면이 자동 업데이트됨
    // @StateObject: 클래스 객체를 이 화면이 "소유"함

    @EnvironmentObject var authManager: GoogleAuthManager
    @EnvironmentObject var appState: AppState

    // 구독 관리
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    // 친구 초대 관리
    @ObservedObject private var referralManager = ReferralManager.shared

    // 일일 제한 도달 팝업
    @State private var showLimitReachedPopup = false

    // 프리미엄 구독 화면
    @State private var showPremiumView = false

    // 공유 시트
    @State private var showShareSheet = false

    // 초대 코드 입력 화면
    @State private var showReferralCodeInput = false
    @State private var referralCodeInput = ""
    @State private var referralCodeMessage = ""
    @State private var referralCodeSuccess = false

    // 음성 입력 관련
    @StateObject private var speechManager = SpeechRecognitionManager()

    // 현재 녹음 중인지 여부
    @State private var isRecording = false

    // 마이크 버튼 애니메이션용 (누르고 있을 때 크기 변화)
    @State private var micButtonScale: CGFloat = 1.0

    // 음성 파형 애니메이션용
    @State private var wavePhase: CGFloat = 0

    // 녹음 타이머 (30초 무음 감지용)
    @State private var recordingTimer: Timer?
    @State private var silenceSeconds: Int = 0
    @State private var lastTranscriptLength: Int = 0

    // Gemini가 분석한 할 일 목록 (UserDefaults에서 불러옴)
    @State private var todoItems: [TodoItem] = [] {
        didSet {
            saveTodoItems()
        }
    }

    // 분석 중인지 여부
    @State private var isAnalyzing = false

    // 인식된 텍스트 표시 여부
    @State private var showTranscript = false

    // 알림 표시용
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertText = ""

    // 캘린더 날짜 이동 및 새로고침 제어
    @State private var calendarDisplayDate: Date = Date()
    @State private var calendarRefreshID: UUID = UUID()

    // 일정 제목 편집 (ID 기반으로 안정적 관리)
    @State private var editingItemID: UUID? = nil

    // 등록 완료 후 캘린더 보기 유지
    @State private var showCalendarAfterRegistration: Bool = false

    // 등록 완료된 일정 목록
    @State private var registeredEvents: [(title: String, date: Date, hour: Int, minute: Int, priority: Priority)] = []

    // 할 일/캘린더 분할 비율 (드래그로 조절)
    @State private var splitRatio: CGFloat = 0.45

    // 시간에 관한 명언
    @State private var currentQuote: (text: String, author: String) = TimeQuotes.random()

    // 명언 목록 (다국어 지원)
    private struct TimeQuotes {
        static let quotes: [String: [(text: String, author: String)]] = [
            "ko": [
                ("시간은 가장 희소한 자원이며, 그것을 관리하지 못하면 아무것도 관리할 수 없다.", "Peter Drucker"),
                ("잃어버린 시간은 다시 찾을 수 없다.", "Benjamin Franklin"),
                ("당신의 시간은 한정되어 있다. 다른 사람의 삶을 사느라 낭비하지 마라.", "Steve Jobs"),
                ("어제는 지나갔고, 내일은 미스터리다. 오늘은 선물이다.", "Eleanor Roosevelt"),
                ("시간을 지배하라, 그렇지 않으면 시간이 당신을 지배할 것이다.", "Brian Tracy"),
                ("가장 큰 낭비는 시간의 낭비이다.", "Seneca"),
                ("매 순간이 새로운 시작이다.", "T.S. Eliot"),
                ("1년 후, 당신은 오늘 시작했으면 좋겠다고 바랄 것이다.", "Karen Lamb")
            ],
            "en": [
                ("Time is the scarcest resource, and unless it is managed, nothing else can be managed.", "Peter Drucker"),
                ("Lost time is never found again.", "Benjamin Franklin"),
                ("Your time is limited. Don't waste it living someone else's life.", "Steve Jobs"),
                ("Yesterday is gone. Tomorrow is a mystery. Today is a gift.", "Eleanor Roosevelt"),
                ("Either you run the day, or the day runs you.", "Jim Rohn"),
                ("The greatest gift you can give someone is your time.", "Rick Warren"),
                ("Time is what we want most, but what we use worst.", "William Penn"),
                ("A year from now you will wish you had started today.", "Karen Lamb")
            ],
            "ja": [
                ("時間は最も希少な資源であり、それを管理できなければ何も管理できない。", "Peter Drucker"),
                ("失われた時間は二度と戻らない。", "Benjamin Franklin"),
                ("あなたの時間は限られている。他人の人生を生きて無駄にしてはいけない。", "Steve Jobs"),
                ("昨日は過ぎ去り、明日は謎。今日は贈り物だ。", "Eleanor Roosevelt"),
                ("時間を支配せよ、さもなければ時間があなたを支配する。", "Brian Tracy"),
                ("最大の無駄は時間の無駄である。", "Seneca"),
                ("すべての瞬間が新しい始まりだ。", "T.S. Eliot"),
                ("1年後、今日始めておけばよかったと思うだろう。", "Karen Lamb")
            ],
            "zh-Hans": [
                ("时间是最稀缺的资源，如果不能管理时间，就无法管理任何事情。", "Peter Drucker"),
                ("失去的时间永远无法找回。", "Benjamin Franklin"),
                ("你的时间有限，不要浪费在别人的生活上。", "Steve Jobs"),
                ("昨天已经过去，明天是个谜，今天是礼物。", "Eleanor Roosevelt"),
                ("要么你掌控时间，要么时间掌控你。", "Jim Rohn"),
                ("最大的浪费是时间的浪费。", "Seneca"),
                ("每一刻都是新的开始。", "T.S. Eliot"),
                ("一年后，你会希望今天就开始。", "Karen Lamb")
            ],
            "es": [
                ("El tiempo es el recurso más escaso; si no se gestiona, nada más puede gestionarse.", "Peter Drucker"),
                ("El tiempo perdido nunca se recupera.", "Benjamin Franklin"),
                ("Tu tiempo es limitado. No lo desperdicies viviendo la vida de otro.", "Steve Jobs"),
                ("El ayer se fue. El mañana es un misterio. El hoy es un regalo.", "Eleanor Roosevelt"),
                ("O diriges el día, o el día te dirige a ti.", "Jim Rohn"),
                ("El mayor desperdicio es el desperdicio del tiempo.", "Seneca"),
                ("Cada momento es un nuevo comienzo.", "T.S. Eliot"),
                ("En un año desearás haber empezado hoy.", "Karen Lamb")
            ],
            "pt-BR": [
                ("O tempo é o recurso mais escasso; se não for gerenciado, nada mais pode ser.", "Peter Drucker"),
                ("Tempo perdido nunca é recuperado.", "Benjamin Franklin"),
                ("Seu tempo é limitado. Não o desperdice vivendo a vida de outra pessoa.", "Steve Jobs"),
                ("O ontem se foi. O amanhã é um mistério. O hoje é um presente.", "Eleanor Roosevelt"),
                ("Ou você controla o dia, ou o dia controla você.", "Jim Rohn"),
                ("O maior desperdício é o desperdício de tempo.", "Seneca"),
                ("Cada momento é um novo começo.", "T.S. Eliot"),
                ("Daqui a um ano você desejará ter começado hoje.", "Karen Lamb")
            ],
            "hi": [
                ("समय सबसे दुर्लभ संसाधन है; इसे प्रबंधित किए बिना कुछ भी प्रबंधित नहीं किया जा सकता।", "Peter Drucker"),
                ("खोया हुआ समय कभी वापस नहीं मिलता।", "Benjamin Franklin"),
                ("आपका समय सीमित है। इसे दूसरों की जिंदगी जीने में बर्बाद न करें।", "Steve Jobs"),
                ("कल बीत गया, कल रहस्य है, आज एक उपहार है।", "Eleanor Roosevelt"),
                ("या तो आप दिन को चलाएं, या दिन आपको चलाएगा।", "Jim Rohn"),
                ("सबसे बड़ी बर्बादी समय की बर्बादी है।", "Seneca"),
                ("हर पल एक नई शुरुआत है।", "T.S. Eliot"),
                ("एक साल बाद आप चाहेंगे कि आज शुरू किया होता।", "Karen Lamb")
            ]
        ]

        static func random() -> (text: String, author: String) {
            let language = LocalizationManager.shared.currentLanguage
            let languageQuotes = quotes[language] ?? quotes["en"]!
            return languageQuotes.randomElement() ?? languageQuotes[0]
        }
    }

    var body: some View {
        // NavigationStack: iOS 16+의 네비게이션 컨테이너
        // 화면 상단에 제목 표시줄을 만들어줍니다
        NavigationStack {
            // GeometryReader: 화면 크기 정보를 얻을 수 있게 해줌
            GeometryReader { geometry in
                ZStack {
                    // ========================================
                    // 배경
                    // ========================================
                    backgroundGradient

                    // ========================================
                    // 메인 컨텐츠
                    // ========================================
                    VStack(spacing: 0) {
                        // 사용자 정보 헤더
                        userHeader

                        // 메인 영역
                        if todoItems.isEmpty && !showCalendarAfterRegistration {
                            // 할 일이 없으면 음성 입력 화면
                            voiceInputSection(geometry: geometry)
                        } else if showCalendarAfterRegistration {
                            // 등록 완료 후 캘린더 확인 화면
                            calendarConfirmationSection(geometry: geometry)
                        } else {
                            // 할 일이 있으면 분할 화면 (할 일 + 캘린더)
                            splitViewSection(geometry: geometry)
                        }
                    }

                    // ========================================
                    // 분석 중 오버레이
                    // ========================================
                    if isAnalyzing {
                        analyzingOverlay
                    }

                    // ========================================
                    // 일일 제한 도달 팝업
                    // ========================================
                    if showLimitReachedPopup {
                        limitReachedPopup
                    }

                    // ========================================
                    // 웰컴 기간 종료 팝업
                    // ========================================
                    if subscriptionManager.showWelcomeEndedAlert {
                        welcomeEndedPopup
                    }

                    // ========================================
                    // 친구 초대 보상 축하 팝업
                    // ========================================
                    if referralManager.showRewardCelebration {
                        rewardCelebrationPopup
                    }

                    // ========================================
                    // 초대 코드 입력 팝업
                    // ========================================
                    if showReferralCodeInput {
                        referralCodeInputPopup
                    }
                }
            }
            .navigationBarHidden(true)  // 기본 네비게이션 바 숨기기
            .onAppear {
                // 앱 시작 시 항상 첫 화면(음성 입력)으로 시작
                todoItems = []
                speechManager.transcribedText = ""
                showTranscript = false
                showCalendarAfterRegistration = false
                calendarDisplayDate = Date()
                // 새로운 명언 표시
                currentQuote = TimeQuotes.random()
            }
            // 위젯에서 녹음 시작 요청이 오면 자동으로 녹음 시작
            .onChange(of: appState.shouldStartRecording) { _, shouldStart in
                if shouldStart {
                    appState.shouldStartRecording = false
                    // 약간의 딜레이 후 녹음 시작 (화면 전환 완료 대기)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !isRecording {
                            toggleRecording()
                        }
                    }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button(L10n.confirm, role: .cancel) {}
            } message: {
                Text(alertText)
            }
            .sheet(isPresented: $showPremiumView) {
                PremiumSubscriptionView()
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: referralManager.getShareItems())
            }
            // 일정 제목 편집 (안정적인 ID 기반)
            .fullScreenCover(item: $editingItemID) { itemID in
                if let index = todoItems.firstIndex(where: { $0.id == itemID }) {
                    EditTitleView(
                        originalTitle: todoItems[index].title,
                        onSave: { newTitle in
                            if let idx = todoItems.firstIndex(where: { $0.id == itemID }) {
                                todoItems[idx].title = newTitle
                            }
                            editingItemID = nil
                        },
                        onCancel: {
                            editingItemID = nil
                        }
                    )
                }
            }
        }
    }

    // ============================================
    // MARK: - 배경 그라데이션
    // ============================================

    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.05, blue: 0.2)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // ============================================
    // MARK: - 사용자 정보 헤더
    // ============================================

    private var userHeader: some View {
        HStack {
            // 프로필 이미지
            if let imageURL = authManager.userProfileImageURL {
                // AsyncImage: URL에서 이미지를 비동기로 불러옴
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    // 이미지 로딩 중일 때 보여줄 뷰
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())  // 원형으로 자르기
            }

            // 인사말
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.greeting)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                Text(authManager.userName)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()  // 나머지 공간 차지

            // 오늘 무제한 배지 (친구 초대 보상)
            if referralManager.isUnlimitedToday {
                HStack(spacing: 4) {
                    Image(systemName: "infinity")
                        .font(.system(size: 12))
                    Text(L10n.referralUnlimitedActive)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(12)
            }
            // 웰컴 베네핏 배지 (웰컴 기간 중에만 표시)
            else if !subscriptionManager.isPremium && subscriptionManager.isInWelcomePeriod {
                HStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 12))
                    Text("\(L10n.welcomeGift): \(subscriptionManager.dailyLimit)\(L10n.times)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(12)
            }

            // 로그아웃 버튼
            Button(action: {
                authManager.signOut()
            }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
    }

    // ============================================
    // MARK: - 음성 입력 섹션 (할 일이 없을 때)
    // ============================================

    private func voiceInputSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // ========================================
            // 상단: 시간에 관한 명언
            // ========================================
            if !isRecording {
                VStack(spacing: 12) {
                    Text("\"\(currentQuote.text)\"")
                        .font(.system(size: 15, weight: .light))
                        .italic()
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("— \(currentQuote.author)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            Spacer()

            // ========================================
            // 중앙: 마이크 버튼 영역
            // ========================================
            VStack(spacing: 28) {
                // 인식된 텍스트 표시 영역
                if showTranscript && !speechManager.transcribedText.isEmpty {
                    transcriptView
                }

                // 마이크 버튼 (크기 증가: 160 → 200)
                microphoneButton(size: min(geometry.size.width * 0.5, 200))

                // 간단한 안내 문구 (글자 크기 증가)
                if !isRecording {
                    Text(L10n.tapMicInstruction)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding()
    }

    // ============================================
    // MARK: - 마이크 버튼
    // ============================================

    private func microphoneButton(size: CGFloat) -> some View {
        VStack(spacing: 16) {
            // 녹음 중 상태 표시
            if isRecording {
                Text(L10n.listening)
                    .font(.headline)
                    .foregroundColor(.white)
                    .transition(.opacity.combined(with: .scale))
            }

            ZStack {
                // 녹음 중일 때 파동 효과
                if isRecording {
                    // 첫 번째 파동
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 3)
                        .frame(width: size * 1.3, height: size * 1.3)
                        .scaleEffect(wavePhase)
                        .opacity(2 - wavePhase)

                    // 두 번째 파동 (시차를 두고)
                    Circle()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                        .frame(width: size * 1.5, height: size * 1.5)
                        .scaleEffect(wavePhase * 0.8 + 0.2)
                        .opacity(2 - wavePhase)
                }

                // 메인 버튼 (그라데이션 원)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isRecording
                                ? [Color.red, Color.orange]  // 녹음 중: 빨강
                                : [Color.blue, Color.purple], // 대기 중: 파랑
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(
                        color: (isRecording ? Color.red : Color.blue).opacity(0.5),
                        radius: 20
                    )

                // 마이크 아이콘 (크기 증가: 0.35 → 0.4)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(micButtonScale)  // 애니메이션 스케일
        // 탭(터치) 제스처
        .onTapGesture {
            toggleRecording()
        }
        // 길게 누르기 제스처 (누르고 있는 동안만 녹음)
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            // pressing: 현재 누르고 있는지 여부
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                micButtonScale = pressing ? 0.9 : 1.0
            }
        }, perform: {})
        // 파동 애니메이션
        .onAppear {
            // 무한 반복 애니메이션
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                wavePhase = 2
            }
        }
    }

    // ============================================
    // MARK: - 인식된 텍스트 표시
    // ============================================

    private var transcriptView: some View {
        VStack(spacing: 8) {
            Text(L10n.recognizedText)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            ScrollView {
                Text(speechManager.transcribedText)
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: 150)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // ============================================
    // MARK: - 분할 화면 (할 일 목록 + 캘린더)
    // ============================================

    private func splitViewSection(geometry: GeometryProxy) -> some View {
        // 가로 모드면 좌우 분할, 세로 모드면 상하 분할
        let isLandscape = geometry.size.width > geometry.size.height

        return Group {
            if isLandscape {
                // 가로 모드: 좌우 분할
                HStack(spacing: 0) {
                    todoListSection
                        .frame(width: geometry.size.width * 0.4)

                    Divider()
                        .background(Color.white.opacity(0.2))

                    calendarTimelineSection
                        .frame(width: geometry.size.width * 0.6)
                }
            } else {
                // 세로 모드: 상하 분할 (드래그로 조절 가능)
                VStack(spacing: 0) {
                    todoListSection
                        .frame(height: geometry.size.height * splitRatio)

                    // 드래그 가능한 구분선
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 40, height: 4)
                        Spacer()
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let delta = value.translation.height / geometry.size.height
                                let newRatio = splitRatio + delta
                                splitRatio = min(max(newRatio, 0.25), 0.75)
                            }
                    )

                    calendarTimelineSection
                        .frame(height: geometry.size.height * (0.90 - splitRatio))
                }
            }
        }
    }

    // ============================================
    // MARK: - 할 일 목록 섹션
    // ============================================

    private var todoListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 섹션 헤더
            HStack {
                Text(L10n.extractedTasks)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // 우선순위 범례
                HStack(spacing: 12) {
                    PriorityLegend(color: .red, text: L10n.priorityHigh)
                    PriorityLegend(color: .orange, text: L10n.priorityMedium)
                    PriorityLegend(color: .green, text: L10n.priorityLow)
                }
            }
            .padding(.horizontal)

            // 할 일 카드 목록
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($todoItems) { $item in
                        TodoCardView(
                            item: $item,
                            onEditRequest: {
                                editingItemID = item.id
                            }
                        )
                        .overlay(alignment: .topLeading) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    todoItems.removeAll { $0.id == item.id }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white, .red.opacity(0.8))
                            }
                            .offset(x: -6, y: 4)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
            }

            // 하단 버튼 영역
            HStack(spacing: 16) {
                // 뒤로가기 (초기화) 버튼
                Button(action: {
                    todoItems = []
                    speechManager.transcribedText = ""
                    showTranscript = false
                    calendarDisplayDate = Date()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(16)
                }

                // 자동 캘린더 등록 버튼
                Button(action: {
                    autoScheduleByPriority()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                        Text(L10n.autoSchedule)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding(.top)
    }

    // ============================================
    // MARK: - 캘린더 타임라인 섹션
    // ============================================

    private var calendarTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 섹션 헤더
            HStack {
                Text(Calendar.current.isDateInToday(calendarDisplayDate)
                     ? L10n.todaySchedule
                     : calendarDisplayDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: openGoogleCalendar) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                        Text(L10n.googleCalendar)
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal)

            // 타임라인 뷰
            CalendarTimelineView(
                todoItems: $todoItems,
                displayDate: $calendarDisplayDate,
                refreshID: calendarRefreshID,
                onDropItem: { item, hour in
                    // 할 일을 캘린더에 드롭했을 때 처리
                    scheduleToGoogleCalendar(item: item, hour: hour)
                }
            )
        }
        .padding(.top)
    }

    // ============================================
    // MARK: - 등록 완료 후 캘린더 확인 섹션
    // ============================================

    private func calendarConfirmationSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // 섹션 헤더
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                Text(L10n.calendarRegistered)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: openGoogleCalendar) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                        Text(L10n.googleCalendar)
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // 등록된 일정 목록 (날짜별 그룹)
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(groupedRegisteredEvents.keys.sorted(), id: \.self) { date in
                        VStack(alignment: .leading, spacing: 8) {
                            // 날짜 헤더
                            Text(formatDateHeader(date))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 4)

                            // 해당 날짜의 일정들
                            ForEach(groupedRegisteredEvents[date] ?? [], id: \.title) { event in
                                RegisteredEventRow(
                                    title: event.title,
                                    hour: event.hour,
                                    minute: event.minute,
                                    priority: event.priority
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            // 하단 버튼
            Button(action: {
                withAnimation {
                    showCalendarAfterRegistration = false
                    todoItems = []
                    registeredEvents = []
                    speechManager.transcribedText = ""
                    calendarDisplayDate = Date()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.addNewSchedule)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // ============================================
    // MARK: - 등록된 일정 날짜별 그룹화
    // ============================================

    private var groupedRegisteredEvents: [Date: [(title: String, hour: Int, minute: Int, priority: Priority)]] {
        let calendar = Calendar.current
        var grouped: [Date: [(title: String, hour: Int, minute: Int, priority: Priority)]] = [:]

        for event in registeredEvents {
            let dateOnly = calendar.startOfDay(for: event.date)
            if grouped[dateOnly] == nil {
                grouped[dateOnly] = []
            }
            grouped[dateOnly]?.append((title: event.title, hour: event.hour, minute: event.minute, priority: event.priority))
        }

        // 각 날짜 내에서 시간순 정렬
        for (date, events) in grouped {
            grouped[date] = events.sorted { $0.hour < $1.hour }
        }

        return grouped
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.today
        } else if calendar.isDateInTomorrow(date) {
            return L10n.tomorrow
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M월 d일 (E)"
            formatter.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
            return formatter.string(from: date)
        }
    }

    // ============================================
    // MARK: - 분석 중 오버레이
    // ============================================

    private var analyzingOverlay: some View {
        ZStack {
            // 반투명 검은 배경
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // 로딩 애니메이션
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(L10n.analyzing)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(L10n.pleaseWait)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // ============================================
    // MARK: - 일일 제한 도달 팝업
    // ============================================

    private var limitReachedPopup: some View {
        ZStack {
            // 반투명 배경
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    showLimitReachedPopup = false
                }

            // 팝업 카드
            VStack(spacing: 20) {
                // 아이콘
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }

                // 제목
                Text(L10n.dailyLimitReachedTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // 메시지
                Text(L10n.dailyLimitReachedMessage)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // 친구 초대 버튼 (보라색 그라데이션)
                Button(action: {
                    showLimitReachedPopup = false
                    // 공유 후 보상 지급 (테스트용 - 실제로는 서버 연동 필요)
                    showShareSheet = true
                    // 공유 완료 후 보상 지급 시뮬레이션
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        referralManager.grantShareReward()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18))
                        Text(L10n.referralInviteButton)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }

                // 프리미엄 버튼
                Button(action: {
                    showLimitReachedPopup = false
                    showPremiumView = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18))
                        Text(L10n.upgradeToPremium)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }

                // 닫기 버튼
                Button(action: {
                    showLimitReachedPopup = false
                }) {
                    Text(L10n.close)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // ============================================
    // MARK: - 웰컴 기간 종료 팝업
    // ============================================

    private var welcomeEndedPopup: some View {
        ZStack {
            // 반투명 배경
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            // 팝업 카드
            VStack(spacing: 24) {
                // 아이콘
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }

                // 제목
                Text(L10n.welcomeEndedTitle)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // 메시지
                Text(L10n.welcomeEndedMessage)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // 프리미엄 버튼
                Button(action: {
                    subscriptionManager.markWelcomeEndedAlertShown()
                    showPremiumView = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18))
                        Text(L10n.welcomeEndedCta)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }

                // 나중에 버튼
                Button(action: {
                    subscriptionManager.markWelcomeEndedAlertShown()
                }) {
                    Text(L10n.close)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // ============================================
    // MARK: - 친구 초대 보상 축하 팝업
    // ============================================

    private var rewardCelebrationPopup: some View {
        ZStack {
            // 반투명 배경
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            // 팝업 카드
            VStack(spacing: 24) {
                // 축하 아이콘 (애니메이션)
                ZStack {
                    // 배경 원 파동 효과
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                referralManager.receivedRewardType == .unlimitedToday
                                    ? Color.purple.opacity(0.3 - Double(i) * 0.1)
                                    : Color.yellow.opacity(0.3 - Double(i) * 0.1),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(100 + i * 30), height: CGFloat(100 + i * 30))
                            .scaleEffect(wavePhase * 0.5 + 0.5)
                            .opacity(2 - wavePhase)
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: referralManager.receivedRewardType == .unlimitedToday
                                    ? [Color.purple, Color.blue]
                                    : [Color.yellow, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: referralManager.receivedRewardType.icon)
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }

                // 제목
                Text(referralManager.receivedRewardType.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // 메시지
                Text(referralManager.receivedRewardType.message)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // 확인 버튼
                Button(action: {
                    withAnimation(.spring()) {
                        referralManager.showRewardCelebration = false
                    }
                }) {
                    Text(L10n.confirm)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: referralManager.receivedRewardType == .unlimitedToday
                                    ? [Color.purple, Color.blue]
                                    : [Color.yellow, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // ============================================
    // MARK: - 초대 코드 입력 팝업
    // ============================================

    private var referralCodeInputPopup: some View {
        ZStack {
            // 반투명 배경
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    showReferralCodeInput = false
                }

            // 팝업 카드
            VStack(spacing: 20) {
                // 아이콘
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)

                    Image(systemName: "ticket.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }

                // 제목
                Text(L10n.referralEnterCode)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // 입력 필드
                TextField(L10n.referralEnterCodePlaceholder, text: $referralCodeInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: referralCodeInput) { _, newValue in
                        // 6자리로 제한
                        if newValue.count > 6 {
                            referralCodeInput = String(newValue.prefix(6))
                        }
                    }

                // 결과 메시지
                if !referralCodeMessage.isEmpty {
                    Text(referralCodeMessage)
                        .font(.subheadline)
                        .foregroundColor(referralCodeSuccess ? .green : .red)
                        .multilineTextAlignment(.center)
                }

                // 적용 버튼
                Button(action: {
                    let result = referralManager.applyReferralCode(referralCodeInput)
                    referralCodeMessage = result.message
                    referralCodeSuccess = result.success
                    if result.success {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showReferralCodeInput = false
                            referralCodeInput = ""
                            referralCodeMessage = ""
                        }
                    }
                }) {
                    Text(L10n.referralApply)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }

                // 닫기 버튼
                Button(action: {
                    showReferralCodeInput = false
                    referralCodeInput = ""
                    referralCodeMessage = ""
                }) {
                    Text(L10n.close)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // ============================================
    // MARK: - 녹음 시작/중지
    // ============================================

    private func toggleRecording() {
        if isRecording {
            // 녹음 중지
            stopRecordingTimer()
            speechManager.stopRecording()
            isRecording = false

            // 텍스트가 있으면 AI 분석 시작
            if !speechManager.transcribedText.isEmpty {
                analyzeWithGemini()
            } else {
                alertTitle = L10n.alertNotice
                alertText = L10n.voiceNotRecognized
                showAlert = true
            }
        } else {
            // 녹음 시작 (실패 시 상태를 변경하지 않음)
            let started = speechManager.startRecording()
            if started {
                isRecording = true
                showTranscript = true
                startRecordingTimer()
            } else {
                // 시작 실패: 에러 메시지 표시
                alertTitle = L10n.alertNotice
                alertText = speechManager.errorMessage ?? L10n.speechRecognitionFailed
                showAlert = true
            }
        }
    }

    // ============================================
    // MARK: - 녹음 타이머 (30초 무음 감지)
    // ============================================

    private func startRecordingTimer() {
        silenceSeconds = 0
        lastTranscriptLength = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let currentLength = speechManager.transcribedText.count

            if currentLength > lastTranscriptLength {
                // 새로운 음성이 인식됨 - 무음 카운터 리셋
                silenceSeconds = 0
                lastTranscriptLength = currentLength
            } else {
                // 음성 인식 없음 - 무음 시간 증가
                silenceSeconds += 1

                // 30초 동안 음성 인식이 없으면 자동 중지
                if silenceSeconds >= 30 {
                    DispatchQueue.main.async {
                        self.cancelRecordingDueToSilence()
                    }
                }
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    /// 30초 무음으로 인한 녹음 취소
    private func cancelRecordingDueToSilence() {
        stopRecordingTimer()
        speechManager.stopRecording()
        isRecording = false
        showTranscript = false
        speechManager.transcribedText = ""
    }

    // ============================================
    // MARK: - Gemini AI로 분석하기
    // ============================================

    private func analyzeWithGemini() {
        isAnalyzing = true
        let inputText = speechManager.transcribedText

        // 15초 타임아웃 - AI가 응답하지 않으면 폴백 파서 사용
        var didComplete = false
        let timeoutWork = DispatchWorkItem {
            guard !didComplete else { return }
            didComplete = true
            #if DEBUG
            print("⏱️ AI 타임아웃 - 폴백 파서 사용")
            #endif
            DispatchQueue.main.async {
                self.useFallbackParser(text: inputText)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutWork)

        // Gemini 서비스 호출
        GeminiService.shared.analyzeTasks(text: inputText) { result in
            guard !didComplete else { return }
            didComplete = true
            timeoutWork.cancel()

            DispatchQueue.main.async {
                self.isAnalyzing = false

                switch result {
                case .success(let items):
                    if items.isEmpty {
                        // AI가 빈 결과 반환 시 폴백 사용
                        #if DEBUG
                        print("⚠️ AI 빈 결과 - 폴백 파서 사용")
                        #endif
                        self.useFallbackParser(text: inputText)
                    } else {
                        // 성공: 기존 목록에 새 항목 추가
                        withAnimation {
                            self.todoItems.append(contentsOf: items)
                        }
                    }
                case .failure(let error):
                    // 실패: 폴백 파서 사용
                    #if DEBUG
                    print("❌ AI 분석 실패: \(error) - 폴백 파서 사용")
                    #endif
                    self.useFallbackParser(text: inputText)
                }
            }
        }
    }

    /// 폴백 파서 사용 (AI 실패 시)
    private func useFallbackParser(text: String) {
        isAnalyzing = false

        let items = GeminiService.shared.fallbackParse(text: text)
        if items.isEmpty {
            alertTitle = L10n.analysisFailed
            alertText = L10n.voiceNotRecognized
            showAlert = true
        } else {
            withAnimation {
                self.todoItems.append(contentsOf: items)
            }
        }
    }

    // ============================================
    // MARK: - 할 일 저장/불러오기 (영구 저장)
    // ============================================

    private func saveTodoItems() {
        if let encoded = try? JSONEncoder().encode(todoItems) {
            UserDefaults.standard.set(encoded, forKey: "savedTodoItems")
        }
    }

    private func loadTodoItems() {
        if let data = UserDefaults.standard.data(forKey: "savedTodoItems"),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            todoItems = decoded
        }
    }

    // ============================================
    // MARK: - 우선순위별 자동 캘린더 등록
    // ============================================

    private func autoScheduleByPriority() {
        #if DEBUG
        print("🚀 autoScheduleByPriority 호출됨")
        #endif

        // 0. 일일 사용 제한 확인
        if !subscriptionManager.canUse() {
            showLimitReachedPopup = true
            return
        }

        // 1. 등록할 항목 확인 (최대 10개 제한)
        let allItems = todoItems.filter { !$0.isScheduled }.sorted { item1, item2 in
            let priorityOrder: [Priority: Int] = [.high: 0, .medium: 1, .low: 2]
            return (priorityOrder[item1.priority] ?? 1) < (priorityOrder[item2.priority] ?? 1)
        }
        let sortedItems = Array(allItems.prefix(10))

        if sortedItems.isEmpty {
            alertTitle = L10n.alertNotice
            alertText = L10n.noTasksToRegister
            showAlert = true
            return
        }

        #if DEBUG
        print("📋 등록할 항목 수: \(sortedItems.count)")
        #endif

        // 2. 유효한 토큰 가져오기
        authManager.getValidAccessToken { validToken in
            DispatchQueue.main.async {
                guard let token = validToken else {
                    #if DEBUG
                    print("❌ 유효한 토큰 없음")
                    #endif
                    self.alertTitle = L10n.alertError
                    self.alertText = L10n.tokenRefreshFailed
                    self.showAlert = true
                    return
                }

                #if DEBUG
                print("✅ 유효한 토큰 확보, 일정 등록 시작")
                #endif

                let calendar = Calendar.current
                var nextAvailableHour = calendar.component(.hour, from: Date()) + 1

                let totalCount = sortedItems.count
                var successCount = 0
                var failCount = 0
                var processedCount = 0
                var firstRegisteredDate: Date?

                // 등록된 일정 목록 초기화
                self.registeredEvents = []

                // 순차적으로 등록 (rate limit 방지를 위해 0.5초 간격)
                func registerNext(index: Int) {
                    guard index < sortedItems.count else {
                        // 모든 등록 완료
                        DispatchQueue.main.async {
                            if successCount == totalCount {
                                self.alertTitle = L10n.alertCompleted
                                self.alertText = "\(successCount)" + L10n.allEventsRegistered
                            } else if successCount > 0 {
                                self.alertTitle = L10n.alertPartial
                                self.alertText = String(format: L10n.partialEventsRegistered, totalCount, successCount, failCount)
                            } else {
                                self.alertTitle = L10n.alertError
                                self.alertText = L10n.eventRegistrationFailed
                            }
                            self.showAlert = true
                            // 첫 번째 등록된 일정 날짜로 캘린더 이동
                            if let firstDate = firstRegisteredDate {
                                self.calendarDisplayDate = firstDate
                            }
                            self.calendarRefreshID = UUID()
                            // 등록 완료 후 캘린더 확인 화면 표시
                            if successCount > 0 {
                                self.showCalendarAfterRegistration = true
                                // 일일 사용 횟수 증가
                                self.subscriptionManager.incrementUsage()
                            }
                            self.todoItems.removeAll { $0.isScheduled }
                        }
                        return
                    }

                    let item = sortedItems[index]
                    let scheduleHour = item.suggestedHour ?? nextAvailableHour
                    let scheduleMinute = item.suggestedMinute
                    let itemId = item.id

                    #if DEBUG
                    print("📅 등록 시도 (\(index + 1)/\(totalCount)): \(item.title) → \(scheduleHour)시 \(scheduleMinute)분")
                    #endif

                    GoogleCalendarService.shared.createEvent(
                        accessToken: token,
                        title: "[\(item.priority.localizedName)] \(item.title)",
                        date: item.scheduledDate,
                        hour: scheduleHour,
                        minute: scheduleMinute,
                        duration: item.estimatedDuration,
                        recurrence: item.recurrence
                    ) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                #if DEBUG
                                print("✅ 등록 성공: \(item.title)")
                                #endif
                                successCount += 1
                                // 첫 번째 등록 성공한 일정의 날짜 저장
                                if firstRegisteredDate == nil {
                                    firstRegisteredDate = item.scheduledDate
                                }
                                // 등록된 일정 목록에 추가
                                self.registeredEvents.append((
                                    title: item.title,
                                    date: item.scheduledDate,
                                    hour: scheduleHour,
                                    minute: scheduleMinute,
                                    priority: item.priority
                                ))
                                if let idx = self.todoItems.firstIndex(where: { $0.id == itemId }) {
                                    self.todoItems[idx].isScheduled = true
                                }
                            case .failure(let error):
                                #if DEBUG
                                print("❌ 등록 실패: \(item.title) - \(error)")
                                #endif
                                failCount += 1
                            }
                            processedCount += 1
                            nextAvailableHour = scheduleHour + max(item.estimatedDuration / 60, 1)

                            // 1초 후 다음 항목 등록 (rate limit 방지)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                registerNext(index: index + 1)
                            }
                        }
                    }
                }

                // 첫 번째 항목부터 시작
                registerNext(index: 0)
            }
        }
    }

    // ============================================
    // MARK: - 구글 캘린더에 일정 등록
    // ============================================

    private func scheduleToGoogleCalendar(item: TodoItem, hour: Int) {
        let itemId = item.id

        authManager.getValidAccessToken { validToken in
            DispatchQueue.main.async {
                guard let token = validToken else {
                    self.alertTitle = L10n.alertError
                    self.alertText = L10n.loginRequired
                    self.showAlert = true
                    return
                }

                GoogleCalendarService.shared.createEvent(
                    accessToken: token,
                    title: item.title,
                    date: item.scheduledDate,
                    hour: hour,
                    minute: item.suggestedMinute,
                    duration: item.estimatedDuration,
                    recurrence: item.recurrence
                ) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.todoItems.removeAll { $0.id == itemId }
                            // 캘린더를 해당 날짜로 이동 + 새로고침 + 햅틱
                            self.calendarDisplayDate = item.scheduledDate
                            self.calendarRefreshID = UUID()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        case .failure(let error):
                            self.alertTitle = L10n.alertError
                            self.alertText = String(format: L10n.eventRegistrationError, error.localizedDescription)
                            self.showAlert = true
                        }
                    }
                }
            }
        }
    }

    // ============================================
    // MARK: - 구글 캘린더 바로가기
    // ============================================

    private func openGoogleCalendar() {
        // Google Calendar 앱 URL scheme
        let appURL = URL(string: "com.google.calendar://")!
        let webURL = URL(string: "https://calendar.google.com")!

        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(webURL)
        }
    }
}

// ============================================
// MARK: - 우선순위 범례 컴포넌트
// ============================================

struct PriorityLegend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// ============================================
// MARK: - 등록된 일정 행 컴포넌트
// ============================================

struct RegisteredEventRow: View {
    let title: String
    let hour: Int
    let minute: Int
    let priority: Priority

    private var priorityColor: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }

    private func formatTime() -> String {
        let lang = LocalizationManager.shared.currentLanguage
        let isAM = hour < 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)

        switch lang {
        case "ko":
            return "\(isAM ? "오전" : "오후") \(displayHour)시\(minute > 0 ? " \(minute)분" : "")"
        case "ja":
            return "\(isAM ? "午前" : "午後") \(displayHour)時\(minute > 0 ? "\(minute)分" : "")"
        case "zh-Hans":
            return "\(isAM ? "上午" : "下午") \(displayHour)点\(minute > 0 ? "\(minute)分" : "")"
        default:
            let minuteStr = minute > 0 ? String(format: ":%02d", minute) : ""
            return "\(displayHour)\(minuteStr) \(isAM ? "AM" : "PM")"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 우선순위 색상 바
            RoundedRectangle(cornerRadius: 3)
                .fill(priorityColor)
                .frame(width: 4)

            // 시간 (시:분)
            Text(formatTime())
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)

            // 제목
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // 체크 아이콘
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 18))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// ============================================
// MARK: - ShareSheet (공유 시트)
// ============================================

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// 미리보기
#Preview {
    MainVoiceView()
        .environmentObject(GoogleAuthManager())
}
