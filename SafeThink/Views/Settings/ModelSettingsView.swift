import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // Active model info
            Section {
                HStack {
                    Text("Active Model")
                    Spacer()
                    Text(InferenceService.shared.loadedModelId?.components(separatedBy: "/").last ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Picker("Response Style", selection: $viewModel.responseFormat) {
                    ForEach(ResponseFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Toggle("Show Tokens/sec", isOn: $viewModel.showTokensPerSec)
            }

            Section {
                Toggle("Thinking Mode", isOn: $viewModel.thinkingMode)
            } footer: {
                Text("When enabled, the model shows its reasoning process before answering. Produces more accurate responses but takes longer to generate.")
            }

            // Customization toggle
            Section {
                Toggle("Enable Customization", isOn: $viewModel.customizationEnabled.animation())
            } footer: {
                Text("Adjust generation parameters and system prompt for advanced control.")
            }

            // Advanced options — only visible when customization is on
            if viewModel.customizationEnabled {
                Section("Generation") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text("\(viewModel.temperature, specifier: "%.2f")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.temperature, in: 0...2, step: 0.05)
                        Text("Lower = focused, Higher = creative")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Top-P")
                            Spacer()
                            Text("\(viewModel.topP, specifier: "%.2f")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.topP, in: 0...1, step: 0.05)
                    }
                }

                Section("System Prompt") {
                    TextEditor(text: $viewModel.systemPrompt)
                        .frame(minHeight: 100)
                        .font(.subheadline)

                    if viewModel.systemPrompt != SettingsViewModel.defaultSystemPrompt {
                        Button("Reset to Default") {
                            viewModel.systemPrompt = SettingsViewModel.defaultSystemPrompt
                        }
                    }
                }
            }
        }
        .navigationTitle("Model Settings")
        .onDisappear { viewModel.saveSettings() }
    }
}
