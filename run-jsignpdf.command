#!/bin/bash
# Launches JSignPdf with Java 11 against a Watchdata ProxKey token on macOS.
#
# Why Java 11: JSignPdf 2.3.0's PKCS#11 code touches internal sun.security.*
# classes that newer JDKs (16+) removed outright. No amount of --add-opens
# fixes that; an older JDK is the only working option.
#
# Why the ProxkeyCertMND kill: Watchdata's ProxkeyCertMND background helper
# grabs an exclusive lock on the token (via NSDistributedLock) and never
# releases it, which hangs every other PKCS#11 client — including JSignPdf
# and Watchdata's own GUI tool. See README.md for the full diagnosis.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
JSIGNPDF_JAR="$REPO_DIR/vendor/jsignpdf-2.3.0/JSignPdf.jar"

if [ ! -f "$JSIGNPDF_JAR" ]; then
  osascript -e 'display alert "JSignPdf.jar not found" message "Download JSignPdf 2.3.0 from https://github.com/intoolswetrust/jsignpdf/releases and place JSignPdf.jar in vendor/jsignpdf-2.3.0/"'
  exit 1
fi

JAVA11=$(/usr/libexec/java_home -v 11 2>/dev/null)
if [ -z "$JAVA11" ]; then
  osascript -e 'display alert "Java 11 not found" message "Install it with: brew install --cask temurin@11"'
  exit 1
fi

if pgrep -f ProxkeyCertMND > /dev/null; then
  pkill -f ProxkeyCertMND
  sleep 1
fi

# conf/pkcs11.cfg in the repo is the single source of truth; JSignPdf only
# reads its own vendor/.../conf/pkcs11.cfg (relative path baked into
# vendor/.../conf/conf.properties), so mirror it in on every launch.
cp "$REPO_DIR/conf/pkcs11.cfg" "$REPO_DIR/vendor/jsignpdf-2.3.0/conf/pkcs11.cfg"

cd "$REPO_DIR/vendor/jsignpdf-2.3.0" || exit 1

"$JAVA11/bin/java" \
  -Xdock:name="JSignPdf ProxKey" \
  -Xdock:icon="$REPO_DIR/scripts/AppIcon.png" \
  -jar JSignPdf.jar
