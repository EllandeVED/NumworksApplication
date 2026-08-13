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
                Text("Epsilon v\(AppInfo.epsilonVersion)")
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
                .accessibilityIdentifier("licence-button")
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

    private static let gplURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Licence")
                .font(.headline)
                .frame(maxWidth: .infinity)

            Text("NumWorks for Mac is free software licensed under the GNU General Public License v3.0 (GPLv3).")
                .fixedSize(horizontal: false, vertical: true)

            Text("Copyright © 2025–2026 EllandeVED.")
                .foregroundStyle(.secondary)

            Text("It embeds Epsilon (NumWorks), also under GPLv3. You may redistribute and modify this software under the terms of the GPL; derivative works must remain under GPLv3.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            if let url = Self.gplURL {
                Link("Read the full GPLv3 text", destination: url)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("licence-close-button")
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 400)
        .accessibilityIdentifier("licence-sheet")
    }
}
