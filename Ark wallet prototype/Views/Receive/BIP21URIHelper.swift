//
//  BIP21URIHelper.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import Foundation

struct BIP21URIHelper {
    // Helper method to create BIP 21 URI
    static func createBIP21URI(arkAddress: String? = nil, onchainAddress: String? = nil, amount: String? = nil, label: String? = nil, message: String? = nil) -> String {
        var components = URLComponents()
        components.scheme = "bitcoin"
        components.path = onchainAddress ?? ""
        
        var queryItems: [URLQueryItem] = []
        
        if let arkAddress = arkAddress {
            queryItems.append(URLQueryItem(name: "ark", value: arkAddress))
        }
        
        if let amount = amount {
            queryItems.append(URLQueryItem(name: "amount", value: amount))
        }
        
        if let label = label {
            queryItems.append(URLQueryItem(name: "label", value: label))
        }
        
        if let message = message {
            queryItems.append(URLQueryItem(name: "message", value: message))
        }
        
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        return components.url?.absoluteString ?? "bitcoin:\(onchainAddress ?? "")"
    }
}
