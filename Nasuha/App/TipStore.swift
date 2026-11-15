import StoreKit
import SwiftUI

/// Optional tips, paid through Apple. They unlock nothing.
@MainActor
@Observable
final class TipStore {
    static let productIDs = ["app.nasuha.ios.tip.small", "app.nasuha.ios.tip.medium", "app.nasuha.ios.tip.large"]

    /// Empty until the products load. While it is empty, the Support row stays hidden.
    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var didThank = false
    private(set) var failed = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        // Finish purchases that completed while the app was closed.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                    await MainActor.run { self?.didThank = true }
                }
            }
        }
    }

    var isAvailable: Bool { !products.isEmpty }

    func load() async {
        guard products.isEmpty else { return }
        let loaded = (try? await Product.products(for: Self.productIDs)) ?? []
        products = loaded.sorted { $0.price < $1.price }
    }

    func tip(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        failed = false
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                didThank = true
            case .success(.unverified), .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            failed = true
        }
    }
}
