import SwiftUI
import AppKit
import MarkdownUI

struct AppUpdateView: View {

    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(spacing: 16) {
            switch updater.phase {
            case .idle:
                EmptyView()

            case .updateAvailable(let version, let url, let releaseNotes):
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)

                    Text("A new version of the app is available")
                        .font(.headline)
                }

                Text("Version \(version)")
                    .foregroundColor(.secondary)

                if !releaseNotes.isEmpty {
                    ScrollView {
                        Markdown(releaseNotes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 220)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }

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

                HStack {
                    Button("Later") {
                        updater.dismiss()
                    }
                    Button("Retry") {
                        updater.retry()
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}
