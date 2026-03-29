// LocalizationManager.swift
// 다국어 지원을 위한 헬퍼 클래스와 확장입니다.

import Foundation
import SwiftUI
import Combine

// ============================================================
// MARK: - String Extension for Localization
// ============================================================

extension String {
    /// 현재 언어로 번역된 문자열을 반환합니다
    /// 사용법: "greeting".localized
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// 포맷 문자열을 현재 언어로 번역합니다
    /// 사용법: "minutes_format".localized(with: 30)
    func localized(with arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}

// ============================================================
// MARK: - Localization Manager
// ============================================================

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// 현재 언어 코드 (예: "ko", "en", "ja", "zh-Hans")
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "appLanguage")
        }
    }

    /// 지원하는 언어 목록
    static let supportedLanguages: [(code: String, name: String, flag: String)] = [
        ("en", "English", "🇺🇸"),
        ("ko", "한국어", "🇰🇷"),
        ("ja", "日本語", "🇯🇵"),
        ("zh-Hans", "简体中文", "🇨🇳"),
        ("pt-BR", "Português", "🇧🇷"),
        ("hi", "हिन्दी", "🇮🇳"),
        ("es", "Español", "🇪🇸")
    ]

    private init() {
        // 저장된 언어 또는 시스템 언어 사용
        if let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") {
            self.currentLanguage = savedLanguage
        } else {
            // 시스템 언어 감지
            let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"

            // 시스템 언어 코드 → 앱 언어 코드 매핑 (pt → pt-BR 등)
            let mapped = LocalizationManager.mapSystemLanguage(systemLanguage)
            self.currentLanguage = LocalizationManager.supportedLanguages.contains { $0.code == mapped }
                ? mapped
                : "en"
        }
    }

    /// 시스템 언어 코드를 앱 지원 언어 코드로 매핑
    private static func mapSystemLanguage(_ code: String) -> String {
        switch code {
        case "pt": return "pt-BR"
        case "zh": return "zh-Hans"
        default: return code
        }
    }

    /// Gemini AI 프롬프트에 사용할 언어 이름을 반환합니다
    var languageNameForAI: String {
        switch currentLanguage {
        case "ko": return "Korean"
        case "ja": return "Japanese"
        case "zh-Hans": return "Simplified Chinese"
        case "pt-BR": return "Brazilian Portuguese"
        case "hi": return "Hindi"
        case "es": return "Spanish"
        default: return "English"
        }
    }

    /// 시간 포맷을 언어에 맞게 반환합니다
    /// 예: 14시 → "오후 2시" (한국어), "2 PM" (영어)
    func formatHour(_ hour: Int) -> String {
        let isAM = hour < 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)

        switch currentLanguage {
        case "ko":
            return "\(isAM ? "오전" : "오후") \(displayHour)시"
        case "ja":
            return "\(isAM ? "午前" : "午後") \(displayHour)時"
        case "zh-Hans":
            return "\(isAM ? "上午" : "下午") \(displayHour)点"
        case "pt-BR":
            return "\(displayHour)h \(isAM ? "AM" : "PM")"
        case "hi":
            return "\(isAM ? "सुबह" : "शाम") \(displayHour) बजे"
        case "es":
            return "\(displayHour) \(isAM ? "AM" : "PM")"
        default:
            return "\(displayHour) \(isAM ? "AM" : "PM")"
        }
    }
}

// ============================================================
// MARK: - Localized Text Keys (타입 안전한 키 관리)
// ============================================================

enum L10n {
    // Common
    static var appName: String { "app_name".localized }
    static var appTagline: String { "app_tagline".localized }
    static var cancel: String { "cancel".localized }
    static var confirm: String { "confirm".localized }
    static var delete: String { "delete".localized }
    static var save: String { "save".localized }
    static var close: String { "close".localized }

    // Login
    static var loginGoogle: String { "login_google".localized }
    static var loginPermissionNotice: String { "login_permission_notice".localized }

    // Main Voice View
    static var greeting: String { "greeting".localized }
    static var listening: String { "listening".localized }
    static var speakSchedule: String { "speak_schedule".localized }
    static var addNewSchedule: String { "add_new_schedule".localized }
    static var whatToDo: String { "what_to_do".localized }
    static var speakFreely: String { "speak_freely".localized }
    static var tapMicInstruction: String { "tap_mic_instruction".localized }
    static var recognizedText: String { "recognized_text".localized }
    static var trySaying: String { "try_saying".localized }

    // Example Phrases
    static var exampleMeeting: String { "example_meeting".localized }
    static var exampleDeadline: String { "example_deadline".localized }
    static var exampleChores: String { "example_chores".localized }

    // Todo List
    static var extractedTasks: String { "extracted_tasks".localized }
    static var autoSchedule: String { "auto_schedule".localized }
    static var todaySchedule: String { "today_schedule".localized }
    static var minutes: String { "minutes".localized }
    static var today: String { "today".localized }
    static var tomorrow: String { "tomorrow".localized }

    // Priority
    static var priorityHigh: String { "priority_high".localized }
    static var priorityMedium: String { "priority_medium".localized }
    static var priorityLow: String { "priority_low".localized }

    // Analysis
    static var analyzing: String { "analyzing".localized }
    static var pleaseWait: String { "please_wait".localized }
    static var analysisFailed: String { "analysis_failed".localized }

