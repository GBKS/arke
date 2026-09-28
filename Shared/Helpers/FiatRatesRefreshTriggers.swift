//
//  FiatRatesRefreshTriggers.swift
//  Arké
//
//  The foreground refresh triggers for RatesService, attached to the
//  wallet UI root so they only run once a wallet exists
//  (Docs/Features/Fiat_Rates.md): a gated check on appearance and on
//  every return to `.active`, plus the 5-minute loop while active,
//  cancelled on `.background`. No background fetch, no push-triggered
//  fetch — by design.
//

import SwiftUI

struct FiatRatesRefreshTriggers: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ratesService) private var ratesService

    func body(content: Content) -> some View {
        content
            .task {
                await ratesService.refreshIfDue()
                ratesService.startPeriodicRefresh()
            }
            .onDisappear {
                ratesService.stopPeriodicRefresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    ratesService.startPeriodicRefresh()
                    Task { await ratesService.refreshIfDue() }
                case .background:
                    ratesService.stopPeriodicRefresh()
                default:
                    break
                }
            }
    }
}

extension View {
    /// Drive exchange-rate refreshes from this view's lifetime and scene phase
    func fiatRatesRefreshTriggers() -> some View {
        modifier(FiatRatesRefreshTriggers())
    }
}
