<div align="center">

# NUMWORKS APP FOR MAC

<img width="128" height="128" alt="icon_128x128" src="https://github.com/user-attachments/assets/ebf83080-d4f8-4cfd-9b79-790e0f1f98ce" />

</div>

A native macOS application that embeds **[Epsilon](https://github.com/numworks/epsilon)** — NumWorks’ open-source calculator firmware — as a real `.app`, with menu bar integration, keyboard shortcuts, offline use, and automatic updates via [Sparkle](https://github.com/sparkle-project/Sparkle).

---

> **This is an independent project and is not affiliated with, endorsed by, or sponsored by NumWorks.**

> The purpose of this project is to provide a native macOS shell around Epsilon, with desktop integration and update management.

> Looking for the **previous generation** of this app (embedded **HTML** NumWorks simulator)? See release **[1.3.1](https://github.com/EllandeVED/NumworksApplication/releases/tag/1.3.1)** — the last version based on the web simulator. Current releases (**2.x**) use a compiled Epsilon build from [github.com/numworks/epsilon](https://github.com/numworks/epsilon) instead.

---

## Overview

**NumWorks App for Mac** aims to make the calculator feel at home on macOS:

- Runs as a real macOS app (Dock, menu bar, global shortcuts, Settings)
- Embeds a **compiled Epsilon** simulator (same engine as the physical calculator)
- Works **fully offline** once installed
- **App updates** via Sparkle (signed appcast on GitHub Pages)
- Optional automatic tracking of new **upstream Epsilon** versions (maintainers)

No browser, no WebKit, no download of the official HTML simulator at runtime.

---

## Preview

<div align="center">
  <img width="265" height="479" alt="NumWorks App Preview" src="https://github.com/user-attachments/assets/c5fba75b-d4da-41e8-8c04-0a69f164ffa7" />
  <img width="420" height="435" alt="Settings" src="https://github.com/user-attachments/assets/74369c62-eb10-4cdd-ba53-83053fdc70d6" />
</div>

---

## Installation

### Requirements

- **macOS 15.5** or later (deployment target of the current build)
- Apple Silicon or Intel Mac

### Option 1 — Download

1. Open the latest release:  
   [https://github.com/EllandeVED/NumworksApplication/releases/latest](https://github.com/EllandeVED/NumworksApplication/releases/latest)

2. Download **`NumWorks-<version>.zip`** (for example `NumWorks-2.0.6.zip`).

3. Unzip, then drag **NumWorks** into **Applications**.

4. Because the app may not be notarized with a paid Developer ID, macOS can show a security warning:

<img width="220" height="200" alt="Security Warning" src="https://github.com/user-attachments/assets/12e0d587-f73c-43fb-a1dd-d413e34dacba" />

5. Open **System Settings → Privacy & Security**, then choose **Open Anyway**:

   <img width="379" height="324" alt="Open Anyway" src="https://github.com/user-attachments/assets/a2b2fa2f-db6a-49ec-b6ae-9c7ad19b583e" />

> **Put the app in `/Applications`.** Sparkle updates are disabled until it lives there (you’ll also see a prompt in Settings).

### Option 2 — Build from source

```bash
git clone https://github.com/EllandeVED/NumworksApplication.git
cd NumworksApplication
# Prepare & build the linked Epsilon static library, then open in Xcode:
./NumWorks/Scripts/prepare-epsilon.sh latest   # or a specific tag, e.g. 23.2.3
./NumWorks/Scripts/build-epsilon-lib.sh
open NumWorks.xcodeproj
```

The `main` branch tracks the current native (Epsilon) app.

---

## Updates

### App updates (Sparkle)

- The app can check for updates automatically (toggle in **Settings → General**).
- You can also use **Check for Updates…** from the menu or Settings.
- Release notes appear in the Sparkle UI.

> Updates only install when the app is in the **Applications** folder.

### Epsilon (calculator engine)

- Each app release embeds a specific Epsilon version (shown in **Settings → About**).
- Upstream Epsilon changes ship with new app releases (sometimes prepared automatically for maintainers when a new Epsilon tag appears).
- There is **no** separate “simulator download” into Application Support anymore.

---

## Offline support

- After installation, the calculator runs **entirely locally**.
- Network access is only needed to **check for / download app updates** (GitHub / GitHub Pages).

---

## Features (macOS shell)

- Show / hide calculator (menu bar or global shortcut)
- Always on top (pin)
- Native or toolbar window chrome
- Launch at login, Dock icon on/off, menu bar icon style
- Window size / position remembered

---

## Known issues

- [ ] **⌘,** to open Settings is not always reliable. Workaround: open Settings from the menu bar icon menu, or focus the menu bar item first, then try ⌘, again.

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**.

Copyright (c) 2025–2026 **EllandeVED**

See the [`LICENSE`](LICENSE) file in this repository for the full text.

The app embeds **[Epsilon](https://github.com/numworks/epsilon)** (also GPLv3) and uses other third-party components (for example [Sparkle](https://github.com/sparkle-project/Sparkle)) under their respective licenses. Combining this shell with Epsilon means redistributed binaries of the app are covered by **GPLv3**: you may use, study, share, and modify the software, and derivative works must remain under GPLv3 with appropriate attribution and source availability.

This project is **not** affiliated with, endorsed by, or sponsored by NumWorks.

---

## Privacy

NumWorks for Mac does not collect, store, or send personal data about your usage.

- Settings live only on your Mac (`UserDefaults`).
- Update checks contact **GitHub** / **GitHub Pages** (Sparkle appcast and releases).
- The calculator runs **locally** inside the app process (no embedded browser, no numworks.com simulator fetch).

---

## Contributing & feedback

Issues, feature requests, and pull requests are welcome.

If you find this project useful, feel free to star the repository and share it with others.
