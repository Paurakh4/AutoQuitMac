# AutoQuit

AutoQuit is a lightweight macOS utility that automatically quits applications when their last window is closed. It helps keep your workspace clean and saves system resources by ensuring that apps don't stay running in the background unnecessarily.

## Features

- **Automatic Termination**: Automatically quits apps when you close their last standard window.
- **Smart Detection**: Distinguishes between standard windows and background/utility windows.
- **Menu Bar Integration**: Runs quietly in the menu bar for easy access.
- **Accessibility Integration**: Uses macOS Accessibility APIs to monitor window states securely.

## How it Works

Many macOS applications (like Mail, Calendar, or Spotify) continue to run even after you've closed all their windows. AutoQuit monitors these applications and sends a terminate signal once it detects that no visible, standard windows remain open.

## Installation

1. Download or build the project using Xcode.
2. Move `AutoQuit.app` to your `/Applications` folder.
3. Launch the app.
4. **Grant Permissions**: AutoQuit requires **Accessibility** permissions to monitor other apps' windows. Follow the on-screen instructions to enable this in `System Settings > Privacy & Security > Accessibility`.

## Development

- **Language**: Swift
- **Framework**: SwiftUI / AppKit
- **Requirements**: macOS 12.0 or later

### Building from Source

```bash
git clone https://github.com/[your-username]/AutoQuit.git
cd AutoQuit
open AutoQuit.xcodeproj
```

Build and run the project directly from Xcode.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
