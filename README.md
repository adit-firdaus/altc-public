# AltC

Terminals in the browser and on your phone, with Claude Code in them. One command
installs it, one starts it; it runs in the background and comes back by itself.

On macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/adit-firdaus/altc-public/main/install.sh | sh
altc start
```

On Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/adit-firdaus/altc-public/main/install.ps1 | iex
altc start
```

The first `altc start` at a terminal asks a few questions first (see `altc setup`
below), then prints where to open it (http://localhost:65535). No sudo and no
admin: it's a launchd agent on macOS, a systemd user service on Linux, and a Task
Scheduler task of yours on Windows. Where none is available (a container, WSL
without systemd), it runs as a detached process.

Bun comes with it, so you don't need to install anything else. macOS, Linux
(glibc or musl) and Windows 10 (1809) or later, x64 and arm64.

The install script puts altc and a Bun of its own in `~/.altc` (on Windows
`%LOCALAPPDATA%\Programs\altc`), and adds its `bin` folder to your PATH. It
takes everything from the releases of
[altc-public](https://github.com/adit-firdaus/altc-public/releases), and checks
each download against its sha256 there first. altc is one bundle with nothing else to
install, and no npm. Nothing goes outside that folder, except the PATH line
in your shell's startup file (on Windows, your user PATH). Running it again,
or `altc update`, updates altc and restarts a running server onto the new
version. It keeps the version before, in case you want to go back. To change
what it does, set these first:

| Variable | What it does |
| --- | --- |
| `ALTC_VERSION` | A version to install, instead of the latest, e.g. `0.1.0` |
| `ALTC_HOME` | Where it goes |
| `ALTC_NO_MODIFY_PATH=1` | Leave the PATH alone |
| `ALTC_NO_RESTART=1` | Leave a running server on the version it runs |
| `ALTC_BASE` | Another copy of the releases, e.g. one `bun run release serve` serves for a test |

## As a desktop app

Installed from the browser, AltC opens in a window of its own, with its icon in the dock,
the taskbar or the app launcher. In Chrome, Edge or Brave, open http://localhost:65535 and
choose **settings › app › install** (or the install button in the address bar); in Safari,
**File › Add to Dock**. Firefox can't install web apps. Once it's installed, `altc open`
opens the app instead of a browser tab.

The app shows how many panes want you on its icon, opens a new terminal from the icon's
menu, and in full screen (**Full screen** in the palette; Chrome, Edge and Brave) keeps Ctrl+W, Ctrl+T and Ctrl+N
for the terminal. When AltC isn't running, the window says so and how to start it, and
reloads once it answers. After an update, a bar offers to reload.

Browsers install apps only from a secure page: localhost on the same computer, or HTTPS.

## The Android app

`altc.apk`, in each [release](https://github.com/adit-firdaus/altc-public/releases/latest),
is the app for your phone (Android 8.0 or later). Install it, allow installs from
your browser or files app when Android asks, then pair it with `altc pair`. Each
release installs over the one before. This release has no AltC Cloud, so the phone
reaches your computer on the same network or over a tailnet (see below).

## Every day

| Command | What it does |
| --- | --- |
| `altc start` | Start in the background and keep it running. Starts at login too (`--no-autostart` turns that off) |
| `altc stop` | Stop it, and end its terminals. The next start brings them back in their folders, and resumes a coding agent that ran in one |
| `altc restart` | Restart it. Terminals, and what runs in them, carry on |
| `altc update` | Update to the latest version and restart onto it |
| `altc status` | Is it running, where, which version (`--json`; exits 3 when stopped) |
| `altc open` | Open it: as an app when it's installed as one (see below), else in the browser. `--browser` opens a browser tab either way |
| `altc pair` | Pair a phone, on your network or through AltC Cloud: scan the QR code, open the link or type the code, or accept the phone's ask. Each phone gets its own token |
| `altc devices` | The phones and browsers paired with it: rename one, or sign it out |
| `altc link` | Link it to your AltC Cloud account, for agent alerts on your phone: opens the cloud in your browser, or prints the link for `c` to copy. `altc link status` says whether it's linked, and to whom |
| `altc unlink` | Unlink it from AltC Cloud |
| `altc logs -f` | Follow the log |

`altc` on its own, at a terminal, says whether it runs and offers these as a menu.

## Setting up

```sh
altc setup
```

It asks, one question after another, and Esc skips one and keeps what's there:

1. **Port**: 65535 unless you say; it tells you when another program holds the one you pick.
2. **Who can connect**: tick the networks that may reach AltC, with Space. This machine
   always may. Each network is listed with its addresses: Tailscale, the local network
   (`en0`…), and any other. You can also tick **Tailscale HTTPS** (it sets up
   `tailscale serve` on an HTTPS port nothing else uses), **an address of yours** (a
   domain on a tunnel or proxy, typed in), or **every network**. A connection from a
   network that isn't ticked is turned away before it reaches anything, token or not.
3. **Start at login**.
4. **Voice**: the Groq API key and the models for speech to text and refine, picked from
   what the key can use. The server keeps them in its database, and the app changes them
   too (settings → voice); either way a change works at once.
5. **Agent notifications**: which coding agents (Claude Code, Codex…) tell AltC when they
   finish or need you.
6. **Folder access** (macOS): whether terminals may open Desktop, Documents and Downloads,
   and the Settings pane to allow them all at once.
7. **A phone**: pairs one, as `altc pair` does.

It starts AltC, or restarts it last, after asking, when something changed.

## Phones and other machines

```sh
altc pair
```

When this AltC has a cloud, it first asks how the phone should reach it: **your network**
or **AltC Cloud**.

AltC Cloud reaches it from anywhere, with no address to set up. If this computer isn't
linked yet, it signs in the way `altc link` does: the cloud's page opens in your browser,
or, over SSH or with no display, the link is printed and `c` copies it (through the
terminal, so it lands on the computer you type on). Then, on the phone, sign in to the
same account and tap **Pair** beside this computer. Both screens show the same six
digits; accept here, or refuse, or block the phone.

On your network, it asks where the phone should reach AltC, with the arrow keys:

- **Tailscale**: its tailnet address, from anywhere the phone is on your tailnet.
- **Tailscale HTTPS**: `https://<machine>.<tailnet>.ts.net`, through `tailscale serve`.
  If that isn't set up for AltC yet, it sets it up on an HTTPS port nothing else uses.
- **Local network**: the Wi-Fi or Ethernet address, for a phone on the same network.
- **Another address**: a tunnel or proxy of yours.

It starts AltC if it isn't running, or restarts it (after asking) when the address needs
it to listen on the network. Then it shows a link, a QR code and a one-time code, and
waits until the phone pairs. `n` makes a new code; each lasts 5 minutes.
`altc pair --url <address>` skips the question.

AltC listens on this machine only (127.0.0.1) unless you ask, with `altc setup` or:

```sh
altc start --networks tailscale,en0    # these networks and this machine
altc start --remote                    # every network (0.0.0.0)
altc start --port 4000                 # 65535 unless you say
altc start --public-url https://mac.tailnet.ts.net,https://altc.example.com   # addresses in front of it
altc start --local                     # back to this machine only
```

Linked to AltC Cloud (`altc link`), AltC also keeps a connection open to the cloud's relay,
so the paired phone reaches it from any network, with nothing to open or set up. The relay
sees only ciphertext, and each request through it needs the phone's own token, as on the
local network. `altc doctor` says whether it's connected.

Options given to `start` or `restart` are saved. `altc run` takes the same options but
runs the server in the terminal until Ctrl-C, and uses them for that run only.

## Settings

```sh
altc config                            # show
altc config set networks tailscale     # who can connect; `all` for every network
altc config set urls https://altc.example.com
altc config unset port
altc autostart off
```

A background service doesn't see what you export in your shell. Settings made
with `altc config` do reach it, after `altc restart`. Config and token files are
readable by you only. The Groq key and models for voice aren't here: they're in
the app (settings → voice) or `altc setup`, and a change works without a restart.

## Permissions (macOS)

Its terminals run as `bun`, so macOS asks once per protected folder (Desktop, Documents,
Downloads, iCloud Drive, external drives). The dialog appears on the Mac's screen, even
when you're typing on your phone. `altc permissions` shows what's allowed and opens the
right Settings pane. There you can give bun Full Disk Access once, instead of answering
folder by folder. Linux and Windows ask for nothing.

## Windows

Native Windows, not WSL. Terminals run PowerShell 7 (`pwsh`) when it's installed,
else Windows PowerShell, else `cmd`; `altc config set ALTC_SHELL <path>` picks
another. The app follows a `cd` from the prompt: AltC wraps whatever prompt your
PowerShell profile sets (oh-my-posh, starship, your own) so it also says the
folder, the way Windows Terminal reads it (OSC 9;9).

- The task runs while you're signed in to Windows, from sign-in when autostart is
  on, with no console window. It keeps the server up: it starts it again after a
  crash, and gives up after ten crashes in a minute (`altc start` tries again).
- Hyper-V, WSL and Docker reserve ranges of ports. When the port is one of them,
  `altc start` and `altc doctor` say so; pick another with `altc config set port <n>`.
- For other networks, allow `bun.exe` through Windows Defender Firewall when it asks.
- Some endpoint security tools flag `conhost.exe --headless`, which keeps the task's
  window hidden. If yours stops the task, `altc run` in a terminal still works.

`altc doctor` checks Bun, the shell, the service, the port, the cloud and its relay, Claude Code and its account, git and folder access. `altc config set ALTC_CLOUD_URL off` turns the cloud off; the published build otherwise uses the one it was built with.

## Where things are

| | macOS | Linux | Windows |
| --- | --- | --- | --- |
| altc and its Bun (install script) | `~/.altc` | `~/.altc` | `%LOCALAPPDATA%\Programs\altc` |
| Settings, token | `~/.config/altc` | `~/.config/altc` | `%APPDATA%\altc` |
| Database, uploads | `~/.local/share/altc` | `~/.local/share/altc` | `%LOCALAPPDATA%\altc\data` |
| Log | `~/Library/Logs/AltC/server.log` | `~/.local/state/altc/server.log` | `%LOCALAPPDATA%\altc\state\server.log` |
| Service | `~/Library/LaunchAgents/com.alterndigital.altc.plist` | `~/.config/systemd/user/altc.service` | Task Scheduler task `AltC` |

The `XDG_*` variables move them. On Linux the server stops when you log out;
`loginctl enable-linger` keeps it running and starts it at boot.

## Uninstall

```sh
altc uninstall        # stops it and removes the service; keeps settings and data
```

Then remove altc itself; `altc uninstall` says how:

- macOS and Linux: `rm -rf ~/.altc`, and the `# altc` line in your shell's
  startup file.
- Windows: `Remove-Item -Recurse "$env:LOCALAPPDATA\Programs\altc"`, and that
  folder's `bin` from your user PATH.

Run `altc uninstall` first: removing the files doesn't remove the launchd,
systemd or Task Scheduler service. To also delete your data, remove the folders
listed above.

## License

[FSL-1.1-ALv2](LICENSE): use, change and share it for anything but a competing
product or service. Each release becomes Apache 2.0 two years after it ships.
