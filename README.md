# Official KernelSU x86_64 Builder Suite

Automated builder and loader suite for compiling and running **Official KernelSU** ([tiann/KernelSU](https://github.com/tiann/KernelSU)) as a Loadable Kernel Module (**LKM**) on **Ubuntu 26.04 LTS (Resolute Raccoon)** x86_64 systems (Kernel `7.0.x` / `6.x`).

Designed specifically for hosts running containers like **Redroid**, **Waydroid**, or emulators on standard distribution Linux kernels where standard GKI builds do not apply.

---

## 📖 Background & Architecture

Compiling Official KernelSU out-of-tree against standard Linux distribution kernels (e.g. Ubuntu `7.0.0-38-generic`) involves resolving several platform requirements:

1. **Missing SELinux Subsystem Headers:**
   Distribution `-headers` packages (`linux-headers-$(uname -r)`) omit internal security headers (`security/selinux/genheaders`, `include/objsec.h`, `flask.h`, `av_permissions.h`). Without them, compilation halts with:
   ```text
   fatal error: flask.h: No such file or directory
   ```
   The suite downloads the matching kernel source tree and builds the missing headers via `genheaders`.
2. **x86_64 Syscall Dispatcher Hardening:**
   On x86_64 Linux kernels, standard kprobe/ftrace hooks fail unless the dispatcher is dynamically patched at runtime using:
   ```bash
   CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y
   ```
3. **Unexported Kernel Symbols & Vermagic (`lkmloader`):**
   Using `KBUILD_MODPOST_WARN=1` produces `kernelsu.ko` with unresolved symbols. The specialized loader **[maxsteeel/lkmloader](https://github.com/maxsteeel/lkmloader)** reads `/proc/kallsyms`, dynamically resolves unexported symbols into the module's ELF table in memory, automatically adapts `vermagic` via `/dev/kmsg`, and calls `init_module()`.

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
│   ├── 04-build-ksu.sh          # Clones Official KernelSU (tiann/KernelSU) & builds kernelsu.ko
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

### Run on Ubuntu Host

```bash
# 1. Clone repository
git clone https://github.com/BloodCorrupt/ksulkmubuntu.git
cd ksulkmubuntu

# 2. Run the Full Automated Pipeline:
./ksu-suite.sh --all
```

*(Or simply run `./ksu-suite.sh` without arguments to launch the interactive menu).*

---

## ⚙️ Configuration (`config.env`)

You can select the target repository branch or release tag:

```bash
# Official Upstream KernelSU Repository & Branch
# "main" (latest) or a specific release tag such as "v3.1.0", "v3.3.1"
KSU_GIT_REPO="https://github.com/tiann/KernelSU.git"
KSU_GIT_BRANCH="main"
```

---

## 🔒 UEFI Secure Boot Notice

If UEFI Secure Boot is active on your host (e.g. ThinkStation P330 Tiny):
* The Linux kernel enters **Lockdown mode: integrity**, preventing `init_module()` from loading unsigned third-party modules.
* Pre-flight check (`01-check-env.sh`) detects and alerts you if Secure Boot is enabled.
* **Solution:** Enter UEFI/BIOS setup during boot (F1/F12 on ThinkStation) and disable Secure Boot.

---

## 📱 Manager APK Integration

Once `kernelsu.ko` is loaded into the host kernel:
1. Install the official **[KernelSU Manager APK](https://github.com/tiann/KernelSU/releases)** matching your version.
2. Open the Manager app inside your Android container (Redroid or Waydroid) to manage superuser access and modules!
