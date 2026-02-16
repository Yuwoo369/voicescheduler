// SmartSchedulingService.swift
// 스마트 타임 슬롯 추천 서비스
// - 비어있는 시간대 분석
// - 집중력 최적 시간대 추천
// - 사용자 패턴 학습

import Foundation
import UIKit

// ============================================================
// MARK: - 스마트 스케줄링 서비스
// ============================================================

class SmartSchedulingService: ObservableObject {
    static let shared = SmartSchedulingService()

    // --------------------------------------------------------
    // MARK: - 집중력 시간대 설정
    // --------------------------------------------------------

    /// 시간대별 기본 집중력 점수 (0-100)
    /// 연구 기반: 오전 10-12시, 오후 2-4시가 가장 집중력이 높음
    private let defaultFocusScores: [Int: Int] = [
        0: 10, 1: 5, 2: 5, 3: 5, 4: 5, 5: 10,      // 새벽 (0-5시)
        6: 30, 7: 50, 8: 70, 9: 85,                 // 아침 (6-9시)
        10: 95, 11: 100,                            // 오전 피크 (10-11시)
        12: 60, 13: 50,                             // 점심 (12-13시)
        14: 85, 15: 90, 16: 80,                     // 오후 피크 (14-16시)
        17: 70, 18: 60,                             // 저녁 전환 (17-18시)
        19: 50, 20: 40, 21: 30,                     // 저녁 (19-21시)
        22: 20, 23: 15                              // 밤 (22-23시)
    ]

    /// 우선순위별 추천 시간대
    private let priorityPreferredHours: [Priority: [Int]] = [
        .high: [10, 11, 9, 14, 15],      // 높음: 오전 피크 우선
        .medium: [14, 15, 16, 10, 11],   // 보통: 오후 피크 우선
        .low: [17, 18, 19, 8, 7]         // 낮음: 저녁/아침 활용
    ]

    // --------------------------------------------------------
    // MARK: - 사용자 패턴 학습
    // --------------------------------------------------------

    /// 사용자별 시간대 선호도 (학습된 데이터)
    private var userFocusPatterns: [Int: Int] {
        get {
            if let data = UserDefaults.standard.dictionary(forKey: "userFocusPatterns") as? [String: Int] {
                var result: [Int: Int] = [:]
                for (key, value) in data {
                    if let hour = Int(key) {
                        result[hour] = value
                    }
                }
                return result
            }
            return [:]
        }
        set {
            var data: [String: Int] = [:]
            for (key, value) in newValue {
                data[String(key)] = value
            }
            UserDefaults.standard.set(data, forKey: "userFocusPatterns")
        }
    }

    /// 일정 완료 기록 (시간대별 성공률 학습용)
    func recordCompletedTask(at hour: Int) {
        var patterns = userFocusPatterns
        patterns[hour] = (patterns[hour] ?? 50) + 5  // 성공 시 점수 증가
        patterns[hour] = min(100, patterns[hour]!)
        userFocusPatterns = patterns
        #if DEBUG
        print("📊 학습: \(hour)시 완료 기록 (점수: \(patterns[hour]!))")
        #endif
    }

    // --------------------------------------------------------
    // MARK: - 추천 결과 모델
    // --------------------------------------------------------

    struct TimeSlotRecommendation: Identifiable {
        let id = UUID()
        let date: Date
        let hour: Int
        let minute: Int
        let focusScore: Int           // 집중력 점수 (0-100)
        let availabilityScore: Int    // 여유 점수 (0-100)
        let overallScore: Int         // 종합 점수 (0-100)
        let reason: RecommendationReason

        /// 추천 이유
        enum RecommendationReason {
            case peakFocus          // 집중력 최고 시간대
            case userPattern        // 사용자 패턴 기반
            case priorityMatch      // 우선순위에 맞는 시간대
            case freeSlot          // 여유 있는 시간대
            case balancedDay       // 하루 균형 배치

            var localizedDescription: String {
                switch self {
                case .peakFocus:
                    return "smart_reason_peak_focus".localized
                case .userPattern:
                    return "smart_reason_user_pattern".localized
                case .priorityMatch:
                    return "smart_reason_priority_match".localized
                case .freeSlot:
                    return "smart_reason_free_slot".localized
                case .balancedDay:
                    return "smart_reason_balanced_day".localized
                }
            }

            var icon: String {
                switch self {
                case .peakFocus: return "brain.head.profile"
                case .userPattern: return "chart.line.uptrend.xyaxis"
                case .priorityMatch: return "target"
                case .freeSlot: return "calendar.badge.clock"
                case .balancedDay: return "scale.3d"
                }
            }
        }

        /// 시간 표시 문자열
        var timeString: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
            formatter.dateFormat = "a h:mm"

            var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute

