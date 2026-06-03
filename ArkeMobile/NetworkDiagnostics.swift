//
//  NetworkDiagnostics.swift
//  Arké
//
//  Created by Christoph on 12/1/25.
//

import Foundation
import OSLog

class NetworkDiagnostics {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "NetworkDiagnostics")

    func runAllTests() {
        Self.logger.debug("=== Starting Network Diagnostics ===")
        
        /*
        // Test 1: Enable detailed logging
        print("Enabling network debug logging...")
        enableNetworkDebugLogging()
        print("✅ Logging enabled\n")
        
        // Test 2: Basic HTTPS (control test)
        print("Test 2: Basic HTTPS to httpbin.org")
        let httpsResult = testHttpsRequest(testUrl: "https://httpbin.org/get")
        print(httpsResult)
        print()
        
        // Test 3: TLS/ALPN to ARK server
        print("Test 3: TLS/ALPN negotiation with ARK server")
        let tlsResult = testTlsAlpn(serverUrl: "https://ark.signet.2nd.dev")
        print(tlsResult)
        print()
        
        // Test 4: Short timeout connection
        print("Test 4: Connection with 5s timeout")
        let timeout5 = testConnectionWithTimeout(
            serverUrl: "https://ark.signet.2nd.dev",
            timeoutSecs: 5
        )
        print(timeout5)
        print()
        
        // Test 5: Medium timeout connection
        print("Test 5: Connection with 30s timeout")
        let timeout30 = testConnectionWithTimeout(
            serverUrl: "https://ark.signet.2nd.dev",
            timeoutSecs: 30
        )
        print(timeout30)
        print()
        
        // Test 6: Full ARK connection
        print("Test 6: Full ARK connection test")
        let arkResult = testArkConnection(serverUrl: "https://ark.signet.2nd.dev")
        print(arkResult)
        print()
        
        print("=== Diagnostics Complete ===\n")
         
         */
    }
}
