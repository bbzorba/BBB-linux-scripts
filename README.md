# BBB Linux Scripts

Build, rootfs, deployment, and host-networking scripts for a custom embedded Linux system on the **BeagleBone Black (AM335x)**.

The current setup supports:
- **U-Boot** bootloader (`MLO`, `u-boot.img`, `u-boot-spl.bin`)
- **Linux kernel** (`zImage` + `am335x-boneblack.dtb`)
- **BusyBox 1.37.0** rootfs builds in two modes:
  - **static** rootfs for minimal standalone initramfs boot
  - **dynamic** rootfs for testing dynamically linked ARM applications
- **Login shell** via `getty` on `ttyS0` (`root` / `root`)
- **Networking:** static `eth0` (`192.168.7.2/24`) + DHCP `usb0` via USB `g_ether`
- SD card boot via **extlinux** (`distro_bootcmd`)

---

## Directory layout

The scripts are now grouped by function.

```text
BBB_linux_scripts/
├── busybox_scripts/
│   ├── build_static_rootfs_busybox.sh
│   ├── build_dynamic_rootfs_busybox.sh
│   └── rootfs_overlay/
│       ├── etc/
│       │   ├── inittab
│       │   ├── passwd
│       │   ├── group
│       │   ├── profile
│       │   ├── init.d/
│       │   │   ├── rcS
│       │   │   ├── S01logging
│       │   │   ├── S02module
│       │   │   ├── S40network
│       │   │   └── S50sshd
│       │   └── network/
│       │       └── interfaces
│       └── usr/share/udhcpc/
│           └── default.script
├── kernel_and_bootloader_scripts/
│   ├── build_BBB_kernel.sh
│   └── build_uboot_image.sh
├── networking_scripts/
│   ├── set_host_and_BBB_IPs.sh
│   └── setup_usb_internet_sharing.sh
├── uEnv.txt/
│   ├── uEnv.txt
│   ├── uEnv_tftp.txt
│   └── uEnv_multiboot.txt
├── copy_all_bins_to_sd.sh
└── README.md

images/
├── bbb_cross_build/          # Linux kernel build output
├── u-boot/release/           # U-Boot build output
├── static_rootfs/            # Static BusyBox install target + overlay
└── dynamic_rootfs/           # Dynamic BusyBox install target + glibc runtime libs

busybox-1.37.0/               # BusyBox source tree
```

### Rootfs overlay

`busybox_scripts/rootfs_overlay/` is the source-controlled `/etc` skeleton for both BusyBox build modes.

It contains:
- `inittab` for BusyBox init + serial `getty`
- `rcS` and `S??*` init scripts
- `interfaces` for `eth0` static + `usb0` DHCP
- `udhcpc/default.script` for DHCP lease handling

Edit files there, not under `images/static_rootfs/` or `images/dynamic_rootfs/`, because those directories are regenerated.

---

## SD card layout

| Partition | FS | Mount | Contents |
|---|---|---|---|
| p1 | FAT32 | `/media/$USER/BOOT` | bootloader files, `extlinux/`, `payload/` |
| p2 | swap | — | swap |
| p3 | ext4 | `/media/$USER/rootfs` | `lib/modules/` persisted outside initramfs |

```text
BOOT/
├── extlinux/
│   └── extlinux.conf
├── payload/
│   ├── zImage
│   ├── am335x-boneblack.dtb
│   └── initramfs
├── MLO
├── u-boot.img
└── u-boot-spl.bin
```

Kernel modules stay on the ext4 rootfs partition because `lib/modules/` is too large for the small FAT boot partition. During boot, `rcS` mounts `mmcblk0p3` at `/mnt/rootfs` and bind-mounts `/mnt/rootfs/lib/modules` onto `/lib/modules`.

---

## Boot sequence

```text
ROM -> MLO -> u-boot-spl.bin -> u-boot.img
   -> distro_bootcmd -> extlinux/extlinux.conf
   -> bootz zImage + am335x-boneblack.dtb + initramfs
   -> kernel -> /sbin/init
   -> /etc/inittab
      -> /etc/init.d/rcS
         -> mount proc / sysfs / devtmpfs
         -> create runtime directories
         -> mount mmcblk0p3 and bind-mount lib/modules
         -> S01logging
         -> S02module
         -> S40network
      -> ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
```

