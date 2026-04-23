# Run USB Drive On QEMU GUI

A Zenity-driven Bash launcher for booting physical USB drives, raw disk dumps, or split boot/root images in QEMU with a cleaner desktop workflow.

## Quick Start

1. Install the required packages for your distro.
2. Make the launcher executable.
3. Run the script.
4. On first launch, confirm or enter the helper paths it asks for.

```bash
chmod +x run-usb-drive-on-qemu-gui.sh
./run-usb-drive-on-qemu-gui.sh
```

## What It Does

- boots a real USB drive or disk directly in QEMU
- boots a full raw disk image
- boots separate boot and root image files
- allows `virtio` or `ide` disk interface selection
- prepares OVMF UEFI variables automatically
- starts `virtiofsd` so the guest can access a shared host folder
- keeps the workflow GUI-driven instead of forcing a long manual QEMU command

## Main Files

- `run-usb-drive-on-qemu-gui.sh`
  - main launcher

## Runtime Dependencies

- `bash`
- `zenity`
- `qemu-system-x86_64`
- `virtiofsd`
- `lsblk`
- `edk2-ovmf`

Example package names on Arch Linux:

```bash
sudo pacman -S qemu-desktop qemu-system-x86 edk2-ovmf virtiofsd zenity
```

## Notes

- the user should be in the `disk` group to access block devices without switching to root
- the shared folder defaults to `$HOME/share`
- firmware and helper paths can be overridden with environment variables
- on first launch, the script will prompt for missing helper paths and save them in `~/.config/run-usb-drive-on-qemu-gui/config`
- image and block-device access can be destructive if the wrong target is selected, so verify the disk choice carefully before launching

## Environment Variables

- `RUNUSB_QEMU_SHARE_DIR`
  - host folder exported to the guest with `virtiofsd`
- `RUNUSB_QEMU_VIRTIOFSD`
  - path to the `virtiofsd` binary
- `RUNUSB_QEMU_OVMF_CODE`
  - path to the OVMF code firmware image
- `RUNUSB_QEMU_OVMF_VARS_TEMPLATE`
  - path to the OVMF vars template copied before launch
- `RUNUSB_QEMU_SPICE_PORT`
  - Spice port, default `5910`

## License

MIT
