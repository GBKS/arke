//
//  ArkServerSelectionSheet.swift
//  Arké
//
//  Cover-screen sheet about the Ark server the wallet will connect to. Page
//  one describes the current choice (the default, Second's Bitcoin server,
//  unless changed) and offers "Other options"; page two chooses between the
//  default, Second's signet server for development, and a custom server
//  entered by address and checked with `BarkWalletFFI.probeServer` before it
//  can be saved. Features/Ark_Server_Selection.md §4.3, §4.9, §4.10.
//
//  Styled like the import screen (dark, serif title, bordered cards).
//
//  Pre-wallet only: the selection lives in the onboarding flow until a wallet
//  exists; `NetworkConfigPersistence` takes over after that. Nothing here
//  writes persistence.
//

import SwiftUI
import ArkeUI

struct ArkServerSelectionSheet: View {
    @Binding var selection: NetworkConfig
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    /// Page one is sized to its content; the pushed pages need the full height.
    @State private var detent: PresentationDetent = .height(Self.fallbackPageOneHeight)
    /// Measured height of page one's content, so the compact detent fits it
    /// exactly instead of landing on the system's half-screen size.
    @State private var pageOneContentHeight: CGFloat = Self.fallbackPageOneHeight

    fileprivate enum Route: Hashable {
        case options
        case customServer
    }

    private static let fallbackPageOneHeight: CGFloat = 400
    /// The sheet's top inset plus the navigation bar above the content
    /// (measured 19 + 52 pt on iOS 27). The system keeps the content above
    /// the home indicator on its own, so the bottom safe area is not added:
    /// adding it once produced a 60 pt gap on first open and a 30 pt gap
    /// after a pop, depending on what the geometry callback reported.
    private static let pageOneTopChrome: CGFloat = 72

    private var compactDetent: PresentationDetent {
        .height(pageOneContentHeight + Self.pageOneTopChrome)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "server_sheet_title", defaultValue: "Server"))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "server_sheet_intro", defaultValue: "A server helps create your wallet and make payments. Note that this can't be changed later."))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Never trade lines for height: a detent that is a few
                        // points short must overflow, not collapse the paragraph
                        // (and feed the shorter measurement back into the detent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ServerRow(config: selection, accessory: .none, selected: false)

                NavigationLink(value: Route.options) {
                    HStack(spacing: 6) {
                        Text(String(localized: "server_sheet_options", defaultValue: "Options"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(.title3))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                pageOneContentHeight = height
                if path.isEmpty { detent = compactDetent }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.buttonDone) { dismiss() }
                        .tint(Color.Arke.gold)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .options:
                    ServerOptionsPage(selection: $selection, onPicked: { path.removeAll() })
                case .customServer:
                    CustomArkServerForm(
                        initial: selection.serverKind == .custom ? selection : nil,
                        onSave: { config in
                            selection = config
                            path.removeAll()
                        }
                    )
                }
            }
            .background(Color.Arke.gold4)
        }
        .colorScheme(.dark)
        .presentationBackground(Color.Arke.gold4)
        .presentationDetents([compactDetent, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .onChange(of: path) { _, newPath in
            // Page one fits the compact height; Options and the form do not
            detent = newPath.isEmpty ? compactDetent : .large
        }
    }
}

// MARK: - Page 2: options

