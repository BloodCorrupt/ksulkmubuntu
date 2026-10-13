# KernelSU-Next x86_64 Builder Suite

Automated builder and loader suite for compiling and running **KernelSU-Next** as a Loadable Kernel Module (**LKM**) on **Ubuntu 26.04 LTS (Resolute Raccoon)** x86_64 systems (Kernel `7.0.x` / `6.x`).

Designed specifically for hosts running containers like **Waydroid** or emulators on standard distribution Linux kernels where standard GKI builds do not apply.

---

## 📖 Background & Problem Solved

Compiling KernelSU-Next out-of-tree against standard Linux distribution kernels (e.g. Ubuntu `7.0.0-38-generic`) traditionally encounters several obstacles:

1. **Missing SELinux Subsystem Headers:**
   Distribution `-headers` packages (`linux-headers-$(uname -r)`) omit internal security headers (`security/selinux/genheaders`, `include/objsec.h`, `flask.h`, `av_permissions.h`). Without them, compilation halts with:
   ```text
   fatal error: flask.h: No such file or directory
   ```
2. **x86_64 Syscall Dispatcher Hardening:**
   On x86_64 Linux kernels, standard kprobe/ftrace hooks fail unless the dispatcher is dynamically patched at runtime using:
   ```bash
   CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y
   ```
3. **Unexported Kernel Symbols:**
   Distribution kernels do not export internal symbols (e.g. `sidtab_destroy`, `ebitmap_destroy`, `avtab_search_node`) to external modules, causing `modpost` errors.
