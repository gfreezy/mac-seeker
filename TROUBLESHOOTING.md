# Troubleshooting Guide

## Daemon Registration Error: Code 22 "Invalid argument"

If you see this error when trying to register the daemon:
```
Error Domain=SMAppServiceErrorDomain Code=22 "Invalid argument"
```

### Solution Steps:

1. **Clean and Rebuild:**
   ```bash
   xcodebuild clean -scheme seeker
   xcodebuild -scheme seeker -configuration Debug build
   ```

2. **Check the plist file in the built app:**
   ```bash
   cat /Users/feichao/Library/Developer/Xcode/DerivedData/seeker-*/Build/Products/Debug/seeker.app/Contents/Library/LaunchDaemons/io.allsunday.seeker.launchDaemon.plist
   ```

   It should look like:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>io.allsunday.seeker.launchDaemon</string>
       <key>BundleProgram</key>
       <string>Contents/MacOS/launchDaemon</string>
       <key>MachServices</key>
       <dict>
           <key>io.allsunday.seeker.launchDaemon</key>
           <true/>
       </dict>
       <key>StandardOutPath</key>
       <string>/tmp/io.allsunday.seeker.launchDaemon.out.log</string>
       <key>StandardErrorPath</key>
       <string>/tmp/io.allsunday.seeker.launchDaemon.err.log</string>
   </dict>
   </plist>
   ```

3. **Verify the daemon executable exists:**
   ```bash
   ls -la /Users/feichao/Library/Developer/Xcode/DerivedData/seeker-*/Build/Products/Debug/seeker.app/Contents/MacOS/launchDaemon
   ```

4. **Check if a previous daemon is registered:**
   ```bash
   # Check if daemon is already registered
   launchctl print-disabled system | grep seeker
   ```

5. **If daemon was previously registered, unregister first:**
   - Open System Settings
   - Go to General → Login Items & Extensions
   - Find "io.allsunday.seeker.launchDaemon" and remove it
   - Or use the "Unregister Daemon" button in the app

6. **Try registering again:**
   - Run the app from Xcode
   - Click "Edit Config"
   - Click "Register Daemon"

## Daemon Registration Error: Code 1 "Operation not permitted"

This means you need to grant permission in System Settings.

### Solution:
1. Go to System Settings → General → Login Items & Extensions
2. Look for "seeker" or "io.allsunday.seeker.launchDaemon"
3. Toggle it ON
4. Try starting the seeker again

## XPC Connection Issues

If you see "XPC connection interrupted" or "XPC connection invalidated":

### Solution:
1. Make sure the daemon is registered and enabled
2. Check daemon logs:
   ```bash
   tail -f /tmp/io.allsunday.seeker.launchDaemon.out.log
   tail -f /tmp/io.allsunday.seeker.launchDaemon.err.log
   ```
3. Try unregistering and re-registering the daemon
4. Restart the app

## Rust Binary Not Found

If the daemon can't find the Rust seeker binary:

### Solution:
1. Check if the binary was built:
   ```bash
   ls -la /Users/feichao/Library/Developer/Xcode/DerivedData/seeker-*/Build/Products/Debug/seeker.app/Contents/MacOS/seeker-proxy
   ```

2. If not found, rebuild:
   ```bash
   xcodebuild clean -scheme seeker
   xcodebuild -scheme seeker -configuration Debug build
   ```

3. Make sure Rust is installed:
   ```bash
   cargo --version
   ```

4. Initialize git submodule:
   ```bash
   git submodule update --init --recursive
   ```

## Config File Issues

If the seeker starts but fails immediately:

### Solution:
1. Check if config file exists:
   ```bash
   ls -la ~/Library/Containers/io.allsunday.seeker/Data/Library/Application\ Support/seeker/config.yml
   ```

2. If not, run setup script:
   ```bash
   ./scripts/setup-config.sh
   ```

3. Validate config file syntax (YAML)

4. Check seeker logs:
   ```bash
   cat ~/Library/Containers/io.allsunday.seeker/Data/Library/Logs/seeker.log
   ```

## General Debugging Tips

1. **Check all logs:**
   - Daemon logs: `/tmp/io.allsunday.seeker.launchDaemon.{out,err}.log`
   - Seeker logs: `~/Library/Containers/io.allsunday.seeker/Data/Library/Logs/seeker.log`
   - Xcode console output

2. **Verify all components:**
   ```bash
   # Check daemon status
   launchctl print system/io.allsunday.seeker.launchDaemon

   # Check if seeker process is running
   ps aux | grep seeker
   ```

3. **Clean slate approach:**
   ```bash
   # Unregister daemon
   # (Use "Unregister Daemon" button in app)

   # Clean build
   xcodebuild clean -scheme seeker

   # Remove derived data
   rm -rf ~/Library/Developer/Xcode/DerivedData/seeker-*

   # Rebuild
   xcodebuild -scheme seeker -configuration Debug build

   # Register daemon again
   ```

4. **Check System Settings:**
   - macOS may require manual approval for the daemon
   - Check General → Login Items & Extensions
   - Look for pending approvals

## Still Having Issues?

1. Check the daemon initialization logs in `/tmp/`
2. Verify code signing is working
3. Make sure you're running macOS 13.0 or later
4. Try building and running from Xcode instead of command line
5. Check if any security software is blocking the daemon
