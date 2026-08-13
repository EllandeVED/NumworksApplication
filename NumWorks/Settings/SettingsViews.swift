import SwiftUI
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

/// Window/shortcut actions invoked from Settings, provided by AppController.
struct SettingsActions {
    let restoreDefaultSettings: () -> Void
    let checkForUpdates: () -> Void
}

enum SettingsTab: String {
    case general, window, shortcuts, advanced, about
}

struct SettingsRootView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    @State private var selection = SettingsRootView.initialTab()

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(preferences: preferences, actions: actions)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            WindowToolbarSettingsView(preferences: preferences)
                .tabItem { Label("Window", systemImage: "macwindow") }
                .tag(SettingsTab.window)
            ShortcutSettingsView(preferences: preferences)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            AdvancedSettingsView(actions: actions)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 460, height: 520)
    }

    private static func initialTab() -> SettingsTab {
        UITesting.settingsTabArgument ?? .general
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    private var isInApplicationsFolder: Bool {
        Bundle.main.isInstalled
    }

    private var automaticUpdates: Binding<Bool> {
        Binding(
            get: {
                if UITesting.isEnabled { return true }
                return UpdateController.shared.automaticallyChecksForUpdates
            },
            set: { newValue in
                guard !UITesting.isEnabled else { return }
                UpdateController.shared.automaticallyChecksForUpdates = newValue
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch NumWorks at login", isOn: $preferences.launchAtLogin)
                    .disabled(!Preferences.isLaunchAtLoginAvailable)
                Toggle("Show calculator when NumWorks launches",
                       isOn: $preferences.launchWindowVisible)
            } footer: {
                if !Preferences.isLaunchAtLoginAvailable {
                    Text("Launch at login requires the LaunchAtLogin package, "
                         + "which is missing from this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
            } footer: {
                Text("The Dock icon will always stay visible while the app Settings window is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Enable menu bar icon", isOn: $preferences.showMenuBarIcon)
                Picker("Menu bar icon style", selection: $preferences.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!preferences.showMenuBarIcon)
            }

            Section {
                Toggle("Check for updates automatically", isOn: automaticUpdates)
                    .disabled(UITesting.isEnabled)
                CheckForUpdatesButton(actions: actions)
                if !isInApplicationsFolder {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Button("Move to Applications Folder") {
                            guard !UITesting.skipAppMover else { return }
                            AppMover.moveIfNecessary(prompt: false)
                        }
                        .controlSize(.small)
                        .disabled(UITesting.skipAppMover)
                    }
                }
            } footer: {
                if isInApplicationsFolder {
                    Text("Automatic checks run shortly after launch (at most once a day). "
                         + "Keep NumWorks in the Applications folder so updates can install.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label {
                        Text("NumWorks can check for updates here, but installation requires the Applications folder. "
                             + "If an update is found, you’ll be asked to move the app first.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityLabel(
                        "Warning: Updates can be checked, but installation requires the Applications folder.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Observes `UpdateController` so the label swaps to a spinner while checking.
private struct CheckForUpdatesButton: View {
    let actions: SettingsActions

    var body: some View {
        if UITesting.isEnabled {
            Button("Check for Updates…", action: {})
                .disabled(true)
        } else {
            CheckForUpdatesButtonLive(actions: actions)
        }
    }
}

private struct CheckForUpdatesButtonLive: View {
    @ObservedObject private var updates = UpdateController.shared
    let actions: SettingsActions

    var body: some View {
        HStack {
            Button {
                actions.checkForUpdates()
            } label: {
                if updates.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking for updates")
                } else {
                    Text("Check for Updates…")
                }
            }
            .disabled(!updates.canCheckForUpdates || updates.isCheckingForUpdates)
            .accessibilityValue(updates.isCheckingForUpdates ? "Checking" : "Idle")
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Window (merged with Toolbar)

struct WindowToolbarSettingsView: View {
    @ObservedObject var preferences: Preferences

    private var isToolbarStyle: Bool {
        preferences.windowStyle == .toolbar
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always on top", isOn: $preferences.alwaysOnTop)
                Toggle("Move calculator to current desktop when shown",
                       isOn: $preferences.moveWindowToCurrentSpaceWhenShown)
            }
            Section {
                Picker("Toolbar style", selection: $preferences.windowStyle) {
                    Text("Native").tag(WindowStyle.native)
                    Text("Toolbar").tag(WindowStyle.toolbar)
                }
                .pickerStyle(.radioGroup)
            }
            if isToolbarStyle {
                Section {
                    Toggle("Show pin button", isOn: $preferences.showPinButton)
                    Toggle("Show settings button", isOn: $preferences.showSettingsButton)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Enable shortcuts", isOn: $preferences.shortcutsEnabled)
            }
            Section {
#if canImport(KeyboardShortcuts)
                KeyboardShortcuts.Recorder(
                    "Show or hide calculator", name: .toggleCalculator)
                    .disabled(!preferences.shortcutsEnabled)
                KeyboardShortcuts.Recorder(
                    "Toggle always on top", name: .toggleAlwaysOnTop)
                    .disabled(!preferences.shortcutsEnabled)
#else
                LabeledContent("Shortcuts") {
                    Text("Requires the KeyboardShortcuts package")
                        .foregroundStyle(.secondary)
                }
#endif
            } footer: {
                Text("The shortcuts work from any application. Showing the "
                     + "calculator from another desktop brings it to that desktop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    let actions: SettingsActions

    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                Button("Restore Default Settings…") {
                    isConfirmingReset = true
                }
                .accessibilityIdentifier("restore-defaults-button")
            }
            Section {
                LabeledContent("Custom Epsilon Framework") {
                    Text("Coming in a future release.")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
        .alert("Restore all settings to their default values?",
               isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Defaults", action: actions.restoreDefaultSettings)
        } message: {
            Text("Every preference and both keyboard shortcuts will return "
                 + "to their defaults. The calculator window keeps its "
                 + "current position and size.")
        }
    }
}
