#!/bin/bash

set -euo pipefail

abort() {
  printf "Error: %s\n" "$*" >&2
  exit 1
}

if [[ -z "${BASH_VERSION:-}" ]]; then
  abort "Bash is required to run this installer."
fi

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  abort "Seeker can only be installed on macOS."
fi

if [[ -t 1 ]]; then
  tty_blue="\033[1;34m"
  tty_green="\033[1;32m"
  tty_yellow="\033[1;33m"
  tty_reset="\033[0m"
else
  tty_blue=""
  tty_green=""
  tty_yellow=""
  tty_reset=""
fi

ohai() {
  printf "${tty_blue}==>${tty_reset} %s\n" "$*"
}

warn() {
  printf "${tty_yellow}Warning:${tty_reset} %s\n" "$*" >&2
}

version_at_least() {
  local current_major current_minor current_patch
  local required_major required_minor required_patch

  IFS=. read -r current_major current_minor current_patch <<< "$1"
  IFS=. read -r required_major required_minor required_patch <<< "$2"
  current_minor="${current_minor:-0}"
  current_patch="${current_patch:-0}"
  required_minor="${required_minor:-0}"
  required_patch="${required_patch:-0}"

  (( current_major > required_major )) ||
    (( current_major == required_major && current_minor > required_minor )) ||
    (( current_major == required_major && current_minor == required_minor && current_patch >= required_patch ))
}

RELEASE_URL="https://github.com/gfreezy/mac-seeker/releases/latest/download/Seeker.dmg"
INSTALL_DIR="${SEEKER_INSTALL_DIR:-/Applications}"
DESTINATION="$INSTALL_DIR/seeker.app"
INSTALLED_EXECUTABLE="$DESTINATION/Contents/MacOS/seeker"
NO_OPEN="${SEEKER_NO_OPEN:-0}"
ELEVATE=()
PENDING_APP=""
BACKUP_APP=""
INSTALL_COMPLETE=0

