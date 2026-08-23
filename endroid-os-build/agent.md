# Endroid OS — Bootable Build — Agent Spec

## What this is

A real, bootable, self-contained operating system with a **custom minimal Linux kernel**,
a **browser engine as the entire GUI shell**, **hardware access brokered through a native
daemon**, and **JavaScript as the application layer**. Not a simulation, not a kiosk wrapper
around a normal distro — a purpose-built OS image that boots on real hardware or in a VM,
installs to disk, and persists state across reboots.

This document is the single source of truth. Do not deviate from the architecture below
without updating this file first.

---

## 1. Non-negotiable constraints

- **No general-purpose distro base.** Do not build on Ubuntu/Debian/Fedora/Arch. Use
  **Buildroot** as the root filesystem builder. Yocto is acceptable only if Buildroot proves
  insufficient for a specific driver — default to Buildroot.
- **Kernel is custom-configured, not stock.** Start from mainline `linux-stable`, strip via
  `make menuconfig`/`savedefconfig` to only what the target hardware needs. Target uncompressed
  kernel + initramfs under 15MB where feasible; document any overage.
- **One browser engine, chosen once, not swapped mid-project.** Default: **WebKitGTK** via
  **cog** (a minimal WPE/WebKit launcher with no full desktop environment dependency). Do not
  add Chromium or Servo as a parallel track — pick one, build it, ship it.
- **JS never talks to hardware directly.** All hardware/OS access goes through the local
  daemon over HTTP/WebSocket on `localhost`. The browser process has zero special
  privileges beyond what any sandboxed web page has.
- **Everything on the system partition is read-only at runtime.** All writes (prefs, user
  data, installed apps) go to a separate writable data partition. This is what makes
  updates/rollback safe and prevents state corruption.
- **JSON is the only on-disk preference format.** No SQLite, no binary blobs, no dotfiles
  scattered across the tree, unless a component (e.g. NetworkManager) requires its own format
  — in that case, isolate it, don't let it leak into app-facing state.

---

## 2. Architecture overview

```
┌─────────────────────────────────────────────────────────┐
│  Browser engine (WebKitGTK / cog) — fullscreen, kiosk    │
│    → renders index.html (the OS shell UI, JS + CSS)      │
│    → talks to localhost daemon via fetch()/WebSocket      │
└───────────────────────────┬───────────────────────────────┘
                             │ HTTP :7331 / WS :7332
┌───────────────────────────┴───────────────────────────────┐
│  endroidd — native daemon (Rust, statically linked)        │
│    → exposes REST + WS API                                 │
│    → reads /sys, /proc, D-Bus (NetworkManager, UPower)     │
│    → writes JSON prefs to /data/system/*.json               │
│    → manages app install/uninstall (writes to /data/apps/) │
└───────────────────────────┬───────────────────────────────┘
                             │ syscalls, ioctl, sysfs, D-Bus
┌───────────────────────────┴───────────────────────────────┐
│  Custom Linux kernel (mainline, trimmed config)             │
│    → DRM/KMS for display, no full X11 required              │
│    → minimal driver set for target hardware                 │
└───────────────────────────┬───────────────────────────────┘
                             │
┌───────────────────────────┴───────────────────────────────┐
│  Disk layout                                                │
│    /dev/sdaX  ESP (FAT32, GRUB/systemd-boot)                │
│    /dev/sdaY  system-a (squashfs, read-only)                │
│    /dev/sdaZ  system-b (squashfs, read-only, for A/B update)│
│    /dev/sdaW  data (ext4, read-write — prefs, apps, cache)  │
└───────────────────────────────────────────────────────────┘
```

---

## 3. Components and build order

Build and validate in this order. Do not start component N+1 until N boots in QEMU.

### 3.1 Kernel
- Source: `linux-stable`, latest LTS.
- Config baseline: `make tinyconfig`, then add back only:
  - DRM/KMS driver for target GPU (start with `virtio-gpu` for QEMU dev, add real driver later)
  - Storage: AHCI/SATA or NVMe, virtio-blk for QEMU
  - Input: `evdev`, USB HID
  - Networking: target NIC driver or `virtio-net` for QEMU, plus `CONFIG_WIRELESS` only if
    target has Wi-Fi
  - Filesystems: `EXT4_FS`, `SQUASHFS`, `VFAT_FS` (for ESP), `OVERLAY_FS` (for future
    writable-overlay experiments)
  - `CONFIG_DEVTMPFS`, `CONFIG_DEVTMPFS_MOUNT`
