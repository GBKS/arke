//
//  ShareHelper.swift
//  Arké
//
//  Created by Assistant on 4/23/26.
//

import SwiftUI
import UIKit

/// Helper for sharing multiple items using UIActivityViewController
struct ShareHelper {
    
    /// Presents the share sheet with multiple items
    /// - Parameters:
    ///   - items: The items to share (can be String, URL, Data, etc.)
    ///   - completion: Optional completion handler; `true` when the user
    ///     finished an activity (saved, sent, copied), `false` when the sheet
    ///     was dismissed or the activity failed. Called on the main thread.
    static func share(items: [Any], from viewController: UIViewController? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !items.isEmpty else { return }
        
        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        // Get the appropriate view controller to present from
        let presentingVC = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        
        // For iPad, configure popover presentation
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = presentingVC?.view
            popover.sourceRect = CGRect(
                x: presentingVC?.view.bounds.midX ?? 0,
                y: presentingVC?.view.bounds.midY ?? 0,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        
        activityViewController.completionWithItemsHandler = { _, completed, _, error in
            completion?(completed && error == nil)
        }
        
        presentingVC?.present(activityViewController, animated: true)
    }
}

/// A view modifier that adds a share action to a view
struct ShareButton: View {
    let items: [Any]
    let label: () -> AnyView
    
    init(items: [Any], @ViewBuilder label: @escaping () -> some View) {
        self.items = items
        self.label = { AnyView(label()) }
    }
    
    var body: some View {
        Button {
            ShareHelper.share(items: items)
        } label: {
            label()
        }
    }
}
