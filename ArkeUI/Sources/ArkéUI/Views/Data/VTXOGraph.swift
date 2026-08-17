//
//  VTXOGraph.swift
//  ArkéUI
//
//  Created by Christoph on 7/7/26.
//  Horizontal bar graph visualizing the lifecycle of the wallet's VTXOs.
//  Each bar is a VTXO; its width is the time left until expiry relative to
//  the horizon (the server's full VTXO lifetime, so a freshly refreshed
//  VTXO spans the full width). A light blue zone on the left marks the
//  window in which refreshes are free, per the server's fee schedule.
//  Bar color reflects the cost of unilaterally exiting the VTXO, from
//  green (cheap) to pink (expensive).
//

import SwiftUI

public struct VTXOGraph: View {
    let vtxos: [VTXOModel]
    let currentBlockHeight: Int
    let now: Date
    let horizonBlocks: Int?
    let freeRefreshBlocks: Int?
    let maxExitDepth: Int?
    let onSelect: ((VTXOModel) -> Void)?

    private let barHeight: CGFloat = 28
    private let barSpacing: CGFloat = 10

    /// Blocks are assumed to arrive every 10 minutes on all networks,
    /// matching `BlockTimeFormatter` on the app side.
    private static let blocksPerDay = 144.0

    /// Fallbacks for when the server's ark info isn't available.
    private static let defaultHorizonBlocks = 30 * 144
    private static let defaultMaxExitDepth = 12

    /// Nominal weight of a single transaction in an exit chain, used to
    /// derive the worst-case exit weight (`maxExitDepth` transactions of
    /// this size) that anchors the cost coloring.
    private static let nominalTxWeightWu = 500.0

    /// - Parameters:
    ///   - horizonBlocks: Full VTXO lifetime in blocks (`vtxoExpiryDelta`
    ///     from the ark info); the graph's horizontal axis spans this range.
    ///   - freeRefreshBlocks: Size of the free refresh window in blocks
    ///     (`freeRefreshBlocks` from the fee schedule's refresh structure).
    ///     Pass `nil` to hide the free refresh zone.
    ///   - maxExitDepth: The server's `maxVtxoExitDepth`, anchoring the
    ///     worst-case scale of the exit-cost bar coloring.
    public init(
        vtxos: [VTXOModel],
        currentBlockHeight: Int,
        now: Date = .now,
        horizonBlocks: Int? = nil,
        freeRefreshBlocks: Int? = nil,
        maxExitDepth: Int? = nil,
        onSelect: ((VTXOModel) -> Void)? = nil
    ) {
        self.vtxos = vtxos
        self.currentBlockHeight = currentBlockHeight
        self.now = now
        self.horizonBlocks = horizonBlocks
        self.freeRefreshBlocks = freeRefreshBlocks
        self.maxExitDepth = maxExitDepth
        self.onSelect = onSelect
    }

    private struct GraphEntry: Identifiable {
        let vtxo: VTXOModel
        let daysLeft: Double
        var id: String { vtxo.id }
    }

    private var resolvedHorizonBlocks: Int {
        horizonBlocks ?? Self.defaultHorizonBlocks
    }

    private var horizonDays: Double {
        Double(resolvedHorizonBlocks) / Self.blocksPerDay
    }

    /// Fraction of the graph width covered by the free refresh zone,
    /// or nil when the server never offers free refreshes.
    private var freeRefreshFraction: Double? {
        guard let freeRefreshBlocks, freeRefreshBlocks > 0 else { return nil }
        return min(Double(freeRefreshBlocks) / Double(resolvedHorizonBlocks), 1)
    }

    private var entries: [GraphEntry] {
        vtxos
            .filter { !$0.isSpent && $0.state != .exited }
            .map { GraphEntry(vtxo: $0, daysLeft: daysLeft(for: $0)) }
            .sorted { $0.daysLeft < $1.daysLeft }
    }

