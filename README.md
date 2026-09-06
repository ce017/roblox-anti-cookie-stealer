# roblox-anti-cookie-stealer

Two small PowerShell watchers for Windows that address how Roblox accounts
actually get drained: **theft of the `.ROBLOSECURITY` session cookie.**

Built after a real incident. A fake "CapCut Pro activator" was run on
2026-09-05; 19 seconds later it had copied the browser cookie stores into
`C:\ProgramData\<random hex>\`, and the Roblox account was emptied of ~30,000
Robux. Windows Defender never flagged it. The staging folders sat on disk,
unnoticed, for a full day.

---

## Read this before you install anything

**This does not prevent cookie theft.** No user-mode program can. Any process
running as your user can read your cookie files, and by the time anything
notices, the files are already copied. What is still winnable is the **upload**.

So this does two realistic things:

1. **Shrinks the window.** The Roblox app keeps `.ROBLOSECURITY` in its own
   embedded WebView2 cookie jar, and *nothing ever clears it*. In the incident
   above, a token created at 13:28 and valid until **2027** was still sitting
   there hours later. `RobloxSessionGuard` clears it whenever Roblox is closed,
   so it only exists while you are actually playing.
2. **Cuts detection time from a day to seconds.** `StealerCanary` watches for
   the staging pattern and alerts in about 8 seconds, with evidence naming the
   process responsible — so you rotate sessions immediately instead of finding
   out when your Robux is gone.

If you want real prevention, the answer is not software: run untrusted programs
on a separate machine, a separate Windows install, or in Windows Sandbox — and
never sign into anything valuable there.

---

## What each part does

### StealerCanary

Watches `ProgramData`, `Temp`, `LocalAppData` and `AppData` for a **newly
created directory with a random hex name** that rapidly fills with **copies of
browser credential databases** (files beginning `SQLite format 3`). That is the
signature of essentially every commodity infostealer — Lumma, Vidar, StealC,
Rhadamanthys and friends all stage to disk this way before uploading.

It detects **by file content, never by filename** - staged copies are routinely
renamed to random hex with no extension, so extensions tell you nothing. It
recognises four credential-store signatures:

| Signature | What it catches |
|---|---|
| `SQLite format 3` header | browser cookie / login / autofill databases |
| LevelDB SSTable footer magic | Discord and Chromium token stores |
| `dQw4w9WgXcQ:` marker | a Discord session token in a staged copy |
| `os_crypt` / `encrypted_key` | Chromium `Local State` master-key file |

It fires on: any Discord token found, or 2+ SQLite DBs, or 3+ LevelDB
segments, or 3+ mixed credential artifacts, or 40+ files appearing at once.

The LevelDB rules matter because a **Discord-only** token grab stages fewer
than ten files and contains no SQLite at all - it slid under a SQLite-only
threshold completely. On detection it:

- saves **evidence first** - directory listing plus the full running-process
  table with start times, so the culprit is identifiable afterwards
- **beeps loudly** - the only channel that reaches you inside a fullscreen game
- drops a **`!! STEALER ALERT <time>.txt` marker on your Desktop**
- shows a popup and writes to a log
- optionally kills the suspect process and/or shuts the machine down (**off by
  default** - see below)

Alerting is deliberately multi-channel. A popup alone is unreliable: exclusive
fullscreen hides it, and a task running in session 0 cannot draw a window at
all. That is why the installer registers the tasks as **Interactive**.

### RobloxSessionGuard

Polls every 20 seconds. When Roblox is not in use, it clears **both** places
Roblox keeps your session:

```
%LOCALAPPDATA%\Roblox\UniversalApp\WebView2\EBWebView\...\Network\Cookies
%LOCALAPPDATA%\Roblox\RobloxStudio\WebView2\EBWebView\...\Network\Cookies
%LOCALAPPDATA%\Roblox\LocalStorage\RobloxCookies.dat
```

That last one matters and is easy to miss. The WebView2 jars are Chromium
SQLite databases, but the Player and Studio clients *also* keep the session
in `RobloxCookies.dat` - a DPAPI-encrypted blob. **DPAPI is no protection
here:** it decrypts automatically for any process running as your user, which
is exactly what an infostealer is. Clearing only the WebView2 jars leaves your
session sitting on disk while appearing to have worked.

Only `RobloxCookies.dat` is touched inside `LocalStorage` - `appStorage.json`
beside it holds your app settings and is left alone.

**"In use" means Roblox owns a visible window**, not merely that a process
exists. Roblox autostarts a tray-resident `RobloxPlayerBeta.exe` that never
exits, so a naive process-name check would mean the guard never fires.

Roblox recreates them on next launch. **Trade-off: you sign in again every time
you open Roblox.** That is the entire cost, and it is what makes a stolen cookie
worthless when you are not playing. 2FA continues to work normally.

---

## Install

**You run the installer once. After that it starts by itself, forever.**
There is nothing to click again and nothing to remember.

Needs Windows 10/11. **No admin rights. Nothing is downloaded. No reboot.**

### Step 1 - get the files

Click the green **Code** button at the top of this page, choose
**Download ZIP**, then right-click the ZIP and **Extract All**.

(Or, if you have git: `git clone https://github.com/ce017/roblox-anti-cookie-stealer`)

### Step 2 - open PowerShell in that folder

Open the extracted folder. Hold **Shift**, right-click on any empty space
inside it, and choose **"Open PowerShell window here"** (on Windows 11 it may
say **"Open in Terminal"**).

### Step 3 - run the installer

Copy this line, paste it in, press Enter:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

You should see:

```
  [+] StealerCanary installed and started
  [+] RobloxSessionGuard installed and started
```

