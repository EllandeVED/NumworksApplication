import SwiftUI
import AppKit

struct SimulatorUpdateView: View {
    @ObservedObject private var updater = SimulatorUpdater.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .requestEpsilonUpdateUI)) { n in
                print("[SimulatorUpdateView] received requestEpsilonUpdateUI")
                guard let u = n.userInfo else {
                    print("[SimulatorUpdateView] missing userInfo")
                    return
                }
                guard let url = u["remoteURL"] as? URL else {
                    print("[SimulatorUpdateView] missing remoteURL")
                    return
                }
                let v = (u["remoteVersion"] as? String) ?? ""
                let required = (u["required"] as? Bool) ?? false
                print("[SimulatorUpdateView] remoteVersion=\(v) url=\(url) required=\(required)")

                Task { @MainActor in
                    if required {
                        updater.presentRequiredDownload(remoteURL: url, remoteVersion: v)
                    } else {
                        updater.presentUpdate(remoteURL: url, remoteVersion: v)
                    }
                }
            }
    }
}

struct SimulatorUpdateSheet: View {
    @ObservedObject private var updater = SimulatorUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(updater.headline)
                        .font(.title2)
                        .bold()

                    Text(updater.message)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if updater.isRequired {
                HStack(spacing: 8) {
                    Text("Version")
                    Text("\(updater.toVersion)")
                        .monospaced()
                }
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("\(updater.fromVersion)")
                        .monospaced()
                    Text("→")
                    Text("\(updater.toVersion)")
                        .monospaced()
                }
                .foregroundStyle(.secondary)
            }

            if updater.phase == .downloading || updater.phase == .readyToInstall {
                ProgressView(value: updater.progress)
                    .animation(.linear(duration: 0.12), value: updater.progress)
                Text(updater.progressText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if updater.phase == .installing {
                ProgressView()
                Text(updater.progressText)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                if updater.isRequired {
                    Button("Quit App") {
                        NSApp.terminate(nil)
                    }
                } else if updater.phase != .restartCountdown {
                    Button("Not Now") {
                        updater.dismiss()
                    }
                }

                Spacer()

                if updater.phase == .prompt {
                    Button("Download") {
                        updater.startDownload()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if updater.phase == .readyToInstall {
                    Button("Install") {
                        updater.install()
                    }
                    .keyboardShortcut(.defaultAction)
                    .transition(.opacity)
                }

                if updater.phase == .downloading {
                    Button("Downloading…") {}
                        .disabled(true)
                }

                if updater.phase == .installing {
                    Button("Installing…") {}
                        .disabled(true)
                }

                if updater.phase == .restartCountdown {
                    Text("Restarting in \(updater.restartSecondsRemaining)s")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))

                    Button("Restart App") {
                        updater.restartNow()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: updater.phase)
        .padding(18)
        .frame(width: 420, height: 220)
    }
}

#Preview("Simulator update sheet") {
    let u = SimulatorUpdater.shared
    u.presentUpdate(
        remoteURL: URL(string: "https://cdn.numworks.com/x/numworks-simulator-24.11.0.zip")!,
        remoteVersion: "24.11.0"
    )
    return SimulatorUpdateSheet()
}