    /// How costly a unilateral exit of this VTXO would be, from 0 (cheap)
    /// to 1 (expensive). Onchain fees are paid on weight, so the weight of
    /// the exit transaction chain (`exitTxWeightWu`) is the cost measure,
    /// normalized against a fixed worst case of `maxExitDepth` transactions
    /// at a nominal weight each.
    ///
    /// The app has no fee rate source yet, so this is a relative measure.
    /// Once fee rates are available, consider coloring by the cost-to-value
    /// ratio instead (estimated exit fee in sats relative to `amountSat`),
    /// which would flag VTXOs that aren't worth exiting.
    private func exitCostFraction(for vtxo: VTXOModel) -> Double {
        let depthLimit = maxExitDepth ?? Self.defaultMaxExitDepth
        let worstCaseWeight = Double(depthLimit) * Self.nominalTxWeightWu
        guard worstCaseWeight > 0 else { return 0 }
        return min(Double(vtxo.exitTxWeightWu) / worstCaseWeight, 1)
    }

    private var horizonDate: Date {
        now.addingTimeInterval(horizonDays * 24 * 60 * 60)
    }

    private func daysLeft(for vtxo: VTXOModel) -> Double {
        let blocksLeft = Double(vtxo.expiryHeight - currentBlockHeight)
        return min(max(blocksLeft / Self.blocksPerDay, 0), horizonDays)
    }

    public var body: some View {
        let entries = self.entries

        if entries.isEmpty {
            emptyState
        } else {
            graph(entries: entries)
        }
    }

