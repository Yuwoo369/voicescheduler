// PremiumSubscriptionView.swift
// 프리미엄 구독 화면

import SwiftUI
import StoreKit

struct PremiumSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreManager.shared

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // 배경 그라데이션
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // 닫기 버튼
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal)

                    // 프리미엄 아이콘
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .orange.opacity(0.5), radius: 20)

                    // 제목
                    VStack(spacing: 8) {
                        Text("Voice Scheduler")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Premium")
                            .font(.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }

                    // 혜택 목록
                    VStack(alignment: .leading, spacing: 16) {
                        BenefitRow(
                            icon: "infinity",
                            title: L10n.benefitUnlimited,
                            description: L10n.benefitUnlimitedDesc
                        )

                        BenefitRow(
                            icon: "bolt.fill",
                            title: L10n.benefitPriority,
                            description: L10n.benefitPriorityDesc
                        )

                        BenefitRow(
                            icon: "sparkles",
                            title: L10n.benefitAdvanced,
                            description: L10n.benefitAdvancedDesc
                        )

                        BenefitRow(
                            icon: "heart.fill",
                            title: L10n.benefitSupport,
                            description: L10n.benefitSupportDesc
                        )
                    }
                    .padding(.horizontal, 24)

                    // 구독 옵션
                    VStack(spacing: 12) {
                        ForEach(storeManager.products, id: \.id) { product in
                            SubscriptionOptionCard(
                                product: product,
                                isSelected: selectedProduct?.id == product.id,
                                storeManager: storeManager
                            ) {
                                selectedProduct = product
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 구매 버튼
                    Button(action: {
                        Task {
                            await purchase()
                        }
                    }) {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text(L10n.startPremium)
                                    .font(.headline)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: selectedProduct != nil ? [.orange, .pink] : [.gray, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .disabled(selectedProduct == nil || isPurchasing)
                    .padding(.horizontal)

                    // 구매 복원
                    Button(action: {
                        Task {
                            await storeManager.restorePurchases()
                        }
                    }) {
                        Text(L10n.restorePurchases)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    // 약관
                    VStack(spacing: 4) {
                        Text(L10n.subscriptionAutoRenew)
                        Text(L10n.subscriptionCancelAnytime)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
        }
        .alert(L10n.alertError, isPresented: $showError) {
            Button(L10n.confirm, role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // 연간 구독을 기본 선택 (더 좋은 가치)
            if selectedProduct == nil {
                // 연간 상품 우선 선택, 없으면 첫 번째 상품
                if let yearly = storeManager.products.first(where: { $0.id == StoreManager.premiumYearlyID }) {
                    selectedProduct = yearly
                } else if let first = storeManager.products.first {
                    selectedProduct = first
                }
            }
        }
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            if let _ = try await storeManager.purchase(product) {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 혜택 행

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }
}

// MARK: - 구독 옵션 카드

struct SubscriptionOptionCard: View {
    let product: Product
    let isSelected: Bool
    let storeManager: StoreManager
    let onSelect: () -> Void

    private var isYearly: Bool {
        product.id == StoreManager.premiumYearlyID
    }

    private var discountPercent: Int {
        guard isYearly,
              let monthlyProduct = storeManager.products.first(where: { $0.id == StoreManager.premiumMonthlyID }) else { return 0 }
        let originalYearly = NSDecimalNumber(decimal: monthlyProduct.price * 12).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: product.price).doubleValue
        guard originalYearly > 0 else { return 0 }
        return Int(((originalYearly - yearlyPrice) / originalYearly * 100).rounded())
    }

    private var originalYearlyPrice: String? {
        guard isYearly,
              let monthlyProduct = storeManager.products.first(where: { $0.id == StoreManager.premiumMonthlyID }) else { return nil }
        let originalPrice = monthlyProduct.price * 12
        return originalPrice.formatted(.currency(code: product.priceFormatStyle.currencyCode ?? "USD"))
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isYearly ? L10n.yearlySubscription : L10n.monthlySubscription)
                            .font(.headline)
                            .foregroundColor(.white)

                        if isYearly, discountPercent > 0 {
                            Text("-\(discountPercent)%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [Color.red, Color.orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(4)
                        }
                    }

                    if isYearly {
                        // 연간 구독: 월 환산 가격 강조
                        HStack(spacing: 4) {
                            Text(L10n.yearlyDesc)
                                .font(.caption)
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                    } else {
                        Text(L10n.monthlyDesc)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if isYearly, let priceText = originalYearlyPrice {
                        Text(priceText)
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Text(product.displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(isYearly ? .green : .white)

                    Text("/ \(storeManager.formattedPeriod(for: product))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? (isYearly ? Color.green.opacity(0.15) : Color.orange.opacity(0.2)) : Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ? (isYearly ? Color.green : Color.orange) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
    }
}

// MARK: - 미리보기

#Preview {
    PremiumSubscriptionView()
}
