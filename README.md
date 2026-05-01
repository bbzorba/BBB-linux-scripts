# BBB Linux Scripts

Build and deployment scripts for a custom embedded Linux system on the **BeagleBone Black (AM335x)**.

The system consists of:
- **U-Boot** bootloader (MLO + u-boot.img)
- **Linux kernel** (zImage + DTB)
- **BusyBox** static rootfs packed as a cpio initramfs
- SD card boot via **extlinux** (U-Boot `distro_bootcmd`)

---

## Directory layout

```
BBB_linux_scripts/        ← this folder (scripts + uEnv files)
images/
  bbb_cross_build/        ← Linux kernel source tree (ARM cross-build output here)
  u-boot/                 ← U-Boot source tree
    release/              ← U-Boot build output (MLO, u-boot.img, u-boot-spl.bin)
  static_rootfs/          ← BusyBox install target / initramfs source
    bin/  sbin/  usr/     ← BusyBox applets (symlinks → busybox binary)
    lib/modules/          ← kernel modules (installed by build_BBB_kernel.sh)
    etc/inittab           ← BusyBox init config (serial console on ttyS0)
    etc/init.d/rcS        ← mounts proc / sysfs / devtmpfs at boot
busybox-1.37.0/           ← BusyBox source tree
  _install/               ← temporary BusyBox install prefix (not used for SD card)
```

### SD card partition layout

| Partition | FS    | Mount        | Contents |
|-----------|-------|--------------|----------|
| p1        | FAT32 | `/media/$USER/BOOT`   | MLO, u-boot.img, extlinux/, payload/ |
| p2        | swap  | —            | swap (optional) |
| p3        | ext4  | `/media/$USER/rootfs` | BusyBox binaries + kernel modules |

```
BOOT/
├── extlinux/
│   └── extlinux.conf      ← tells U-Boot where to load kernel, DTB, initramfs
├── payload/
│   ├── zImage             ← ARM Linux kernel (bootz format)
│   ├── am335x-boneblack.dtb
│   └── initramfs          ← cpio+gzip BusyBox rootfs (NO kernel modules — too large)
├── MLO                    ← AM335x 1st-stage bootloader (ROM looks here)
├── u-boot.img             ← 2nd-stage bootloader
└── u-boot-spl.bin         ← SPL
```

> **Note:** `MLO` must be at the FAT root — the AM335x ROM loader hard-wires that path.
> All kernel images live under `payload/` as referenced by `extlinux/extlinux.conf`.

---

## Scripts

### `build_uboot_image.sh`
Cross-compiles U-Boot from source for the `am335x_evm` target.

```bash
bash build_uboot_image.sh
```

**Output:** `images/u-boot/release/` — MLO, u-boot.img, spl/u-boot-spl.bin

Only needs to be re-run when U-Boot source changes. The kernel and rootfs are
completely independent — this script never touches kernel images.

---

### `build_BBB_kernel.sh`
Cross-compiles the Linux kernel using `bb.org_defconfig` (BeagleBone default config).

```bash
bash build_BBB_kernel.sh
```

**Output:**
- `images/bbb_cross_build/arch/arm/boot/zImage` — kernel image for extlinux/bootz
- `images/bbb_cross_build/arch/arm/boot/uImage` — mkimage-wrapped kernel (kept for reference)
- `images/bbb_cross_build/arch/arm/boot/dts/am335x-boneblack.dtb`
- Kernel modules installed to `images/static_rootfs/lib/modules/` (if SD card is mounted)
  and to `/media/$USER/rootfs/lib/modules/` (if SD card rootfs is mounted)

Re-run whenever kernel source or `defconfig` changes.

---

### `build_fs_busybox.sh`
Cross-compiles BusyBox as a **static binary** and installs it to `images/static_rootfs/`.
Also runs `modules_install` to populate `images/static_rootfs/lib/modules/`.

```bash
bash build_fs_busybox.sh
```

Re-run whenever BusyBox config or source changes.

---

### `copy_all_bins_to_sd.sh`
**Main deployment script.** Copies everything to the mounted SD card.

```bash
bash copy_all_bins_to_sd.sh
```

