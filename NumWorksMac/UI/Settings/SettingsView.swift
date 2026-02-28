import SwiftUI
import AppKit
import KeyboardShortcuts
import LaunchAtLogin

private let settingsTitleSize: CGFloat = 30

private func formatUpdateCheckError(_ error: Error) -> String {
    if let ns = error as NSError? {
        return "\(ns.domain) (code \(ns.code)): \(ns.localizedDescription)"
    }
    return error.localizedDescription
}

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general
        case appUpdate
        case epsilonUpdate
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .appUpdate: return "App Update"
            case .epsilonUpdate: return "Epsilon Update"
            case .about: return "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .appUpdate: return "arrow.triangle.2.circlepath"
            case .epsilonUpdate: return "terminal"
            case .about: return "info.circle"
            }
        }
    }

    struct Pane: Identifiable {
        let tab: Tab
        let view: AnyView
        var id: String { tab.id }
    }

    @State private var selection: Tab = .general

    private let panes: [Pane] = [
        .init(tab: .general, view: AnyView(GeneralSettingsPane())),
        .init(tab: .appUpdate, view: AnyView(AppUpdateSettingsPane())),
        .init(tab: .epsilonUpdate, view: AnyView(EpsilonUpdateSettingsPane())),
        .init(tab: .about, view: AnyView(AboutSettingsPane())),
    ]

    var body: some View {
        TabView(selection: $selection) {
            ForEach(panes) { pane in
                pane.view
                    .tag(pane.tab)
                    .tabItem { Label(pane.tab.title, systemImage: pane.tab.systemImage) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 420, minHeight: 460)
        .onAppear {
            NotificationCenter.default.post(name: .settingsWindowDidAppear, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .settingsWindowDidDisappear, object: nil)
        }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.title2)
                .bold()

            
                // Shortcuts
                Text("Shortcuts")
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    KeyboardShortcuts.Recorder(for: .hideShowApp)
                    Text("Hide / Show App")
                }

                HStack(spacing: 12) {
                    KeyboardShortcuts.Recorder(for: .pinUnpinApp)
                    Text("Pin / Unpin App")
                }

                // Startup
                Text("Startup")
                    .fontWeight(.bold)

                LaunchAtLogin.Toggle()
                    .onAppear {
                        let key = "didSetDefaultLaunchAtLogin"
                        if !UserDefaults.standard.bool(forKey: key) {
                            LaunchAtLogin.isEnabled = true
                            UserDefaults.standard.set(true, forKey: key)
                        }
                    }

                // Interface
                Text("Interface")
                    .fontWeight(.bold)

                Toggle("Show Menu Bar Icon", isOn: $prefs.isMenuBarIconEnabled)
                Toggle("Show Pin/Unpin button on Calculator", isOn: $prefs.showPinButtonOnCalculator)
                Toggle("Show Dock Icon", isOn: $prefs.showDockIcon)

                // Preferred icon
                Text("Preferred Icon")
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    iconChoice(title: "Filled", style: .filled)
                    iconChoice(title: "Outline", style: .outline)
                    Spacer(minLength: 0)
                }

                // Calculator image
                Text("Calculator Image")
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    calculatorImageChoice(title: "3D", use3D: true)
                    calculatorImageChoice(title: "Flat", use3D: false)
                    Spacer(minLength: 0)
                }

                Spacer()
            }
        
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func iconChoice(title: String, style: MenuBarIconStyle) -> some View {
        let selected = prefs.menuBarIconStyle == style

        Button {
            prefs.menuBarIconStyle = style
        } label: {
            HStack(spacing: 8) {
                Image(style.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(title)
            }
            .frame(minWidth: 120)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .gray.opacity(0.2))
    }

    @ViewBuilder
    private func calculatorImageChoice(title: String, use3D: Bool) -> some View {
        let selected = prefs.use3DCalculatorImage == use3D
        let assetName = use3D ? "CalculatorImage3D" : "CalculatorImage"

        Button {
            prefs.use3DCalculatorImage = use3D
        } label: {
            HStack(spacing: 8) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(title)
            }
            .frame(minWidth: 120)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .gray.opacity(0.2))
    }
}