Login credentials: `root` / `root`

---

## Networking

### `eth0` over direct Ethernet

| Side | Interface | IP |
|---|---|---|
| BBB | `eth0` | `192.168.7.2/24` |
| Host | auto-detected NIC | `192.168.7.1/24` |

Use `networking_scripts/set_host_and_BBB_IPs.sh` whenever you want direct host-to-BBB Ethernet access.

### `usb0` over `g_ether`

The BBB loads `g_ether` with fixed MAC addresses so the host always sees the same USB Ethernet device.

| Side | Interface | MAC | IP |
|---|---|---|---|
| BBB | `usb0` | `b2:d5:cc:d1:57:a2` | DHCP (`10.42.0.x`) |
| Host | `enxbe528e1c67f4` | `be:52:8e:1c:67:f4` | `10.42.0.1/24` |

The host-side NetworkManager profile provides DHCP + NAT, so the BBB gets internet access through `usb0`. `eth0` intentionally has no default gateway.

---

## Scripts

### Kernel and bootloader

#### `kernel_and_bootloader_scripts/build_uboot_image.sh`

Builds U-Boot for the BeagleBone Black target.

```bash
bash kernel_and_bootloader_scripts/build_uboot_image.sh
```

Output:
- `images/u-boot/release/MLO`
- `images/u-boot/release/u-boot.img`
- `images/u-boot/release/spl/u-boot-spl.bin`

#### `kernel_and_bootloader_scripts/build_BBB_kernel.sh`

Builds the Linux kernel using `bb.org_defconfig`.

```bash
bash kernel_and_bootloader_scripts/build_BBB_kernel.sh
```

Output:
- `images/bbb_cross_build/arch/arm/boot/zImage`
- `images/bbb_cross_build/arch/arm/boot/dts/am335x-boneblack.dtb`
- kernel modules under `images/static_rootfs/lib/modules/`

### BusyBox rootfs builds

#### `busybox_scripts/build_static_rootfs_busybox.sh`

Builds a **statically linked** BusyBox rootfs and applies the shared overlay.

```bash
bash busybox_scripts/build_static_rootfs_busybox.sh
```

What it does:
1. Generates a BusyBox `defconfig` for ARM.
2. Forces `CONFIG_STATIC=y`.
3. Enables shadow password support.
4. Installs BusyBox into `images/static_rootfs/`.
5. Copies `busybox_scripts/rootfs_overlay/` into the rootfs.
6. Generates `/etc/shadow` with the root password hash.
7. Runs `modules_install` into `images/static_rootfs/`.

Use this when you want the smallest, most self-contained initramfs.

#### `busybox_scripts/build_dynamic_rootfs_busybox.sh`

Builds a **dynamically linked** BusyBox rootfs for testing normal ARM ELF binaries that depend on glibc shared libraries.

```bash
bash busybox_scripts/build_dynamic_rootfs_busybox.sh
```

What it does:
1. Generates a BusyBox `defconfig` for ARM.
2. Forces `CONFIG_STATIC` off.
3. Enables shadow password support.
4. Installs BusyBox into `images/dynamic_rootfs/`.
5. Copies `busybox_scripts/rootfs_overlay/` into the rootfs.
6. Generates `/etc/shadow` with the root password hash.
7. Copies ARM runtime libraries from `/usr/arm-linux-gnueabi/lib/` into `images/dynamic_rootfs/lib/`.
8. Runs `modules_install` into `images/dynamic_rootfs/`.

This is the right build when you want to deploy and run a dynamically linked test program such as:

```bash
arm-linux-gnueabi-gcc -o hello hello.c
arm-linux-gnueabi-readelf -d hello | grep NEEDED
cp hello images/dynamic_rootfs/usr/bin/
```

### Deployment

#### `copy_all_bins_to_sd.sh`

Main deployment script. It copies kernel artifacts, bootloader files, modules, and a generated initramfs to the mounted SD card.

```bash
bash copy_all_bins_to_sd.sh
```

Behavior:
1. Copies kernel modules from `images/static_rootfs/lib/modules/` to `/media/$USER/rootfs/lib/modules/`.
2. Copies BusyBox applets from `busybox-1.37.0/_install/` to `/media/$USER/rootfs/`.
3. Copies `zImage` and `am335x-boneblack.dtb` to `/media/$USER/BOOT/payload/`.
4. Prompts you to choose which initramfs to package:
   - `s` = `images/static_rootfs/`
   - `d` = `images/dynamic_rootfs/`