    private var emptyState: some View {
        VStack {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
            Text(String(localized: "vtxo_graph_empty", defaultValue: "No active VTXOs", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private func graph(entries: [GraphEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: barSpacing) {
                ForEach(entries) { entry in
                    let bar = VTXOGraphBar(
                        vtxo: entry.vtxo,
                        fraction: entry.daysLeft / horizonDays,
                        daysLeft: entry.daysLeft,
                        exitCostFraction: exitCostFraction(for: entry.vtxo),
                        isExpired: entry.vtxo.expiryHeight <= currentBlockHeight
                    )
                    .frame(height: barHeight)

                    if let onSelect {
                        Button {
                            onSelect(entry.vtxo)
                        } label: {
                            bar
                        }
                        .buttonStyle(.plain)
                    } else {
                        bar
                    }
                }

                Rectangle()
                    .fill(Color.systemSeparator)
                    .frame(height: 1)
                    .padding(.top, 4)
            }
            .background(alignment: .topLeading) {
                // Free refresh zone, behind the bars and the baseline.
                if let freeRefreshFraction {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.Arke.blue.opacity(0.25))
                            .frame(width: geometry.size.width * freeRefreshFraction)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color.Arke.blue.opacity(0.5))
                                    .frame(width: 1)
                            }
                    }
                }
            }

            HStack {
                if freeRefreshFraction != nil {
                    Text(String(localized: "vtxo_graph_free_refresh_zone", defaultValue: "Free refresh zone", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(Color.Arke.blue)
                }

                Spacer()

                Text(horizonDate, format: .dateTime.month(.abbreviated).day())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A single VTXO bar with its amount label. The label sits to the right of
/// the bar; when the bar is too long for the label to fit, it moves inside
/// the bar, right-aligned in white. The label is kept invisible until its
/// width has been measured, then fades in, so it never flashes at the
/// wrong position on the first layout pass.
private struct VTXOGraphBar: View {
    let vtxo: VTXOModel
    let fraction: Double
    let daysLeft: Double
    let exitCostFraction: Double
    let isExpired: Bool

    @State private var labelWidth: CGFloat = 0

    private let cornerRadius: CGFloat = 6
    private let labelSpacing: CGFloat = 8
    private let insideLabelPadding: CGFloat = 12
    private let minBarWidth: CGFloat = 4

    private var barColor: Color {
        if isExpired {
            return Color.Arke.red
        }
        return Color.Arke.gold.mix(with: .primary, by: exitCostFraction)
    }

    private var accessibilityText: Text {
        var label = String(
            localized: "accessibility_vtxo_graph_bar %@ %lld",
            defaultValue: "\(vtxo.formattedAmount), expires in ^[\(Int(daysLeft.rounded(.up))) days](inflect: true)",
            bundle: .module
        )
        if isExpired {
            label += ", " + String(localized: "accessibility_vtxo_graph_expired", defaultValue: "expired", bundle: .module)
        }
        if vtxo.state == .locked {
            label += ", " + String(localized: "accessibility_vtxo_graph_locked", defaultValue: "locked", bundle: .module)
        }
        return Text(label)
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(minBarWidth, geometry.size.width * fraction)
            let fitsOutside = barWidth + labelSpacing + labelWidth <= geometry.size.width

            ZStack(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
                .fill(barColor)
                    .frame(width: barWidth)

                if fitsOutside {
                    label(inside: false)
                        .offset(x: barWidth + labelSpacing)
                } else {
                    label(inside: true)
                        .foregroundStyle(Color.Arke.gold3)
                        .padding(.trailing, insideLabelPadding)
                        .frame(width: barWidth, alignment: .trailing)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            // The full row (bar plus trailing whitespace) is the tap target.
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func label(inside: Bool) -> some View {
        HStack(spacing: 6) {
            Text(vtxo.formattedAmount)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(inside ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .fixedSize()

            if isExpired {
                Text(String(localized: "vtxo_graph_expired", defaultValue: "Expired", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.Arke.red, in: Capsule())
            }

            if vtxo.state == .locked {
                Image(systemName: "lock.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.Arke.blue)
                    .font(.title3)
            }
        }
        .opacity(labelWidth > 0 ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: labelWidth > 0)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            labelWidth = width
        }
    }
}

// MARK: - Preview

#Preview("VTXOGraph") {
    let currentHeight = 250_000
    let vtxos = [
        VTXOModel(
            id: "9c21be5a7f30412d8e6a0f47c1db92e5a83f60d1b24c9e7a5061f38da2c47b13:0",
            amountSat: 1_337,
            expiryHeight: currentHeight - 50, // expired
            kind: .pubkey,
            state: .spendable
        ),
        VTXOModel(
            id: "4f35af824858dd69802af664a2d1b03d2a49d60b7f66741ba3292de3b756d49a:0",
            amountSat: 569,
            expiryHeight: currentHeight + 115, // < 1 day, inside the free refresh zone
            kind: .pubkey,
            state: .spendable
        ),
        VTXOModel(
            id: "abc123def456789012345678901234567890abcdef123456789012345678901234:1",
            amountSat: 456,
            expiryHeight: currentHeight + 144 * 7, // 7 days
            kind: .pubkey,
            state: .locked
        ),
        VTXOModel(
            id: "def456abc123789012345678901234567890abcdef123456789012345678901234:2",
            amountSat: 212,
            expiryHeight: currentHeight + 144 * 12, // 12 days
            kind: .pubkey,
            state: .spendable,
            exitDepth: 4,
            exitTxWeightWu: 2_000 // moderate exit chain, leaning pink
        ),
        VTXOModel(
            id: "789abcdef123456012345678901234567890abcdef123456789012345678901234:0",
            amountSat: 20_746,
            expiryHeight: currentHeight + 144 * 21, // 21 days
            kind: .pubkey,
            state: .spendable,
            exitDepth: 11,
            exitTxWeightWu: 5_500 // near the worst case, full pink
        ),
        VTXOModel(
            id: "456789abcdef123012345678901234567890abcdef123456789012345678901234:3",
            amountSat: 672,
            expiryHeight: currentHeight + 144 * 30, // full horizon, label inside bar
            kind: .pubkey,
            state: .spendable
        )
    ]

    VTXOGraph(
        vtxos: vtxos,
        currentBlockHeight: currentHeight,
        horizonBlocks: 144 * 30,
        freeRefreshBlocks: 288,
        maxExitDepth: 12
    )
    .padding(24)
}

#Preview("VTXOGraph – Empty") {
    VTXOGraph(vtxos: [], currentBlockHeight: 250_000)
        .padding(24)
}
