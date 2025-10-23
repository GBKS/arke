//
//  TotalBalanceModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

struct TotalBalanceModel: Codable {
    let arkBalance: ArkBalanceModel
    let onchainBalance: OnchainBalanceModel
    
    enum CodingKeys: String, CodingKey {
        case arkBalance = "ark_balance"
        case onchainBalance = "onchain_balance"
    }
    
    // MARK: - Combined Spendable Balance
    
    /// Total spendable balance in satoshis (Ark + Onchain trusted spendable)
    var totalSpendableSat: Int {
        arkBalance.spendableSat + onchainBalance.trustedSpendableSat
    }
    
    /// Total spendable balance in BTC
    var totalSpendableBTC: Double {
        Double(totalSpendableSat) / 100_000_000
    }
    
    // MARK: - Combined Confirmed Balance
    
    /// Total confirmed balance in satoshis (Ark spendable + Onchain confirmed)
    var totalConfirmedSat: Int {
        arkBalance.spendableSat + onchainBalance.confirmedSat
    }
    
    /// Total confirmed balance in BTC
    var totalConfirmedBTC: Double {
        Double(totalConfirmedSat) / 100_000_000
    }
    
    // MARK: - Combined Pending Balance
    
    /// Total pending balance in satoshis (Ark pending + Onchain pending)
    var totalPendingSat: Int {
        arkBalance.totalPendingSat + onchainBalance.trustedPendingSat + onchainBalance.untrustedPendingSat
    }
    
    /// Total pending balance in BTC
    var totalPendingBTC: Double {
        Double(totalPendingSat) / 100_000_000
    }
    
    // MARK: - Grand Total Balance
    
    /// Total balance in satoshis (everything combined)
    var grandTotalSat: Int {
        arkBalance.totalSat + onchainBalance.totalSat
    }
    
    /// Total balance in BTC
    var grandTotalBTC: Double {
        Double(grandTotalSat) / 100_000_000
    }
    
    // MARK: - Convenience Properties
    
    /// Returns true if there are any pending balances
    var hasPendingBalance: Bool {
        totalPendingSat > 0
    }
    
    /// Returns true if the user has spendable funds
    var hasSpendableBalance: Bool {
        totalSpendableSat > 0
    }
    
    // MARK: - Percentage Breakdown
    
    /// Percentage of total balance that's in Ark (0.0 to 1.0)
    var arkBalancePercentage: Double {
        guard grandTotalSat > 0 else { return 0.0 }
        return Double(arkBalance.totalSat) / Double(grandTotalSat)
    }
    
    /// Percentage of total balance that's onchain (0.0 to 1.0)
    var onchainBalancePercentage: Double {
        guard grandTotalSat > 0 else { return 0.0 }
        return Double(onchainBalance.totalSat) / Double(grandTotalSat)
    }
}

// MARK: - Convenience Initializer

extension TotalBalanceModel {
    /// Creates a TotalBalanceModel with default zero balances
    static var empty: TotalBalanceModel {
        TotalBalanceModel(
            arkBalance: ArkBalanceModel(
                spendableSat: 0,
                pendingLightningSendSat: 0,
                pendingInRoundSat: 0,
                pendingExitSat: 0,
                pendingBoardSat: 0
            ),
            onchainBalance: OnchainBalanceModel(
                totalSat: 0,
                trustedSpendableSat: 0,
                immatureSat: 0,
                trustedPendingSat: 0,
                untrustedPendingSat: 0,
                confirmedSat: 0
            )
        )
    }
}