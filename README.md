<div align="center">

# NUMWORKS APP FOR MAC

</div>

A native macOS application that embeds the official **NumWorks htlm simulator** into a real `.app`, with full macOS integration, offline support, and built-in update mechanisms.

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

<img width="315" height="611" alt="NumWorks App Preview" src="https://github.com/user-attachments/assets/054255dc-bfcb-4314-8de6-0241dce6d988" />

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

   <img width="261" height="265" alt="Security Warning" src="https://github.com/user-attachments/assets/cc02b7e0-5220-4e7a-9ea5-d83e355945bb" />

4. Open **System Settings → Privacy & Security**, then click **Open Anyway**:

   <img width="737" height="648" alt="Open Anyway" src="https://github.com/user-attachments/assets/a2b2fa2f-db6a-49ec-b6ae-9c7ad19b583e" />

5. **Move the app to your Applications folder** (recommended).

The app is now ready to use.

---

## Updates

### App Updates
- The app checks for updates automatically
- Updates are handled **inside the app**
- When an update is available:
  - The new version is downloaded to `~/Downloads`
  - You are prompted to open the updated app

> For app updates to work correctly, the app **must be located in the Applications folder**.

### Simulator (Epsilon) Updates
- The NumWorks simulator is managed separately from the app
- Simulator files are stored in **Application Support**
- If no simulator is installed, or if it is outdated, the app **forces a simulator update**
- Simulator updates can also be triggered manually from Settings

---

## Offline Support

- The simulator is downloaded and stored locally
- Once installed, the calculator works **fully offline**
- An internet connection is only required:
  - on first launch
  - or when checking for updates

There are **no bundled simulators** inside the app — everything is managed dynamically.

---

## Settings & Customization

The app includes a native **Settings window** with multiple tabs:

### General
- Menu bar icon visibility
- Dock icon visibility
- Pin / unpin calculator window
- Keyboard shortcuts
- Launch at login

### App Update
- Manual “Check for updates” button
- In-app update UI if a new version is available

### Epsilon Update
- Displays the current simulator version
- Manual “Check for updates” button
- In-app simulator update UI
- Alert when already up to date

### About
- App version
- Simulator version
- Project links and license

### Accessing Settings

You can open the Settings window:
1. By right-clicking the menu bar icon  
2. From the macOS menu bar: **NumWorks → Settings**

<img width="357" height="308" alt="Settings Menu" src="https://github.com/user-attachments/assets/cbd895cd-71b2-44a3-8bd5-2d7047f08399" />

---
## Advanced
If you want to use a custom NumWorks framework (not the official simulator provided by NumWorks) follow these instuctions:
- Got to ~/Library/Application Support/<USERNAME>.NumworksApplication/Simulator/current'
- Paste your custom framework
- Make sure you name it `numworks-simulator-99.99.99.html` to avoid triggering the simulator auto updater.

- [ ] I plan to add an option in settings to disable `Webinjection.swift`so it doesn't mess up with your custom framework


---

## License

This project is licensed under the **MIT License**.

Copyright (c) 2025–2026 **EllandeVED**

This app embeds the official **NumWorks web simulator**, which is developed and licensed separately by **NumWorks** under the **GNU General Public License v3 (GPL-3.0)**.

This project is **not affiliated with, endorsed by, or sponsored by NumWorks**.

---

## Contributing & Feedback

Issues, feature requests, and pull requests are welcome.

If you find this project useful, feel free to star the repository and share it with others.
