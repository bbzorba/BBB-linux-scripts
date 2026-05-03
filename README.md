# BBB Linux Scripts

Build and deployment scripts for a custom embedded Linux system on the **BeagleBone Black (AM335x)**.

The system consists of:
- **U-Boot** bootloader (MLO + u-boot.img)
- **Linux kernel** (zImage + DTB)
- **BusyBox 1.37.0** static ARM rootfs packed as a cpio initramfs
- **Login shell** via `getty` on ttyS0 (user: `root`, password: `root`)
- **Networking:** static eth0 (192.168.7.2) + DHCP usb0 via USB g_ether (internet)
- SD card boot via **extlinux** (U-Boot `distro_bootcmd`)

---

## Directory layout

```
BBB_linux_scripts/          ← this folder: scripts, uEnv files, rootfs overlay
  rootfs_overlay/           ← source-controlled /etc skeleton (copied at build time)
    etc/
      inittab               ← BusyBox init: getty on ttyS0, sysinit → rcS
      passwd / group        ← root user definition
      profile               ← shell environment (PS1, PATH)
      init.d/
        rcS                 ← early init: mounts, runtime dirs, bind-mounts lib/modules
        S01logging          ← starts syslogd + klogd
        S02module           ← modprobe g_ether (with fixed MACs)
        S40network          ← ifup -a (lo + eth0 static + usb0 DHCP)
        S50sshd             ← starts sshd (only if /usr/sbin/sshd present)
      network/
        interfaces          ← eth0: 192.168.7.2/24 static; usb0: dhcp (internet)
    usr/share/udhcpc/
      default.script        ← udhcpc DHCP event handler (sets IP, route, resolv.conf)
images/
  bbb_cross_build/          ← Linux kernel build output
  u-boot/
    release/                ← U-Boot build output (MLO, u-boot.img, u-boot-spl.bin)
  static_rootfs/            ← BusyBox install target + overlay = initramfs source
    bin/  sbin/  usr/       ← BusyBox applets (symlinks → busybox binary)
    etc/                    ← copied from rootfs_overlay/ at build time
    lib/modules/            ← kernel modules (~32 MB, excluded from initramfs)
busybox-1.37.0/             ← BusyBox source tree
```

### SD card partition layout

| Partition | FS    | Mount                  | Contents                               |
|-----------|-------|------------------------|----------------------------------------|
| p1        | FAT32 | `/media/$USER/BOOT`    | MLO, u-boot.img, extlinux/, payload/   |
| p2        | swap  | —                      | swap (unused at runtime)               |
| p3        | ext4  | `/media/$USER/rootfs`  | kernel modules (`lib/modules/`)        |

```
BOOT/
├── extlinux/
│   └── extlinux.conf        ← U-Boot boot descriptor (kernel, DTB, initramfs paths)
├── payload/
│   ├── zImage               ← ARM Linux kernel (bootz format)
│   ├── am335x-boneblack.dtb
│   └── initramfs            ← cpio+gzip BusyBox rootfs (~1.2 MB, no kernel modules)
├── MLO                      ← AM335x 1st-stage bootloader (ROM looks here)
├── u-boot.img               ← 2nd-stage bootloader
└── u-boot-spl.bin           ← SPL
```

> **Why modules are not in the initramfs:** `lib/modules/` is ~32 MB; the BOOT FAT
> partition is only 36 MB. `rcS` mounts the ext4 rootfs partition (p3) read-only at
> `/mnt/rootfs` and bind-mounts its `lib/modules` to `/lib/modules`, making
> `modprobe` work correctly from within the initramfs environment.

---

## Boot sequence

```
ROM → MLO → u-boot-spl.bin → u-boot.img
  → distro_bootcmd → extlinux/extlinux.conf
  → bootz zImage + am335x-boneblack.dtb + initramfs
  → kernel → /sbin/init (BusyBox init)
  → /etc/inittab:
      ::sysinit:/etc/init.d/rcS
        ├── mount proc / sysfs / devtmpfs
        ├── mkdir /var/run /var/lock /etc/network/if-*.d
        ├── mount mmcblk0p3 (ext4) → bind-mount lib/modules
        ├── S01logging  → syslogd + klogd
        ├── S02module   → modprobe g_ether (fixed MACs)
        └── S40network  → ifup -a: lo + eth0 (192.168.7.2/24 static) + usb0 (DHCP → internet)
      ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
```

