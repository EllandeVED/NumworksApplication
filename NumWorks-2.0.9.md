## What's New in 2.x.x

This release introduces a modern update system powered by [Sparkle](https://github.com/sparkle-project/Sparkle), the standard open-source framework for keeping macOS apps up to date securely and reliably.

NumWorks now embeds a compiled build of [Epsilon](https://github.com/numworks/epsilon) (the official calculator firmware) taken directly from NumWorks’ open-source project on GitHub, rather than relying on their website’s HTML simulator at [numworks.com](https://www.numworks.com/simulator/download/).

### This make the calculator
- **Safer, more reliable updates** — Sparkle verifies each release cryptographically before installing
- **Closer to the real calculator** — running native Epsilon improves stability and makes the display feel calmer and more consistent
- **Built from upstream source** — easier to track official Epsilon improvements as they ship

With any new updates to the Epsilon software, an automatic GitHub Action will publish an update so that you always get the latest version of NumWorks. 

### 2.0.7
- Bug fix: the calculator would stay hidden behind the front most app 

### 2.0.8
- Bug fix: Fixed logic with the automatic update checkbox
- Chage: AppMover is now triggered once on first launch

### 2.0.9
- Updates check on launch now


**Full Changelog**: https://github.com/EllandeVED/NumworksApplication/compare/2.0.8...2.0.9