private struct ServerOptionsPage: View {
    @Binding var selection: NetworkConfig
    /// Called after a preset is picked so the sheet returns to page one.
    let onPicked: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "server_sheet_options", defaultValue: "Options"))
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(Color.Arke.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 12) {
                    Button {
                        pick(.mainnet)
                    } label: {
                        ServerRow(config: .mainnet, accessory: .checkmark, selected: selection.id == NetworkConfig.mainnet.id)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pick(.signet)
                    } label: {
                        ServerRow(config: .signet, accessory: .checkmark, selected: selection.id == NetworkConfig.signet.id)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: ArkServerSelectionSheet.Route.customServer) {
                        ServerRow(
                            config: selection.serverKind == .custom ? selection : nil,
                            accessory: .chevron,
                            selected: selection.serverKind == .custom
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .background(Color.Arke.gold4)
    }

    private func pick(_ preset: NetworkConfig) {
        selection = preset
        onPicked()
    }
}

// MARK: - Server row

/// The one row both pages use. The title names the role (Default,
/// Development, a custom host), the lines below say who runs it and what it
/// is, and the tile is a distinct picture per row (§4.11b, DECIDED
/// 2026-10-30). Quiet fill, no stroke; a thin gold stroke when selected.
struct ServerRow: View {
    enum Line: Equatable {
        case text(String)
        case termsLink(URL)
    }

    enum Accessory {
        case none
        /// Checkmark when selected, nothing otherwise.
        case checkmark
        /// Chevron (the row navigates); the checkmark joins it when selected.
        case chevron
    }

    /// Nil for the unsaved Custom row, which has no server yet.
    let config: NetworkConfig?
    let accessory: Accessory
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tile

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title(for: config))
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ForEach(Array(Self.lines(for: config).enumerated()), id: \.offset) { _, line in
                    switch line {
                    case .text(let text):
                        Text(text)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    case .termsLink(let url):
                        // Second's mainnet server advertises its terms; hard-coded
                        // like the preset (the bindings do not expose
                        // ArkInfo.tos_link yet). No consent step: the app's own
                        // terms already bind the user to the server's (§4.9).
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Text(String(localized: "server_sheet_terms_link", defaultValue: "Terms of use"))
                                Image(systemName: "arrow.up.right.square")
                                    .accessibilityHidden(true)
                            }
                            .font(.callout)
                            .foregroundStyle(Color.Arke.gold)
                        }
                        .accessibilityHint(String(localized: "server_sheet_terms_hint", defaultValue: "Opens the server operator's terms in the browser"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if selected, accessory != .none {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.Arke.gold)
                        .accessibilityHidden(true)
                }
                if accessory == .chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 60)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.Arke.gold.opacity(selected && accessory != .none ? 0.5 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected && accessory != .none ? .isSelected : [])
    }

    /// Role, not operator: Default / Development / the custom host.
    static func title(for config: NetworkConfig?) -> String {
        guard let config else {
            return String(localized: "server_sheet_custom", defaultValue: "Custom server")
        }
        switch config.serverKind {
        case .secondMainnet:
            return String(localized: "server_sheet_default", defaultValue: "Default")
        case .secondSignet:
            return String(localized: "server_sheet_development", defaultValue: "Development")
        case .custom:
            return NetworkConfig.serverHost(config.arkServerURL) ?? config.name
        }
    }

    /// Who runs it and what it is, one fact per line.
    static func lines(for config: NetworkConfig?) -> [Line] {
        guard let config else {
            return [.text(String(localized: "server_sheet_custom_enter", defaultValue: "Enter an address"))]
        }
        let bySecond = Line.text(String(localized: "server_sheet_by_second", defaultValue: "By Second"))
        let testNetwork: [Line] = [
            .text(String(localized: "server_sheet_signet_test_network", defaultValue: "Signet test network")),
            .text(String(localized: "server_sheet_coins_no_value", defaultValue: "Coins have no value")),
        ]
        switch config.serverKind {
        case .secondMainnet:
            return [bySecond, .termsLink(NetworkConfig.secondMainnetTermsURL)]
        case .secondSignet:
            return [bySecond] + testNetwork
        case .custom:
            let custom = Line.text(String(localized: "server_sheet_custom", defaultValue: "Custom server"))
            return config.isMainnet ? [custom] : [custom] + testNetwork
        }
    }

    @ViewBuilder
    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
            switch config?.serverKind {
            case .secondMainnet:
                Image("second")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            case .secondSignet:
                // The lab vial: the cover button's icon and the signet video's motif
                Image(systemName: "testtube.2")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.Arke.gold4)
            case .custom, .none:
                Image(systemName: "server.rack")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.Arke.gold4)
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
    }
}