private struct AppUpdateSettingsPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var currentAppVersion: String = ""
    @State private var isChecking = false
    @State private var showNoUpdatesAlert = false
    @State private var showErrorAlert = false
    @State private var lastErrorMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Update")
                .font(.title2)
                .bold()

            HStack(spacing: 8) {
                Text("Current version:")
                    .fontWeight(.semibold)
                Text(currentAppVersion)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Toggle("Check for app updates automatically", isOn: $prefs.checkForAppUpdatesAutomatically)

            Button {
                checkForUpdates()
            } label: {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Check for updates")
                }
            }
            .disabled(isChecking)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            currentAppVersion = appVersionString()
        }
        .alert("No updates available", isPresented: $showNoUpdatesAlert) {
            Button("OK") {}
        } message: {
            Text("You already have the latest app version.")
        }
        .alert("Update check failed", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(lastErrorMessage)
        }
    }

    private func appVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        ?? ""
    }

    private func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task { @MainActor in
            defer { isChecking = false }
            do {
                let report = try await AppUpdateChecker.checkLatestRelease()

                if report.needsUpdate {
                    NotificationCenter.default.post(
                        name: .requestAppUpdateUI,
                        object: nil,
                        userInfo: [
                            "latestURL": report.latestZipURL,
                            "latestTag": report.latestTag
                        ]
                    )
                } else {
                    showNoUpdatesAlert = true
                }

                currentAppVersion = appVersionString()
            } catch {
                print("[Settings] app update check failed: \(error)")
                lastErrorMessage = formatUpdateCheckError(error)
                showErrorAlert = true
            }
        }
    }
}

private enum RelaunchSetting {
    case webInjection
    case calculatorImage
}

private struct EpsilonUpdateSettingsPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var currentSimulatorVersion: String = ""
    @State private var isChecking = false
    @State private var showNoUpdatesAlert = false

    @State private var webInjectionDisabledLocal: Bool = false
    @State private var calculatorImageHiddenLocal: Bool = false
    @State private var showRelaunchAlert = false
    @State private var pendingRelaunchSetting: RelaunchSetting?
    @State private var isReverting = false
    @State private var isSyncingFromPrefs = false
    @State private var showErrorAlert = false
    @State private var lastErrorMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Epsilon Update")
                .font(.title2)
                .bold()

            HStack(spacing: 8) {
                Text("Current version:")
                    .fontWeight(.semibold)
                Text(currentSimulatorVersion)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Toggle("Check for simulator updates automatically", isOn: $prefs.checkForEpsilonUpdatesAutomatically)

            Button {
                checkForUpdates()
            } label: {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Check for updates")
                }
            }
            .disabled(isChecking)

            Text("Simulator")
                .fontWeight(.bold)
                .padding(.top, 8)

            Toggle("Disable web injection", isOn: $webInjectionDisabledLocal)
                .onChange(of: webInjectionDisabledLocal) { _, _ in
                    guard !isReverting, !isSyncingFromPrefs, !showRelaunchAlert else { return }
                    pendingRelaunchSetting = .webInjection
                    showRelaunchAlert = true
                }

            Toggle("Disable calculator image", isOn: $calculatorImageHiddenLocal)
                .onChange(of: calculatorImageHiddenLocal) { _, _ in
                    guard !isReverting, !isSyncingFromPrefs, !showRelaunchAlert else { return }
                    pendingRelaunchSetting = .calculatorImage
                    showRelaunchAlert = true
                }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            currentSimulatorVersion = simulatorVersionString()
            isSyncingFromPrefs = true
            webInjectionDisabledLocal = prefs.webInjectionDisabled
            calculatorImageHiddenLocal = prefs.calculatorImageHidden
            DispatchQueue.main.async {
                isSyncingFromPrefs = false
            }
        }
        .alert("The app needs to relaunch", isPresented: $showRelaunchAlert) {
            Button("Undo") {
                isReverting = true
                if let pending = pendingRelaunchSetting {
                    switch pending {
                    case .webInjection: webInjectionDisabledLocal = prefs.webInjectionDisabled
                    case .calculatorImage: calculatorImageHiddenLocal = prefs.calculatorImageHidden
                    }
                }
                pendingRelaunchSetting = nil
                showRelaunchAlert = false
                DispatchQueue.main.async { isReverting = false }
            }
            Button("Relaunch") {
                if let pending = pendingRelaunchSetting {
                    switch pending {
                    case .webInjection: prefs.webInjectionDisabled = webInjectionDisabledLocal
                    case .calculatorImage: prefs.calculatorImageHidden = calculatorImageHiddenLocal
                    }
                }
                pendingRelaunchSetting = nil
                SimulatorUpdater.relaunchApplication()
            }
        } message: {
            Text("Your change will take effect after the app restarts.")
        }
        .alert("No updates available", isPresented: $showNoUpdatesAlert) {
            Button("OK") {}
        } message: {
            Text("You already have the latest simulator version.")
        }
        .alert("Update check failed", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(lastErrorMessage)
        }
    }

    private func simulatorVersionString() -> String {
        EpsilonVersions.currentSimulatorVersionString()
    }

    private func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task { @MainActor in
            defer { isChecking = false }
            do {
                let current = simulatorVersionString()
                let report = try await EpsilonUpdateChecker.checkLatest(currentVersionString: current)

                if report.needsUpdate {
                    NotificationCenter.default.post(
                        name: .requestEpsilonUpdateUI,
                        object: nil,
                        userInfo: [
                            "remoteURL": report.remoteURL,
                            "remoteVersion": report.remoteVersion.string,
                            "required": false
                        ]
                    )
                } else {
                    showNoUpdatesAlert = true
                }

                currentSimulatorVersion = simulatorVersionString()
            } catch {
                print("[EpsilonUpdateChecker] error: \(error)")
                lastErrorMessage = formatUpdateCheckError(error)
                showErrorAlert = true
            }
        }
    }
}

private struct AboutSettingsPane: View {
    private let repoURL = URL(string: "https://github.com/EllandeVED/NumworksApplication")!
    private let issueURL = URL(string: "https://github.com/EllandeVED/NumworksApplication/issues")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2)
                .bold()

            HStack(spacing: 8) {
                Text("App version")
                    .fontWeight(.bold)
                Text(appVersionString())
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Running on Epsilon")
                    .fontWeight(.bold)
                Text(simulatorVersionString())
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 6)

            HStack(spacing: 8) {
                Text("Made by:")
                    .fontWeight(.bold)
                Text("Ellande VED")
            }
            
            HStack(spacing: 8) {
                Text("See on GitHub:")
                Link("NumworksApplication", destination: repoURL)

            }
            
            HStack(spacing: 8) {
                Text("Report an issue/request:")
                Link("Report", destination: issueURL)
            }
            

            Divider().padding(.vertical, 6)

            Button {
                MITLiscence.present()
            } label: {
                Text("MIT LISCENCE")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Button {
                AppErrorsReference.present()
            } label: {
                Text("APP ERRORS REFERENCE")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func appVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        ?? ""
    }

    private func simulatorVersionString() -> String {
        EpsilonVersions.currentSimulatorVersionString()
    }
}

extension KeyboardShortcuts.Name {
    static let hideShowApp = Self("hideShowApp")
    static let pinUnpinApp = Self("pinUnpinApp")
}

extension Notification.Name {
    static let settingsWindowDidAppear = Notification.Name("settingsWindowDidAppear")
    static let settingsWindowDidDisappear = Notification.Name("settingsWindowDidDisappear")
}