- Output artifact: `bzImage`.
- Validation: boot in QEMU with `-kernel bzImage -initrd initramfs.cpio.gz -append "console=ttyS0"`,
  confirm kernel reaches userspace init without panic.

### 3.2 Root filesystem (Buildroot)
- `BR2_TARGET_GENERIC_HOSTNAME="endroid"`
- Init system: **s6** or **runit** (not systemd, to keep boot time and image size down).
  Only switch to systemd if a required package hard-depends on it (e.g. some NetworkManager
  builds do — evaluate `connman` as a lighter alternative first).
- Packages to include:
  - `wpewebkit` + `cog` (browser engine + minimal launcher)
  - `mesa3d` (software or hardware GL, depending on target)
  - `dbus` (required by most hardware daemons)
  - `connman` or `networkmanager` (network management — prefer connman for size)
  - `util-linux`, `e2fsprogs`, `dosfstools` (partitioning/formatting, needed by installer)
  - `endroidd` (your own daemon — added as a Buildroot package, see 3.3)
- Output artifact: `rootfs.squashfs`.
- Validation: boot in QEMU, confirm `cog` launches and can load a local `file://` test page.

### 3.3 endroidd — the hardware bridge daemon
- Language: **Rust** (static binary via musl target, zero runtime deps, small size, safe
  syscalls). Do not use Node.js for this layer — a native daemon should not itself depend
  on a JS runtime with its own footprint and attack surface.
- Responsibilities:
  - `GET /api/system/info` — hostname, kernel version, uptime, memory, disk usage
  - `GET/POST /api/prefs` — read/write `/data/system/prefs.json`
  - `GET /api/network/status`, `POST /api/network/connect` — via D-Bus to connman/NM
  - `GET /api/power/battery` — via `/sys/class/power_supply/*` (if applicable) or UPower
  - `GET/POST /api/apps` — list/install/uninstall apps (writes to `/data/apps/<id>/`)
  - `WS /events` — push events (battery level change, network state change, hotplug) to
    the browser without polling
  - `POST /api/system/brightness`, `/api/system/volume` — direct sysfs/ALSA control
- Security: bind only to `127.0.0.1`, no external network exposure. No auth needed since
  only the local browser process can reach it — but validate/sanitize every input anyway,
  since the browser process is untrusted from the daemon's perspective (a malicious app
  installed by the user still runs as regular JS in the same browser process).
- Output artifact: single static `endroidd` binary, included in rootfs at `/usr/bin/endroidd`,
  started by init before the browser launches.

### 3.4 OS shell UI (the part already built)
- This is the existing `index.html` + `apps.js` web app (window manager, launcher, apps).
- Change required for bootable target: replace all `localStorage`/`IndexedDB` calls used for
  *system-level* state (installed apps list, `.epk` bytes, system prefs) with calls to
  `endroidd`'s REST API instead. Keep `localStorage`/IndexedDB only for ephemeral,
  per-app state that doesn't need to survive a factory reset.
- The browser-only demo (`endroid-os-wized1s-projects.vercel.app`) stays as-is for web
  distribution — do not merge these two targets into one codebase with feature-flags. Keep
  the bootable build's UI as a fork that swaps the storage layer.

### 3.5 Boot chain
- Bootloader: **GRUB2** (BIOS+UEFI both supported, well-documented) or **systemd-boot**
  (UEFI-only, simpler config) — default to GRUB2 for broader hardware compatibility.
- Boot flow: firmware → GRUB → kernel (`bzImage`) with `root=` pointing at the active
  squashfs slot → init (s6/runit) → mount `/data` read-write → start `dbus`, `connman`,
  `endroidd` → start `cog` fullscreen pointed at `file:///usr/share/endroid/index.html`.
- A/B slots: GRUB config tracks which slot (`system-a`/`system-b`) is active via a boot
  counter; a failed boot (no "boot successful" signal within N seconds) triggers automatic
  fallback to the other slot. Implement this as a systemd/s6 service that touches a marker
  file after the browser successfully renders.

### 3.6 Installer
- Do not write a custom installer from scratch initially — use **Calamares**, a modular,
  skinnable Linux installer, configured with:
  - Partitioning module: creates ESP + system-a + system-b + data partitions
  - Unpackfs module: writes `rootfs.squashfs` to `system-a`
  - Bootloader module: installs GRUB to the target disk
  - Custom branding: Endroid OS logo/colors matching the web UI's design tokens
