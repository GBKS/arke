//
//  BalanceCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import ArkeUI
import Combine

struct BalanceCard: View {
    @Environment(WalletManager.self) private var walletManager
    @AppStorage(BitcoinAmountFormat.userDefaultsKey) private var formatPreference: BitcoinAmountFormat = .defaultFormat
    @AppStorage(UserDefaults.appThemeKey) private var theme: AppTheme = .defaultTheme

    let totalBalance: TotalBalanceModel?
    @Binding var isHidden: Bool
    
    @State private var isAnimating = false
    
    private var hiddenImageName: String {
        if isHidden {
            return theme.images.hiddenCard
        } else {
            return theme.images.card
        }
    }

    private var hiddenCardMaskName: String? {
        switch formatPreference {
        case .corn, .unicorn:
            return nil // easter-egg art has no holo mask
        default:
            return theme.images.hiddenCardMask
        }
    }
    
    var body: some View {
        ZStack {
            if isHidden {
                // Privacy mode - show "Arké" text centered with refresh tag in bottom-left
                ZStack(alignment: .bottomLeading) {
                    // Centered "Arké" text
                    Text(L10n.appName)
                        #if os(iOS)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        #else
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        #endif
                        .foregroundColor(theme.textColor)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Bottom-left aligned refresh tag
                    BalanceRefreshTag()
                        .padding(.bottom, 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Normal mode - show balance details
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "balance_your_balance", defaultValue: "Your Balance"))
                        #if os(iOS)
                        .font(.system(size: 24, weight: .semibold))
                        #else
                        .font(.system(size: 17, weight: .semibold))
                        #endif
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    /*
                        .opacity(isAnimating ? 0.5 : 1.0)
                        .animation(
                            isAnimating 
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .easeInOut(duration: 0.3),
                            value: isAnimating
                        )
                        .onChange(of: walletManager.isRefreshing) { oldValue, newValue in
                            withAnimation {
                                isAnimating = newValue
                            }
                        }
                    */
                    
                    Spacer()
                    
                    if let totalBalance = totalBalance {
                        BalanceRefreshTag()
                        
                        Text(BitcoinFormatter.shared.formatAmount(totalBalance.grandTotalSat))
                            #if os(iOS)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            #else
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            #endif
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                            .contentTransition(.numericText())
                            .animation(.smooth, value: totalBalance.grandTotalSat)
                    } else {
                        // Empty space to maintain card height
                        Spacer()
                            .frame(height: 40) // Approximate height to match the text + tag
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .aspectRatio(3/2, contentMode: .fit)
        .background {
            if isHidden {
                // Privacy mode - holo when the theme provides a hidden mask (iOS),
                // flat image otherwise (easter eggs, maskless themes, macOS)
                #if os(iOS)
                if let maskName = hiddenCardMaskName {
                    HoloCard_iOS(cardImageName: hiddenImageName, maskImageName: maskName)
                } else {
                    flatHiddenBackground
                }
                #else
                flatHiddenBackground
                #endif
            } else {
                // Normal mode - use HoloCard on iOS, regular card image on macOS
                #if os(iOS)
                HoloCard_iOS(cardImageName: theme.images.card, maskImageName: theme.images.cardMask)
                #else
                RoundedRectangle(cornerRadius: 15)
                    .overlay {
                        Image(theme.images.card)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                #endif
            }
        }
        .cornerRadius(15)
    }

    private var flatHiddenBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .overlay {
                Image(hiddenImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}
