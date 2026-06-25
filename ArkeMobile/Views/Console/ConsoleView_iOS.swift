//
//  ConsoleView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct ConsoleView_iOS: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel = ConsoleViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            historySection
            Divider()
            inputSection
        }
        .navigationTitle("console_name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            keyboardToolbar
        }
        .onAppear {
            viewModel.setWalletManager(walletManager)
        }
        .onTapGesture {
            isInputFocused = true
        }
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.history.isEmpty {
                        emptyStateView
                    }
                    
                    ForEach(viewModel.history) { entry in
                        ConsoleHistoryRow(entry: entry)
                    }
                    
                    if viewModel.isExecuting {
                        ExecutingIndicator(command: viewModel.commandInput)
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: viewModel.history.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isExecuting) { _, newValue in
                if newValue {
                    scrollToExecuting(proxy)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(String(localized: "console_help_hint"))
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        HStack(spacing: 8) {
            promptSymbol
            commandTextField
            executeButton
        }
        .padding()
        .background(.background)
    }
    
    private var promptSymbol: some View {
        Text("symbol_chevron")
            .foregroundStyle(.secondary)
            .font(.system(.callout, design: .monospaced))
    }
    
    private var commandTextField: some View {
        TextField(String(localized: "console_placeholder"), text: $viewModel.commandInput)
            .textFieldStyle(.plain)
            .font(.system(.callout, design: .monospaced))
            .focused($isInputFocused)
            .disabled(viewModel.isExecuting)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.go)
            .onSubmit {
                executeCommand()
            }
    }
    
    private var executeButton: some View {
        Button(action: executeCommand) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(buttonColor)
        }
        .disabled(viewModel.commandInput.isEmpty || viewModel.isExecuting)
    }
    
    private var buttonColor: Color {
        viewModel.commandInput.isEmpty || viewModel.isExecuting ? .secondary : .Arke.blue
    }
    
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("button_done") {
                isInputFocused = false
            }
        }
    }
    
    // MARK: - Actions
    
    private func executeCommand() {
        Task {
            await viewModel.executeCommand()
            isInputFocused = true
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastEntry = viewModel.history.last {
            withAnimation {
                proxy.scrollTo(lastEntry.id, anchor: .bottom)
            }
        }
    }
    
    private func scrollToExecuting(_ proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo("executing", anchor: .bottom)
        }
    }
}

// MARK: - Supporting Views

private struct ConsoleHistoryRow: View {
    let entry: ConsoleEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            commandLine
            resultLine
        }
        .padding(.horizontal)
        .id(entry.id)
    }
    
    private var commandLine: some View {
        HStack(spacing: 4) {
            Text("symbol_chevron")
                .foregroundStyle(.secondary)
            Text(entry.command)
                .foregroundStyle(.primary)
        }
        .font(.system(.callout, design: .monospaced))
    }
    
    private var resultLine: some View {
        Text(entry.result)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(entry.isError ? Color.Arke.red : .secondary)
            .textSelection(.enabled)
            .padding(.leading, 12)
    }
}

private struct ExecutingIndicator: View {
    let command: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            commandLine
            progressLine
        }
        .id("executing")
    }
    
    private var commandLine: some View {
        HStack(spacing: 4) {
            Text("symbol_chevron")
                .foregroundStyle(.secondary)
            Text(command)
                .foregroundStyle(.primary)
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.horizontal)
    }
    
    private var progressLine: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(String(localized: "status_executing"))
                .foregroundStyle(.secondary)
                .font(.system(.callout, design: .monospaced))
        }
        .padding(.leading, 12)
        .padding(.horizontal)
    }
}
