// APIUsageGuard.swift
// API 사용량 안전장치를 관리합니다.
// - 일일 토큰 하드 리밋 (100,000 토큰)
// - 비정상 활동 감지 (1분 내 10회 이상 요청)
// - 예산 모니터링 및 알림
//
// ============================================================
// Google Cloud Console 예산 알림 설정 가이드
// ============================================================
//
// 1. Google Cloud Console (console.cloud.google.com) 접속
// 2. Billing → Budgets & alerts 이동
// 3. "CREATE BUDGET" 클릭
// 4. Budget settings:
//    - Name: "Voice Scheduler API Budget"
//    - Scope: "All projects" 또는 특정 프로젝트 선택
//    - Budget type: "Specified amount"
//    - Target amount: $50 (또는 원하는 금액)
// 5. Thresholds:
//    - 20% ($10): 주의
//    - 50% ($25): 경고
//    - 100% ($50): 위험
//    - 150% ($75): 초과
// 6. Notifications:
//    - Email: 관리자 이메일 추가
//    - (선택) Pub/Sub: 서버 연동 시 사용
//
// ⚠️ 참고: 이 앱은 클라이언트 전용이므로 Google Cloud의
// 실시간 예산 알림을 직접 수신할 수 없습니다.
// 로컬에서 추정 비용을 계산하고 로그를 기록합니다.
// 서버 연동 시 Pub/Sub 알림을 푸시 알림으로 전달할 수 있습니다.
// ============================================================

import Foundation
import SwiftUI
import UIKit

// ============================================================
// MARK: - API 사용량 안전장치
// ============================================================

class APIUsageGuard: ObservableObject {
    static let shared = APIUsageGuard()

    // --------------------------------------------------------
    // MARK: - 설정 상수
    // --------------------------------------------------------

    /// 일일 토큰 하드 리밋 (무제한 사용자 포함)
    private let dailyTokenHardLimit: Int = 100_000

    /// 요청당 평균 토큰 사용량 (프롬프트 + 응답)
    /// - 입력 프롬프트: ~200 토큰
    /// - 출력 응답: ~300 토큰
    /// - 총 평균: ~500 토큰
    private let estimatedTokensPerRequest: Int = 500

    /// 비정상 활동 감지 임계값 (1분 내 요청 수)
    private let abnormalActivityThreshold: Int = 10

    /// 비정상 활동 감지 시간 윈도우 (초)
    private let abnormalActivityWindow: TimeInterval = 60

    /// 비정상 활동 차단 시간 (초)
    private let abnormalActivityBlockDuration: TimeInterval = 300  // 5분

    /// 예산 경고 임계값 (USD)
    private let budgetWarningThresholds: [Double] = [10, 25, 50, 75, 100]

    // --------------------------------------------------------
    // MARK: - Published 프로퍼티
    // --------------------------------------------------------

    /// 오늘 사용한 토큰 수
    @Published private(set) var todayTokenUsage: Int = 0

    /// 비정상 활동으로 차단 중인지
    @Published private(set) var isBlocked: Bool = false

    /// 차단 해제까지 남은 시간 (초)
    @Published private(set) var blockRemainingSeconds: Int = 0

    /// 예산 경고 메시지
    @Published var budgetWarningMessage: String = ""

    /// 예산 경고 표시 여부
    @Published var showBudgetWarning: Bool = false

    // --------------------------------------------------------
    // MARK: - Private 프로퍼티
    // --------------------------------------------------------

    /// 요청 타임스탬프 기록 (비정상 활동 감지용)
    private var requestTimestamps: [Date] = []