What it does:
1. Copies kernel modules → `rootfs/lib/modules/`
2. Copies BusyBox binaries → `rootfs/`
3. Copies `zImage` + DTB → `BOOT/payload/`
4. Packs `images/static_rootfs/` (excluding `lib/modules/`) as a cpio+gzip
   initramfs → `BOOT/payload/initramfs`
5. Copies U-Boot binaries (MLO, u-boot.img, u-boot-spl.bin) → `BOOT/`

> **Kernel modules are excluded from the initramfs** because they are ~32 MB and
> the BOOT FAT partition is only 36 MB. They are available on the ext4 rootfs (p3).

**Requirements:** SD card must be mounted (`BOOT` and `rootfs` partitions).

---

### `copy_dtbo_uImage_to_sd.sh`
Quick helper to update only the kernel image and DTB overlays on the BOOT partition,
without rebuilding or recopying the full rootfs.

```bash
bash copy_dtbo_uImage_to_sd.sh
```

---

### `set_IPs_for_tftp.sh`
Configures static IP addresses for TFTP development workflow (host ↔ BBB over Ethernet).

```bash
bash set_IPs_for_tftp.sh
# Enter "server" (host PC) or "client" (BBB side)
```

| Role   | IP           | Interface |
|--------|--------------|-----------|
| Server (host PC) | 192.168.7.1 | eno1 |
| Client (BBB)     | 192.168.7.2 | eth0 |

---

## uEnv files

| File | Purpose |
|------|---------|
| `uEnv.txt` | Default SD card boot (copies to BOOT partition root) |
| `uEnv_tftp.txt` | TFTP boot — loads uImage + DTB + initramfs over Ethernet |
| `uEnv_multiboot.txt` | Priority boot chain: eMMC → SD → TFTP → NFS |

> **Active boot method:** `extlinux/extlinux.conf` (U-Boot `distro_bootcmd`).
> The `uEnv.txt` files are provided as alternatives for workflows that need
> `uenvcmd`-based boot instead of extlinux.

---

## Typical workflows

### First-time setup (build everything from scratch)

```bash
cd BBB_linux_scripts
bash build_uboot_image.sh      # ~5 min
bash build_BBB_kernel.sh       # ~15 min (j4)
bash build_fs_busybox.sh       # ~2 min
# Insert and mount SD card, then:
bash copy_all_bins_to_sd.sh
```

### Kernel change only

```bash
bash build_BBB_kernel.sh
bash copy_all_bins_to_sd.sh    # or: bash copy_dtbo_uImage_to_sd.sh (faster)
```

### BusyBox / rootfs change only

```bash
bash build_fs_busybox.sh
bash copy_all_bins_to_sd.sh
```

### U-Boot change only

```bash
bash build_uboot_image.sh
bash copy_all_bins_to_sd.sh
```

### Quick kernel + DTB update (no rootfs change)

```bash
bash build_BBB_kernel.sh
bash copy_dtbo_uImage_to_sd.sh
```

---

## Expected boot output

```
U-Boot SPL ... Trying to boot from MMC1
...
Scanning mmc 0:1...
Found /extlinux/extlinux.conf
BeagleBone Black Boot Menu
1: BBB payload (zImage+initramfs from BOOT/payload)
...
Embedded Linux BBB - initramfs ready

Please press Enter to activate this console.
~ #
```

`~ #` is the BusyBox shell. The message
`Not activating Mandatory Access Control as /sbin/tomoyo-init does not exist`
is a normal BusyBox init informational line — not an error.

---

## Cross-compiler

All scripts use `arm-linux-gnueabi-` (soft-float ABI).

```bash
sudo apt install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
```

Verify:
```bash
arm-linux-gnueabi-gcc --version
```

---

## Hardware

- **Board:** BeagleBone Black (TI AM335x, ARM Cortex-A8, 512 MB DDR3)
- **Serial console:** UART0 — ttyS0 @ 115200 8N1 (3-pin header P9.21/P9.22/GND)
- **Boot media:** microSD in slot (mmc0 in U-Boot / mmcblk0 in Linux)