4. **Runtime Resolution & Vermagic (`lkmloader`):**
   Using `KBUILD_MODPOST_WARN=1` produces `kernelsu.ko` with unresolved symbols. The specialized loader **[maxsteeel/lkmloader](https://github.com/maxsteeel/lkmloader)** reads `/proc/kallsyms`, dynamically resolves unexported symbols into the module's ELF table in memory, automatically adapts `vermagic` via `/dev/kmsg`, and calls `init_module()`.

This suite packages the entire workflow into a **single automated script** with an interactive menu and command-line flags.

---

## 📁 Repository Structure

```
ksu-x64-builder/
├── ksu-suite.sh                 # Master CLI & Interactive menu runner
├── config.env                   # User-configurable repositories and settings
├── scripts/
│   ├── 00-common.sh             # Shared helper functions, logging, colors
│   ├── 01-check-env.sh          # System audit (kernel, x86_64, secure boot, disk)
│   ├── 02-install-deps.sh       # Installs build-essential, linux-headers, libelf, etc.
│   ├── 03-prepare-selinux.sh    # Fetches kernel source & compiles missing SELinux headers
│   ├── 04-build-ksu.sh          # Clones KernelSU-Next (dev branch) and builds kernelsu.ko
│   ├── 05-fetch-lkmloader.sh    # Downloads/compiles maxsteeel/lkmloader-x86_64
│   ├── 06-load-module.sh        # Loads kernelsu.ko using lkmloader & verifies dmesg
│   ├── 07-systemd-service.sh    # Sets up persistent /etc/systemd/system boot service
│   └── 08-clean.sh              # Cleans build workspace and temporary downloads
├── src/
│   └── lkmloader.c              # Bundled source of maxsteeel/lkmloader
├── systemd/
│   └── kernelsu-lkm.service     # Systemd unit template
├── deploy-remote.ps1            # Windows PowerShell SSH/SCP deployer
├── deploy-remote.sh             # Linux/WSL SSH/SCP deployer
└── README.md                    # This documentation
```

---

## 🚀 Quick Start

### Method A: Deploy from Windows Workstation (Recommended)

From PowerShell on your Windows workstation, deploy the suite to your Ubuntu machine over SSH:

```powershell
# Transfer files to ThinkStation P330 Tiny
.\deploy-remote.ps1 -RemoteHost "10.13.37.183" -RemoteUser "bloodtek"

# Or transfer AND immediately trigger the full automated pipeline:
.\deploy-remote.ps1 -RemoteHost "10.13.37.183" -RemoteUser "bloodtek" -ExecuteNow
```

### Method B: Run Directly on Ubuntu via SSH

1. SSH into your Ubuntu 26.04 machine:
   ```bash
   ssh bloodtek@10.13.37.183
   ```
2. Navigate to the suite directory:
   ```bash
   cd ~/ksu-x64-builder
   chmod +x ksu-suite.sh scripts/*.sh
   ```
3. Run the **Full Automated Pipeline**:
   ```bash
   ./ksu-suite.sh --all
   ```
   *(Or simply run `./ksu-suite.sh` without arguments to open the interactive menu).*

---

## 🖥️ Interactive Console Menu

Running `./ksu-suite.sh` launches an interactive interface:

```text
╔═════════════════════════════════════════════════════════════════════════╗
║         KernelSU-Next x86_64 Builder Suite - Ubuntu 26.04 LTS           ║
╚═════════════════════════════════════════════════════════════════════════╝
  Active Kernel: 7.0.0-38-generic | Arch: x86_64

  [1] Full Automated Pipeline (Check -> Deps -> SELinux -> Build -> Load)
  [2] Check Environment & Secure Boot Status
  [3] Install Compilation Dependencies & Kernel Headers
  [4] Download & Prepare Missing SELinux Headers (genheaders)
  [5] Clone & Build KernelSU-Next LKM (kernelsu.ko)
  [6] Fetch/Compile LKM Loader (maxsteeel/lkmloader)
  [7] Load KernelSU Module via lkmloader
  [8] Configure Persistent Systemd Boot Service
  [9] Clean Build Workspace
  [0] Exit
```

---

## 🛠️ CLI Options & Individual Steps

You can run individual phases independently:

| Command | Action |
| :--- | :--- |
| `./ksu-suite.sh -a` or `--all` | Runs the full pipeline end-to-end |
| `./ksu-suite.sh -c` or `--check` | Runs pre-flight audit (Secure Boot, kernel headers, storage) |
| `./ksu-suite.sh -d` or `--deps` | Updates APT and installs `linux-headers-$(uname -r)` and compilers |
| `./ksu-suite.sh -s` or `--selinux` | Downloads matching kernel source, extracts & generates `flask.h` |
| `./ksu-suite.sh -b` or `--build` | Builds `KernelSU-Next/kernel/kernelsu.ko` |
| `./ksu-suite.sh -l` or `--loader` | Fetches release binary or compiles `src/lkmloader.c` |
| `./ksu-suite.sh -m` or `--load` | Loads `kernelsu.ko` into active kernel |
| `./ksu-suite.sh --service` | Installs `/etc/systemd/system/kernelsu-lkm.service` for automatic boot |
| `./ksu-suite.sh --clean` | Cleans `build_workspace/` temporary files |

---

## ⚙️ How the Pipeline Works

### 1. Missing SELinux Headers (`03-prepare-selinux.sh`)
* Detects running kernel version from `uname -r` (e.g. `7.0.0`).
* Downloads the matching kernel source from `cdn.kernel.org` (or via `apt source linux`).
* Efficiently extracts only `security/selinux` (saving gigabytes of bandwidth and disk space).
* Copies missing directories (`genheaders`, `include`, `ss`) into `/lib/modules/$(uname -r)/build/security/selinux/`.
* Compiles `genheaders.c` and runs `./genheaders flask.h av_permissions.h`.
* Places `flask.h` and `av_permissions.h` in both the root of SELinux and `include/` to ensure all `#include` directives succeed.

### 2. KernelSU-Next Compilation (`04-build-ksu.sh`)
* Clones `KernelSU-Next` from branch `dev` (which integrates PR `#1457` providing generic Linux 7.x/6.x out-of-tree support).
* Invokes `kbuild` using:
  ```bash
  make -j$(nproc) -C /lib/modules/$(uname -r)/build \
      M=$(pwd)/KernelSU-Next/kernel \
      CONFIG_KSU=m \
      KBUILD_MODPOST_WARN=1 \
      CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y \
      modules
  ```
* Saves the resulting module to `output/kernelsu.ko`.

### 3. Module Loading (`05-fetch-lkmloader.sh` & `06-load-module.sh`)
* Obtains `lkmloader-x86_64` from GitHub Release v1.0.0 (verified by SHA256 checksum) or compiles from bundled `src/lkmloader.c`.
* Executes:
  ```bash
  sudo ./output/lkmloader-x86_64 ./output/kernelsu.ko
  ```
* `lkmloader` dynamically parses `/proc/kallsyms` to resolve unexported kernel symbols, adapts vermagic dynamically via `/dev/kmsg`, and calls `init_module()`.
* The script confirms module loading via `lsmod | grep kernelsu` and inspects `dmesg`.

### 4. Persistent Boot Service (`07-systemd-service.sh`)
* Installs binaries to `/opt/kernelsu/`.
* Installs and enables `kernelsu-lkm.service`:
  ```ini
  [Unit]
  Description=KernelSU-Next LKM Boot Loader
  DefaultDependencies=no
  After=systemd-modules-load.service
  Before=sysinit.target basic.target waydroid-container.service

  [Service]
  Type=oneshot
  RemainAfterExit=yes
  ExecStart=/opt/kernelsu/lkmloader-x86_64 /opt/kernelsu/kernelsu.ko

  [Install]
  WantedBy=basic.target
  ```
* Ensures KernelSU is initialized prior to `waydroid-container.service` or user login.

---

## 🔒 UEFI Secure Boot Notice

If UEFI Secure Boot is active on your host (e.g. ThinkStation P330 Tiny):
* The Linux kernel enters **Lockdown mode: integrity**, preventing `init_module()` from loading unsigned third-party modules.
* The pre-flight check (`01-check-env.sh`) detects and alerts you if Secure Boot is enabled.
* **Solution:** Enter UEFI/BIOS setup during boot (F1/F12 on ThinkStation) and disable Secure Boot, or enroll a custom MOK key.

---

## 🤖 Redroid (Docker) Integration & Troubleshooting

When running Android inside Docker using **Redroid** (e.g. `redroid13_x86_64`):

### Why Manager reports "Not installed" & dmesg shows `permission denied for cmd=0x4b01 uid=10091`
1. **Root Namespace Disconnect:**
   KernelSU verifies and "crowns" the manager app by reading `/data/system/packages.list` in the kernel (`throne_tracker.c`).
   On bare metal, Android is the root OS. In Redroid, Android is containerized inside Docker, and `/data/system/packages.list` exists **inside the container**, NOT on the Ubuntu host root `/`!
2. **Result:**
   `throne_tracker` on the host kernel fails to open `/data/system/packages.list` (ENOENT -2). Consequently, `ksu_manager_appid` stays `-1`.
   When the Manager app (UID `10091`) tries to call ioctl `0x4b01` or `0xc0004b0d`, KernelSU rejects it with `EPERM` (`permission denied`), and the app displays **"Not installed"**!

### Fix A: Automatic Host Bind-Mount (Recommended)
Run the automated helper to detect your running Redroid container and bind-mount its data directory to `/data` on the host:
```bash
./ksu-suite.sh --redroid
# or directly:
sudo ./scripts/09-setup-redroid.sh
```
This maps `<redroid_data>/system/packages.list` to `/data/system/packages.list` on the host, allowing the kernel to crown UID 10091. Reopening the Manager app will now show **Working**!

### Fix B: Dynamic Manager UID Parameter
The suite patches `throne_tracker.c` and `manager_identity.h` during build to add a container parameter:
```bash
# Dynamically authorize the manager UID without reloading:
echo 10091 | sudo tee /sys/module/kernelsu/parameters/manager_uid
```

---

## 🔀 Switching Backends: KernelSU-Next vs SukiSU-Ultra

The suite supports both **KernelSU-Next** and **SukiSU-Ultra** (the active successor to ReSukiSU):

* **In Interactive Menu:** Press `[T]` to toggle between `KernelSU-Next` and `SukiSU-Ultra`.
* **In `config.env`:** Set `KSU_VARIANT`:
  ```bash
  # Options: "ksu-next" or "sukisu"
  KSU_VARIANT="sukisu"
  ```
* Rebuild and load:
  ```bash
  ./ksu-suite.sh --build
  ./ksu-suite.sh --load
  ```

---

## 📱 Waydroid Integration

Once `kernelsu.ko` is loaded on the Ubuntu host:
1. Start Waydroid:
   ```bash
   waydroid session start
   ```
2. Download and install the latest **[KernelSU-Next Manager APK](https://github.com/KernelSU-Next/KernelSU-Next/releases)** inside Waydroid:
   ```bash
   waydroid app install KernelSU_Next_Manager.apk
   ```
3. Open the Manager app to verify that KernelSU status shows **Working**!

