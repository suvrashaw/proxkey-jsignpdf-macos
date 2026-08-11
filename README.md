# ProxKey + JSignPdf on macOS

Get a Watchdata **ProxKey** USB PKI token (a common Indian DSC — Digital
Signature Certificate — token, sold/rebranded by CAs such as Capricorn,
eMudhra, Sify, Pantasign, and distributed via resellers like
[cryptoplanet.in](https://support.cryptoplanet.in)) working with
[JSignPdf](https://github.com/intoolswetrust/jsignpdf) on macOS, so you can
digitally sign PDFs (invoices, contracts, tax filings, e-tendering
documents...) the same way you would on Windows.

This exists because Watchdata's own macOS driver **does not work out of the
box** on current macOS — not "needs a config tweak," but a genuine,
reproducible bug in their compiled driver that hangs every PKCS#11 client
indefinitely. This repo documents the root cause and ships the fix.

If you have a WD ProxKey / Watchdata-branded token and JSignPdf hangs, sits
with every button greyed out, or never returns from listing slots — this is
almost certainly your problem too.

## Symptoms this fixes

Search-matching this repo if you're seeing any of the following on macOS
with a WD ProxKey / Watchdata DSC token:

- **ProxKey Token Tool.app** — every button (User Login, Change PIN, Import
  Cert...) stays permanently greyed out / disabled, clicking does nothing
- `pkcs11-tool --list-slots` **hangs forever** and never returns
- JSignPdf's **"Load keys"** button hangs indefinitely, PIN prompt never
  appears
- Java: `NoClassDefFoundError: sun/security/action/GetPropertyAction`
- Java: `IllegalAccessException: class ... cannot access class
  sun.security.pkcs11.SunPKCS11 ... module jdk.crypto.cryptoki does not
  export sun.security.pkcs11`
- `IllegalAccessError: ... cannot access class sun.security.util.Debug`
- WD ProxKey / Watchdata token **not detected on macOS Sonoma / Sequoia /
  Tahoe**, Apple Silicon or Intel
- "Digital Signature Certificate (DSC) token not working on Mac" — for
  India-specific DSC tokens issued by eMudhra, Capricorn, Sify, Pantasign,
  or similar CAs on a Watchdata-manufactured USB token
- ProxKey works fine on Windows but **does nothing when plugged into a
  Mac**

**Short answer:** it's not your Mac, your token, or your certificate.
Watchdata's own macOS driver has a locking bug (their `ProxkeyCertMND`
background helper never releases an exclusive device lock), and JSignPdf
2.3.0 needs an older JDK than what ships by default. Both are fixable in a
few minutes — see [Setup](#setup) below.

## Who this is for

- You have a WD ProxKey (or any Watchdata TimeCos/PK-based) USB token.
- You're on macOS (Apple Silicon or Intel — the vendor driver ships as a
  universal binary; the bug reproduces on both architectures).
- You want to PKCS#11-sign PDFs via JSignPdf, or more generally get *any*
  PKCS#11 client (a script, another Java tool, `pkcs11-tool` for testing)
  talking to the token without hanging.
- You've tried Watchdata's official "ProxKey Token Tool.app" and its "User
  Login" button just... does nothing.

## The problem, in one paragraph

Watchdata's `libwdpkcs_Proxkey.dylib` (the PKCS#11 library every signing
tool loads) calls into a function called `StartMutexDevice` before it will
talk to the token. That function acquires a Cocoa `NSDistributedLock`
(a lock implemented via a directory on disk) to serialize access to the
device. **A separate background helper Watchdata installs,
`ProxkeyCertMND`, grabs that same lock on launch and never releases it.**
Every other process that then tries to use the token — JSignPdf, `keytool`,
`pkcs11-tool`, even Watchdata's *own* GUI app — spins forever waiting for a
lock that will never be freed, because the only thing holding it is a
background daemon with no reason to ever let go. On top of that, JSignPdf
2.3.0 itself only works on an older JDK (see below). Fix both and it works
perfectly.

## Prerequisites

- macOS (tested on macOS 26 "Tahoe", Apple Silicon; the root cause is
  OS-version-independent so this should hold on other recent macOS
  versions too).
- [Homebrew](https://brew.sh).
- Your WD ProxKey token, already provisioned with a certificate (i.e. you've
  used it on Windows before — this repo doesn't cover initial certificate
  issuance/enrollment, only getting an *already-working* token functional
  on macOS).

## Setup

### Fast path

```bash
curl -fsSL https://raw.githubusercontent.com/suvrashaw/proxkey-jsignpdf-macos/main/install.sh | bash
```

This clones the repo, installs Java 11, disables the lock-holding daemon,
and builds the app — everything that's safe to automate. It **cannot**
install Watchdata's driver package or run the `sudo` command for you
(different vendors host the driver at different URLs, and unattended
`sudo` in a piped script is bad practice) — the script prints exactly
what's left to do manually. If you'd rather see every step before running
anything, or just want to understand what's happening, follow the manual
steps below instead — `install.sh` does exactly what steps 4–6 describe.

### 1. Install the official Watchdata macOS driver

Get `proxkey_mac.pkg` from your token vendor's support portal — for
cryptoplanet.in / Pagaria Group tokens it's at
`https://support.cryptoplanet.in/downloads.php` (Apple → macOS section).
Verify it's genuinely signed by Watchdata before installing:

```bash
pkgutil --check-signature proxkey_mac.pkg
# Should show: signed by a developer certificate issued by Apple for
# distribution, Certificate Chain: Developer ID Installer: Watchdata
# System Co.,Ltd.
```

Run the installer (double-click, or `open proxkey_mac.pkg`).

### 2. Enable the vendor's CCID driver over Apple's built-in one

macOS ships its own generic CCID smart-card driver, which by default claims
USB CCID-class devices — including the ProxKey — before Watchdata's own
driver gets a chance to. This isn't fatal (macOS's native PC/SC layer will
still see the reader and card fine — `pcsctl`/`opensc-tool --list-readers`
work either way), but Watchdata's driver expects to own the device itself:

```bash
sudo defaults write /Library/Preferences/com.apple.security.smartcard useIFDCCID -bool yes
```

Reboot after this. (Source: Ludovic Rousseau — upstream CCID/PCSC-lite
maintainer —
["In case of smart card issues on macOS"](https://blog.apdu.fr/posts/2025/06/in-case-of-smart-card-issues-on-macos/).)

### 3. Disable `ProxkeyCertMND` — the actual fix

This is the important one. `ProxkeyCertMND` is installed as a
`LaunchAgent` (`/Library/LaunchAgents/com.watchdata.proxkey.launchd.certmnd.plist`,
`RunAtLoad=true`, `KeepAlive=true`) and a macOS Login Item. It has no
purpose relevant to signing (it's a certificate-management helper you don't
need for day-to-day use), and it permanently holds the device lock the
moment it starts.

```bash
# Stop it now
pkill -f ProxkeyCertMND

# Stop it from ever auto-launching again (persists across reboots,
# survives even though the LaunchAgent plist itself still has
# RunAtLoad=true — this writes to launchd's per-user override database)
launchctl disable gui/$(id -u)/com.watchdata.proxkey.launchd.certmnd
```

No `sudo` needed — this is a per-user launchd override, separate from the
(root-owned) plist file itself.

Verify it stuck:

```bash
launchctl print-disabled gui/$(id -u) | grep certmnd
# → "com.watchdata.proxkey.launchd.certmnd" => disabled
```

`WDProxKeyUIServer` (another bundled helper) is safe to leave running — it
hasn't been observed to interfere.

**If the token ever "goes quiet" again** (JSignPdf hangs on Load Keys,
`pkcs11-tool` never returns): check `ps aux | grep -i proxkeycertmnd`
first. If it's running, something re-enabled it — `pkill -f ProxkeyCertMND`
clears it immediately without a reboot.

### 4. Install Java 11

JSignPdf 2.3.0's PKCS#11 registration code touches internal JDK classes
(`sun.security.pkcs11.SunPKCS11`, `sun.security.util.Debug`,
`sun.security.action.GetPropertyAction`) that current JDKs either block via
the module system or have **removed outright**. `--add-opens` flags fix
the access-restriction errors, but not the removed-class one
(`NoClassDefFoundError: sun/security/action/GetPropertyAction`) — that
class simply doesn't exist anymore past JDK ~11-13. There's no flag that
brings back a deleted class. The fix is to run JSignPdf on an older JDK
where these classes still exist, while leaving your system's default Java
untouched:

```bash
brew install --cask temurin@11
```

### 5. Build the launcher app

**JSignPdf 2.3.0 is bundled in `vendor/jsignpdf-2.3.0/`** — no separate
download needed. (It's redistributed here under its own license terms,
LGPLv2/MPL 1.0, both of which permit redistributing the compiled jar as
long as copyright notices and license text are preserved and source stays
available — see `vendor/jsignpdf-2.3.0/licenses/` for the license texts
JSignPdf ships, and its source is at
[intoolswetrust/jsignpdf](https://github.com/intoolswetrust/jsignpdf). It's
unmodified from the official 2.3.0 release; only `conf/pkcs11.cfg` in
*this* repo — a separate file, not JSignPdf's own — is customized.)

```bash
./scripts/build-app.sh
```

This extracts JSignPdf's own icon from its jar, builds a proper `.icns`,
and creates **`JSignPdf ProxKey.app`** in `/Applications` — a real
double-clickable macOS app (findable via Spotlight) that wraps
`run-jsignpdf.command`. Ad-hoc code-signs it too, so Gatekeeper doesn't
reject it on open.

> If macOS still refuses to open it the first time ("cannot be opened
> because the developer cannot be verified"), right-click the app → **Open**
> → **Open** in the dialog. This is the standard one-time approval macOS
> requires for any app that isn't notarized through the App Store — after
> that first approval it opens normally forever.

## Usage

1. Plug in the ProxKey.
2. Open **JSignPdf ProxKey** from Applications or Spotlight.
3. Set Keystore type to **PKCS11**, click **Load keys**, enter your token
   PIN when prompted.
4. Pick your input PDF, fill in whatever signature metadata you want, click
   **Sign It**.

That's the whole workflow — no Terminal needed after setup.

## What `run-jsignpdf.command` actually does

```
1. Locates vendor/jsignpdf-2.3.0/JSignPdf.jar (bundled in this repo;
   fails with a clear dialog if it's somehow missing)
2. Locates Java 11 via `/usr/libexec/java_home -v 11`
3. Kills ProxkeyCertMND if it's somehow running (belt-and-suspenders,
   in case step 3 of Setup ever gets undone by a driver reinstall)
4. Copies the repo's conf/pkcs11.cfg into vendor/jsignpdf-2.3.0/conf/
   (JSignPdf only reads its own vendor-relative conf/pkcs11.cfg — see
   vendor/jsignpdf-2.3.0/conf/conf.properties's pkcs11config.path — so
   this keeps the repo's tracked file as the single source of truth)
5. Launches JSignPdf.jar on Java 11 with -Xdock:name/-Xdock:icon so it
   shows the right name and icon in the Dock instead of Java's default
   rocket-ship icon
```

`conf/pkcs11.cfg` (tracked in this repo) points at the driver's installed
location:

```
name=ProxKey
library=/usr/local/lib/wdProxKeyUsbKeyTool/libwdpkcs_Proxkey.dylib
```

This path is fixed by Watchdata's installer package — it'll be identical
on any Mac that installed `proxkey_mac.pkg`, so it's safe to commit as-is
rather than templating it per-machine.

## Troubleshooting

**JSignPdf hangs on "Load keys" / every button in Watchdata's own GUI is
greyed out and never enables:**
`ProxkeyCertMND` is running and holding the lock. `pkill -f ProxkeyCertMND`,
retry. If it keeps coming back, re-run the `launchctl disable` command from
Setup step 3 — something re-enabled it (a driver reinstall/update will
reset the LaunchAgent, for instance).

**Want to verify the driver itself works, independent of JSignPdf/GUI, for
debugging:** install OpenSC (`brew install opensc`) and run:

```bash
pkcs11-tool --module /usr/local/lib/wdProxKeyUsbKeyTool/libwdpkcs_Proxkey.dylib --list-slots
```

Should return instantly with your token's label, serial number, and
manufacturer info. If it hangs indefinitely instead, `ProxkeyCertMND` (or
something else holding the same lock) is your problem — see above.

**Want to confirm macOS sees the reader at all, independent of Watchdata's
driver entirely:**

```bash
opensc-tool --list-readers
# → watchdata prox key v1   Card: Yes
opensc-tool --atr
# → an ATR string, read instantly
```

If this fails, it's a hardware/USB/PC-SC problem, not the lock bug — check
the physical connection and Setup step 2 (`useIFDCCID`).

**`NoClassDefFoundError: sun/security/action/GetPropertyAction` or
`IllegalAccessException` in the console:** you're running on a JDK newer
than JSignPdf 2.3.0 supports. Confirm `run-jsignpdf.command` is actually
finding Java 11 (`/usr/libexec/java_home -v 11` should print a path) and
not silently falling through to your system Java.

**"JSignPdf ProxKey" won't open from Finder / Gatekeeper blocks it:**
right-click → Open → Open, once. If `scripts/build-app.sh`'s ad-hoc
`codesign` step failed for some reason, re-run it — check for a Xcode
Command Line Tools install (`codesign` requires it):
`xcode-select --install`.

**Nothing shows up in `Keystore type` dropdown except PKCS12/BCFKS/etc.,
no PKCS11 option:** this appeared for us only *after* a security provider
had successfully registered at least once in that JVM session (i.e., after
a prior attempt got far enough to call
`Security.addProvider(new SunPKCS11(...))`). If you don't see it on a
completely fresh run, check the Terminal output for the registration log
line (`FINE Registering SunPKCS11 provider from configuration in
conf/pkcs11.cfg`) to confirm the config is even being picked up.

## Why not just use Watchdata's official GUI app?

You can try — it's still installed after Setup (`ProxKey Token Tool.app`
in Applications) and is only needed for certificate management (import/
delete/rename), not signing. It's subject to the exact same lock bug
described above, so if `ProxkeyCertMND` is disabled per Setup step 3, it
should also start working. This repo exists because for the *signing*
use case specifically, going straight through JSignPdf is simpler and
skips the GUI's own reliability issues entirely.

## Technical appendix: how the lock bug was actually diagnosed

For anyone hitting a similar issue with a different vendor's PKCS#11
driver, the methodology here generalizes:

1. Reproduced the hang with the simplest possible reproducer
   (`pkcs11-tool --list-slots`), ruling out JSignPdf/Java-specific causes.
2. Confirmed macOS's own PC/SC layer worked independently
   (`opensc-tool --list-readers`/`--atr`), isolating the bug to Watchdata's
   library specifically rather than USB/hardware/OS smart-card stack.
3. Attached `lldb` to the hung process mid-hang:
   ```
   lldb -p <pid> --batch -o "bt all" -o detach
   ```
   showed the thread parked in `StartMutexDevice` → `usleep`, i.e. a
   polling wait loop, not a true deadlock/kernel wait.
4. Disassembled `StartMutexDevice` (`otool -tV`) and found it uses Cocoa's
   `NSDistributedLock lockWithPath:` / `tryLock` — a lock implemented as a
   directory on disk, not an anonymous kernel semaphore.
5. Found the lock directories themselves on disk
   (`/usr/local/lib/wdProxKeyUsbKeyTool/lockfinddevice*`) and matched a
   `lockfinddevice_<pid>` name against `ps aux` — the PID belonged to a
   live `ProxkeyCertMND` process.
6. Killing that process released the lock immediately; disabling its
   LaunchAgent made the fix permanent.

## FAQ

**Does WD ProxKey / Watchdata work on macOS at all?**
Yes, but only after fixing the two bugs this repo documents — a locking
bug in Watchdata's driver, and a Java-version incompatibility in JSignPdf
2.3.0. There is no working configuration that skips both fixes.

**Why are all the buttons in ProxKey Token Tool greyed out on Mac?**
`ProxkeyCertMND`, a background helper Watchdata installs, holds an
exclusive lock on the token forever and never releases it, so every
PKCS#11 client — including Watchdata's own GUI — hangs waiting for a lock
that's never coming free. Disable it (Setup step 3) and the buttons work
immediately.

**Why does `pkcs11-tool --list-slots` / JSignPdf's "Load keys" hang
forever?**
Same root cause as above — it's not a timeout you need to wait out, it
will genuinely never return on its own. Kill `ProxkeyCertMND`
(`pkill -f ProxkeyCertMND`) and retry.

**What Java version does JSignPdf need for PKCS#11 / smart card
signing?**
Java 11. JSignPdf 2.3.0's PKCS#11 code depends on internal JDK classes
(`sun.security.pkcs11.SunPKCS11`, `sun.security.action.GetPropertyAction`)
that JDK 16+ removed outright — not just restricted, actually deleted, so
no `--add-opens`/`--add-exports` flag can work around it. Use
`brew install --cask temurin@11` and run JSignPdf on that specifically,
independent of your system's default Java.

**Does this work on Apple Silicon (M1/M2/M3/M4) or only Intel Macs?**
Both — Watchdata's driver (`libwdpkcs_Proxkey.dylib`) ships as a universal
binary, and the locking bug reproduces identically on both architectures.

**Is this specific to the ProxKey brand, or does it affect other DSC
tokens too?**
The bug is in Watchdata's shared macOS driver package, which is used
across DSC tokens sold under different brand names by different
Certifying Authorities (eMudhra, Capricorn, Sify, Pantasign, and others).
If your token uses a Watchdata TimeCos/PK chip — check
`pkcs11-tool --list-slots`, it'll report `token manufacturer: Watchdata
Corp.` — this almost certainly applies to you too, regardless of which CA
issued your certificate.

**Can I sign PDFs on Mac without buying a Windows license or running a
VM?**
Yes — that's the entire point of this repo. No VM, no Windows, no Wine.

## License

This repo's own scripts (`run-jsignpdf.command`, `scripts/build-app.sh`)
are provided as-is, MIT-licensed — see `LICENSE`. `vendor/jsignpdf-2.3.0/`
is JSignPdf 2.3.0, unmodified, redistributed under its own LGPLv2/MPL 1.0
terms (license texts included at `vendor/jsignpdf-2.3.0/licenses/`;
source at [intoolswetrust/jsignpdf](https://github.com/intoolswetrust/jsignpdf)).
Watchdata's driver (proprietary) is **not** included — install it from
your vendor's official source per Setup step 1.