5. Creates `BOOT/payload/initramfs` by packing the selected rootfs, excluding `lib/modules/`.
6. Copies U-Boot binaries into `/media/$USER/BOOT/`.

Requirements:
- SD card partitions mounted at `/media/$USER/BOOT` and `/media/$USER/rootfs`
- built kernel artifacts
- built BusyBox rootfs artifacts

### Host networking

#### `networking_scripts/set_host_and_BBB_IPs.sh`

Assigns `192.168.7.1/24` to the host NIC connected to the BBB and checks reachability.

```bash
bash networking_scripts/set_host_and_BBB_IPs.sh
```

#### `networking_scripts/setup_usb_internet_sharing.sh`

One-time host setup for USB internet sharing through NetworkManager.

```bash
bash networking_scripts/setup_usb_internet_sharing.sh
```

After this runs once, plugging in the BBB over USB is enough for the host to provide DHCP + NAT.

---

## uEnv files

These files are stored under `uEnv.txt/` because they are optional boot configuration variants.

| File | Purpose |
|---|---|
| `uEnv.txt/uEnv.txt` | default SD boot |
| `uEnv.txt/uEnv_tftp.txt` | TFTP boot |
| `uEnv.txt/uEnv_multiboot.txt` | multi-source boot chain |

The active path is still `extlinux/extlinux.conf`. The `uEnv` files are kept as alternatives for `uenvcmd`-based workflows.

---

## Typical workflows

### Full rebuild

```bash
cd BBB_linux_scripts
bash kernel_and_bootloader_scripts/build_uboot_image.sh
bash kernel_and_bootloader_scripts/build_BBB_kernel.sh
bash busybox_scripts/build_static_rootfs_busybox.sh
bash copy_all_bins_to_sd.sh
bash networking_scripts/setup_usb_internet_sharing.sh
```

### Static BusyBox rootfs rebuild

```bash
cd BBB_linux_scripts
bash busybox_scripts/build_static_rootfs_busybox.sh
bash copy_all_bins_to_sd.sh
```

### Dynamic BusyBox rootfs rebuild

```bash
cd BBB_linux_scripts
bash busybox_scripts/build_dynamic_rootfs_busybox.sh
bash copy_all_bins_to_sd.sh
# choose 'd' when prompted
```

### Add a dynamically linked test program

```bash
cd BBB_linux_scripts/..
arm-linux-gnueabi-gcc -o hello hello.c
cp hello images/dynamic_rootfs/usr/bin/
cd BBB_linux_scripts
bash copy_all_bins_to_sd.sh
# choose 'd' when prompted
```

### Kernel-only rebuild

```bash
cd BBB_linux_scripts
bash kernel_and_bootloader_scripts/build_BBB_kernel.sh
bash copy_all_bins_to_sd.sh
```

### Host-to-BBB Ethernet access

```bash
cd BBB_linux_scripts
bash networking_scripts/set_host_and_BBB_IPs.sh
ssh root@192.168.7.2
```

---

## Expected boot result

```text
U-Boot SPL ... Trying to boot from MMC1
Scanning mmc 0:1 ...
Found /extlinux/extlinux.conf
...
Embedded Linux BBB - initramfs ready
Starting logging: OK
Loading kernel modules : OK
Starting network: OK

(none) login: root
Password:
[root@(none) ~]#
```

Quick checks after login:

```sh
ip a
ping 8.8.8.8
ping 192.168.7.1
lsmod
```

---

## Toolchain

All scripts use the soft-float ARM toolchain prefix `arm-linux-gnueabi-`.

```bash
sudo apt install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi libc6-dev-armel-cross
arm-linux-gnueabi-gcc --version
```

For the dynamic rootfs build, the runtime shared libraries are expected under:

```text
/usr/arm-linux-gnueabi/lib/
```

---

## Hardware

- **Board:** BeagleBone Black, TI AM335x, ARM Cortex-A8, 512 MB DDR3
- **Serial console:** UART0 on `ttyS0`, `115200 8N1`
- **Boot media:** microSD
- **USB:** mini-USB client port used for `g_ether`