**That's it. You are now protected, immediately - no reboot needed.**

Only want one of the two:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -CanaryOnly
powershell -ExecutionPolicy Bypass -File install.ps1 -GuardOnly
```

---

## How it runs (read this if you are unsure whether it is working)

| Question | Answer |
|---|---|
| Do I have to start it every time? | **No.** It starts automatically when you log into Windows. |
| Do I need to keep a window open? | **No.** It runs hidden in the background. |
| Do I need to run it as admin? | **No.** |
| Do I need to reboot after installing? | **No.** It starts the moment you install it. |
| Does it survive a restart? | **Yes.** It re-starts at every logon. |
| What if it crashes? | Windows automatically restarts it, up to 3 times. |
| Does it run when I am logged out? | No - and it does not need to. Nothing runs as you then either. |

It installs as two **Windows scheduled tasks** with an *at logon* trigger.

### Checking it is actually running

Paste this into PowerShell at any time:

```powershell
Get-ScheduledTask StealerCanary, RobloxSessionGuard | Select-Object TaskName, State
```

`State: Running` on both means you are protected. If one says `Ready` instead
of `Running`, it is registered but stopped - start it again with:

```powershell
Start-ScheduledTask -TaskName StealerCanary
Start-ScheduledTask -TaskName RobloxSessionGuard
```

### Testing that it works

The easiest real test: **open Roblox, log in, then fully close it.** Wait about
30 seconds, then open the log:

```powershell
notepad $env:LOCALAPPDATA\RobloxSessionGuard\guard.log
```

You should see a `cleared ... Cookies` line. That means your session token was
wiped and is no longer sitting on disk for malware to steal.

### Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Purge
```

---

## Why this is not a .exe

Deliberate. This is a security tool aimed at people who were just compromised by
an unsigned executable from the internet — shipping another one teaches the
exact reflex that got them robbed. As source you can read every line before
running it, which is the only honest way to distribute something that watches
your filesystem. (PowerShell compiled to .exe is also heavily flagged by
Defender, so it would fail on its own terms.)

---

## Active response (OFF by default)

Both live at the top of `StealerCanary\canary.ps1`:

```powershell
$KillSuspects     = $false
$ShutdownOnAlert  = $false
$ShutdownDelaySec = 20
```

**`$KillSuspects`** terminates processes that are: started under 180 seconds
ago, running from a user-writable directory (`Downloads`, `Temp`, `ProgramData`,
`Desktop`), and **not** Microsoft-signed. On the development machine this
matched **0** of 15 recently-started processes, correctly sparing normal apps —
but that heuristic is untested on *your* machine.

**`$ShutdownOnAlert`** force-shuts-down after an abortable countdown
(`shutdown /a` cancels). It is the backstop for cutting an upload in progress.

> **Both are off by default for a reason.** A false positive means killed
> applications and, with shutdown enabled, **lost unsaved work**. Enable them
> only once you have watched the logs for a while and seen no false alarms.
> Killing the process is much faster than shutting down — a shutdown takes
> 10-30 seconds to tear down networking, which an upload can easily beat.

---

## If you have already been robbed

Do this **from a different device** — phone is fine — in this order:

1. **Email first.** Your inbox is the recovery path to everything else. Change
   the password, sign out all sessions, then check for attacker persistence:
   mail **forwarding rules**, **filters**, **recovery email/phone**, **app
   passwords**, and **third-party app access**. People skip this and get
   re-compromised a week later.
2. **Roblox.** Change the password and tick **"Log out of all other sessions"**.
   A password change *alone does not invalidate a stolen cookie*. Then enable
   2FA, revoke authorized apps, remove saved payment methods, and confirm your
   email and username were not changed.
3. Any other account you were signed into in that browser.
4. Only then clean the machine. Emptying the Recycle Bin matters — "deleted"
   malware still sits there intact.

Note that stolen-cookie logins **bypass both your password and 2FA**, which is
why signing out all sessions is the step that actually matters.

---

## Hardening worth doing anyway

- **WinRAR → Options → Settings → Security → "Propagate Zone.Id stream" → All
  files.** Archive tools strip the mark-of-the-web by default, so extracted
  executables get **no SmartScreen check at all**. This is why the sample in the
  original incident ran silently.
- **Enable firewall logging** so a future incident is traceable — it is off by
  default, which is why the original upload destination could never be
  recovered:
  `netsh advfirewall set allprofiles logging allowedconnections enable`
- **Defender:** set PUA protection to *block* (it often ships as audit-only),
  and raise the cloud block level — that is what catches novel obfuscated
  samples.
- **Never add Defender exclusions for game or crack folders.** It is common
  advice online and it is precisely how people get owned.
- **Smart App Control** blocks unsigned, no-reputation executables outright, but
  can only be switched on during a clean Windows install.

---

## Limitations — please read

- **Detection, not prevention.** Data is already copied locally when it fires.
- **Only catches disk-staging stealers.** Malware that harvests straight to
  memory and uploads without touching disk will not trip it. Disk staging is
  common, not universal.
- **Runs as your user**, so malware with admin can simply kill it.
- **The kill heuristic can be wrong** on machines unlike the one it was
  developed on. Watch the logs before enabling active response.
- Not antivirus, and not a replacement for one.

---

## Logs

```
%LOCALAPPDATA%\StealerCanary\canary.log
%LOCALAPPDATA%\StealerCanary\evidence\<timestamp>\
%LOCALAPPDATA%\RobloxSessionGuard\guard.log
```

## License

MIT — see [LICENSE](LICENSE). Provided as-is, with no warranty. You are
responsible for testing it on your own system before relying on it.
