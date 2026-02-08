

import SwiftUI

struct AppUpdateView: View {

    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(spacing: 16) {
            switch updater.phase {
            case .idle:
                EmptyView()

            case .updateAvailable(let version, let url):
                Text("A new version of the app is available")
                    .font(.headline)

                Text("Version \(version)")
                    .foregroundColor(.secondary)

                HStack {
                    Button("Later") {
                        updater.dismiss()
                    }

                    Button("Download and install") {
                        Task {
                            await updater.downloadAndInstall(remoteURL: url)
                        }
                    }
                }

            case .downloading:
                ProgressView("Downloading update…")

            case .readyToOpen:
                Text("Open \"NumWorks\" located in the Downloads folder")
                    .font(.headline)

                Button("Open") {
                    updater.openDownloadsAndQuit()
                }

            case .failed(let message):
                Text("Update failed")
                    .font(.headline)
                Text(message)
                    .foregroundColor(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}