- Ship the installer as a separate bootable ISO (live environment: kernel + minimal rootfs
  + Calamares + your OS's browser-based UI, in installer mode). Installing to disk uses this
  ISO; the installed system itself boots directly into the OS shell, not into an installer.
- Validation: boot installer ISO in QEMU with a blank virtual disk attached, run through
  install, reboot, confirm the installed system boots to the OS shell.

### 3.7 Persistent storage details
- `/data` partition, ext4, mounted read-write at boot.
- Layout:
  ```
  /data/system/prefs.json       — system preferences (theme, accent, network saved, etc.)
  /data/system/installed.json   — installed app manifest list (replaces the web demo's
                                   localStorage meta key)
  /data/apps/<app-id>/           — unpacked .epk contents per installed app
  /data/user/                    — per-app user data (notes, contacts, etc.), one dir per app
  ```
- `endroidd` is the only process that writes to `/data/system/*.json`. The browser never
  writes files directly — it always goes through the daemon's API, so file writes stay
  atomic and validated (write to temp file, `fsync`, rename — never partial writes).

---

## 4. JSON preference schema (baseline)

`/data/system/prefs.json`:
```json
{
  "version": 1,
  "theme": "dark",
  "accent": "#4FD1C5",
  "accentDim": "#2C8A80",
  "reduceMotion": false,
  "network": { "lastConnectedSsid": null },
  "display": { "brightness": 80 },
  "sound": { "volume": 70, "systemSounds": true }
}
```
`/data/system/installed.json`:
```json
{
  "version": 1,
  "apps": [
    { "id": "epk_1234", "type": "epk", "name": "Hello Endroid", "installedAt": "2026-08-23T00:00:00Z" }
  ]
}
```
Every schema change bumps `version` and `endroidd` must migrate old files forward on read,
never silently drop unknown fields.

---

## 5. Build tooling and directory layout

```
endroid-os-build/
├── kernel/                  # linux-stable submodule + endroid_defconfig
├── buildroot/                # buildroot submodule + external tree
│   └── br2-external/
│       ├── package/endroidd/ # Buildroot package definition for the daemon
│       └── configs/endroid_defconfig
├── daemon/                   # endroidd Rust source
│   ├── src/
│   └── Cargo.toml
├── ui/                       # OS shell (index.html, apps.js) — bootable-target fork
├── installer/                # Calamares config + branding
├── scripts/
│   ├── build-kernel.sh
│   ├── build-rootfs.sh
│   ├── build-iso.sh
│   ├── run-qemu.sh
│   └── run-installer-qemu.sh
└── agent.md                  # this file
```

---

## 6. Validation checklist (must pass before claiming "done")

1. `scripts/run-qemu.sh` boots to the OS shell UI in under 15 seconds, no kernel panics,
   no init errors in the console log.
2. `endroidd` responds to `GET /api/system/info` from within the browser's dev console.
3. Changing accent color in Settings persists across a QEMU reboot (proves `/data` write
   path works).
4. Installing a `.epk` via the App Installer survives a reboot (app still listed and
   launchable).
5. Killing network mid-boot does not hang the boot sequence (daemon/UI must handle absent
   network gracefully).
6. `scripts/run-installer-qemu.sh` installs to a blank virtual disk and the resulting disk
   boots standalone (no longer needs the installer ISO attached).
7. Simulating a corrupted `system-a` (e.g. truncate the squashfs) triggers automatic
   fallback boot into `system-b`.
8. Total system image size (kernel + rootfs squashfs, excluding `/data`) is documented and
   tracked — flag any single change that grows it by more than 10%.

---

## 7. Explicit non-goals (do not build these unless this file is updated)

- No support for multiple browser engines simultaneously.
- No systemd unless a hard dependency forces it — re-justify in this file if so.
- No writable system partition at runtime — updates replace the inactive slot wholesale,
  never patch the running one.
- No cloud sync, accounts, or telemetry in this phase.
- No multi-user support — single-user device model only, for now.

---

## 8. Open decisions to resolve before kernel work starts

- [ ] Target hardware: real device (specify model) vs. QEMU-only for this phase?
- [ ] Display stack: DRM/KMS direct (no compositor) vs. a minimal Wayland compositor
      (e.g. `cage`) if multi-window-outside-the-browser is ever needed? Default: DRM/KMS
      direct, single fullscreen browser surface, no compositor — simplest, matches
      "browser IS the GUI" goal.
- [ ] connman vs. NetworkManager — decide based on final target's Wi-Fi driver requirements.

---

## 9. UI Assets

- Use Lucide icons sprite SVG for full offline experience
- Use GUI from endroid-os.vercel.app as the reference implementation
