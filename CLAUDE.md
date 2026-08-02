# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Seeker is a macOS menu bar application that manages a Rust-based proxy server through a privileged launch daemon. The Rust seeker (from https://github.com/gfreezy/seeker) is included as a Git submodule at `rust-seeker/` and compiled automatically during Xcode builds. The architecture uses XPC to allow the unprivileged menu bar app to control a privileged daemon that manages the Rust seeker process with root access.

## Build Commands

### Prerequisites
- **Rust**: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Git submodule**: `git submodule update --init --recursive`

### Building
```bash
# Build everything (main app + daemon + Rust binary via Run Script Phase)
xcodebuild -scheme seeker -configuration Debug build

# Build for Release (optimized Rust binary)
xcodebuild -scheme seeker -configuration Release build

# Build and export signed .app + DMG
./scripts/build-and-export.sh release    # or debug
```

### Tests
```bash
xcodebuild test -scheme seeker -target seekerTests
xcodebuild test -scheme seeker -target seekerUITests
```

### Clean
```bash
xcodebuild clean -scheme seeker
```

## Architecture

### Three-Process Design

1. **Main App** (`seeker/`) - AppKit menu bar app and XPC client
2. **Launch Daemon** (`launchDaemon/`) - Privileged launchd service, XPC server, manages Rust process lifecycle
3. **Rust Seeker** (`rust-seeker/` submodule) - The actual proxy server binary, bundled at `seeker.app/Contents/MacOS/seeker-proxy`

### Shared Code (`shared/`)

Local Swift package (`shared/Package.swift`) containing types shared between the main app and daemon:
- **`LaunchDaemonProtocol`** - XPC interface with methods: `startSeeker(config:)`, `stopSeeker()`, `getSeekerStatus()`
- **`SeekerConfig`** - NSSecureCoding-conformant config passed over XPC (binaryPath, configPath, logPath)
- **`SeekerStatusInfo`** - NSSecureCoding-conformant status with enum `.unknown/.stopped/.running(pid:)/.error(msg)`
- **`AnyError`** - Simple LocalizedError wrapper

Dependencies: [Yams](https://github.com/jpsim/Yams) (YAML parsing)

### Key Files

**State Management:**
- `seeker/GlobalStateVm.swift` - Central `@Observable` view model. Manages XPC connection, daemon registration via `SMAppService`, seeker start/stop, status polling. All XPC calls go through `callToDaemon { proxy in ... }`.

**Daemon:**
- `launchDaemon/main.swift` - Entry point. `ServiceDelegate` accepts XPC connections and auto-shuts down the seeker process when all connections close (2-second delay).
- `launchDaemon/launchDaemon.swift` - `LaunchDaemon` class implementing `LaunchDaemonProtocol`. Spawns `seeker-proxy` via `Process` API, captures stdout/stderr, handles graceful + force termination.

**Configuration:**
- `seeker/Models/SeekerConfiguration.swift` - Full config model (Codable to YAML). Includes `ProxyServer`, `ProxyGroup`, `ParsedRule`, `RuleType`, `RuleAction` types. Config keys use snake_case (`dns_start_ip`, `tun_name`, etc.).
- `seeker/Services/ConfigurationService.swift` - Loads/saves/edits YAML config. Tracks dirty state. Manages rules and server lists.
- `seeker/Services/RemoteConfigService.swift` - Fetches remote Clash/SS subscription URLs, parses Base64 SS and Clash YAML formats, caches results locally.

**Views:**
- `seeker/seekerApp.swift` - `@main` app entry. MenuBarExtra with fish icon, plus a "Settings" WindowGroup.
- `seeker/MenuBarController.swift` - Native status item and daemon/proxy controls.
- `seeker/AppKit/SettingsWindowController.swift` - Native settings sidebar and save/reload flow; section controllers live in `seeker/AppKit/`.

### File Paths at Runtime
- Config: `~/Library/Application Support/seeker/config.yml`
- Log: `~/Library/Application Support/seeker/seeker.log`
- Remote cache: `~/Library/Application Support/seeker/remote_cache/`
- Daemon logs: `/tmp/io.allsunday.seeker.launchDaemon.{out,err}.log`

### XPC Communication

- Service name: `io.allsunday.seeker.launchDaemon`
- Connection type: `NSXPCConnection` with `.privileged` mach service
- Protocol: `LaunchDaemonProtocol` (defined in `shared` package)
- The main app sends `SeekerConfig` (with binary path, config path, log path) to the daemon on start

### Adding New XPC Methods

1. Add method to `LaunchDaemonProtocol` in `shared/Sources/shared/shared.swift`
2. Implement in `LaunchDaemon` class in `launchDaemon/launchDaemon.swift`
3. Call from main app: `try await globalState.callToDaemon { proxy in await proxy.yourMethod() }`

Note: XPC types must conform to `NSSecureCoding`. See `SeekerConfig` and `SeekerStatusInfo` for examples.

## Important Constraints

### Bundle Identifier Consistency
`io.allsunday.seeker.launchDaemon` must match across:
- `GlobalStateVm.swift` (`launchDaemonIdentifier` constant)
- `launchDaemon/main.swift` (`launchDaemonIdentifier` constant)
- `seeker/io.allsunday.seeker.launchDaemon.plist` (`Label` and `MachServices` keys)

### Entitlements
The main app runs **without** App Sandbox (`com.apple.security.app-sandbox: false`) to enable XPC communication with the privileged daemon and ServiceManagement access.

### Gotchas
- Daemon plist must be named exactly `io.allsunday.seeker.launchDaemon.plist`
- Changes to daemon code require unregistering and re-registering the daemon
- `SMAppService` calls must happen on the main thread (see `getDaemonStatus()` for the pattern)
- Daemon has `RunAtLoad: true` and auto-shuts down when no XPC connections remain
- The Rust binary is renamed to `seeker-proxy` in the app bundle to avoid naming conflicts with the main app binary
- Swift 6 concurrency: daemon uses `nonisolated(unsafe)` for process/file handle properties and a `DispatchQueue` for synchronization