            if let date = Calendar.current.date(from: components) {
                return formatter.string(from: date)
            }
            return "\(hour):\(String(format: "%02d", minute))"
        }
    }

    // --------------------------------------------------------
    // MARK: - 스마트 추천 알고리즘
    // --------------------------------------------------------

    /// 최적의 시간대를 추천합니다
    /// - Parameters:
    ///   - task: 일정 항목
    ///   - existingEvents: 기존 일정 목록 (시간대별)
    ///   - date: 대상 날짜
    /// - Returns: 추천 시간대 목록 (최대 3개, 점수순)
    func recommendTimeSlots(
        for task: TodoItem,
        existingEvents: [Int: [String]],
        on date: Date
    ) -> [TimeSlotRecommendation] {
        var recommendations: [TimeSlotRecommendation] = []

        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // 오늘인지 확인
        let isToday = calendar.isDateInToday(date)

        // 작업 가능한 시간대 (7시 ~ 22시)
        // 오늘이면 현재 시간 이후부터, 아니면 7시부터
        let startHour = isToday ? max(7, currentHour + 1) : 7
        let workingHours = startHour...21

        // 추천 가능한 시간이 없으면 빈 배열 반환
        guard startHour <= 21 else { return [] }

        for hour in workingHours {
            // 1. 여유도 계산 (기존 일정과의 충돌 확인)
            let availabilityScore = calculateAvailabilityScore(
                hour: hour,
                duration: task.estimatedDuration,
                existingEvents: existingEvents
            )

            // 충돌 시간대는 제외
            guard availabilityScore > 0 else { continue }

            // 2. 집중력 점수 계산
            let focusScore = calculateFocusScore(hour: hour, priority: task.priority)

            // 3. 종합 점수 계산 (가중치: 집중력 60%, 여유도 40%)
            let overallScore = Int(Double(focusScore) * 0.6 + Double(availabilityScore) * 0.4)

            // 4. 추천 이유 결정
            let reason = determineReason(
                focusScore: focusScore,
                availabilityScore: availabilityScore,
                priority: task.priority,
                hour: hour
            )

            // 5. 추천 생성
            let recommendation = TimeSlotRecommendation(
                date: date,
                hour: hour,
                minute: task.suggestedMinute,
                focusScore: focusScore,
                availabilityScore: availabilityScore,
                overallScore: overallScore,
                reason: reason
            )

            recommendations.append(recommendation)
        }

        // 점수순 정렬 후 상위 3개 반환
        return recommendations
            .sorted { $0.overallScore > $1.overallScore }
            .prefix(3)
            .map { $0 }
    }

    /// 여유도 점수 계산
    private func calculateAvailabilityScore(
        hour: Int,
        duration: Int,
        existingEvents: [Int: [String]]
    ) -> Int {
        let durationHours = max(1, duration / 60)

        // 해당 시간대에 이미 일정이 있는지 확인
        for h in hour..<(hour + durationHours) {
            if let events = existingEvents[h], !events.isEmpty {
                return 0  // 충돌 - 사용 불가
            }
        }

        // 전후 1시간 여유 확인
        var score = 100
        if let prevEvents = existingEvents[hour - 1], !prevEvents.isEmpty {
            score -= 20  // 직전에 일정 있음
        }
        if let nextEvents = existingEvents[hour + durationHours], !nextEvents.isEmpty {
            score -= 20  // 직후에 일정 있음
        }

        // 하루 일정 밀도 확인
        let totalEvents = existingEvents.values.flatMap { $0 }.count
        if totalEvents > 5 {
            score -= 10  // 바쁜 날
        }

        return max(0, score)
    }

    /// 집중력 점수 계산
    private func calculateFocusScore(hour: Int, priority: Priority) -> Int {
        // 기본 집중력 점수
        var score = defaultFocusScores[hour] ?? 50

        // 사용자 패턴 반영 (학습된 데이터가 있으면 가중치 적용)
        if let userScore = userFocusPatterns[hour] {
            score = Int(Double(score) * 0.7 + Double(userScore) * 0.3)
        }

        // 우선순위별 선호 시간대 보너스
        if let preferredHours = priorityPreferredHours[priority] {
            if preferredHours.prefix(2).contains(hour) {
                score += 15  // 최우선 시간대
            } else if preferredHours.contains(hour) {
                score += 5   // 선호 시간대
            }
        }

        return min(100, score)
    }

    /// 추천 이유 결정
    private func determineReason(
        focusScore: Int,
        availabilityScore: Int,
        priority: Priority,
        hour: Int
    ) -> TimeSlotRecommendation.RecommendationReason {
        // 사용자 패턴이 강하게 반영된 경우
        if let userScore = userFocusPatterns[hour], userScore >= 80 {
            return .userPattern
        }

        // 피크 집중력 시간대
        if focusScore >= 90 {
            return .peakFocus
        }

        // 우선순위 매칭
        if let preferred = priorityPreferredHours[priority],
           preferred.prefix(2).contains(hour) {
            return .priorityMatch
        }

        // 여유 시간대
        if availabilityScore >= 90 {
            return .freeSlot
        }

        return .balancedDay
    }

    // --------------------------------------------------------
    // MARK: - 햅틱 피드백
    // --------------------------------------------------------

    /// "찰칵" 햅틱 피드백 (일정 배치 성공)
    func playSlotSnapHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        // 더블 탭 느낌을 위해 짧은 딜레이 후 한번 더
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let lightGenerator = UIImpactFeedbackGenerator(style: .light)
            lightGenerator.impactOccurred()
        }
    }

    /// 추천 선택 햅틱 (부드러운 피드백)
    func playRecommendationSelectHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    /// 성공 햅틱 (일정 등록 완료)
    func playSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    // --------------------------------------------------------
    // MARK: - 초기화
    // --------------------------------------------------------

    private init() {
        #if DEBUG
        print("🧠 SmartSchedulingService 초기화됨")
        #endif
    }
}

