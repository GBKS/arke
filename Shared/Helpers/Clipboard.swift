//
//  Clipboard.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Cross-platform clipboard utility
public func copyToClipboard(_ string: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = string
    #endif
}

/// Copy a secret such as the recovery phrase. On iOS the item stays on this
/// device (it is not offered to other devices through Universal Clipboard)
/// and expires after `lifetime`.
public func copySecretToClipboard(_ string: String, lifetime: TimeInterval = 60) {
    #if os(macOS)
    copyToClipboard(string)
    #elseif os(iOS)
    UIPasteboard.general.setItems(
        [["public.utf8-plain-text": string]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(lifetime)]
    )
    #endif
}