run_privileged() {
  if (( ${#ELEVATE[@]} )); then
    "${ELEVATE[@]}" "$@"
  else
    "$@"
  fi
}

if [[ "$INSTALL_DIR" != /* ]]; then
  abort "SEEKER_INSTALL_DIR must be an absolute path."
fi
if [[ ! -d "$INSTALL_DIR" ]]; then
  abort "The installation directory does not exist: $INSTALL_DIR"
fi

INSTALL_TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/seeker-install.XXXXXX")"
DMG_PATH="$INSTALL_TEMP_DIR/Seeker.dmg"
MOUNT_DIR="$INSTALL_TEMP_DIR/mount"
STAGED_APP="$INSTALL_TEMP_DIR/seeker.app"
MOUNTED=0

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$MOUNTED" == "1" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  if [[ -n "${INSTALL_TEMP_DIR:-}" && -d "$INSTALL_TEMP_DIR" ]]; then
    /bin/rm -rf "$INSTALL_TEMP_DIR"
  fi
  if [[ -n "$PENDING_APP" && -e "$PENDING_APP" ]]; then
    run_privileged /bin/rm -rf "$PENDING_APP" >/dev/null 2>&1 || true
  fi
  if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" && ! -e "$DESTINATION" ]]; then
    run_privileged /bin/mv "$BACKUP_APP" "$DESTINATION" >/dev/null 2>&1 || true
  elif [[ "$INSTALL_COMPLETE" == "1" && -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    run_privileged /bin/rm -rf "$BACKUP_APP" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ohai "Downloading the latest Seeker release"
/usr/bin/curl \
  --fail \
  --location \
  --proto '=https' \
  --tlsv1.2 \
  --retry 3 \
  --progress-bar \
  --output "$DMG_PATH" \
  "$RELEASE_URL"

if [[ ! -s "$DMG_PATH" ]]; then
  abort "The downloaded disk image is empty."
fi

ohai "Verifying and mounting Seeker.dmg"
/bin/mkdir -p "$MOUNT_DIR"
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$MOUNT_DIR" \
  "$DMG_PATH" >/dev/null
MOUNTED=1

SOURCE_APP="$MOUNT_DIR/seeker.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  abort "Seeker.dmg does not contain seeker.app."
fi

APP_INFO="$SOURCE_APP/Contents/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO" 2>/dev/null || true)"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_INFO" 2>/dev/null || true)"
CURRENT_MACOS="$(/usr/bin/sw_vers -productVersion)"

if [[ -n "$MINIMUM_MACOS" ]] && ! version_at_least "$CURRENT_MACOS" "$MINIMUM_MACOS"; then
  abort "Seeker $APP_VERSION requires macOS $MINIMUM_MACOS or newer; this Mac is running $CURRENT_MACOS."
fi

HOST_ARCH="$(/usr/bin/uname -m)"
if [[ "$HOST_ARCH" == "x86_64" ]] && [[ "$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || true)" == "1" ]]; then
  HOST_ARCH="arm64"
fi
PROXY_EXECUTABLE="$SOURCE_APP/Contents/MacOS/seeker-proxy"
PROXY_ARCHS="$(/usr/bin/lipo -archs "$PROXY_EXECUTABLE" 2>/dev/null || true)"
case " $PROXY_ARCHS " in
  *" $HOST_ARCH "*) ;;
  *) abort "This Seeker release does not support the $HOST_ARCH architecture." ;;
esac

ohai "Preparing Seeker ${APP_VERSION:-release}"
/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"
/usr/bin/xattr -cr "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"
/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

if [[ ! -w "$INSTALL_DIR" ]] || [[ -e "$DESTINATION" && ! -w "$DESTINATION" ]]; then
  if [[ ! -x /usr/bin/sudo ]]; then
    abort "Administrator access is required to install Seeker into $INSTALL_DIR."
  fi
  ohai "Requesting administrator access for $INSTALL_DIR"
  /usr/bin/sudo -v
  ELEVATE=(/usr/bin/sudo)
fi

PENDING_APP="$INSTALL_DIR/.seeker.app.install.$$"
BACKUP_APP="$INSTALL_DIR/.seeker.app.backup.$$"
if [[ -e "$PENDING_APP" || -e "$BACKUP_APP" ]]; then
  abort "Temporary installation paths already exist in $INSTALL_DIR."
fi

ohai "Installing Seeker into $DESTINATION"
run_privileged /usr/bin/ditto "$STAGED_APP" "$PENDING_APP"
run_privileged /usr/bin/xattr -cr "$PENDING_APP"
/usr/bin/codesign --verify --deep --strict "$PENDING_APP"

RUNNING_PIDS=()
while IFS= read -r running_pid; do
  if [[ -n "$running_pid" ]]; then
    RUNNING_PIDS+=("$running_pid")
  fi
done < <(/usr/bin/pgrep -f -x "$INSTALLED_EXECUTABLE" 2>/dev/null || true)
if (( ${#RUNNING_PIDS[@]} )); then
  ohai "Closing the installed Seeker app"
  /bin/kill -TERM "${RUNNING_PIDS[@]}" 2>/dev/null || true
  for _ in {1..30}; do
    if ! /usr/bin/pgrep -f -x "$INSTALLED_EXECUTABLE" >/dev/null 2>&1; then
      break
    fi
    /bin/sleep 0.1
  done
  if /usr/bin/pgrep -f -x "$INSTALLED_EXECUTABLE" >/dev/null 2>&1; then
    run_privileged /bin/rm -rf "$PENDING_APP"
    abort "The running Seeker app could not be closed. Quit it and run the installer again."
  fi
fi

if [[ -e "$DESTINATION" ]]; then
  run_privileged /bin/mv "$DESTINATION" "$BACKUP_APP"
fi
if ! run_privileged /bin/mv "$PENDING_APP" "$DESTINATION"; then
  if [[ -e "$BACKUP_APP" ]]; then
    run_privileged /bin/mv "$BACKUP_APP" "$DESTINATION" || true
  fi
  abort "Seeker could not be moved into $INSTALL_DIR."
fi
INSTALL_COMPLETE=1
if [[ -e "$BACKUP_APP" ]]; then
  run_privileged /bin/rm -rf "$BACKUP_APP"
fi

run_privileged /usr/bin/xattr -cr "$DESTINATION"
/usr/bin/codesign --verify --deep --strict "$DESTINATION"

if [[ "$NO_OPEN" == "1" ]]; then
  warn "SEEKER_NO_OPEN=1 is set; Seeker was installed but not opened."
else
  ohai "Opening Seeker"
  /usr/bin/open "$DESTINATION"
fi

printf "${tty_green}Seeker ${APP_VERSION:-} was installed successfully.${tty_reset}\n"
