// ReferralManager.swift
// 친구 초대 바이럴 시스템을 관리합니다.
// - 고유 초대 코드 생성
// - 초대 보상 지급 (초대자: 오늘 하루 무제한, 피초대자: 7일 프리미엄)
// - 초대 통계 관리

import Foundation
import SwiftUI
import Security

// ============================================================
// MARK: - 초대 관리자
// ============================================================

class ReferralManager: ObservableObject {
    static let shared = ReferralManager()

    // --------------------------------------------------------
    // MARK: - Published 프로퍼티
    // --------------------------------------------------------

    /// 현재 사용자의 고유 초대 코드
    @Published private(set) var myReferralCode: String = ""

    /// 성공한 초대 횟수
    @Published private(set) var successfulReferrals: Int = 0

    /// 오늘 하루 무제한 모드 활성화 여부
    @Published private(set) var isUnlimitedToday: Bool = false

    /// 보상 수령 축하 애니메이션 표시 여부
    @Published var showRewardCelebration: Bool = false

    /// 받은 보상 타입 (애니메이션용)
    @Published var receivedRewardType: RewardType = .unlimitedToday

    // --------------------------------------------------------
    // MARK: - 보상 타입 정의
    // --------------------------------------------------------

    enum RewardType {
        case unlimitedToday     // 초대자: 오늘 하루 무제한
        case premiumTrial       // 피초대자: 7일 프리미엄 체험

        var title: String {
            switch self {
            case .unlimitedToday:
                return "referral_reward_unlimited_title".localized
            case .premiumTrial:
                return "referral_reward_trial_title".localized
            }
        }

        var message: String {
            switch self {
            case .unlimitedToday:
                return "referral_reward_unlimited_message".localized
            case .premiumTrial:
                return "referral_reward_trial_message".localized
            }
        }

        var icon: String {
            switch self {
            case .unlimitedToday:
                return "infinity"
            case .premiumTrial:
                return "crown.fill"
            }
        }
    }

    // --------------------------------------------------------
    // MARK: - Private 프로퍼티
    // --------------------------------------------------------

