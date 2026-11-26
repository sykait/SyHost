# SyHost

**English** · [Türkçe](README.tr.md) · [日本語](README.ja.md)

**Set up, run and manage a modded Minecraft server with one click.**
Pick a Modrinth pack (`.mrpack`) and SyHost installs Java, the mod loader, the mods and the settings for you.
Your friends join over the internet, and you control everything from a slick, animated terminal screen.

> Windows 10 / 11 · NeoForge · Forge · Fabric · English, Türkçe, 日本語 · Made by [**sykait**](https://github.com/sykait)

---

## ✨ Features

- **One-click server install** – pick a `.mrpack`, SyHost does the rest
  (right Java version, NeoForge/Forge/Fabric, server-side mods, config files, the pack's world).
- **Multiple servers** – all in one list, pick one and press Enter.
- **Connection for your friends** – a free, fixed address with [playit.gg](https://playit.gg)
  (works around CGNAT on most home internet). playit only runs while SyHost is open.
- **Live status** – starting / online / stopping bar, players, RAM and CPU usage.
- **Simple console** – only the important stuff (joins, leaves, chat, errors). All logs one key away.
- **Performance packs** – Low / Normal / High, tuned automatically to your PC's RAM and cores.
- **Automatic backups** – every 3 hours, the last 10 are kept.
- **Safe shutdown** – F10 → the world is saved, the server stops, nothing is left running.
- **Mini mode** – a tiny status window in the corner of your screen (Ctrl+Alt+K).
- **Hide / show** – even while gaming, with Ctrl+Alt+G.
- **3 languages** – English, Türkçe, 日本語 (press **L** in the main menu).

---

## 📥 Install

### Option 1 — one line (easiest)

Open **PowerShell** from the Start menu, paste this line and press Enter:

```powershell
irm https://raw.githubusercontent.com/sykait/SyHost/main/install.ps1 | iex
```

It downloads SyHost and starts the setup. Run the same command later to **update**
(your servers and settings are kept).

### Option 2 — zip

1. Click the green **Code** button on this page → **Download ZIP**.
2. Extract it to a folder (e.g. `Documents\SyHost`).
3. Double-click **`Setup.bat`**.
   - If Windows says "Windows protected your PC": **More info → Run anyway**.

### What does the setup do?

| Step | What happens |
|---|---|
| 0 | You pick a language (English / Türkçe / 日本語) |
| 1 | Checks Windows and winget |
| 2 | Installs Java 21 if missing |
| 3 | Optionally installs playit.gg and links it to your account in the browser |
| 4 | Installs the Cascadia Mono font (so the animations render correctly) |
| 5 | Adds a **SyHost** shortcut to your Desktop and Start menu |

Windows may ask for permission once or twice, just click **Yes**.

---

## 🎮 Your first server

1. Open **SyHost**.
2. Choose **Add a new server** (or press `+`).
3. Pick a `.mrpack` you downloaded from [Modrinth](https://modrinth.com/modpacks).
4. Give it a name → (if the pack has a world) choose the world → **Enter** to install.
5. When it's done press **Enter** → the server starts.
   It's ready when the bar at the top says **SERVER ONLINE**.

## 👥 Invite your friends

1. In the server screen type `copy` and press Enter → the address is copied.
2. Paste it to your friend on Discord.
3. Your friend opens the same modpack (same version!) with the Modrinth App or Prism Launcher →
   **Multiplayer → Add Server** → pastes the address.

---

## ⌨️ Shortcuts

| Key | What it does |
|---|---|
| **F1** | Help |
| **F2** | Hide – the server keeps running |
| **F3** | Choose a performance pack |
| **F4** | Mini / full mode |
| **F5** | Simple / detailed console |
| **F6** | Keep mini mode on top |
| **F10** | Close (the world is saved) |
| **L** | Change language (main menu) |
| **Ctrl+Alt+K** | Mini / full mode – works anywhere, even in game |
| **Ctrl+Alt+G** | Hide / show – works anywhere |

## 💬 Commands

Type in the server screen and press Enter:

| Command | What it does |
|---|---|
| `start` / `stop` / `restart` | Start / stop / restart the server |
| `pack normal` | Change the performance pack (`low`, `normal`, `high`) |
| `backup` | Back up the world |
| `players` | Who is online |
| `copy` | Copy the friend address |
| `folder` | Open the server folder |
| `menu` / `exit` | Back to the main menu / quit SyHost |

Anything else goes straight to Minecraft: `op name`, `kick name`, `say hello`, `time set day`…
(Turkish command names such as `baslat` or `durdur` also work.)

---

## ❓ FAQ

**Do I need playit?**
No. If you say "no" during setup, the server can be joined from this PC (`localhost`) and your home network.
If friends join over the internet and your connection is behind CGNAT (very common), you need playit.
If your ISP gives you a real public IP, you don't.

**Will it slow down my PC?**
SyHost itself is very light. You choose how much RAM and how many cores the server may use (F3).
Use **Low** while you play a heavy game, **Normal** otherwise.

**Where are my settings and servers?**
- Settings and server list: `%LOCALAPPDATA%\SyHost` (never inside the program folder)
- Servers: by default `%USERPROFILE%\SyHost Sunuculari` (changeable in the settings)
- Backups: in each server's `yedekler` folder

**Which packs are supported?**
Modrinth `.mrpack` packs for NeoForge, Forge and Fabric. Java 8 / 17 / 21 is installed automatically when needed.

**Mac / Linux?**
Windows 10 and 11 only for now.

---

## 📁 Project layout

```
SyHost/
├── SyHost.bat                 → opens SyHost
├── Setup.bat                  → first-time setup (one click)
├── install.ps1                → one-line internet install / update
├── src/
│   ├── SyHost.ps1             → the app itself
│   ├── SyHost.Core.cs         → window, tray icon, process and backup helpers
│   ├── Lang.ps1               → translations (English / Türkçe / 日本語)
│   └── Setup.ps1              → setup steps
├── config/
│   └── default-settings.json  → default settings on first launch
└── fonts/                     → Cascadia Mono font (SIL OFL 1.1)
```

---

## 🛠️ How it was made

SyHost is designed and directed by **sykait**: the features, the flow and the look.
The code was written together with AI coding tools.

---

## 📜 License & credit

SyHost is **source-available**: you can view it, download it and use it personally.
**If you build something with it and share it, you must give credit:**

> This project is based on **SyHost** by **sykait** — https://github.com/sykait/SyHost

Selling it or using it commercially without written permission is not allowed. Details: [LICENSE.md](LICENSE.md)

Minecraft is a trademark of Mojang Studios. SyHost is not affiliated with Mojang or Microsoft.
