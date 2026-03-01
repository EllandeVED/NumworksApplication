<div align="center">

# NUMWORKS APP FOR MAC

<img width="128" height="128" alt="icon_128x128" src="https://github.com/user-attachments/assets/ebf83080-d4f8-4cfd-9b79-790e0f1f98ce" />

</div>

A native macOS application that embeds the official **NumWorks htlm simulator** into a real `.app`, with full macOS integration, offline support, and built-in update mechanisms.

---

> This is an independent project and is not affiliated with, endorsed by, or sponsored by NumWorks.

---

## Overview

**NumWorks App for Mac** provides a smooth, native experience around the official NumWorks simulator:

- Runs as a real macOS app (menu bar, Dock, shortcuts)
- Uses the official NumWorks web simulator
- Manages **offline simulator assets** automatically
- Handles **app updates** and **simulator (Epsilon) updates** directly inside the app
- No browser required

The goal is to make the NumWorks calculator feel like a first-class macOS application.

---

## Preview

<img width="265" height="479" alt="NumWorks App Preview" src="https://github.com/user-attachments/assets/c5fba75b-d4da-41e8-8c04-0a69f164ffa7" />

The app includes a full **Settings panel** to control appearance, behavior, and updates.

---

## Installation

### Requirements
- **macOS 15.0 (Sonoma) or later**
- Apple Silicon or Intel Mac

### Steps

1. Go to the latest release:  
   https://github.com/EllandeVED/NumworksApplication/releases/latest

2. Download the `.zip` file.

3. Unzip it and open the app.  
   Because the app is not signed with a paid Apple Developer ID, macOS will display a security warning:

<img width="220" height="200" alt="Security Warning" src="https://github.com/user-attachments/assets/12e0d587-f73c-43fb-a1dd-d413e34dacba" />

4. Open **System Settings → Privacy & Security**, then click **Open Anyway**:

   <img width="379" height="324" alt="Open Anyway" src="https://github.com/user-attachments/assets/a2b2fa2f-db6a-49ec-b6ae-9c7ad19b583e" />

5. **Move the app to your Applications folder** (recommended).

The app is now ready to use.

---

## Updates

### App Updates
- The app checks for updates automatically
- Updates are handled **inside the app**


> For app updates to work correctly, the app **must be located in the Applications folder**.

### Simulator (Epsilon) Updates
- The NumWorks simulator is managed separately from the app
- Simulator files are stored in **Application Support** (at `~/Library/Application Support/<USERNAME>.NumworksApplication/Simulator/current`)
- If no simulator is installed, the app **forces a simulator instalation** (it won't work without it)
- If it is outdated, the app **suggests a simulator update** (see [**Advanced**](https://github.com/EllandeVED/NumworksApplication?tab=readme-ov-file#advanced) to embed yoou own simulator this)

---

## Offline Support

- The simulator is downloaded and stored locally
- Once installed, the calculator works **fully offline**
- An internet connection is only required:
  - on first launch
  - or when checking for updates

> This app **does not bundled the official NumWorks simulator** — everything is managed dynamically.


---
## Advanced
If you want to use a custom NumWorks framework (not the official simulator provided by NumWorks) follow these instuctions:
1. Go to `~/Library/Application Support/<USERNAME>.NumworksApplication/Simulator/current`
2. Paste your custom framework
3. Make sure you name it `numworks-simulator-99.99.99.html` to avoid triggering the simulator auto updater.

- [x] I plan to add an option in settings to disable `Webinjection.swift`so it doesn't mess up with your custom framework (Done)


---

## License

This project is licensed under the **MIT License**.

Copyright (c) 2025–2026 **EllandeVED**

This project includes third-party open-source components licensed under their respective licenses  
(e.g. MIT, BSD). See individual repositories for details.

This app **does not embed** or redistribute the official **NumWorks web simulator**.
Instead, the simulator is downloaded directly from the **official NumWorks** source after the application is launched.

The **NumWorks web simulator** is developed and licensed **separately** by NumWorks under the **GNU General Public License v3 (GPL-3.0)**.

This project is **not affiliated with, endorsed by, or sponsored by NumWorks**.

---

## Contributing & Feedback

Issues, feature requests, and pull requests are welcome.

If you find this project useful, feel free to star the repository and share it with others.
