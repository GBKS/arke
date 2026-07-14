//
//  SignetFaucetService.swift
//  Arké
//
//  Created by Assistant on 1/23/26.
//

import Foundation

// MARK: - Faucet Response Models

enum FaucetStatus: String, Codable {
    case success
    case failed
    case rateLimited = "rate_limited"
    case insufficientFunds = "insufficient_funds"
    case invalidAddress = "invalid_address"
    case error
}

struct SignetFaucetResponse: Codable {
    let success: Bool
    let amount: Int?
    let data: FaucetData?
    let message: String?
    
    struct FaucetData: Codable {
        // The actual response from the Ark wallet API
        // Add fields as needed based on what the faucet returns
    }
    
    var isSuccess: Bool {
        success
    }
    
    // For backward compatibility - simulate rate limiting based on local tracking
    var retryAfter: Int? {
        nil // The new API doesn't provide this, will handle locally
    }
    
    var retryAfterTimeInterval: TimeInterval? {
        guard let seconds = retryAfter else { return nil }
        return TimeInterval(seconds)
    }
    
    var txid: String? {
        // Extract transaction ID from data if available
        nil
    }
}

// MARK: - Faucet Service

@Observable
@MainActor
class SignetFaucetService {
    
    // MARK: - Configuration
    
    /// Ark faucet endpoint
    private let faucetURL = "http://arke.cash/api/faucet"
    
    // MARK: - Dependencies
    
    private let urlSession: URLSession
    private let taskManager: TaskDeduplicationManager
    
    // MARK: - State
    
    var isRequesting = false
    var lastResponse: SignetFaucetResponse?
    var lastRequestDate: Date?
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager, urlSession: URLSession = .shared) {
        self.taskManager = taskManager
        self.urlSession = urlSession
    }
    
    // MARK: - Public API
    
    /// Request faucet funds from the Ark faucet
    /// - Parameter address: Ark address to receive the testnet coins (should start with 'ark1' or 'tark1')
    /// - Returns: Faucet response with status and details
    func requestFaucet(toAddress address: String) async throws -> SignetFaucetResponse {
        // Validate address format (basic check for Ark addresses)
        guard !address.isEmpty else {
            throw FaucetError.invalidAddress("Address cannot be empty")
        }
        
        guard address.hasPrefix("ark1") || address.hasPrefix("tark1") else {
            throw FaucetError.invalidAddress("Address must be a valid Ark address (starting with 'ark1' or 'tark1')")
        }
        
        // Check if we're rate limited from previous request
        if let lastRequest = lastRequestDate,
           let retryAfter = lastResponse?.retryAfterTimeInterval {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < retryAfter {
                let remainingTime = Int(retryAfter - timeSinceLastRequest)
                throw FaucetError.rateLimited(remainingSeconds: remainingTime)
            }
        }
        
        isRequesting = true
        defer { isRequesting = false }
        
        print("🚰 [SignetFaucetService] Requesting faucet for Ark address: \(address)")
        
        do {
            let response = try await performFaucetRequest(address: address)
            lastResponse = response
            lastRequestDate = Date()
            
            print("   ✅ Faucet response: success=\(response.success)")
            if let amount = response.amount {
                print("   💰 Amount: \(amount) sats")
            }
            if let txid = response.txid {
                print("   📝 Transaction ID: \(txid)")
            }
            
            return response
        } catch let error as FaucetError {
            print("   ❌ Faucet error: \(error.localizedDescription)")
            throw error
        } catch {
            print("   ❌ Unexpected error: \(error.localizedDescription)")
            throw FaucetError.networkError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func performFaucetRequest(address: String) async throws -> SignetFaucetResponse {
        // Construct request
        guard let url = URL(string: faucetURL) else {
            throw FaucetError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        
        // Request body
        let requestBody: [String: Any] = [
            "address": address
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Perform request
        let (data, response) = try await urlSession.data(for: request)
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FaucetError.invalidResponse
        }
        
        // Parse response
        let decoder = JSONDecoder()
        
        if (200...299).contains(httpResponse.statusCode) {
            // Success response
            let faucetResponse = try decoder.decode(SignetFaucetResponse.self, from: data)
            
            if faucetResponse.isSuccess {
                return faucetResponse
            } else {
                throw FaucetError.serverError(faucetResponse.message ?? "Request failed")
            }
        } else {
            // Error response - try to parse error message
            struct ErrorResponse: Codable {
                let message: String?
            }
            
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data),
               let message = errorResponse.message {
                // Check for specific error types
                if message.contains("Invalid Ark address") {
                    throw FaucetError.invalidAddress(message)
                } else {
                    throw FaucetError.serverError(message)
                }
            }
            throw FaucetError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Utility Methods
    
    /// Get remaining time before next request is allowed
    var remainingCooldownTime: TimeInterval? {
        guard let lastRequest = lastRequestDate,
              let retryAfter = lastResponse?.retryAfterTimeInterval else {
            return nil
        }
        
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
        let remaining = retryAfter - timeSinceLastRequest
        
        return remaining > 0 ? remaining : nil
    }
    
    /// Check if we can make a request right now
    var canMakeRequest: Bool {
        remainingCooldownTime == nil
    }
}

// MARK: - Faucet Errors

enum FaucetError: LocalizedError {
    case invalidAddress(String)
    case rateLimited(remainingSeconds: Int)
    case insufficientFunds(String)
    case serverError(String)
    case networkError(Error)
    case invalidResponse
    case invalidURL
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress(let message):
            return "Invalid Address: \(message)"
        case .rateLimited(let seconds):
            let minutes = seconds / 60
            if minutes > 0 {
                return String(localized: "error_faucet_rate_limited_minutes \(minutes)")
            } else {
                return String(localized: "error_faucet_rate_limited_seconds \(seconds)")
            }
        case .insufficientFunds(let message):
            return "Faucet Empty: \(message)"
        case .serverError(let message):
            return "Server Error: \(message)"
        case .networkError(let error):
            return "Network Error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from faucet server"
        case .invalidURL:
            return "Invalid faucet URL configuration"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        }
    }
}