    /// 마지막 사용 날짜 (일일 리셋용)
    private var lastUsageDate: Date? {
        get { UserDefaults.standard.object(forKey: "apiGuard_lastUsageDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "apiGuard_lastUsageDate") }
    }

    /// 저장된 오늘 토큰 사용량
    private var storedTodayTokenUsage: Int {
        get { UserDefaults.standard.integer(forKey: "apiGuard_todayTokenUsage") }
        set { UserDefaults.standard.set(newValue, forKey: "apiGuard_todayTokenUsage") }
    }

    /// 차단 종료 시간
    private var blockEndTime: Date? {
        get { UserDefaults.standard.object(forKey: "apiGuard_blockEndTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "apiGuard_blockEndTime") }
    }

    /// 이번 달 예상 비용 (USD)
    private var estimatedMonthlyCost: Double {
        get { UserDefaults.standard.double(forKey: "apiGuard_estimatedMonthlyCost") }
        set { UserDefaults.standard.set(newValue, forKey: "apiGuard_estimatedMonthlyCost") }
    }

    /// 차단 타이머
    private var blockTimer: Timer?

    // --------------------------------------------------------
    // MARK: - 초기화
    // --------------------------------------------------------

    private init() {
        // 날짜가 바뀌었으면 리셋
        checkAndResetIfNewDay()

        // 저장된 값 불러오기
        todayTokenUsage = storedTodayTokenUsage

        // 차단 상태 확인
        checkBlockStatus()

        #if DEBUG
        print("🛡️ APIUsageGuard 초기화: 오늘 토큰 사용량 \(todayTokenUsage)/\(dailyTokenHardLimit)")
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 요청 허용 여부 확인
    // --------------------------------------------------------

    /// API 요청을 허용할 수 있는지 확인합니다
    /// - Returns: (허용 여부, 거부 사유)
    func canMakeRequest() -> (allowed: Bool, reason: String?) {
        // 날짜 변경 확인
        checkAndResetIfNewDay()

        #if DEBUG
        // 디버그 모드에서는 차단 비활성화 (테스트 용이성)
        print("🛡️ [DEBUG] 안전장치 체크 생략")
        return (true, nil)
        #else
        // 1. 차단 상태 확인
        if isBlocked {
            return (false, "abnormal_activity_blocked".localized)
        }

        // 2. 토큰 하드 리밋 확인
        if todayTokenUsage >= dailyTokenHardLimit {
            return (false, "daily_token_limit_reached".localized)
        }

        // 3. 비정상 활동 감지
        if detectAbnormalActivity() {
            blockUser()
            return (false, "abnormal_activity_detected".localized)
        }

        return (true, nil)
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 요청 기록
    // --------------------------------------------------------

    /// API 요청을 기록합니다 (요청 시작 시 호출)
    func recordRequestStart() {
        // 요청 타임스탬프 기록
        requestTimestamps.append(Date())

        // 오래된 타임스탬프 정리 (1분 이상 된 것)
        let cutoff = Date().addingTimeInterval(-abnormalActivityWindow)
        requestTimestamps = requestTimestamps.filter { $0 > cutoff }

        #if DEBUG
        print("📊 요청 기록: 최근 1분간 \(requestTimestamps.count)회 요청")
        #endif
    }

    /// API 응답 완료 후 토큰 사용량을 기록합니다
    /// - Parameter tokenCount: 실제 사용된 토큰 수 (nil이면 추정치 사용)
    func recordTokenUsage(_ tokenCount: Int? = nil) {
        let tokens = tokenCount ?? estimatedTokensPerRequest
        todayTokenUsage += tokens
        storedTodayTokenUsage = todayTokenUsage

        // 예산 추적 업데이트
        updateBudgetTracking(tokens: tokens)

        #if DEBUG
        print("📊 토큰 사용 기록: +\(tokens) (오늘 총 \(todayTokenUsage)/\(dailyTokenHardLimit))")
        #endif

        // 토큰 사용량 경고 (80%, 90%, 95% 도달 시)
        let usagePercent = Double(todayTokenUsage) / Double(dailyTokenHardLimit) * 100
        if usagePercent >= 95 {
            #if DEBUG
            print("⚠️ 토큰 사용량 경고: 95% 도달!")
            #endif
        } else if usagePercent >= 90 {
            #if DEBUG
            print("⚠️ 토큰 사용량 경고: 90% 도달")
            #endif
        } else if usagePercent >= 80 {
            #if DEBUG
            print("⚠️ 토큰 사용량 주의: 80% 도달")
            #endif
        }
    }

    // --------------------------------------------------------
    // MARK: - 비정상 활동 감지
    // --------------------------------------------------------

    /// 비정상 활동을 감지합니다 (1분 내 10회 이상 요청)
    private func detectAbnormalActivity() -> Bool {
        let cutoff = Date().addingTimeInterval(-abnormalActivityWindow)
        let recentRequests = requestTimestamps.filter { $0 > cutoff }

        if recentRequests.count >= abnormalActivityThreshold {
            #if DEBUG
            print("🚨 비정상 활동 감지: 1분 내 \(recentRequests.count)회 요청!")
            #endif
            return true
        }

        return false
    }

    /// 사용자를 일시적으로 차단합니다
    private func blockUser() {
        isBlocked = true
        blockEndTime = Date().addingTimeInterval(abnormalActivityBlockDuration)
        blockRemainingSeconds = Int(abnormalActivityBlockDuration)

        // 타이머 시작
        startBlockTimer()

        // 로그 기록 (서버 전송용)
        logSecurityEvent(type: "abnormal_activity_block", details: [
            "requests_in_window": requestTimestamps.count,
            "block_duration_seconds": abnormalActivityBlockDuration
        ])

        #if DEBUG
        print("🔒 사용자 차단됨: \(Int(abnormalActivityBlockDuration))초간 API 사용 불가")
        #endif
    }

    /// 차단 상태를 확인하고 업데이트합니다
    private func checkBlockStatus() {
        guard let endTime = blockEndTime else {
            isBlocked = false
            return
        }

        if Date() >= endTime {
            // 차단 해제
            isBlocked = false
            blockEndTime = nil
            blockRemainingSeconds = 0
            #if DEBUG
            print("🔓 차단 해제됨")
            #endif
        } else {
            // 아직 차단 중
            isBlocked = true
            blockRemainingSeconds = Int(endTime.timeIntervalSinceNow)
            startBlockTimer()
        }
    }

    /// 차단 타이머 시작
    private func startBlockTimer() {
        blockTimer?.invalidate()
        blockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if let endTime = self.blockEndTime {
                let remaining = Int(endTime.timeIntervalSinceNow)
                if remaining <= 0 {
                    self.isBlocked = false
                    self.blockEndTime = nil
                    self.blockRemainingSeconds = 0
                    self.blockTimer?.invalidate()
                    #if DEBUG
                    print("🔓 차단 해제됨")
                    #endif
                } else {
                    self.blockRemainingSeconds = remaining
                }
            }
        }
    }

    // --------------------------------------------------------
    // MARK: - 날짜 변경 확인
    // --------------------------------------------------------

    /// 날짜가 변경되었으면 토큰 사용량을 리셋합니다
    private func checkAndResetIfNewDay() {
        let calendar = Calendar.current

        guard let lastDate = lastUsageDate else {
            lastUsageDate = Date()
            return
        }

        if !calendar.isDateInToday(lastDate) {
            // 새로운 날 - 리셋
            todayTokenUsage = 0
            storedTodayTokenUsage = 0
            lastUsageDate = Date()
            requestTimestamps = []
            #if DEBUG
            print("🔄 새로운 날 - 토큰 사용량 리셋")
            #endif
        }
    }

    // --------------------------------------------------------
    // MARK: - 예산 모니터링
    // --------------------------------------------------------

    /// 토큰 사용량 기반 예산 추적 업데이트
    private func updateBudgetTracking(tokens: Int) {
        // Gemini API 가격 (2024년 기준 추정)
        // gemini-2.0-flash: 입력 $0.10/1M tokens, 출력 $0.40/1M tokens
        // 평균 가정: $0.25/1M tokens = $0.00000025/token
        let costPerToken: Double = 0.00000025
        let requestCost = Double(tokens) * costPerToken

        // 월간 비용 누적 (매월 1일에 리셋)
        let calendar = Calendar.current
        let currentDay = calendar.component(.day, from: Date())

        if currentDay == 1 {
            // 매월 1일 리셋
            let lastResetMonth = UserDefaults.standard.integer(forKey: "apiGuard_lastResetMonth")
            let currentMonth = calendar.component(.month, from: Date())
            if lastResetMonth != currentMonth {
                estimatedMonthlyCost = 0
                UserDefaults.standard.set(currentMonth, forKey: "apiGuard_lastResetMonth")
            }
        }

        estimatedMonthlyCost += requestCost

        // 예산 경고 확인
        checkBudgetWarnings()
    }

    /// 예산 경고 확인
    private func checkBudgetWarnings() {
        for threshold in budgetWarningThresholds.reversed() {
            if estimatedMonthlyCost >= threshold {
                let shownKey = "apiGuard_budgetWarningShown_\(Int(threshold))"
                if !UserDefaults.standard.bool(forKey: shownKey) {
                    UserDefaults.standard.set(true, forKey: shownKey)
                    triggerBudgetWarning(threshold: threshold)
                }
                break
            }
        }
    }

    /// 예산 경고 트리거
    private func triggerBudgetWarning(threshold: Double) {
        DispatchQueue.main.async {
            self.budgetWarningMessage = String(
                format: "budget_warning_message".localized,
                threshold,
                self.estimatedMonthlyCost
            )
            self.showBudgetWarning = true
        }

        // 로그 기록
        logSecurityEvent(type: "budget_threshold_reached", details: [
            "threshold_usd": threshold,
            "current_cost_usd": estimatedMonthlyCost
        ])

        #if DEBUG
        print("💰 예산 경고: $\(Int(threshold)) 임계값 도달 (현재 추정 비용: $\(String(format: "%.2f", estimatedMonthlyCost)))")
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 보안 이벤트 로깅
    // --------------------------------------------------------

    /// 보안 관련 이벤트를 로깅합니다 (추후 서버 전송용)
    private func logSecurityEvent(type: String, details: [String: Any]) {
        let event: [String: Any] = [
            "type": type,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "details": details
        ]

        // 로컬 로그 저장 (추후 서버 전송 가능)
        var logs = UserDefaults.standard.array(forKey: "apiGuard_securityLogs") as? [[String: Any]] ?? []
        logs.append(event)

        // 최근 100개만 유지
        if logs.count > 100 {
            logs = Array(logs.suffix(100))
        }
        UserDefaults.standard.set(logs, forKey: "apiGuard_securityLogs")

        #if DEBUG
        print("📝 보안 이벤트 로그: \(type)")
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 상태 정보
    // --------------------------------------------------------

    /// 현재 토큰 사용 비율 (0.0 ~ 1.0)
    var tokenUsageRatio: Double {
        Double(todayTokenUsage) / Double(dailyTokenHardLimit)
    }

    /// 남은 토큰 수
    var remainingTokens: Int {
        max(0, dailyTokenHardLimit - todayTokenUsage)
    }

    /// 예상 남은 요청 가능 횟수
    var estimatedRemainingRequests: Int {
        remainingTokens / estimatedTokensPerRequest
    }

    /// 이번 달 예상 비용 문자열
    var monthlyCostString: String {
        String(format: "$%.2f", estimatedMonthlyCost)
    }

    // --------------------------------------------------------
    // MARK: - 디버그용
    // --------------------------------------------------------

    #if DEBUG
    func resetForTesting() {
        todayTokenUsage = 0
        storedTodayTokenUsage = 0
        requestTimestamps = []
        isBlocked = false
        blockEndTime = nil
        blockRemainingSeconds = 0
        estimatedMonthlyCost = 0
        #if DEBUG
        print("🧪 APIUsageGuard 테스트 리셋 완료")
        #endif
    }

    func simulateHighUsage() {
        todayTokenUsage = 95000
        storedTodayTokenUsage = 95000
        #if DEBUG
        print("🧪 높은 토큰 사용량 시뮬레이션: \(todayTokenUsage)")
        #endif
    }

    func simulateAbnormalActivity() {
        // 1분 내 15개 요청 시뮬레이션
        let now = Date()
        for i in 0..<15 {
            requestTimestamps.append(now.addingTimeInterval(Double(-i * 3)))
        }
        #if DEBUG
        print("🧪 비정상 활동 시뮬레이션: \(requestTimestamps.count)개 요청")
        #endif
    }
    #endif
}