    // Calendar
    static var calendarRegistered: String { "calendar_registered".localized }
    static var calendarFailed: String { "calendar_failed".localized }
    static var scheduleFull: String { "schedule_full".localized }
    static var loginRequired: String { "login_required".localized }
    static var googleCalendar: String { "google_calendar".localized }
    static var noTasksToRegister: String { "no_tasks_to_register".localized }
    static var tokenRefreshFailed: String { "token_refresh_failed".localized }
    static var allEventsRegistered: String { "all_events_registered".localized }
    static var partialEventsRegistered: String { "partial_events_registered".localized }
    static var eventRegistrationFailed: String { "event_registration_failed".localized }
    static var eventRegistrationError: String { "event_registration_error".localized }
    static var event: String { "event".localized }
    static var registered: String { "registered".localized }

    // Alerts
    static var alertNotice: String { "alert_notice".localized }
    static var alertError: String { "alert_error".localized }
    static var alertCompleted: String { "alert_completed".localized }
    static var alertPartial: String { "alert_partial".localized }

    // Voice Recognition
    static var voiceNotRecognized: String { "voice_not_recognized".localized }
    static var speechRecognitionFailed: String { "speech_recognition_failed".localized }
    static var rateLimitError: String { "rate_limit_error".localized }

    // Time Format
    static var am: String { "am".localized }
    static var pm: String { "pm".localized }
    static var hourSuffix: String { "hour_suffix".localized }

    // Subscription
    static var dailyLimitReachedTitle: String { "daily_limit_reached_title".localized }
    static var dailyLimitReachedMessage: String { "daily_limit_reached_message".localized }
    static var upgradeToPremium: String { "upgrade_to_premium".localized }
    static var remainingToday: String { "remaining_today".localized }
    static var times: String { "times".localized }
    static var restorePurchases: String { "restore_purchases".localized }
    static var subscriptionAutoRenew: String { "subscription_auto_renew".localized }
    static var subscriptionCancelAnytime: String { "subscription_cancel_anytime".localized }
    static var startPremium: String { "start_premium".localized }
    static var monthlySubscription: String { "monthly_subscription".localized }
    static var yearlySubscription: String { "yearly_subscription".localized }
    static var bestValue: String { "best_value".localized }
    static var monthlyDesc: String { "monthly_desc".localized }
    static var yearlyDesc: String { "yearly_desc".localized }
    static var benefitUnlimited: String { "benefit_unlimited".localized }
    static var benefitUnlimitedDesc: String { "benefit_unlimited_desc".localized }
    static var benefitPriority: String { "benefit_priority".localized }
    static var benefitPriorityDesc: String { "benefit_priority_desc".localized }
    static var benefitAdvanced: String { "benefit_advanced".localized }
    static var benefitAdvancedDesc: String { "benefit_advanced_desc".localized }
    static var benefitSupport: String { "benefit_support".localized }
    static var benefitSupportDesc: String { "benefit_support_desc".localized }

    // Welcome Benefit
    static var welcomeGift: String { "welcome_gift".localized }
    static var welcomeDaysRemaining: String { "welcome_days_remaining".localized }
    static var welcomeEndedTitle: String { "welcome_ended_title".localized }
    static var welcomeEndedMessage: String { "welcome_ended_message".localized }
    static var welcomeEndedCta: String { "welcome_ended_cta".localized }

    // Referral System
    static var referralInviteButton: String { "referral_invite_button".localized }
    static var referralShareMessage: String { "referral_share_message".localized }
    static var referralMyCode: String { "referral_my_code".localized }
    static var referralEnterCode: String { "referral_enter_code".localized }
    static var referralEnterCodePlaceholder: String { "referral_enter_code_placeholder".localized }
    static var referralApply: String { "referral_apply".localized }
    static var referralSuccessApplied: String { "referral_success_applied".localized }
    static var referralErrorInvalidCode: String { "referral_error_invalid_code".localized }
    static var referralErrorOwnCode: String { "referral_error_own_code".localized }
    static var referralErrorAlreadyUsed: String { "referral_error_already_used".localized }
    static var referralRewardUnlimitedTitle: String { "referral_reward_unlimited_title".localized }
    static var referralRewardUnlimitedMessage: String { "referral_reward_unlimited_message".localized }
    static var referralRewardTrialTitle: String { "referral_reward_trial_title".localized }
    static var referralRewardTrialMessage: String { "referral_reward_trial_message".localized }
    static var referralUnlimitedActive: String { "referral_unlimited_active".localized }

    // API Safety (안전장치)
    static var abnormalActivityBlocked: String { "abnormal_activity_blocked".localized }
    static var abnormalActivityDetected: String { "abnormal_activity_detected".localized }
    static var dailyTokenLimitReached: String { "daily_token_limit_reached".localized }
    static var budgetWarningMessage: String { "budget_warning_message".localized }

    // Demo Mode (데모 모드)
    static var demoMode: String { "demo_mode".localized }
    static var tryDemoMode: String { "try_demo_mode".localized }
    static var demoModeDescription: String { "demo_mode_description".localized }
    static var demoBanner: String { "demo_banner".localized }
    static var appleSignInBanner: String { "apple_sign_in_banner".localized }
    static var demoCalendarSimulated: String { "demo_calendar_simulated".localized }
    static var demoOr: String { "demo_or".localized }

    // Smart Scheduling (스마트 추천)
    static var smartRecommendations: String { "smart_recommendations".localized }
    static var smartSlotConfirmed: String { "smart_slot_confirmed".localized }
    static var smartReasonPeakFocus: String { "smart_reason_peak_focus".localized }
    static var smartReasonUserPattern: String { "smart_reason_user_pattern".localized }
    static var smartReasonPriorityMatch: String { "smart_reason_priority_match".localized }
    static var smartReasonFreeSlot: String { "smart_reason_free_slot".localized }
    static var smartReasonBalancedDay: String { "smart_reason_balanced_day".localized }
}
