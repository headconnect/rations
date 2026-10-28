import AppKit
import SwiftUI

/// The opt-in hub T3 Code reads Claude and Codex usage from: on/off, port and
/// management key, with what to paste into T3 Code's "Add a CLIProxyAPI hub".
struct UsageHubSettings: View {
    let hub: UsageHub
    @AppStorage(Settings.hubEnabled) private var enabled = false
    @AppStorage(Settings.hubPort) private var port = Settings.defaultHubPort
    @State private var key = ""
    @FocusState private var keyFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Serve usage to T3 Code")
                    Text("As a CLIProxyAPI hub on 127.0.0.1")
                }
            } footer: {
                if !enabled {
                    explanation
                }
            }
            if enabled {
                Section {
                    LabeledContent("Hub URL") {
                        HStack {
                            Text(hub.url).textSelection(.enabled).monospaced()
                            copyButton(hub.url, help: "Copy the hub URL")
                        }
                    }
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .help("Port on 127.0.0.1, 1024–65535")
                    LabeledContent("Management key") {
                        HStack {
                            TextField("Management key", text: $key)
                                .labelsHidden()
                                .monospaced()
                                .focused($keyFocused)
                                .onSubmit { hub.setKey(key) }
                                .onChange(of: keyFocused) { _, focused in
                                    if !focused { hub.setKey(key) }
                                }
                            copyButton(hub.key, help: "Copy the management key")
                            Button { hub.regenerateKey() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                                .buttonStyle(.borderless)
                                .help("Generate a new random key")
                        }
                    }
                    LabeledContent("Status") { statusText }
                    if let error = hub.keyError {
                        Text("Key not saved: \(error)").font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    explanation
                }
            }
        }
        .settingsPane()
        .onAppear { key = hub.key }
        .onChange(of: hub.key) { _, new in key = new }
    }

    private var explanation: some View {
        Text("""
            In T3 Code, add a CLIProxyAPI hub with this URL and key. It gets the signed-in \
            Claude and Codex accounts' usage as of Rations' last check; no tokens leave Rations \
            and it causes no extra requests to Anthropic or OpenAI.
            """)
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var statusText: some View {
        switch hub.status {
        case .off:
            Text("Starting…").foregroundStyle(.secondary)
        case .listening(let port):
            Text("Listening on 127.0.0.1:\(String(port))").foregroundStyle(.green)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private func copyButton(_ value: String, help: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
