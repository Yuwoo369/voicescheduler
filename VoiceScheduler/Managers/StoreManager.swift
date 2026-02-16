// StoreManager.swift
// StoreKit 2를 사용한 인앱 결제 관리

import Foundation
import StoreKit

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // 상품 ID (App Store Connect에서 설정한 ID와 일치해야 함)
    static let premiumMonthlyID = "com.voicescheduler.premium.monthly"
    static let premiumYearlyID = "com.voicescheduler.premium.yearly"

    // 상품 목록
    @Published private(set) var products: [Product] = []

    // 구매된 상품 ID
    @Published private(set) var purchasedProductIDs: Set<String> = []

    // 로딩 상태
    @Published private(set) var isLoading = false

    // 에러 메시지
    @Published var errorMessage: String?

    // 구독 활성화 여부
    var isPremiumActive: Bool {
        !purchasedProductIDs.isEmpty
    }

    private var updateListenerTask: Task<Void, Error>?

    private init() {
        // 트랜잭션 업데이트 리스너 시작
        updateListenerTask = listenForTransactions()

        // 상품 로드 및 구매 상태 확인
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - 상품 로드

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let productIDs = [Self.premiumMonthlyID, Self.premiumYearlyID]
            products = try await Product.products(for: productIDs)
            products.sort { $0.price < $1.price }
            #if DEBUG
            print("✅ 상품 로드 완료: \(products.count)개")
            #endif
        } catch {
            #if DEBUG
            print("❌ 상품 로드 실패: \(error)")
            #endif
            errorMessage = "store_load_failed".localized
        }
    }

    // MARK: - 구매

    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()

            // SubscriptionManager 업데이트
            SubscriptionManager.shared.activatePremium()

            #if DEBUG
            print("✅ 구매 성공: \(product.id)")
            #endif
            return transaction

        case .userCancelled:
            #if DEBUG
            print("⚠️ 사용자가 구매를 취소했습니다.")
            #endif
            return nil

        case .pending:
            #if DEBUG
            print("⏳ 구매 대기 중 (승인 필요)")
            #endif
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - 구매 복원

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            #if DEBUG
            print("✅ 구매 복원 완료")
            #endif
        } catch {
            #if DEBUG
            print("❌ 구매 복원 실패: \(error)")
            #endif
            errorMessage = "store_restore_failed".localized
        }
    }

    // MARK: - 구매 상태 업데이트

    func updatePurchasedProducts() async {
        var purchasedIDs: Set<String> = []

        // 현재 자격(entitlements) 확인
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // 구독 상품인 경우
                if transaction.productType == .autoRenewable {
                    purchasedIDs.insert(transaction.productID)
                }
            } catch {
                #if DEBUG
                print("❌ 트랜잭션 검증 실패: \(error)")
                #endif
            }
        }

        purchasedProductIDs = purchasedIDs

        // SubscriptionManager 동기화
        if isPremiumActive {
            SubscriptionManager.shared.activatePremium()
        } else {
            SubscriptionManager.shared.deactivatePremium()
        }

        #if DEBUG
        print("📋 활성 구독: \(purchasedProductIDs)")
        #endif
    }

    // MARK: - 트랜잭션 리스너

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    #if DEBUG
                    print("❌ 트랜잭션 업데이트 실패: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - 검증

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - 구독 정보

    func getSubscriptionStatus() async -> Product.SubscriptionInfo.Status? {
        guard let product = products.first(where: { $0.type == .autoRenewable }) else {
            return nil
        }

        guard let statuses = try? await product.subscription?.status else {
            return nil
        }

        return statuses.first { $0.state == .subscribed || $0.state == .inGracePeriod }
    }

    // MARK: - 가격 포맷

    func formattedPrice(for product: Product) -> String {
        return product.displayPrice
    }

    func formattedPeriod(for product: Product) -> String {
        guard let subscription = product.subscription else { return "" }

        switch subscription.subscriptionPeriod.unit {
        case .month:
            return subscription.subscriptionPeriod.value == 1 ? "store_period_month".localized : "\(subscription.subscriptionPeriod.value)" + "store_period_month".localized
        case .year:
            return subscription.subscriptionPeriod.value == 1 ? "store_period_year".localized : "\(subscription.subscriptionPeriod.value)" + "store_period_year".localized
        case .week:
            return subscription.subscriptionPeriod.value == 1 ? "store_period_week".localized : "\(subscription.subscriptionPeriod.value)" + "store_period_week".localized
        case .day:
            return subscription.subscriptionPeriod.value == 1 ? "store_period_day".localized : "\(subscription.subscriptionPeriod.value)" + "store_period_day".localized
        @unknown default:
            return ""
        }
    }
}

// MARK: - 에러

enum StoreError: Error, LocalizedError {
    case failedVerification
    case productNotFound
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "store_verification_failed".localized
        case .productNotFound:
            return "store_product_not_found".localized
        case .purchaseFailed:
            return "store_purchase_failed".localized
        }
    }
}
