//
//  FeeDetailCardView.swift
//  Arké
//
//  Created by Christoph on 1/12/26.
//

import SwiftUI

/// Detailed card view for displaying fee statistics with sections
struct FeeDetailCardView: View {
    let title: String
    let subtitle: String?
    let prominentMetric: String?
    let prominentMetricAccessibilityLabel: String?
    let keyMetrics: [KeyMetric]
    let sections: [Section]
    let iconSymbol: String?
    let iconBackgroundImage: String?
    
    @State private var expandedSections: Set<Int> = []
    
    struct KeyMetric {
        let label: String
        let value: String
        let isTotal: Bool
        
        init(label: String, value: String, isTotal: Bool = false) {
            self.label = label
            self.value = value
            self.isTotal = isTotal
        }
    }
    
    struct Section {
        let title: String?
        let items: [SectionItem]
    }
    
    struct SectionItem {
        let label: String
        let value: String
        let isTotal: Bool
        
        init(label: String, value: String, isTotal: Bool = false) {
            self.label = label
            self.value = value
            self.isTotal = isTotal
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 20) {
                // Optional icon
                if let iconSymbol, let iconBackgroundImage {
                    ZStack {
                        Image(iconBackgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        Image(systemName: iconSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2)
                        .foregroundStyle(.primary)
                    
                    // Prominent metric (like percentage)
                    if let prominentMetric {
                        Text(prominentMetric)
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .accessibilityLabel(prominentMetricAccessibilityLabel ?? prominentMetric)
                    }
                }
            }
        
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            // Key metrics in a vertical list
            if !keyMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(keyMetrics.enumerated()), id: \.offset) { _, metric in
                        if metric.isTotal {
                            Divider()
                        }
                        
                        HStack {
                            Text(metric.label)
                                .font(metric.isTotal ? .body.weight(.semibold) : .body)
                                .foregroundStyle(metric.isTotal ? .primary : .secondary)
                            Spacer()
                            Text(metric.value)
                                .font(metric.isTotal ? .body.weight(.semibold) : .body)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            
            // Sections
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                VStack(alignment: .leading, spacing: 8) {
                    if index > 0 || !keyMetrics.isEmpty || prominentMetric != nil {
                        Divider()
                            .padding(.top, 5)
                    }
                    
                    if let sectionTitle = section.title {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if expandedSections.contains(index) {
                                    expandedSections.remove(index)
                                } else {
                                    expandedSections.insert(index)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(expandedSections.contains(index) ? 90 : 0))
                                Text(sectionTitle)
                                    .font(.system(.body, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.top, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            expandedSections.contains(index) 
                                ? String(localized: "accessibility_section_collapse")
                                : String(localized: "accessibility_section_expand")
                        )
                    }
                    
                    if expandedSections.contains(index) {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            if item.isTotal {
                                Divider()
                            }
                            
                            HStack {
                                Text(item.label)
                                    .font(item.isTotal ? .body.weight(.semibold) : .body)
                                    .foregroundStyle(item.isTotal ? .primary : .secondary)
                                Spacer()
                                Text(item.value)
                                    .font(item.isTotal ? .body.weight(.semibold) : .body)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Convenience Initializers

extension FeeDetailCardView {
    /// Simple card with just title and sections
    init(title: String, subtitle: String? = nil, sections: [Section], iconSymbol: String? = nil, iconBackgroundImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.prominentMetric = nil
        self.prominentMetricAccessibilityLabel = nil
        self.keyMetrics = []
        self.sections = sections
        self.iconSymbol = iconSymbol
        self.iconBackgroundImage = iconBackgroundImage
    }
    
    /// Card with prominent metric and key metrics
    init(title: String, subtitle: String? = nil, prominentMetric: String, prominentMetricAccessibilityLabel: String? = nil, keyMetrics: [KeyMetric], sections: [Section] = [], iconSymbol: String? = nil, iconBackgroundImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.prominentMetric = prominentMetric
        self.prominentMetricAccessibilityLabel = prominentMetricAccessibilityLabel
        self.keyMetrics = keyMetrics
        self.sections = sections
        self.iconSymbol = iconSymbol
        self.iconBackgroundImage = iconBackgroundImage
    }
}
