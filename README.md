# Seeker macOS App

A macOS menu bar application that provides a convenient interface for managing the [Seeker](https://github.com/gfreezy/seeker) Rust-based proxy server.

## Features

- 🎯 Menu bar interface for easy access
- 🚀 One-click start/stop of the Seeker proxy
- 🔀 Persistent proxy-group switching directly from the menu bar
- ✨ Daily update checks through signed GitHub Releases
- 🔒 Privileged daemon for managing system-level operations
- 🔄 Auto-start on login support
- ⚙️ Configuration and logs stored in app sandbox container

## Prerequisites

1. **macOS 13.0+** (required for ServiceManagement framework)
2. **Xcode 15.0+**
3. **Rust toolchain** (install via [rustup](https://rustup.rs)):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd seeker
git submodule update --init --recursive
```

### 2. Setup Configuration

Run the setup script to create the default configuration:

```bash
./scripts/setup-config.sh
```

This creates the config file in the app sandbox container. Edit it to configure your proxy settings.

### 3. Build and Install

Use the build script to create a signed app bundle:

```bash
# Build Release version (recommended)
./scripts/build-and-export.sh release

# Build Debug version
./scripts/build-and-export.sh debug
```

This will:
- Build the Rust seeker binary from the submodule
- Create an archived app bundle signed with your Apple Development certificate

Install the app:

```bash
# Copy to Applications
cp -R build/export/seeker.app /Applications/
```

**Note:** The build script requires an Apple Development certificate in your Keychain. You can get one for free by signing into Xcode with your Apple ID.

Alternatively, build directly in Xcode:

```bash
open seeker.xcodeproj
```

The Rust seeker binary will be automatically compiled and bundled into the app.

### Alternative: Install from a Release DMG

Pre-built DMGs are published on the [Releases](https://github.com/gfreezy/mac-seeker/releases) page (built by GitHub Actions). These are signed with a **self-signed certificate** and are **not notarized by Apple**, so Gatekeeper will block them on first launch with a message like *"seeker.app is damaged and can't be opened."*

To run it, strip the quarantine attribute that macOS adds to downloaded files:

```bash
# 1. Open the DMG and drag seeker.app to /Applications, then:
xattr -dr com.apple.quarantine /Applications/seeker.app

# 2. Launch it
open /Applications/seeker.app
```

`xattr -dr com.apple.quarantine` recursively (`-r`) deletes (`-d`) the `com.apple.quarantine` extended attribute that triggers the Gatekeeper check. This only needs to be done once, right after installing.

> **Note:** Only do this for builds you trust (e.g. your own CI releases). If you'd rather avoid the manual step entirely, build from source with your own Apple Development certificate (above), or sign + notarize with a paid Apple Developer ID.

### 4. First Run Setup

1. Run the app - it will appear in your menu bar with a fish icon
2. Click the fish icon and select "Edit Config"
3. Click "Register Daemon" to install the launch daemon
4. Approve the daemon in System Settings → General → Login Items
5. Click "Start" to begin using Seeker

## Usage

### Menu Bar Controls

- **Start/Stop** - Launch or terminate the Seeker proxy
- **Proxy Groups** - Switch a group to a fixed server or restore automatic selection; a running Seeker instance restarts automatically
- **Open Settings** - Open the configuration window
- **Check for Updates…** - Check the stable GitHub Release feed immediately
- **Open Log** - Open the seeker log file in your default text editor
- **Auto Start** - Enable/disable auto-start on login
- **Quit** - Exit the application

### Configuration Window

- View daemon and seeker status
- Register/unregister the launch daemon
- Start/stop the Seeker process
- Refresh status information

## Architecture

The app consists of three components:

1. **Menu Bar App** - SwiftUI interface in the menu bar
2. **Launch Daemon** - Privileged daemon that manages the Seeker process
3. **Rust Seeker** - The actual proxy server (from [gfreezy/seeker](https://github.com/gfreezy/seeker))

Communication between components uses XPC (Cross-Process Communication) for security and stability.

Release builds check for updates once per day and ask before downloading and installing. Debug builds do not start the updater. Seeker's running state is restored after a successful update when the installed build version matches the selected update. The first updater-enabled version must still be installed manually by users of v1.0.2 or earlier.

## Development

### Project Structure

```
seeker/
├── seeker/              # Main menu bar app
├── launchDaemon/        # Privileged daemon
├── rust-seeker/         # Git submodule (Rust proxy server)
├── scripts/             # Build and setup scripts
└── CLAUDE.md           # Detailed development guide
```

### Build Process

When you build the Xcode project:

1. The "Build Rust Seeker" run script phase executes
2. It builds the Rust binary from `rust-seeker/` submodule
3. The binary is copied to `seeker.app/Contents/MacOS/seeker-proxy`
4. The daemon can then launch it with proper privileges

### Publishing a Release

Stable releases use `vX.Y.Z` tags. CI passes `X.Y.Z` to both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, verifies the archived bundle versions and code signatures, and publishes `Seeker.dmg` with a signed `appcast.xml`. The repository must have a `SPARKLE_ED_PRIVATE_KEY` Actions secret matching the public key embedded in the app. Keep the long-lived private key out of the repository and build logs. Because current CI releases use a non-Apple self-signed certificate, the packaging script explicitly signs Sparkle's nested helpers and disables library validation only on that self-signed artifact; Apple-signed builds retain normal library validation.

### Debugging

- **Daemon logs**: Check `/tmp/io.allsunday.seeker.launchDaemon.{out,err}.log`
- **Seeker logs**: Check `~/Library/Containers/io.allsunday.seeker/Data/Library/Logs/seeker.log`
- **Console.app**: Filter for "io.allsunday.seeker" to see all logs

### Making Changes

- **Swift code changes**: Just rebuild in Xcode
- **Daemon changes**: Unregister and re-register the daemon
- **Rust changes**: Rebuild in Xcode (or manually run `cargo build` in `rust-seeker/`)

## Troubleshooting

### "seeker.app is damaged and can't be opened" (or won't open)

This happens with DMGs downloaded from Releases because they are self-signed and not notarized. Remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/seeker.app
```

Then launch the app again. If you moved the app elsewhere, point the path at its actual location. To inspect the attribute first:

```bash
xattr /Applications/seeker.app        # lists com.apple.quarantine if present
```

### Build fails with "cargo: command not found"

Install Rust:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### Daemon won't start

1. Check System Settings → General → Login Items
2. Look for pending approval for the daemon
3. Check daemon logs in `/tmp/`

### Seeker won't start

1. Ensure the daemon is registered and running
2. Check that the config file exists and is valid:
   ```bash
   ls -la ~/Library/Containers/io.allsunday.seeker/Data/Library/Application\ Support/seeker/config.yml
   ```
3. Verify the Rust binary was built: `ls -la /path/to/seeker.app/Contents/MacOS/seeker-proxy`

### "rust-seeker" directory is empty

Initialize the submodule:
```bash
git submodule update --init --recursive
```

## License

This macOS wrapper follows the same license as the Seeker project. See the [rust-seeker](https://github.com/gfreezy/seeker) repository for details.

## Credits

- Seeker proxy server by [gfreezy](https://github.com/gfreezy/seeker)
- macOS app wrapper for convenient management
