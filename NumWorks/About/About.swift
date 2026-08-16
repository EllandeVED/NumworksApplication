import AppKit
import SwiftUI

/// The About page shown as a tab of the Settings window.
struct AboutView: View {

    private static let numworksWebsiteURL =
        URL(string: "https://www.numworks.com")
    private static let epsilonRepositoryURL =
        URL(string: "https://github.com/numworks/epsilon")
    private static let repositoryURL =
        URL(string: "https://github.com/EllandeVED/NumworksApplication")
    private static let newIssueURL =
        URL(string: "https://github.com/EllandeVED/NumworksApplication/issues/new")

    @State private var showingLicence = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: AppInfo.aboutIcon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)

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
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .listRowBackground(Color(nsColor: .windowBackgroundColor))
            }

            Section("Official links") {
                if let url = Self.numworksWebsiteURL {
                    AboutLinkRow(
                        title: "NumWorks website",
                        systemImage: "globe",
                        url: url)
                }
                if let url = Self.epsilonRepositoryURL {
                    AboutLinkRow(
                        title: "Epsilon repository",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        url: url)
                }
            }

            Section("Useful links") {
                if let url = Self.repositoryURL {
                    AboutLinkRow(
                        title: "GitHub repository",
                        systemImage: "shippingbox",
                        url: url)
                }
                if let url = Self.newIssueURL {
                    AboutLinkRow(
                        title: "Report a bug or suggest a feature",
                        systemImage: "exclamationmark.bubble",
                        url: url)
                }
                Button {
                    showingLicence = true
                } label: {
                    AboutRowLabel(
                        title: "Licence",
                        systemImage: "doc.text",
                        showsExternalIndicator: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("licence-button")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingLicence) {
            LicencePlaceholderView()
        }
    }
}

private struct AboutLinkRow: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            AboutRowLabel(
                title: title,
                systemImage: systemImage,
                showsExternalIndicator: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) (opens in browser)")
    }
}

private struct AboutRowLabel: View {
    let title: String
    let systemImage: String
    let showsExternalIndicator: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if showsExternalIndicator {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
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