// MARK: - Custom server form

/// Address in, probe, then chain and Esplora out. Save is enabled only after
/// the probe passed for the address as typed; editing the address resets it.
struct CustomArkServerForm: View {
    let initial: NetworkConfig?
    let onSave: (NetworkConfig) -> Void

    @State private var serverURL: String
    @State private var esploraURL: String
    @State private var name: String
    @State private var probe: ProbeState
    @State private var probeTask: Task<Void, Never>?

    enum ProbeState: Equatable {
        case idle
        case running
        case passed(BitcoinNetwork)
        case failed(message: String, detail: String?)
    }

    init(initial: NetworkConfig?, onSave: @escaping (NetworkConfig) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _serverURL = State(initialValue: initial?.arkServerBaseURL ?? "")
        _esploraURL = State(initialValue: initial?.esploraURL ?? "")
        _name = State(initialValue: initial.map { $0.name == NetworkConfig.serverHost($0.arkServerURL) ? "" : $0.name } ?? "")
        // A previously saved custom server was probed when it was saved.
        if let network = initial?.bitcoinNetwork {
            _probe = State(initialValue: .passed(network))
        } else {
            _probe = State(initialValue: .idle)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "server_form_title", defaultValue: "Custom Server"))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "server_form_intro", defaultValue: "Enter the address of an Ark server. The check confirms it is compatible and finds out which network it runs on. Connections use HTTPS."))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Address + check
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel(String(localized: "server_form_address_label", defaultValue: "Server address"))

                    ServerFormField(
                        placeholder: String(localized: "server_form_address_placeholder", defaultValue: "ark.example.com"),
                        text: $serverURL
                    )
                    .disabled(probe == .running)
                    .accessibilityLabel(String(localized: "server_form_address_label", defaultValue: "Server address"))
                    .onChange(of: serverURL) { _, _ in
                        // The probe result belongs to the address it was run for
                        probeTask?.cancel()
                        probe = .idle
                    }

                    checkRow
                }

                if case .passed(let network) = probe {
                    // Detected chain
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel(String(localized: "server_form_network_label", defaultValue: "Network"))
                        HStack(spacing: 12) {
                            Image(systemName: network == .mainnet ? "bitcoinsign.circle.fill" : "testtube.2")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.Arke.gold)
                            Text(Self.networkName(network))
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.Arke.gold.opacity(0.2), lineWidth: 1))
                        .accessibilityElement(children: .combine)

                        if network != .mainnet {
                            footnote(String(localized: "server_form_test_network_footer", defaultValue: "This is a test network. Coins on it have no value."))
                        }
                        // Becomes a link once the bindings expose ArkInfo.tos_link (§4.9)
                        footnote(String(localized: "server_form_terms_footer", defaultValue: "Terms of use are set by the server operator."))
                    }

                    // Esplora
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel(String(localized: "server_form_section_esplora", defaultValue: "Block explorer (Esplora)"))
                        ServerFormField(
                            placeholder: String(localized: "server_form_esplora_placeholder", defaultValue: "esplora.example.com/api"),
                            text: $esploraURL
                        )
                        .accessibilityLabel(String(localized: "server_form_esplora_label", defaultValue: "Block explorer address"))
                        footnote(String(localized: "server_form_section_esplora_footer", defaultValue: "Used for on-chain data such as fees and confirmations. Prefilled with Second's explorer for this network; change it if the server operator provides one."))
                    }

                    // Name
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel(String(localized: "server_form_section_name", defaultValue: "Name"))
                        ServerFormField(
                            placeholder: String(localized: "server_form_name_placeholder", defaultValue: "Optional"),
                            text: $name,
                            isURL: false
                        )
                        .accessibilityLabel(String(localized: "server_form_name_label", defaultValue: "Display name"))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.Arke.gold4)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.buttonSave) { save() }
                    .tint(Color.Arke.gold)
                    .disabled(savedConfig == nil)
            }
        }
        .onDisappear {
            probeTask?.cancel()
        }
    }

    @ViewBuilder
    private var checkRow: some View {
        switch probe {
        case .idle:
            Button {
                runProbe()
            } label: {
                Label(
                    String(localized: "server_form_check", defaultValue: "Check connection"),
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .foregroundStyle(Color.Arke.gold4)
            .disabled(NetworkConfig.serverHost(serverURL) == nil)

        case .running:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color.Arke.gold)
                Text(String(localized: "server_form_checking", defaultValue: "Checking…"))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)

        case .passed:
            statusRow(
                icon: "checkmark.circle.fill",
                color: .green,
                text: String(localized: "server_form_check_passed", defaultValue: "Ark server found")
            )

        case .failed(let message, let detail):
            VStack(alignment: .leading, spacing: 10) {
                statusRow(icon: "xmark.octagon.fill", color: .red, text: message)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .textSelection(.enabled)
                }
                // Same shape as "Check connection": it is the same action
                Button {
                    runProbe()
                } label: {
                    Label(
                        String(localized: "server_form_check_again", defaultValue: "Check again"),
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(Color.Arke.gold)
            }
        }
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The config Save would produce, or nil while it cannot be saved.
    private var savedConfig: NetworkConfig? {
        guard case .passed(let network) = probe,
              NetworkConfig.serverHost(esploraURL) != nil else {
            return nil
        }
        return NetworkConfig.custom(
            arkServerURL: serverURL,
            esploraURL: NetworkConfig.normalizedBaseURL(esploraURL),
            network: network,
            name: name
        )
    }

    private func runProbe() {
        probeTask?.cancel()
        probe = .running
        let url = serverURL
        probeTask = Task {
            do {
                let result = try await BarkWalletFFI.probeServer(url: url)
                guard !Task.isCancelled else { return }
                // Prefill the Esplora for the detected chain unless the user
                // already typed one (re-checking a saved server keeps theirs)
                if esploraURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    esploraURL = NetworkConfig.defaultEsploraURL(for: result.network)
                }
                probe = .passed(result.network)
            } catch is CancellationError {
                // Address edited or form left; state already reset
            } catch let error as ArkServerProbeError {
                guard !Task.isCancelled else { return }
                let detail: String?
                if case .unreachableOrIncompatible(let barkMessage) = error {
                    detail = barkMessage
                } else {
                    detail = nil
                }
                probe = .failed(message: error.localizedDescription, detail: detail)
            } catch {
                guard !Task.isCancelled else { return }
                probe = .failed(message: error.localizedDescription, detail: nil)
            }
        }
    }

    private func save() {
        guard let config = savedConfig else { return }
        onSave(config)
    }

    static func networkName(_ network: BitcoinNetwork) -> String {
        switch network {
        case .mainnet:
            return String(localized: "network_name_bitcoin", defaultValue: "Bitcoin")
        case .signet:
            return String(localized: "network_name_signet", defaultValue: "Signet (test network)")
        case .testnet:
            return String(localized: "network_name_testnet", defaultValue: "Testnet (test network)")
        case .regtest:
            return String(localized: "network_name_regtest", defaultValue: "Regtest (test network)")
        }
    }
}

// MARK: - Text field in the import screen's idiom

struct ServerFormField: View {
    let placeholder: String
    @Binding var text: String
    var isURL: Bool = true

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(15)
            .background(Color.primary.opacity(0.05))
            .foregroundStyle(.white)
            .font(.system(.body))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.Arke.gold.opacity(0.2), lineWidth: 1)
            )
            .autocorrectionDisabled()
            .modifier(URLKeyboard(enabled: isURL))
    }
}

private struct URLKeyboard: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            content
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