    /// 무제한 모드 활성화 날짜 (당일만 유효)
    private var unlimitedActivationDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "unlimitedActivationDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "unlimitedActivationDate")
        }
    }

    /// 7일 프리미엄 체험 종료 날짜
    private var premiumTrialEndDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "premiumTrialEndDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "premiumTrialEndDate")
        }
    }

    /// 이미 사용한 초대 코드 (중복 방지)
    private var usedReferralCode: String? {
        get {
            UserDefaults.standard.string(forKey: "usedReferralCode")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "usedReferralCode")
        }
    }

    // --------------------------------------------------------
    // MARK: - 앱 스토어 URL (출시 후 수정 필요)
    // --------------------------------------------------------

    /// 앱 스토어 URL (출시 후 실제 URL로 교체)
    // TODO: App Store 출시 후 실제 App ID로 교체
    private let appStoreURL = "https://apps.apple.com/app/voicescheduler"

    // --------------------------------------------------------
    // MARK: - 초기화
    // --------------------------------------------------------

    private init() {
        // 저장된 초대 코드 불러오기 또는 새로 생성
        loadOrGenerateReferralCode()

        // 성공한 초대 횟수 불러오기
        successfulReferrals = UserDefaults.standard.integer(forKey: "successfulReferrals")

        // 오늘 무제한 모드 상태 확인
        checkUnlimitedTodayStatus()

        // 프리미엄 체험 상태 확인
        checkPremiumTrialStatus()
    }

    // --------------------------------------------------------
    // MARK: - 초대 코드 생성 및 관리
    // --------------------------------------------------------

    /// 초대 코드 불러오기 또는 새로 생성
    private func loadOrGenerateReferralCode() {
        // 키체인에서 먼저 확인
        if let savedCode = KeychainReferralStorage.getReferralCode() {
            myReferralCode = savedCode
            return
        }

        // UserDefaults에서 확인 (마이그레이션용)
        if let savedCode = UserDefaults.standard.string(forKey: "myReferralCode") {
            myReferralCode = savedCode
            KeychainReferralStorage.saveReferralCode(savedCode)
            return
        }

        // 새 코드 생성
        let newCode = generateUniqueCode()
        myReferralCode = newCode
        KeychainReferralStorage.saveReferralCode(newCode)
        UserDefaults.standard.set(newCode, forKey: "myReferralCode")
    }

    /// 고유한 초대 코드 생성 (6자리 영숫자)
    private func generateUniqueCode() -> String {
        // 디바이스 ID + 타임스탬프 기반으로 고유 코드 생성
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  // 혼동 방지 (0, O, 1, I 제외)
        let timestamp = Int(Date().timeIntervalSince1970)
        let deviceHash = UIDevice.current.identifierForVendor?.uuidString.hashValue ?? Int.random(in: 0...999999)

        // 시드 기반 랜덤 생성
        var code = ""
        var seed = abs(timestamp ^ deviceHash)

        for _ in 0..<6 {
            let index = seed % characters.count
            let char = characters[characters.index(characters.startIndex, offsetBy: index)]
            code.append(char)
            seed = seed / characters.count + Int.random(in: 1...100)
        }

        return code
    }

    // --------------------------------------------------------
    // MARK: - 초대 코드 적용 (피초대자)
    // --------------------------------------------------------

    /// 초대 코드 입력 및 보상 적용
    /// - Parameter code: 입력받은 초대 코드
    /// - Returns: 성공 여부와 메시지
    func applyReferralCode(_ code: String) -> (success: Bool, message: String) {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // 유효성 검사
        guard trimmedCode.count == 6 else {
            return (false, "referral_error_invalid_code".localized)
        }

        // 자기 자신의 코드인지 확인
        guard trimmedCode != myReferralCode else {
            return (false, "referral_error_own_code".localized)
        }

        // 이미 코드를 사용했는지 확인
        guard usedReferralCode == nil else {
            return (false, "referral_error_already_used".localized)
        }

        // 코드 적용 성공 - 7일 프리미엄 체험 부여
        usedReferralCode = trimmedCode
        grantPremiumTrial()

        // 축하 애니메이션 표시
        receivedRewardType = .premiumTrial
        showRewardCelebration = true

        return (true, "referral_success_applied".localized)
    }

    // --------------------------------------------------------
    // MARK: - 초대 성공 처리 (초대자)
    // --------------------------------------------------------

    /// 친구가 내 코드로 가입했을 때 호출 (서버 연동 시 사용)
    /// 현재는 로컬에서 시뮬레이션
    func onFriendJoined() {
        // 성공 횟수 증가
        successfulReferrals += 1
        UserDefaults.standard.set(successfulReferrals, forKey: "successfulReferrals")

        // 오늘 하루 무제한 보상 지급
        grantUnlimitedToday()

        // 축하 애니메이션 표시
        receivedRewardType = .unlimitedToday
        showRewardCelebration = true
    }

    /// 공유 후 보상 지급 (테스트/데모용)
    /// 실제 서비스에서는 서버에서 친구 가입 확인 후 지급
    func grantShareReward() {
        grantUnlimitedToday()
        receivedRewardType = .unlimitedToday
        showRewardCelebration = true
    }

    // --------------------------------------------------------
    // MARK: - 보상 지급
    // --------------------------------------------------------

    /// 오늘 하루 무제한 모드 활성화 (초대자 보상)
    private func grantUnlimitedToday() {
        unlimitedActivationDate = Date()
        isUnlimitedToday = true
        #if DEBUG
        print("🎁 초대 보상: 오늘 하루 무제한 활성화!")
        #endif
    }

    /// 7일 프리미엄 체험 부여 (피초대자 보상)
    private func grantPremiumTrial() {
        let trialEnd = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        premiumTrialEndDate = trialEnd
        SubscriptionManager.shared.activatePremium()
        #if DEBUG
        print("🎁 초대 보상: 7일 프리미엄 체험 시작! (종료: \(trialEnd))")
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 상태 확인
    // --------------------------------------------------------

    /// 오늘 무제한 모드 상태 확인 (날짜 변경 시 리셋)
    private func checkUnlimitedTodayStatus() {
        guard let activationDate = unlimitedActivationDate else {
            isUnlimitedToday = false
            return
        }

        // 오늘 활성화된 경우에만 유효
        isUnlimitedToday = Calendar.current.isDateInToday(activationDate)

        if !isUnlimitedToday {
            #if DEBUG
            print("📅 무제한 모드 만료됨 (어제 활성화)")
            #endif
        }
    }

    /// 프리미엄 체험 상태 확인 (만료 시 비활성화)
    private func checkPremiumTrialStatus() {
        guard let endDate = premiumTrialEndDate else { return }

        if Date() > endDate {
            // 체험 기간 만료
            premiumTrialEndDate = nil
            SubscriptionManager.shared.deactivatePremium()
            #if DEBUG
            print("📅 프리미엄 체험 만료됨")
            #endif
        }
    }

    /// 프리미엄 체험 중인지 확인
    var isInPremiumTrial: Bool {
        guard let endDate = premiumTrialEndDate else { return false }
        return Date() < endDate
    }

    /// 프리미엄 체험 남은 일수
    var premiumTrialDaysRemaining: Int {
        guard let endDate = premiumTrialEndDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(0, days)
    }

    // --------------------------------------------------------
    // MARK: - 공유 메시지 생성
    // --------------------------------------------------------

    /// 공유할 초대 메시지 생성
    func generateShareMessage() -> String {
        let message = String(format: "referral_share_message".localized, myReferralCode, appStoreURL)
        return message
    }

    /// 공유 아이템 배열 (ShareSheet용)
    func getShareItems() -> [Any] {
        return [generateShareMessage()]
    }
}

// ============================================================
// MARK: - 키체인 초대 코드 저장소
// ============================================================

/// 초대 코드를 키체인에 안전하게 저장하는 헬퍼
private struct KeychainReferralStorage {

    private static let service = "com.voicescheduler.referral"
    private static let account = "referralCode"

    /// 초대 코드를 키체인에 저장
    static func saveReferralCode(_ code: String) {
        guard let data = code.data(using: .utf8) else { return }

        // 기존 항목 삭제
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
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// 키체인에서 초대 코드 읽기
    static func getReferralCode() -> String? {
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
              let code = String(data: data, encoding: .utf8) else {
            return nil
        }

        return code
    }
}