Login: `root` / `root`

---

## Networking

### eth0 — direct Ethernet to host PC (static)

| Side  | Interface   | IP            |
|-------|-------------|---------------|
| BBB   | eth0        | 192.168.7.2/24 |
| Host  | eno1 (auto-detected) | 192.168.7.1/24 |

Use `set_host_and_BBB_IPs.sh` on the host PC each time you need to reach the BBB
over Ethernet (SSH, TFTP, etc.).

### usb0 — USB g_ether internet sharing (DHCP)

BBB loads `g_ether` at boot with **fixed MAC addresses** so the host always sees the
same interface name:

| Side  | Interface       | MAC               | IP                |
|-------|-----------------|-------------------|-------------------|
| BBB   | usb0            | b2:d5:cc:d1:57:a2 | DHCP (10.42.0.x)  |
| Host  | enxbe528e1c67f4 | be:52:8e:1c:67:f4 | 10.42.0.1/24      |

The host NM connection `BBB-USB-Share` provides DHCP + NAT (iptables MASQUERADE) so
the BBB's `usb0` gets internet access. The default route on the BBB comes from this
DHCP lease — `eth0` has no gateway configured.

Run `setup_usb_internet_sharing.sh` **once** on the host to create the persistent NM
connection. After that, plugging in the USB cable is enough — NM activates it
automatically, and `ifup -a` in `S40network` runs `udhcpc` on `usb0` via BusyBox's
built-in DHCP support (`iface usb0 inet dhcp` in `/etc/network/interfaces`).

---

## Scripts

### `build_uboot_image.sh`
Cross-compiles U-Boot for the `am335x_evm` target.

```bash
bash build_uboot_image.sh
```

**Output:** `images/u-boot/release/` — MLO, u-boot.img, spl/u-boot-spl.bin

Only re-run when U-Boot source changes.

---

### `build_BBB_kernel.sh`
Cross-compiles the Linux kernel using `bb.org_defconfig`.

```bash
bash build_BBB_kernel.sh
```

**Output:**
- `images/bbb_cross_build/arch/arm/boot/zImage`
- `images/bbb_cross_build/arch/arm/boot/dts/am335x-boneblack.dtb`
- Modules installed to `images/static_rootfs/lib/modules/`

Re-run whenever kernel source or config changes.

---

### `build_fs_busybox.sh`
Cross-compiles BusyBox as a **static ARM binary**, applies `rootfs_overlay/`, generates
`/etc/shadow`, and runs `modules_install` into `images/static_rootfs/`.

```bash
bash build_fs_busybox.sh
```

**What it does:**
1. `defconfig` + `sed` patches (static linking, shadow passwords, disable TC/SUID)
2. `make install` → `images/static_rootfs/`
3. `cp -a rootfs_overlay/ → images/static_rootfs/` (copies all /etc config files)
4. Generates `/etc/shadow` with SHA-512 hash (fixed salt, reproducible builds)
5. `modules_install` → `images/static_rootfs/lib/modules/`

Re-run whenever BusyBox config, source, or any file in `rootfs_overlay/` changes.

