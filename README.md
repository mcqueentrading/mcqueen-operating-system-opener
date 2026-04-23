# Run USB Drive On QEMU GUI

Zenity-based QEMU launcher for booting USB drives, raw disk images, and split boot/root images with a simpler desktop workflow.

## Project Page

For screenshots, the portfolio write-up, and the public project page:

https://tonimcqueen.com/project_runusbdriveonqemugui.html

## Overview

This project wraps a repetitive QEMU boot workflow in a guided Bash launcher.

Instead of rebuilding the same launch command by hand, the script lets you:

- boot a physical USB drive or disk directly in QEMU
- boot a full raw disk image
- boot separate boot and root image files
- choose `virtio` or `ide` depending on guest compatibility
- reuse saved helper paths for `virtiofsd` and OVMF firmware

The goal is not to hide QEMU. The goal is to remove repeated setup work while keeping the launch path understandable.

## Main File

- `run-usb-drive-on-qemu-gui.sh`

## Quick Start

```bash
chmod +x run-usb-drive-on-qemu-gui.sh
./run-usb-drive-on-qemu-gui.sh
```

## Dependencies

Required at runtime:

- `bash`
- `zenity`
- `qemu-system-x86_64`
- `virtiofsd`
- `lsblk`
- `edk2-ovmf`

Example package install on Arch Linux:

```bash
sudo pacman -S qemu-desktop qemu-system-x86 edk2-ovmf virtiofsd zenity
```

## First-Run Setup

On first launch, the script checks:

- shared host folder for `virtiofsd`
- `virtiofsd` binary path
- OVMF code firmware path
- OVMF vars template path

If any of them are missing, it prompts for them and saves the result to:

```text
~/.config/run-usb-drive-on-qemu-gui/config
```

Manual path entry uses a real terminal prompt so tab completion works.

## Environment Overrides

You can override the saved config with environment variables:

```text
RUNUSB_QEMU_SHARE_DIR
RUNUSB_QEMU_VIRTIOFSD
RUNUSB_QEMU_OVMF_CODE
RUNUSB_QEMU_OVMF_VARS_TEMPLATE
RUNUSB_QEMU_SPICE_PORT
```

## What The Launcher Does

Typical flow:

1. Validate local tools and helper paths.
2. Ask whether to boot a physical disk or image-based target.
3. Ask whether the guest should use `virtio` or `ide`.
4. Let the user choose the relevant disk or image files.
5. Prepare OVMF runtime vars.
6. Start `virtiofsd`.
7. Launch QEMU with the selected configuration.

## Notes

- The shared folder defaults to `$HOME/share`.
- The user should be in the `disk` group for physical block-device access.
- Selecting the wrong physical disk can be destructive. Verify the target carefully before launch.

## Repository Scope

This repo is intentionally narrow.

It contains the launcher and the minimal repo scaffolding needed to publish it cleanly. It does not try to package QEMU, OVMF, or `virtiofsd`.

## License

MIT
