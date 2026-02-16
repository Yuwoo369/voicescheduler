// CalendarTimelineView.swift
// 하루의 시간대를 타임라인 형태로 보여주는 뷰입니다.

import SwiftUI

struct CalendarTimelineView: View {

    @Binding var todoItems: [TodoItem]
    @Binding var displayDate: Date
    var refreshID: UUID
    var onDropItem: (TodoItem, Int) -> Void

    @State private var existingEvents: [CalendarEvent] = []
    @State private var selectedHour: Int?

    @EnvironmentObject var authManager: GoogleAuthManager

    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 60

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        let eventsAtHour = existingEvents.filter { $0.startHour == hour }
                        TimeSlotRow(
                            hour: hour,
                            isSelected: selectedHour == hour,
                            events: eventsAtHour,
                            onTap: {
                                selectedHour = hour
                            }
                        )
                        .frame(minHeight: hourHeight)
                        .id(hour)
                    }
                }
                .padding(.vertical, 8)
                .onAppear {
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    withAnimation {
                        proxy.scrollTo(max(currentHour - 1, startHour), anchor: .top)
                    }
                    loadExistingEvents()
                }
                .onChange(of: refreshID) { _ in
                    loadExistingEvents {
                        // 이벤트 로드 완료 후 등록 시간대로 스크롤
                        let targetHour: Int
                        if Calendar.current.isDateInToday(displayDate) {
                            targetHour = Calendar.current.component(.hour, from: Date())
                        } else if let firstEventHour = existingEvents.compactMap({ $0.startHour }).sorted().first {
                            targetHour = firstEventHour
                        } else {
                            targetHour = 9 // 기본값: 오전 9시
                        }
                        withAnimation {
                            proxy.scrollTo(max(targetHour - 1, startHour), anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func loadExistingEvents(completion: (() -> Void)? = nil) {
        let targetDate = displayDate
        authManager.getValidAccessToken { accessToken in
            guard let accessToken = accessToken else { return }

            GoogleCalendarService.shared.getEvents(for: targetDate, accessToken: accessToken) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let events):
                        self.existingEvents = events
                    case .failure(let error):
                        #if DEBUG
                        print("일정 불러오기 실패: \(error)")
                        #endif
                    }
                    completion?()
                }
            }
        }
    }
}

// 시간 슬롯 행
struct TimeSlotRow: View {
    let hour: Int
    let isSelected: Bool
    let events: [CalendarEvent]
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 시간 레이블 (더 선명하게)
            Text(formatHour(hour))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 55, alignment: .trailing)
                .padding(.top, 8)

            // 시간 슬롯
            VStack(alignment: .leading, spacing: 4) {
                if events.isEmpty {
                    // 일정이 없을 때 빈 슬롯
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.blue.opacity(0.25) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                        .frame(height: 44)
                } else {
                    // 일정이 있을 때 모든 일정 표시
                    ForEach(events, id: \.id) { event in
                        EventBlock(event: event)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                onTap()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func formatHour(_ hour: Int) -> String {
        return LocalizationManager.shared.formatHour(hour)
    }
}

// 일정 블록 (시각화 개선)
struct EventBlock: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 0) {
            // 왼쪽 색상 바
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)

            // 일정 내용
            VStack(alignment: .leading, spacing: 2) {
                // 제목
                Text(event.summary ?? L10n.event)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // 시간 정보
                if let startDate = event.startDate {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                        Text(formatEventTime(startDate))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 6)

            Spacer()

            // 캘린더 아이콘
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 14))
                .foregroundColor(.blue.opacity(0.8))
                .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.15))
        )
        .padding(4)
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    CalendarTimelineView(
        todoItems: .constant(TodoItem.sampleItems),
        displayDate: .constant(Date()),
        refreshID: UUID(),
        onDropItem: { item, hour in
            #if DEBUG
            print("드롭: \(item.title) → \(hour)시")
            #endif
        }
    )
    .frame(height: 500)
    .background(Color(red: 0.1, green: 0.1, blue: 0.2))
    .environmentObject(GoogleAuthManager())
}
