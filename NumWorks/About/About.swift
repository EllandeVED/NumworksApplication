import SwiftUI

/// The About page shown as a tab of the Settings window.
struct AboutView: View {

    private static let repositoryURL =
        URL(string: "https://github.com/EllandeVED/NumworksApplication")
    private static let newIssueURL =
        URL(string: "https://github.com/EllandeVED/NumworksApplication/issues/new")

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                .padding(.top, 24)

            Text("NumWorks")
                .font(.title2.weight(.semibold))

            Text("Version \(AppInfo.appVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Epsilon \(AppInfo.epsilonVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Made by Ellande VED")
                .font(.callout)
                .padding(.top, 10)

            Divider()
                .frame(width: 220)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 8) {
                if let url = Self.repositoryURL {
                    ExternalLink(title: "Open Repository", url: url)
                }
                if let url = Self.newIssueURL {
                    ExternalLink(title: "Report a bug or suggest a feature", url: url)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A native-looking link with the conventional external-link arrow.
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
