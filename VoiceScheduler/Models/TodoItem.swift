// TodoItem.swift
// 할 일 하나를 나타내는 데이터 모델입니다.

import Foundation
import SwiftUI

// 우선순위 열거형
enum Priority: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    /// 현재 언어로 번역된 우선순위 이름
    var localizedName: String {
        switch self {
        case .high: return L10n.priorityHigh
        case .medium: return L10n.priorityMedium
        case .low: return L10n.priorityLow
        }
    }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }

    var icon: String {
        switch self {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "circle.fill"
        case .low: return "arrow.down.circle.fill"
        }
    }
}

// 반복 주기 열거형
enum Recurrence: String, Codable, CaseIterable {
    case none = "none"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    /// 현재 언어로 번역된 반복 주기 이름
    var localizedName: String {
        switch self {
        case .none: return "recurrence_none".localized
        case .daily: return "recurrence_daily".localized
        case .weekly: return "recurrence_weekly".localized
        case .monthly: return "recurrence_monthly".localized
        case .yearly: return "recurrence_yearly".localized
        }
    }

    /// Google Calendar API용 RRULE 문자열
    var rrule: String? {
        switch self {
        case .none: return nil
        case .daily: return "RRULE:FREQ=DAILY"
        case .weekly: return "RRULE:FREQ=WEEKLY"
        case .monthly: return "RRULE:FREQ=MONTHLY"
        case .yearly: return "RRULE:FREQ=YEARLY"
        }
    }

    var icon: String {
        switch self {
        case .none: return "calendar"
        case .daily: return "arrow.clockwise"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar.circle"
        case .yearly: return "calendar.badge.exclamationmark"
        }
    }
}

// 할 일 아이템 구조체
struct TodoItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var description: String?
    var priority: Priority
    var estimatedDuration: Int = 60
    var suggestedHour: Int?
    var suggestedMinute: Int = 0  // 분 단위 (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
    var scheduledDate: Date = Date()  // 예정 날짜 (기본값: 오늘)
    var recurrence: Recurrence = .none  // 반복 주기 (기본값: 없음)
    var keywords: [String] = []
    var isCompleted: Bool = false
    var isScheduled: Bool = false

    /// 날짜를 보기 좋은 형식으로 반환
    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(scheduledDate) {
            return "today".localized
        } else if calendar.isDateInTomorrow(scheduledDate) {
            return "tomorrow".localized
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: scheduledDate)
        }
    }
}

// 샘플 데이터
extension TodoItem {
    static let sampleItems: [TodoItem] = [
        TodoItem(title: "태석이랑 미팅", description: "프로젝트 논의", priority: .high, estimatedDuration: 60, suggestedHour: 14, suggestedMinute: 30, scheduledDate: Date(), recurrence: .none, keywords: ["미팅"]),
        TodoItem(title: "저녁 운동", description: "헬스장", priority: .medium, estimatedDuration: 90, suggestedHour: 19, suggestedMinute: 0, scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(), recurrence: .weekly, keywords: ["운동"]),
        TodoItem(title: "장보기", description: "마트", priority: .low, estimatedDuration: 45, suggestedHour: 17, suggestedMinute: 15, scheduledDate: Date(), recurrence: .none, keywords: ["장보기"])
    ]
}