> **rootfs_overlay/** is the single source of truth for all `/etc` config files.
> Edit files there — never edit `images/static_rootfs/` directly (it gets wiped on rebuild).

---

### `copy_all_bins_to_sd.sh`
**Main deployment script.** Copies all build outputs to the mounted SD card.

```bash
bash copy_all_bins_to_sd.sh
```

| Step | Source | Destination |
|------|--------|-------------|
| 1 | `images/static_rootfs/lib/modules/` | `rootfs/lib/modules/` |
| 2 | `busybox-1.37.0/_install/` | `rootfs/` |
| 3 | `bbb_cross_build/.../zImage` + DTB | `BOOT/payload/` |
| 4 | `images/static_rootfs/` (excl. lib/modules) → cpio+gzip | `BOOT/payload/initramfs` |
| 5 | `images/u-boot/release/` MLO + u-boot.img + u-boot-spl.bin | `BOOT/` |

**Requirements:** SD card must be mounted (both `BOOT` and `rootfs` partitions).

---

### `set_host_and_BBB_IPs.sh`
Assigns `192.168.7.1/24` to the host Ethernet port connected to BBB and pings to
verify the link. Auto-detects the correct interface (skips internet-facing and USB
interfaces). Run this each time you need host ↔ BBB Ethernet access.

```bash
bash set_host_and_BBB_IPs.sh
```

Does **not** require BBB to be booted — it pre-assigns the IP so it is ready when BBB
comes up.

---

### `setup_usb_internet_sharing.sh`
**One-time setup.** Creates a persistent NetworkManager connection on the host that
provides DHCP + NAT internet sharing to the BBB over the USB g_ether interface.

```bash
bash setup_usb_internet_sharing.sh
```

Run once. After this, plugging in the USB cable is enough — NM activates the connection
automatically. The BBB's `S40network` script runs `ifup -a` which handles `usb0 inet dhcp`
(calls `udhcpc` via BusyBox's built-in DHCP support) in the same pass as `eth0`.

---

## uEnv files

| File | Purpose |
|------|---------|
| `uEnv.txt` | Default SD card boot (copy to BOOT partition root if needed) |
| `uEnv_tftp.txt` | TFTP boot — loads kernel + DTB + initramfs over Ethernet |
| `uEnv_multiboot.txt` | Priority boot chain: eMMC → SD → TFTP → NFS |

> **Active boot method:** `extlinux/extlinux.conf` (U-Boot `distro_bootcmd`).
> The uEnv files are provided as alternatives for `uenvcmd`-based workflows.

---

## Typical workflows

### First-time setup (build everything from scratch)

```bash
cd BBB_linux_scripts
bash build_uboot_image.sh      # ~5 min
bash build_BBB_kernel.sh       # ~15 min
bash build_fs_busybox.sh       # ~2 min
# Insert and mount SD card, then:
bash copy_all_bins_to_sd.sh

# One-time host PC setup for USB internet sharing:
bash setup_usb_internet_sharing.sh
```

### BusyBox / rootfs / etc config change

```bash
# Edit files in rootfs_overlay/  (NOT in images/static_rootfs/)
bash build_fs_busybox.sh
bash copy_all_bins_to_sd.sh
```

### Kernel change only

```bash
bash build_BBB_kernel.sh
bash copy_all_bins_to_sd.sh    # or: bash copy_dtbo_uImage_to_sd.sh (faster, no rootfs)
```

### U-Boot change only

```bash
bash build_uboot_image.sh
bash copy_all_bins_to_sd.sh
```

### Connect to BBB over Ethernet

```bash
bash set_host_and_BBB_IPs.sh   # sets 192.168.7.1 on host, pings BBB
ssh root@192.168.7.2
```

---

## Expected boot output

```
U-Boot SPL ... Trying to boot from MMC1
Scanning mmc 0:1 ...
Found /extlinux/extlinux.conf
...
Embedded Linux BBB - initramfs ready
Starting logging: OK
Loading kernel modules : OK           ← g_ether loaded, usb0 appears
Starting network: OK                  ← eth0: 192.168.7.2/24, usb0: 10.42.0.x (DHCP)

(none) login: root
Password:
[root@(none) ~]#
```

After login, verify networking:

```sh
ip a              # eth0: 192.168.7.2/24  usb0: 10.42.0.x/24
ping 8.8.8.8      # internet via usb0 → host NAT
ping 192.168.7.1  # direct Ethernet to host PC
lsmod             # g_ether 16384 0
```

---

## Cross-compiler

All scripts use `arm-linux-gnueabi-` (soft-float ABI).

```bash
sudo apt install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
arm-linux-gnueabi-gcc --version
```

---

## Hardware

- **Board:** BeagleBone Black — TI AM335x, ARM Cortex-A8, 512 MB DDR3
- **Serial console:** UART0 — ttyS0 @ 115200 8N1 (header P9: pin21=RX, pin22=TX, GND)
- **Boot media:** microSD slot (mmc0 in U-Boot / mmcblk0 in Linux)
- **USB:** mini-USB client port → g_ether gadget → internet sharing from host PC

