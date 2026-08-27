import ClawdLightCore
import SwiftUI

/// The Settings window's content. One section today — the remote machines —
/// built as a form so the next setting has a place to go.
struct SettingsView: View {
    @ObservedObject var fleet: RemoteFleet

    @State private var newHost = ""
    @State private var addError: String?

    var body: some View {
        Form {
            Section {
                Text("""
                Sessions running on another machine reach the panel through an ssh \
                tunnel this app opens and keeps open. The machine needs ssh key login \
                (no password prompt), python3 and curl, and port \(AppConfig.listenPort) \
                free on its loopback. Add it, then install the hooks there.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if fleet.hosts.isEmpty {
                    Text("No machines yet.").foregroundStyle(.secondary)
                }

                ForEach(fleet.hosts, id: \.self) { host in
                    hostRow(host)
                }

                HStack {
                    TextField("name as ssh knows it — node, or user@host", text: $newHost)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newHost.trimmed.isEmpty)
                }
                if let addError {
                    Text(addError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Remote machines")
            } footer: {
                Text("""
                A machine's sessions appear when they speak — their hooks reach this Mac \
                through the tunnel — and leave when the machine says the process is gone. \
                Clicking one raises its Remote-SSH window here, if one is open.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 580, minHeight: 340)
    }

    private func add() {
        addError = fleet.add(newHost)
        if addError == nil { newHost = "" }
    }

    private func hostRow(_ host: String) -> some View {
        let status = fleet.status[host] ?? RemoteHostStatus()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(host).font(.headline)
                if status.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Check", action: { fleet.run(.check, on: host) })
                if status.hooks == .installed {
                    Button("Remove hooks", action: { fleet.run(.uninstall, on: host) })
                } else {
                    Button("Install hooks", action: { fleet.run(.install, on: host) })
                }
                Button("Test tunnel", action: { fleet.run(.test, on: host) })
                Button(action: { fleet.remove(host) }) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Forget this machine. The hooks installed there stay until you remove them.")
            }
            .disabled(status.busy)

            HStack(spacing: 14) {
                Label(status.tunnel.label, systemImage: tunnelSymbol(status.tunnel))
                Label(status.hooks.label, systemImage: hooksSymbol(status.hooks))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let message = status.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func tunnelSymbol(_ state: RemoteTunnel.State) -> String {
        switch state {
        case .up: return "link"
        case .starting: return "ellipsis.circle"
        case .down: return "exclamationmark.triangle"
        case .stopped: return "link.badge.plus"
        }
    }

    private func hooksSymbol(_ hooks: RemoteHostStatus.Hooks) -> String {
        switch hooks {
        case .installed: return "checkmark.circle"
        case .absent: return "circle"
        case .checking, .unknown: return "questionmark.circle"
        case .failed: return "xmark.circle"
        }
    }
}
