//
//  TransactionSwipeCard.swift
//  Arké
//
//  Created by Christoph on 7/27/26.
//

import SwiftUI
import SwiftData
import UIKit
import ArkeUI

/// A single card in the transaction card stack: dark patterned header with
/// amount and date, light lower section with contact, tags, notes, and a
/// details button.
struct TransactionSwipeCard: View, Equatable {
    let transaction: TransactionModel
    let onShowDetails: () -> Void

    @Environment(\.modelContext) private var modelContext

    // Fee lookup queries linked transactions via the model context; resolved
    // once on appear so drag-frame re-renders don't repeat it
    @State private var feeText: String?
    @State private var hasFees = false

    // Skips body re-evaluation during drags, where only the offset/scale
    // modifiers outside this view change. Contacts and tags feed the header
    // icon, so they participate alongside identity; everything else the body
    // reads is immutable for a given txid or observed by the subviews.
    static func == (lhs: TransactionSwipeCard, rhs: TransactionSwipeCard) -> Bool {
        lhs.transaction.txid == rhs.transaction.txid
            && lhs.transaction.associatedContacts == rhs.transaction.associatedContacts
            && lhs.transaction.associatedTags == rhs.transaction.associatedTags
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            lowerSection
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            hideKeyboard()
        }
        .onAppear {
            if transaction.transactionType == .sent || transaction.transactionType == .transfer {
                hasFees = transaction.totalFeesIncludingLinked(modelContext: modelContext) > 0
                feeText = transaction.formattedTotalFeesIncludingLinked(modelContext: modelContext) ?? BitcoinFormatter.shared.formatAmount(0)
            }
        }
    }

    // MARK: Header (dark, patterned)

    private var headerView: some View {
        VStack(spacing: 8) {
            TransactionIconView(transaction: transaction, size: 72, onDark: true)
                .padding(.bottom, 8)
            
            VStack(alignment: .center, spacing: 0) {
                Text(transaction.shortDisplayText(includeStatusPrefix: true))
                    .font(.system(.title2, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                
                if transaction.category != .refresh {
                    Text(transaction.formattedDisplayAmount)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(headerAmountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }

            VStack(spacing: 4) {
                if transaction.isInternalTransfer {
                    Text(transaction.detailedDisplayText(includeStatusPrefix: true))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 4) {
                    if let feeText {
                        Text(hasFees ? "\(feeText) fee" : String(localized: "label_no_fee"))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.75))

                        Text("symbol_middot")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    Text(transaction.formattedDate)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background {
            Color(hex: "#1C1C1C")

            Image(patternImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .opacity(0.15)

            // Subtle edge highlight against the dark backdrop; the bottom
            // edge is open where the light section begins
            TopEdgeBorder(cornerRadius: 28)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: Lower section (light, quick actions)

    private var lowerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TransactionNotesSection(transaction: transaction)
            
            TransactionContactView(
                transaction: transaction,
                onNavigateToContact: nil
            )

            TransactionTagView(
                transaction: transaction,
                onNavigateToTag: nil
            )

            Spacer(minLength: 0)

            Button {
                onShowDetails()
            } label: {
                HStack(spacing: 4) {
                    Text("label_details")
                        .font(.body)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var headerAmountColor: Color {
        let color = amountColor
        return (color == .black || color == .primary) ? .white : color
    }

    private var amountColor: Color {
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        if transaction.hasUnilateralExit {
            if transaction.isExitComplete {
                return transaction.isInternalTransfer ? .primary : transaction.transactionType.amountColor
            }
            return .Arke.blue
        }

        switch transaction.transactionStatus {
        case .confirmed:
            return transaction.isInternalTransfer ? .primary : transaction.transactionType.amountColor
        case .pending:
            return .Arke.blue
        case .failed:
            return .Arke.red
        case .cancelled:
            return .gray
        }
    }

    private var patternImageName: String {
        switch transaction.category {
        case .boarding, .exit, .offboarding, .refresh:
            return "circle-pattern-gold"
        case .onchainSend, .onchainTransaction:
            return "block-pattern-gold"
        case .lightningSend, .lightningReceive:
            return "lightning-pattern-gold"
        default:
            return "wave-pattern-gold"
        }
    }
}

/// Open path along the left, top, and right edges, following the top corner
/// radii — no bottom edge, so it can outline just the dark header of a card.
private struct TopEdgeBorder: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// The keyboard toolbar's Done button doesn't surface inside a fullScreenCover
// without a NavigationStack, so the note field's keyboard is dismissed by
// resigning first responder on card taps and at drag start. Also used by
// TransactionCardStackView_iOS.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
