<div align="center">

# NUMWORKS APP FOR MAC

<img width="128" height="128" alt="icon_128x128" src="https://github.com/user-attachments/assets/ebf83080-d4f8-4cfd-9b79-790e0f1f98ce" />

 
 
**Download Latest Version [HERE](https://github.com/EllandeVED/NumworksApplication/releases/latest)**
</div>

A native macOS application that embeds **[Epsilon](https://github.com/numworks/epsilon)** (NumWorks’ open-source calculator firmware) as a real `.app`, with menu bar integration, keyboard shortcuts and automatic updates (using [Sparkle](https://github.com/sparkle-project/Sparkle)).



> **This is an independent project and is not affiliated with, endorsed by, or sponsored by NumWorks.**

> The purpose of this project is to provide a native macOS shell around Epsilon, with desktop integration and update management.

> Looking for the **previous generation** of this app (embedded **HTML** NumWorks simulator)? See release **[1.3.1](https://github.com/EllandeVED/NumworksApplication/releases/tag/1.3.1)** — the last version based on the web simulator. Current releases (**2.x**) use a compiled Epsilon build from [github.com/numworks/epsilon](https://github.com/numworks/epsilon) instead.

---

## Overview
No official Numworks app really exists so I made my own.

- Runs as a real macOS app (Dock, menu bar, global shortcuts, Settings)
- Embeds a **compiled Epsilon** simulator (same engine as the physical calculator)
- **App updates** via Sparkle and a GitHub bot automatically updates when epsilon repository publishes a new version


<div align="center">
 <img width="194" height="342" alt="image" src="https://github.com/user-attachments/assets/7e98aef0-7de8-4669-b269-34db9c60971a" /><img width="281" height="330" alt="image" src="https://github.com/user-attachments/assets/39b4e099-3af9-41d8-9913-d3c0d279097b" />

</div>

## Installation

### Requirements

- **macOS 15.5** or later (I mean... it should work on older version I guess)

### Option 1 — Download

1. Open the latest release:  
   [https://github.com/EllandeVED/NumworksApplication/releases/latest](https://github.com/EllandeVED/NumworksApplication/releases/latest)

2. Download **`NumWorks-LATESTVERSION.zip`**

3. Unzip, then drag **NumWorks** into **Applications**.

4. Because the app is not  notarized with a paid Developer ID, macOS can show a security warning:

<img width="220" height="200" alt="Security Warning" src="https://github.com/user-attachments/assets/12e0d587-f73c-43fb-a1dd-d413e34dacba" />

5. Open **System Settings → Privacy & Security**, then choose **Open Anyway**:

   <img width="379" height="324" alt="Open Anyway" src="https://github.com/user-attachments/assets/a2b2fa2f-db6a-49ec-b6ae-9c7ad19b583e" />


### Option 2 — Build from source

```bash
git clone https://github.com/EllandeVED/NumworksApplication.git
cd NumworksApplication
# Prepare & build the linked Epsilon static library, then open in Xcode:
./NumWorks/Scripts/prepare-epsilon.sh latest   # or a specific ref, e.g. version-25
./NumWorks/Scripts/build-epsilon-lib.sh
open NumWorks.xcodeproj
```

## Updates

### App updates ([Sparkle](https://github.com/sparkle-project/Sparkle))

- The app can check for updates automatically (toggle in **Settings → General**).
- You can also use **Check for Updates…** from the menu or Settings.
- Release notes appear in the Sparkle UI.

> Updates only install when the app is in the **Applications** folder.

### Epsilon (calculator engine)

- Directly retrieved from [Epsilon](https://github.com/numworks/epsilon) and slightly modified to embed it into an app window

## Features

- Show / hide calculator (menu bar or global shortcut)
- Always on top (pin)
- Menubar icon


## Known issues

- [ ] **⌘,** to open Settings is not always reliable.

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

- The calculator runs **locally** and only connects to internet for update checks (can be disabled)

---

## Contributing & feedback

Issues, feature requests, and pull requests are welcome.

If you find this project useful, feel free to star the repository and share it with others.
