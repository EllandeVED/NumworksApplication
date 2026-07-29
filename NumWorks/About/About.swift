import SwiftUI

/// The About page shown as a tab of the Settings window.
struct AboutView: View {

    private static let repositoryURL =
        URL(string: "https://github.com/EllandeVED/NumworksApplication")
    private static let newIssueURL =
        URL(string: "https://github.com/EllandeVED/NumworksApplication/issues/new")

    @State private var showingLicence = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppInfo.applicationIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                .padding(.top, 20)

            Text("NumWorks")
                .font(.title2.weight(.semibold))

            VStack(spacing: 2) {
                Text("Version \(AppInfo.bundleVersion)")
                Text("Build \(AppInfo.bundleBuild)")
                Text("Epsilon \(AppInfo.epsilonVersion)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("Made by Ellande VED")
                .font(.callout)
                .padding(.top, 8)

            Divider()
                .frame(width: 240)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 8) {
                if let url = Self.repositoryURL {
                    ExternalLink(title: "GitHub Repository", url: url)
                }
                if let url = Self.newIssueURL {
                    ExternalLink(title: "Report a bug or suggest a feature", url: url)
                }
                Button("Licence") {
                    showingLicence = true
                }
                .buttonStyle(.link)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingLicence) {
            LicencePlaceholderView()
        }
    }
}

private struct ExternalLink: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("\(title) (opens in browser)")
    }
}

private struct LicencePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Licence")
                .font(.headline)
            Text("Licence information will be available in a future release.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 340, height: 160)
    }
}
