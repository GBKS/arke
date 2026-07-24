//
//  BarkWalletFFI+Maintenance.swift
//  Arke
//
//  Maintenance and refresh operations for wallet health
//  Handles automated and delegated VTXO refresh operations
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import OSLog

extension BarkWalletFFI {
    
    // MARK: - Maintenance Operations
    
    func maintenanceRefresh() async throws -> String? {
        // Perform maintenance refresh
        
        if isPreview {
            return nil
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Performing maintenance refresh via FFI...")
        
        do {
            let roundId = try await wallet.maintenanceRefresh()
            
            if let roundId = roundId {
                Self.logger.info("Maintenance refresh initiated, Round ID: \(roundId)")
            } else {
                Self.logger.info("Maintenance refresh completed (no refresh needed)")
            }
            
            return roundId
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error during maintenance refresh: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to perform maintenance refresh: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error during maintenance refresh: \(error)")
            throw error
        }
    }
    
    // MARK: - Delegated / Non-interactive Operations
    
    func maintenanceDelegated() async throws {
        // Schedules maintenance refresh operations without blocking
        
        if isPreview {
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Scheduling delegated maintenance via FFI...")
        
        do {
            try await wallet.maintenanceDelegated()
            Self.logger.info("Delegated maintenance scheduled")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error scheduling delegated maintenance: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to schedule delegated maintenance: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error scheduling delegated maintenance: \(error)")
            throw error
        }
    }
    
}
