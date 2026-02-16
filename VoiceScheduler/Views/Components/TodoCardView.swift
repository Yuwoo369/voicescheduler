// TodoCardView.swift
// 할 일 카드 컴포넌트입니다.
// Liquid Glass UI 디자인 적용
// 스마트 시간대 추천 기능 통합

import SwiftUI
import UIKit

struct TodoCardView: View {

    // 표시할 할 일 데이터 (Binding으로 수정 가능)
    @Binding var item: TodoItem

    // 편집 요청 콜백 (부모에서 처리)
    var onEditRequest: (() -> Void)? = nil

    // 스마트 추천 확장 상태
    @State private var showSmartRecommendations = false
    @State private var recommendations: [SmartSchedulingService.TimeSlotRecommendation] = []
    @State private var isLoadingRecommendations = false

    // 슬롯 스냅 애니메이션
    @State private var showSlotSnap = false
    @State private var selectedTimeString = ""

    var body: some View {
        VStack(spacing: 0) {
            // 메인 카드
            mainCardContent

            // 스마트 추천 패널 (확장 시)
            if showSmartRecommendations && !item.isScheduled {
                smartRecommendationsPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSmartRecommendations)
        // 슬롯 스냅 애니메이션 오버레이
        .overlay {
            if showSlotSnap {
                SlotSnapAnimationView(isVisible: $showSlotSnap, timeString: selectedTimeString)
            }
        }
    }

    // ============================================
    // MARK: - 메인 카드 내용
    // ============================================

    private var mainCardContent: some View {
        HStack(spacing: 14) {
            // 왼쪽: 우선순위 그라데이션 바
            priorityBar

            // 가운데: 할 일 내용
            VStack(alignment: .leading, spacing: 10) {
                // 제목 줄
                HStack {
                    Text(item.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Spacer()

                    // 소요 시간 (글래스 스타일)
                    Text("\(item.estimatedDuration)\(L10n.minutes)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .opacity(0.8)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                }

                // 하단 정보 (아이콘 + 텍스트)
                HStack(spacing: 14) {
                    // 날짜
                    infoChip(icon: "calendar", text: item.formattedDate, color: .cyan)

                    // 반복 주기
                    if item.recurrence != .none {
                        infoChip(icon: item.recurrence.icon, text: item.recurrence.localizedName, color: .purple)
                    }

                    // 추천 시간대
                    if let hour = item.suggestedHour {
                        infoChip(
                            icon: "clock.fill",
                            text: formatTime(hour: hour, minute: item.suggestedMinute),
                            color: .orange
                        )
                    }

                    Spacer()
                }
            }

            // 오른쪽: 상태/액션
            rightPanel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
    }

    // ============================================
    // MARK: - 스마트 추천 토글
    // ============================================

    private func toggleSmartRecommendations() {
        if showSmartRecommendations {
            showSmartRecommendations = false
        } else {
            showSmartRecommendations = true
            loadRecommendations()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // ============================================
    // MARK: - Liquid Glass 카드 배경
    // ============================================

    private var cardBackground: some View {
        ZStack {
            // 유리 효과 배경
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(item.isScheduled ? 0.4 : 0.6)

            // 내부 광택
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(item.isScheduled ? 0.03 : 0.08),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 우선순위 글로우 (미등록 시)
            if !item.isScheduled {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [priorityColor.opacity(0.1), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            // 테두리
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: item.isScheduled
                            ? [Color.green.opacity(0.4), Color.green.opacity(0.2)]
                            : [priorityColor.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: item.isScheduled ? 1.5 : 1
                )
        }
        .shadow(color: priorityColor.opacity(item.isScheduled ? 0 : 0.15), radius: 10, x: 0, y: 4)
    }

    // ============================================
    // MARK: - 우선순위 바
    // ============================================

    private var priorityBar: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [priorityColor, priorityColor.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 5)
            .shadow(color: priorityColor.opacity(0.5), radius: 4, x: 0, y: 0)
    }

    // ============================================
    // MARK: - 정보 칩
    // ============================================

    private func infoChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundColor(color)
    }

    // ============================================
    // MARK: - 오른쪽 패널
    // ============================================

    private var rightPanel: some View {
        VStack(spacing: 8) {
            if item.isScheduled {
                // 등록 완료 상태 + 편집 버튼
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 편집 버튼 (등록 완료 후에도 수정 가능)
                Button(action: openEditor) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                // 미등록: 스마트 추천 + 편집 + 우선순위

                // 🧠 스마트 추천 버튼 (눈에 띄게)
                Button(action: toggleSmartRecommendations) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: showSmartRecommendations
                                        ? [.cyan, .blue]
                                        : [.cyan.opacity(0.3), .blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)

                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .cyan.opacity(showSmartRecommendations ? 0.5 : 0.2), radius: 6, x: 0, y: 2)
                }

                // 편집 버튼
                Button(action: openEditor) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.5))
                }

                // 우선순위 버튼
                Button(action: cyclePriority) {
                    Text(item.priority.localizedName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(priorityColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(priorityColor.opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(priorityColor.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
    }

    // ============================================
    // MARK: - 편집 열기
    // ============================================

    private func openEditor() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onEditRequest?()
    }

    // ============================================
    // MARK: - 스마트 추천 패널
    // ============================================

    private var smartRecommendationsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(.cyan)
                Text(L10n.smartRecommendations)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()

                // 닫기 버튼
                Button(action: {
                    showSmartRecommendations = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // 추천 시간대 목록
            if isLoadingRecommendations {
                // 로딩 상태
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text(L10n.analyzing)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if recommendations.isEmpty {
                // 추천 없음
                Text("smart_reason_free_slot".localized)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(recommendations) { rec in
                    recommendationRow(rec)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private func recommendationRow(_ rec: SmartSchedulingService.TimeSlotRecommendation) -> some View {
        Button(action: {
            selectRecommendation(rec)
        }) {
            HStack(spacing: 12) {
                // 시간
                Text(rec.timeString)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // 추천 이유
                HStack(spacing: 4) {
                    Image(systemName: rec.reason.icon)
                        .font(.system(size: 10))
                    Text(rec.reason.localizedDescription)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.6))

                Spacer()

                // 점수
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 36, height: 36)

                    Circle()
                        .trim(from: 0, to: CGFloat(rec.overallScore) / 100)
                        .stroke(scoreColor(rec.overallScore), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))

                    Text("\(rec.overallScore)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return .green }
        else if score >= 70 { return .cyan }
        else if score >= 50 { return .orange }
        else { return .red }
    }

    // ============================================
    // MARK: - 추천 선택
    // ============================================

    private func selectRecommendation(_ rec: SmartSchedulingService.TimeSlotRecommendation) {
        // 햅틱 피드백
        SmartSchedulingService.shared.playSlotSnapHaptic()

        // 시간 업데이트
        item.suggestedHour = rec.hour
        item.suggestedMinute = rec.minute

        // 애니메이션 표시
        selectedTimeString = rec.timeString
        showSlotSnap = true

        // 패널 닫기
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showSmartRecommendations = false
        }
    }

    // ============================================
    // MARK: - 추천 로드
    // ============================================

    private func loadRecommendations() {
        isLoadingRecommendations = true
        recommendations = []

        // 실제로는 캘린더에서 기존 일정을 가져와야 함
        let existingEvents: [Int: [String]] = [:]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let newRecommendations = SmartSchedulingService.shared.recommendTimeSlots(
                for: self.item,
                existingEvents: existingEvents,
                on: self.item.scheduledDate
            )
            self.recommendations = newRecommendations
            self.isLoadingRecommendations = false
        }
    }

    // ============================================
    // MARK: - 시간 포맷팅
    // ============================================

    private func formatTime(hour: Int, minute: Int) -> String {
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

    // ============================================
    // MARK: - 우선순위별 색상
    // ============================================

    private var priorityColor: Color {
        switch item.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }

    // ============================================
    // MARK: - 우선순위 순환 변경
    // ============================================

    private func cyclePriority() {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch item.priority {
            case .high: item.priority = .medium
            case .medium: item.priority = .low
            case .low: item.priority = .high
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// ============================================
// MARK: - 제목 편집 뷰 (Liquid Glass Style)
// ============================================

struct EditTitleView: View {
    let originalTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var editedTitle: String = ""

    var body: some View {
        ZStack {
            // 배경 그라데이션
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.08, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // 헤더
                HStack {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCancel()
                    }) {
                        Text(L10n.cancel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.cyan)
                    }

                    Spacer()

                    Text("edit_title".localized)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSave(editedTitle)
                    }) {
                        Text(L10n.save)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.cyan, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .shadow(color: .cyan.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // 입력 필드 (Liquid Glass 스타일)
                VStack(alignment: .leading, spacing: 8) {
                    Text("edit_title".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.leading, 4)

                    TextField("", text: $editedTitle)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.6)

                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.08),
                                                Color.white.opacity(0.02)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.cyan.opacity(0.5),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        )
                        .shadow(color: .cyan.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .onAppear {
            editedTitle = originalTitle
        }
    }
}

// ============================================
// MARK: - 미리보기
// ============================================

#Preview {
    VStack(spacing: 16) {
        TodoCardView(item: .constant(TodoItem.sampleItems[0]))
        TodoCardView(item: .constant(TodoItem.sampleItems[1]))
    }
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.12))
}
