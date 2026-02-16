// LiquidGlassUI.swift
// 미니멀하고 세련된 Liquid Glass UI 컴포넌트
// - 유리 효과 카드
// - 부드러운 애니메이션
// - 그라데이션 글래스 효과

import SwiftUI

// ============================================================
// MARK: - Liquid Glass Card
// ============================================================

struct LiquidGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var glassOpacity: Double = 0.15
    var borderOpacity: Double = 0.3
    var shadowRadius: CGFloat = 20

    init(
        cornerRadius: CGFloat = 20,
        glassOpacity: Double = 0.15,
        borderOpacity: Double = 0.3,
        shadowRadius: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.glassOpacity = glassOpacity
        self.borderOpacity = borderOpacity
        self.shadowRadius = shadowRadius
    }

    var body: some View {
        content
            .background(
                ZStack {
                    // 유리 배경
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(0.8)

                    // 내부 그라데이션 광택
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(glassOpacity),
                                    Color.white.opacity(glassOpacity * 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 테두리 하이라이트
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(borderOpacity),
                                    Color.white.opacity(borderOpacity * 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.2), radius: shadowRadius, x: 0, y: 10)
    }
}

// ============================================================
// MARK: - Liquid Glass Button
// ============================================================

struct LiquidGlassButton: View {
    let title: String
    let icon: String?
    let gradient: [Color]
    let action: () -> Void

    @State private var isPressed = false
    @State private var shimmerOffset: CGFloat = -200

    init(
        title: String,
        icon: String? = nil,
        gradient: [Color] = [.blue, .purple],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.action = action
    }

    var body: some View {
        Button(action: {
            // 햅틱 피드백
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // 메인 그라데이션
                    LinearGradient(
                        colors: gradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    // 빛나는 효과 (shimmer)
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: shimmerOffset)
                    .mask(
                        RoundedRectangle(cornerRadius: 16)
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: gradient[0].opacity(0.4), radius: 15, x: 0, y: 8)
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onAppear {
            // Shimmer 애니메이션
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }
}

// ============================================================
// MARK: - Smart Time Slot Card
// ============================================================

struct SmartTimeSlotCard: View {
    let recommendation: SmartSchedulingService.TimeSlotRecommendation
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var appear = false
    @State private var glowOpacity: Double = 0

    var body: some View {
        Button(action: {
            SmartSchedulingService.shared.playRecommendationSelectHaptic()
            onSelect()
        }) {
            HStack(spacing: 16) {
                // 시간 표시
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.timeString)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    // 추천 이유
                    HStack(spacing: 4) {
                        Image(systemName: recommendation.reason.icon)
                            .font(.system(size: 11))
                        Text(recommendation.reason.localizedDescription)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // 점수 표시
                ZStack {
                    // 배경 원
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 50, height: 50)

                    // 점수 원 (애니메이션)
                    Circle()
                        .trim(from: 0, to: appear ? CGFloat(recommendation.overallScore) / 100 : 0)
                        .stroke(
                            LinearGradient(
                                colors: scoreGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))

                    // 점수 텍스트
                    Text("\(recommendation.overallScore)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                // 선택 표시
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // 유리 배경
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)

                    // 선택 시 글로우 효과
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.3), Color.blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    // 테두리
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isSelected
                                ? LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? .green.opacity(0.3) : .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                appear = true
            }
        }
    }

    private var scoreGradient: [Color] {
        let score = recommendation.overallScore
        if score >= 85 {
            return [.green, .cyan]
        } else if score >= 70 {
            return [.blue, .purple]
        } else if score >= 50 {
            return [.orange, .yellow]
        } else {
            return [.red, .orange]
        }
    }
}

// ============================================================
// MARK: - Slot Snap Animation View
// ============================================================

struct SlotSnapAnimationView: View {
    @Binding var isVisible: Bool
    let timeString: String

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 1

    var body: some View {
        ZStack {
            // 반투명 배경
            Color.black.opacity(opacity * 0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // 성공 링 애니메이션
                ZStack {
                    // 외부 링
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.green, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // 체크마크
                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                }

                // 시간 표시
                Text(timeString)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("smart_slot_confirmed".localized)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                showAnimation()
            }
        }
    }

    private func showAnimation() {
        // 등장 애니메이션
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
        }

        // 링 펄스 애니메이션
        withAnimation(.easeOut(duration: 0.6)) {
            ringScale = 1.5
            ringOpacity = 0
        }

        // 햅틱 피드백
        SmartSchedulingService.shared.playSlotSnapHaptic()

        // 자동 닫기
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                scale = 0.8
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isVisible = false
                // 상태 리셋
                scale = 0.5
                ringScale = 0.8
                ringOpacity = 1
            }
        }
    }
}

// ============================================================
// MARK: - Liquid Glass Time Picker
// ============================================================

struct LiquidGlassTimePicker: View {
    @Binding var selectedHour: Int
    @Binding var selectedMinute: Int
    let recommendations: [SmartSchedulingService.TimeSlotRecommendation]

    @State private var selectedRecommendationId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 헤더
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
                Text("smart_recommendations".localized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 4)

            // 추천 시간대 목록
            VStack(spacing: 12) {
                ForEach(recommendations) { recommendation in
                    SmartTimeSlotCard(
                        recommendation: recommendation,
                        isSelected: selectedRecommendationId == recommendation.id,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedRecommendationId = recommendation.id
                                selectedHour = recommendation.hour
                                selectedMinute = recommendation.minute
                            }
                        }
                    )
                }
            }

            // 직접 선택 옵션
            if !recommendations.isEmpty {
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                    Text("or".localized)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.vertical, 8)
            }

            // 수동 시간 선택
            HStack(spacing: 16) {
                // 시간 선택
                Picker("Hour", selection: $selectedHour) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)")
                            .tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60, height: 100)
                .clipped()

                Text(":")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                // 분 선택 (5분 단위)
                Picker("Minute", selection: $selectedMinute) {
                    ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { minute in
                        Text(String(format: "%02d", minute))
                            .tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60, height: 100)
                .clipped()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
        }
    }
}

// ============================================================
// MARK: - Floating Particles Background
// ============================================================

struct FloatingParticlesView: View {
    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: Double
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(particle.opacity), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: particle.size
                            )
                        )
                        .frame(width: particle.size * 2, height: particle.size * 2)
                        .position(x: particle.x, y: particle.y)
                }
            }
            .onAppear {
                generateParticles(in: geometry.size)
                animateParticles(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func generateParticles(in size: CGSize) {
        particles = (0..<20).map { _ in
            Particle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 2...6),
                opacity: Double.random(in: 0.1...0.3),
                speed: Double.random(in: 20...60)
            )
        }
    }

    private func animateParticles(in size: CGSize) {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            for i in particles.indices {
                particles[i].y -= CGFloat(particles[i].speed * 0.05)
                if particles[i].y < -20 {
                    particles[i].y = size.height + 20
                    particles[i].x = CGFloat.random(in: 0...size.width)
                }
            }
        }
    }
}

