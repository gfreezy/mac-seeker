# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Seeker is a macOS menu bar application that manages a Rust-based proxy server through a privileged launch daemon. The Mac app provides a user-friendly interface to control the Rust seeker process, which handles network traffic routing and proxy functionality.

The Rust seeker is included as a Git submodule from https://github.com/gfreezy/seeker and is automatically compiled during the Xcode build process. The architecture uses XPC (Cross-Process Communication) to allow the unprivileged menu bar app to control a privileged daemon that manages the Rust seeker process with root access.

## Architecture

### Three-Process Design

The application consists of three separate processes:

1. **Main App** (`seeker/` directory)
   - SwiftUI menu bar application (MenuBarExtra)
   - Provides UI for starting/stopping the Rust seeker
   - Acts as XPC client to communicate with the launch daemon
   - Uses `GlobalStateVm` as the central state manager

2. **Launch Daemon** (`launchDaemon/` directory)
   - Privileged daemon process that runs as a launchd service
   - Acts as XPC server and process manager
   - Manages the lifecycle of the Rust seeker process
   - Entry point: `launchDaemon/main.swift`

3. **Rust Seeker** (Git submodule at `rust-seeker/`)
   - The actual proxy server written in Rust (from https://github.com/gfreezy/seeker)
   - Built automatically during Xcode build via Run Script Phase
   - Started/stopped by the launch daemon via `Process` API
   - Bundled inside the app at `seeker.app/Contents/MacOS/seeker-proxy`
   - Runs with configuration from app sandbox container
   - Handles DNS, TUN device, and proxy routing

### Key Components

**GlobalStateVm** ([seeker/GlobalStateVm.swift](seeker/GlobalStateVm.swift))
- Observable view model managing app-wide state
- Handles daemon registration/unregistration via `SMAppService`
- Manages XPC connection lifecycle through `NSXPCConnection`
- Provides `callToDaemon()` method for type-safe XPC communication
- Controls Rust seeker start/stop through XPC calls
- Tracks `isStarted` state and `seekerStatus` for UI display

**XPC Communication**
- Protocol defined in `launchDaemon/launchDaemonProtocol.swift`
- Service name: `io.allsunday.seeker.launchDaemon`
- Connection established on-demand in `GlobalStateVm.connectToDaemon()`
- Uses privileged mach service with `.privileged` option

**XPC Methods Available:**
- `startSeeker()` - Launches the Rust seeker process
- `stopSeeker()` - Terminates the Rust seeker process
- `isSeekerRunning()` - Checks if the process is running
- `getSeekerStatus()` - Returns status string with PID if running

**ServiceManagement Integration**
- Uses `SMAppService.daemon()` for daemon lifecycle management
- Plist location: `seeker/io.allsunday.seeker.launchDaemon.plist`
- Auto-start on login managed via `SMAppService.mainApp`
- Daemon logs to: `/tmp/io.allsunday.seeker.launchDaemon.{out,err}.log`

### Entitlements

The main app runs **without** App Sandbox (`com.apple.security.app-sandbox: false`) to enable:
- XPC communication with privileged daemon
- ServiceManagement framework access for daemon registration

## Build Commands

### Prerequisites

1. **Install Rust** (required for building the Rust seeker binary):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Initialize Git Submodule** (first time only):
   ```bash
   git submodule update --init --recursive
   ```

### Building the App

The build process automatically compiles the Rust seeker binary via a Run Script Phase in Xcode.

```bash
# Build main app, daemon, and Rust seeker
xcodebuild -scheme seeker -configuration Debug build

# Build daemon only
xcodebuild -scheme launchDaemon -configuration Debug build

# Build for Release (optimized Rust binary)
xcodebuild -scheme seeker -configuration Release build
```

The Rust binary is automatically:
- Built from `rust-seeker/` submodule
- Compiled in Debug or Release mode based on Xcode configuration
- Copied to `seeker.app/Contents/MacOS/seeker`

### Running Tests
```bash
# Run unit tests
xcodebuild test -scheme seeker -target seekerTests

# Run UI tests
xcodebuild test -scheme seeker -target seekerUITests
```

### Cleaning Build Artifacts
```bash
xcodebuild clean -scheme seeker
```

## Development Workflow

### Running the App from Xcode
Open `seeker.xcodeproj` in Xcode and run the `seeker` scheme. The app will appear in the menu bar with a fish icon.

### Daemon Management
- Register daemon: Use the "Register Daemon" button in the Edit Config window
- Unregister daemon: Use the "Unregister Daemon" button
- Check daemon status: Displayed in the Edit Config window
- Manual daemon logs: Check `/tmp/io.allsunday.seeker.launchDaemon.out.log` and `.err.log`

### Managing the Rust Seeker Process

**Binary Location:**
- Built from `rust-seeker/` Git submodule during Xcode build
- Bundled at: `seeker.app/Contents/MacOS/seeker-proxy`
- Config: `~/Library/Containers/io.allsunday.seeker/Data/Library/Application Support/seeker/config.yml`
- Working Directory: `~/Library/Containers/io.allsunday.seeker/Data/Library/Application Support/seeker`

**First-Time Setup:**
Run the setup script to create the default config:
```bash
./scripts/setup-config.sh
```

This creates the config file in the app sandbox container from the sample config in the rust-seeker submodule.

**Process Management:**
- Launch daemon finds the binary path dynamically from the app bundle
- Uses Swift's `Process` API to spawn the Rust binary
- Uses App Group container (`6NVVN7F4WA.io.allsunday.seeker`) for shared file access
- Launches with: `seeker-proxy -c <sandbox-config-path>`
- Logs all output to the app sandbox container
- Monitors process termination via `terminationHandler`
- Supports graceful shutdown with fallback to force kill

**Viewing Logs:**
- Click "Open Log" in the menu bar to open the log file
- Log file location: `~/Library/Containers/io.allsunday.seeker/Data/Library/Logs/seeker.log`
- Logs include startup time, all seeker output (stdout/stderr), and termination status
- Use Console.app or any text editor to view logs

### Starting/Stopping Seeker

From the UI (ContentView):
```swift
// Start seeker
globalState.toggle() // or globalState.start()

// Stop seeker
globalState.stop()

// Check status
await globalState.updateSeekerStatus()
```

From the menu bar:
- Click fish icon in menu bar
- Select "Start" or "Stop"
- Status reflects whether the Rust process is running

### Adding New XPC Methods

1. Add method signature to `LaunchDaemonProtocol` in `launchDaemon/launchDaemonProtocol.swift`
2. Implement method in `LaunchDaemon` class in `launchDaemon/launchDaemon.swift`
3. Call from main app using `GlobalStateVm.callToDaemon { proxy in await proxy.yourMethod() }`

Example pattern:
```swift
// In protocol
@objc protocol LaunchDaemonProtocol: Sendable {
    func getSeekerLogs() async -> String
}

// In LaunchDaemon
func getSeekerLogs() async -> String {
    // Implementation
}

// In main app
let logs = try await globalState.callToDaemon { proxy in
    await proxy.getSeekerLogs()
}
```

## Important Notes

### Bundle Identifier
The daemon identifier `io.allsunday.seeker.launchDaemon` must match across:
- `GlobalStateVm.swift` (constant `launchDaemonIdentifier`)
- `launchDaemon/main.swift` (constant `launchDaemonIdentifier`)
- `io.allsunday.seeker.launchDaemon.plist` (`Label` and `MachServices` keys)

### Daemon Lifecycle
- Daemon has `KeepAlive: true` - automatically restarted if it crashes
- Daemon has `RunAtLoad: true` - starts immediately when registered
- Connection is lazy-initialized and cached in `GlobalStateVm.connectionToService`
- Always call `closeConnectionToDaemon()` when done to free resources

### Common Gotchas
- The daemon plist must be named exactly `io.allsunday.seeker.launchDaemon.plist` to match the `launchedDaemonServiceName` constant
- App must not be sandboxed for XPC communication with privileged daemon
- Daemon registration requires user approval on first run (appears in System Settings)
- Changes to daemon code require unregistering and re-registering the daemon
- The Rust seeker requires root privileges for TUN device and DNS operations
- Config file changes require restarting the Rust seeker process
- Don't forget to run `git submodule update --init --recursive` after cloning
- Rust must be installed for the build to succeed (install via rustup)
- The Rust binary is automatically rebuilt when you build the Xcode project
