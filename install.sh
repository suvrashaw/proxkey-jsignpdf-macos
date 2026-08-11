#!/bin/bash
# One-line installer for ProxKey + JSignPdf on macOS.
# Usage: curl -fsSL https://raw.githubusercontent.com/suvrashaw/proxkey-jsignpdf-macos/main/install.sh | bash
#
# Automates everything that's safe to automate (cloning, Java 11, disabling
# the lock-holding daemon, building the app). Does NOT auto-install
# Watchdata's proprietary driver package or run sudo commands unattended —
# those need your own admin password and a download from your specific
# token vendor/CA, so they stay manual. See README.md "Setup" for those.
set -e

INSTALL_DIR="$HOME/.proxkey-jsignpdf-macos"
REPO_URL="https://github.com/suvrashaw/proxkey-jsignpdf-macos.git"

echo "==> ProxKey + JSignPdf installer"

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "==> Updating existing install at $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "==> Cloning to $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Install it first: https://brew.sh"
  exit 1
fi

if ! /usr/libexec/java_home -v 11 &>/dev/null; then
  echo "==> Installing Java 11 (Temurin) — required, newer JDKs break JSignPdf's PKCS#11 code"
  brew install --cask temurin@11
else
  echo "==> Java 11 already installed"
fi

if launchctl print-disabled "gui/$(id -u)" 2>/dev/null | grep -q "com.watchdata.proxkey.launchd.certmnd.*disabled"; then
  echo "==> ProxkeyCertMND already disabled"
else
  echo "==> Disabling ProxkeyCertMND (Watchdata's lock-holding background helper, if present)"
  pkill -f ProxkeyCertMND 2>/dev/null || true
  launchctl disable "gui/$(id -u)/com.watchdata.proxkey.launchd.certmnd" 2>/dev/null || true
fi

echo "==> Building JSignPdf ProxKey.app"
"$INSTALL_DIR/scripts/build-app.sh"

cat << 'EOF'

==> Done. Two things still require your own action (can't be automated safely):

  1. Install Watchdata's official macOS driver (proxkey_mac.pkg) from your
     token vendor/CA's own site if you haven't already.

  2. Run this once (needs your admin password):
     sudo defaults write /Library/Preferences/com.apple.security.smartcard useIFDCCID -bool yes
     ...then reboot.

Full details: https://github.com/suvrashaw/proxkey-jsignpdf-macos#setup

Once both are done: plug in your ProxKey, open "JSignPdf ProxKey" from
Applications or Spotlight, and sign.
EOF
