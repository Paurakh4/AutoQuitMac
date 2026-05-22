# AutoQuit

AutoQuit is a lightweight macOS utility that automatically quits applications when their last window is closed. It helps keep your workspace clean and saves system resources by ensuring that apps don't stay running in the background unnecessarily.

## Features

- **Automatic Termination**: Automatically quits apps when you close their last standard window.
- **Smart Detection**: Distinguishes between standard windows and background/utility windows.
- **Menu Bar Integration**: Runs quietly in the menu bar for easy access.
- **Accessibility Integration**: Uses macOS Accessibility APIs to monitor window states securely.

## Why AutoQuit?

If you've recently moved from Windows to macOS, you might find it irritating that closing the last window of an app doesn't actually quit the application. On macOS, many apps (like Mail, Calendar, or Spotify) stay running in the dock even after you've closed all their windows. AutoQuit bridges this gap by bringing the familiar "close to quit" behavior to your Mac, keeping your workspace clean and saving system resources.

## How it Works

Many macOS applications (like Mail, Calendar, or Spotify) continue to run even after you've closed all their windows. AutoQuit monitors these applications and sends a terminate signal once it detects that no visible, standard windows remain open.

## Installation

1. Download the latest `AutoQuit.app.zip` from GitHub Releases, or build the project locally with Xcode.
2. Unzip the archive and move `AutoQuit.app` to your `/Applications` folder.
3. Launch the app.
4. **Grant Permissions**: AutoQuit requires **Accessibility** permissions to monitor other apps' windows. Follow the on-screen instructions to enable this in `System Settings > Privacy & Security > Accessibility`.

## Development

- **Language**: Swift
- **Framework**: SwiftUI / AppKit
- **Requirements**: macOS 12.0 or later, including newer Tahoe releases such as macOS 26.5

### Building from Source

```bash
git clone https://github.com/[your-username]/AutoQuit.git
cd AutoQuit
open AutoQuit.xcodeproj
```

Build and run the project directly from Xcode.

## Release Process

- Build release artifacts from the Xcode project, not from a checked-in `.app` bundle.
- Package the release as `AutoQuit.app.zip` so the download URL stays stable.
- Verify the built app reports `LSMinimumSystemVersion = 12.0` before publishing.

## License

This project is licensed under a custom **Personal Use & Non-Commercial License** - see the [LICENSE](LICENSE) file for details.
