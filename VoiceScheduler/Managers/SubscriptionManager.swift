// SubscriptionManager.swift
// 구독 상태 및 일일 사용 제한을 관리합니다.
// 7일간의 웰컴 베네핏 시스템 포함

import Foundation
import SwiftUI
import Security

// ============================================================
// MARK: - 구독 관리자
// ============================================================

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // --------------------------------------------------------
    // MARK: - Published 프로퍼티 (UI 바인딩용)
    // --------------------------------------------------------

    /// 프리미엄 구독 상태
    @Published var isPremium: Bool {
        didSet {
            UserDefaults.standard.set(isPremium, forKey: "isPremiumUser")
        }
    }

    /// 오늘 사용 횟수
    @Published private(set) var todayUsageCount: Int = 0

    /// 웰컴 기간 종료 알림 표시 여부
    @Published var showWelcomeEndedAlert: Bool = false

    // --------------------------------------------------------
    // MARK: - Private 프로퍼티
    // --------------------------------------------------------

    /// 마지막 사용 날짜 (일일 카운트 리셋용)
    private var lastUsageDate: Date? {
        didSet {
            if let date = lastUsageDate {
                UserDefaults.standard.set(date, forKey: "lastUsageDate")
            }
        }
    }

    /// 웰컴 기간 종료 알림을 이미 표시했는지 여부
    private var hasShownWelcomeEndedAlert: Bool {
        get { UserDefaults.standard.bool(forKey: "hasShownWelcomeEndedAlert") }
        set { UserDefaults.standard.set(newValue, forKey: "hasShownWelcomeEndedAlert") }
    }

    // --------------------------------------------------------
    // MARK: - 앱 설치 날짜 (키체인에 안전하게 저장)
    // --------------------------------------------------------

    /// 앱 최초 설치 날짜
    /// - 키체인에 저장되어 앱 삭제 후 재설치해도 유지됨
    /// - 키체인 접근 실패 시 UserDefaults로 폴백
    var installDate: Date {
        // 1. 키체인에서 먼저 확인
        if let keychainDate = KeychainDateStorage.getInstallDate() {
            return keychainDate
        }

        // 2. UserDefaults에서 확인 (키체인 마이그레이션용)
        if let userDefaultsDate = UserDefaults.standard.object(forKey: "appInstallDate") as? Date {
            // UserDefaults에 있으면 키체인으로 마이그레이션
            KeychainDateStorage.saveInstallDate(userDefaultsDate)
            return userDefaultsDate
        }

        // 3. 둘 다 없으면 지금이 최초 설치
        let now = Date()
        KeychainDateStorage.saveInstallDate(now)
        UserDefaults.standard.set(now, forKey: "appInstallDate") // 백업용
        return now
    }

    // --------------------------------------------------------
    // MARK: - 웰컴 기간 계산
    // --------------------------------------------------------

    /// 웰컴 기간 (7일 = 168시간)
    private let welcomePeriodDays: Int = 7

    /// 현재 웰컴 기간 중인지 확인
    /// - Returns: 설치 후 7일 이내면 true
    var isInWelcomePeriod: Bool {
        let calendar = Calendar.current
        let daysSinceInstall = calendar.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return daysSinceInstall < welcomePeriodDays
    }

    /// 웰컴 기간 남은 일수
    /// - Returns: 남은 일수 (0이면 종료됨)
    var welcomeDaysRemaining: Int {
        let calendar = Calendar.current
        let daysSinceInstall = calendar.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return max(0, welcomePeriodDays - daysSinceInstall)
    }

    /// 웰컴 기간이 오늘 막 종료되었는지 확인
    /// - Returns: 7일차에 처음 접속한 경우 true
    var isWelcomePeriodJustEnded: Bool {
        // 웰컴 기간이 끝났고, 아직 알림을 보여주지 않았다면
        return !isInWelcomePeriod && !hasShownWelcomeEndedAlert && !isPremium
    }

    // --------------------------------------------------------
    // MARK: - 일일 제한 횟수
    // --------------------------------------------------------

    /// 일일 등록 제한 횟수
    /// - 프리미엄: 30회
    /// - 친구 초대 보상 (오늘 무제한): 999회
    /// - 무료 (웰컴 기간): 3회
    /// - 무료 (웰컴 종료 후): 1회
    var dailyLimit: Int {
        if isPremium {
            return 30
        } else if ReferralManager.shared.isUnlimitedToday {
            return 999  // 친구 초대 보상: 오늘 무제한
        } else if isInWelcomePeriod {
            return 3  // 웰컴 베네핏: 7일간 3회
        } else {
            return 1  // 웰컴 종료 후: 1회
        }
    }

    /// 오늘 무제한 모드인지 확인 (친구 초대 보상)
    var isUnlimitedToday: Bool {
        ReferralManager.shared.isUnlimitedToday
    }

    /// 오늘 남은 등록 횟수
    var remainingCount: Int {
        max(0, dailyLimit - todayUsageCount)
    }

    /// 일일 제한에 도달했는지 확인
    var isLimitReached: Bool {
        todayUsageCount >= dailyLimit
    }

    // --------------------------------------------------------
    // MARK: - 초기화
    // --------------------------------------------------------

    private init() {
        // 저장된 값 불러오기
        self.isPremium = UserDefaults.standard.bool(forKey: "isPremiumUser")
        self.todayUsageCount = UserDefaults.standard.integer(forKey: "todayUsageCount")
        self.lastUsageDate = UserDefaults.standard.object(forKey: "lastUsageDate") as? Date

        // 날짜가 바뀌었으면 카운트 리셋
        checkAndResetIfNewDay()

        // 웰컴 기간 종료 체크
        checkWelcomePeriodEnd()

        // ⚠️ 테스트용: 앱 시작시 카운트 리셋 (출시 전 삭제)
        #if DEBUG
        todayUsageCount = 0
        UserDefaults.standard.set(0, forKey: "todayUsageCount")
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 사용량 관리
    // --------------------------------------------------------

    /// 사용 횟수 증가 (등록 성공 시 호출)
    func incrementUsage() {
        checkAndResetIfNewDay()
        todayUsageCount += 1
        UserDefaults.standard.set(todayUsageCount, forKey: "todayUsageCount")
        lastUsageDate = Date()
    }

    /// 사용 가능 여부 확인
    /// - Returns: 일일 제한 미달이면 true
    func canUse() -> Bool {
        checkAndResetIfNewDay()
        return todayUsageCount < dailyLimit
    }

    /// 날짜가 바뀌었으면 카운트 리셋
    private func checkAndResetIfNewDay() {
        let calendar = Calendar.current

        // 마지막 사용 날짜가 없으면 오늘이 첫 사용
        guard let lastDate = lastUsageDate else {
            lastUsageDate = Date()
            return
        }

        // 오늘 날짜와 마지막 사용 날짜 비교
        if !calendar.isDateInToday(lastDate) {
            // 날짜가 다르면 카운트 리셋
            todayUsageCount = 0
            UserDefaults.standard.set(0, forKey: "todayUsageCount")
            lastUsageDate = Date()

            // 새로운 날에 웰컴 기간 종료 체크
            checkWelcomePeriodEnd()
        }
    }

    /// 웰컴 기간 종료 확인 및 알림 트리거
    private func checkWelcomePeriodEnd() {
        if isWelcomePeriodJustEnded {
            // 메인 스레드에서 알림 표시
            DispatchQueue.main.async {
                self.showWelcomeEndedAlert = true
            }
        }
    }

    /// 웰컴 종료 알림을 확인했음을 기록
    func markWelcomeEndedAlertShown() {
        hasShownWelcomeEndedAlert = true
        showWelcomeEndedAlert = false
    }

    // --------------------------------------------------------
    // MARK: - 프리미엄 관리
    // --------------------------------------------------------

    /// 프리미엄 구독 활성화 (인앱 결제 완료 시 호출)
    func activatePremium() {
        isPremium = true
    }

    /// 프리미엄 구독 해제
    func deactivatePremium() {
        isPremium = false
    }

    // --------------------------------------------------------
    // MARK: - 디버그용 (테스트 후 삭제)
    // --------------------------------------------------------

    #if DEBUG
    func resetForTesting() {
        todayUsageCount = 0
        UserDefaults.standard.set(0, forKey: "todayUsageCount")
        lastUsageDate = Date()
    }

    func setUsageForTesting(_ count: Int) {
        todayUsageCount = count
        UserDefaults.standard.set(count, forKey: "todayUsageCount")
    }

    func resetWelcomeAlertForTesting() {
        hasShownWelcomeEndedAlert = false
    }

    func setInstallDateForTesting(daysAgo: Int) {
        let testDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        KeychainDateStorage.saveInstallDate(testDate)
        UserDefaults.standard.set(testDate, forKey: "appInstallDate")
    }
    #endif
}

// ============================================================
// MARK: - 키체인 날짜 저장소
// ============================================================

/// 앱 설치 날짜를 키체인에 안전하게 저장하는 헬퍼
/// - 앱 삭제 후 재설치해도 데이터 유지
/// - 사용자가 날짜를 조작하기 어려움
private struct KeychainDateStorage {

    private static let service = "com.voicescheduler.installdate"
    private static let account = "installDate"

    /// 설치 날짜를 키체인에 저장
    static func saveInstallDate(_ date: Date) {
        // Date를 Data로 변환
        let dateData = withUnsafeBytes(of: date.timeIntervalSince1970) { Data($0) }

        // 기존 항목 삭제 (업데이트를 위해)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 새 항목 추가
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: dateData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            #if DEBUG
            print("⚠️ 키체인 저장 실패: \(status)")
            #endif
        }
    }

    /// 키체인에서 설치 날짜 읽기
    static func getInstallDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == MemoryLayout<TimeInterval>.size else {
            return nil
        }

        // Data를 TimeInterval로 변환
        let timeInterval = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        return Date(timeIntervalSince1970: timeInterval)
    }
}
