#!/bin/bash
# Disk Boot Helper via QEMU (Arch Linux / Hyprland)
# GUI + Auto-detect boot/root partitions + filesystem types + EFI preparation
# Supports: physical disks, full DD image dumps, separate boot+root image dumps

set -euo pipefail

APP_NAME="run-usb-drive-on-qemu-gui"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_DIR="$CONFIG_HOME/$APP_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
VIRTIOFSD_SOCK="/tmp/virtiofsd.sock"
SPICE_PORT="${RUNUSB_QEMU_SPICE_PORT:-5910}"

SHARE_DIR=""
VIRTIOFSD_BIN=""
OVMF_CODE=""
OVMF_VARS_TEMPLATE=""
VIRTIOFSD_PID=""
OVMF_VARS_RUNTIME=""

if ! command -v zenity &>/dev/null; then
    echo "Zenity is not installed. Install it with: sudo pacman -S zenity"
    exit 1
fi

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

SHARE_DIR="${RUNUSB_QEMU_SHARE_DIR:-${SHARE_DIR:-}}"
VIRTIOFSD_BIN="${RUNUSB_QEMU_VIRTIOFSD:-${VIRTIOFSD_BIN:-}}"
OVMF_CODE="${RUNUSB_QEMU_OVMF_CODE:-${OVMF_CODE:-}}"
OVMF_VARS_TEMPLATE="${RUNUSB_QEMU_OVMF_VARS_TEMPLATE:-${OVMF_VARS_TEMPLATE:-}}"

if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "qemu-system-x86_64 is not installed."
    exit 1
fi

prompt_path() {
    local title="$1"
    local prompt="$2"
    local current_value="$3"
    local must_be="file"
    local selected=""

    if [ "${4:-}" = "dir" ]; then
        must_be="dir"
    fi

    while true; do
        selected=$(zenity --entry \
            --title="$title" \
            --text="$prompt" \
            --entry-text="$current_value") || exit 1

        if [ -z "$selected" ]; then
            zenity --error --text="This field cannot be empty."
            continue
        fi

        if [ "$must_be" = "dir" ] && [ ! -d "$selected" ]; then
            zenity --error --text="Directory not found:\n$selected"
            continue
        fi

        if [ "$must_be" = "file" ] && [ ! -f "$selected" ]; then
            zenity --error --text="File not found:\n$selected"
            continue
        fi

        printf '%s\n' "$selected"
        return 0
    done
}

detect_default_file() {
    local candidate
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

detect_default_exec() {
    local candidate
    for candidate in "$@"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
SHARE_DIR=$(printf '%q' "$SHARE_DIR")
VIRTIOFSD_BIN=$(printf '%q' "$VIRTIOFSD_BIN")
OVMF_CODE=$(printf '%q' "$OVMF_CODE")
OVMF_VARS_TEMPLATE=$(printf '%q' "$OVMF_VARS_TEMPLATE")
EOF
}

cleanup() {
    if [ -n "$OVMF_VARS_RUNTIME" ] && [ -f "$OVMF_VARS_RUNTIME" ]; then
        rm -f "$OVMF_VARS_RUNTIME"
    fi

    if [ -n "$VIRTIOFSD_PID" ]; then
        kill "$VIRTIOFSD_PID" 2>/dev/null || true
    fi

    rm -f "$VIRTIOFSD_SOCK"
}

DEFAULT_SHARE_DIR="${HOME}/share"
DEFAULT_VIRTIOFSD="$(detect_default_exec /usr/lib/virtiofsd /usr/libexec/virtiofsd /usr/bin/virtiofsd 2>/dev/null || true)"
DEFAULT_OVMF_CODE="$(detect_default_file /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd 2>/dev/null || true)"
DEFAULT_OVMF_VARS="$(detect_default_file /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd 2>/dev/null || true)"

SHARE_DIR="${SHARE_DIR:-$DEFAULT_SHARE_DIR}"
VIRTIOFSD_BIN="${VIRTIOFSD_BIN:-$DEFAULT_VIRTIOFSD}"
OVMF_CODE="${OVMF_CODE:-$DEFAULT_OVMF_CODE}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-$DEFAULT_OVMF_VARS}"

if [ ! -d "$SHARE_DIR" ]; then
    SHARE_DIR=$(prompt_path \
        "Shared Folder" \
        "Enter the host directory to expose to the guest with virtiofsd.\n\nExample:\n$HOME/share" \
        "$SHARE_DIR" \
        "dir")
fi

if [ ! -x "${VIRTIOFSD_BIN:-/nonexistent}" ]; then
    VIRTIOFSD_BIN=$(prompt_path \
        "virtiofsd Path" \
        "Enter the full path to the virtiofsd binary.\n\nIf you do not know it, try this in a terminal:\nfind /usr -name virtiofsd 2>/dev/null" \
        "${VIRTIOFSD_BIN:-/usr/lib/virtiofsd}")
fi

if [ ! -f "${OVMF_CODE:-/nonexistent}" ]; then
    OVMF_CODE=$(prompt_path \
        "OVMF Code Firmware" \
        "Enter the full path to the OVMF code firmware file.\n\nIf you do not know it, try this in a terminal:\nfind /usr/share -name 'OVMF_CODE*.fd' 2>/dev/null" \
        "${OVMF_CODE:-/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd}")
fi

if [ ! -f "${OVMF_VARS_TEMPLATE:-/nonexistent}" ]; then
    OVMF_VARS_TEMPLATE=$(prompt_path \
        "OVMF Vars Template" \
        "Enter the full path to the OVMF vars template file.\n\nIf you do not know it, try this in a terminal:\nfind /usr/share -name 'OVMF_VARS*.fd' 2>/dev/null" \
        "${OVMF_VARS_TEMPLATE:-/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd}")
fi

save_config

if ! groups | grep -qw disk; then
    echo "Error: your user is not in the 'disk' group and cannot access block devices."
    echo "To fix this, run the following command then log out and back in:"
    echo ""
    echo "    sudo usermod -aG disk $USER"
    echo ""
    zenity --error --title="Permission Denied" \
        --text="Your user is not in the 'disk' group.

Run this command then log out and back in:

    sudo usermod -aG disk \$USER"
    exit 1
fi

DRIVE_IF=$(zenity --list \
    --title="Disk Interface" \
    --text="Which disk interface does your image support?\n\nIf unsure: try virtio first. If you get an empty /dev/ in emergency shell, use ide." \
    --column="Interface" --column="Use for" \
    "virtio"  "Arch Linux, Ubuntu 18+, most modern Linux" \
    "ide"     "Older Linux, unknown OS, or if virtio fails")

if [ -z "$DRIVE_IF" ]; then
    zenity --error --text="No interface selected. Exiting."
    exit 1
fi

BOOT_MODE=$(zenity --list \
    --title="Boot Source" \
    --text="What would you like to boot?" \
    --column="Mode" --column="Description" \
    "physical"  "Boot a physical disk or USB drive" \
    "image"     "Boot a DD image dump (.img, .iso, .dd, etc)")

if [ -z "$BOOT_MODE" ]; then
    zenity --error --text="No boot mode selected. Exiting."
    exit 1
fi

if [ "$BOOT_MODE" = "physical" ]; then
    mapfile -t PARTITIONS < <(lsblk -nlpo NAME,SIZE,FSTYPE,TYPE | awk '$4=="part"{print $1","$2","$3}')

    BOOT_PART_AUTO=$(lsblk -nlpo NAME,FSTYPE | awk '$2 ~ /vfat|fat32|efi/ {print $1}' | head -n1)
    ROOT_PART_AUTO=$(lsblk -nlpo NAME,FSTYPE | awk '$2 ~ /ext4|btrfs|xfs/ {print $1}' | head -n1)

    BOOT_LIST=()
    for part in "${PARTITIONS[@]}"; do
        IFS=',' read -r NAME SIZE FSTYPE <<< "$part"
        BOOT_LIST+=("$NAME" "$SIZE" "$FSTYPE")
    done

    BOOT_PART=$(zenity --list --title="Select Boot Partition" \
        --column="Partition" --column="Size" --column="Filesystem" "${BOOT_LIST[@]}" \
        --text="Auto-detected boot: $BOOT_PART_AUTO")
    if [ -z "$BOOT_PART" ]; then
        zenity --error --text="No boot partition selected. Exiting."
        exit 1
    fi

    ROOT_PART=$(zenity --list --title="Select Root Partition" \
        --column="Partition" --column="Size" --column="Filesystem" "${BOOT_LIST[@]}" \
        --text="Auto-detected root: $ROOT_PART_AUTO")
    if [ -z "$ROOT_PART" ]; then
        zenity --error --text="No root partition selected. Exiting."
        exit 1
    fi

    zenity --question --title="Confirm Partitions" \
      --text="Boot: $BOOT_PART\nRoot: $ROOT_PART\n\nContinue?"
    if [ $? -ne 0 ]; then
        zenity --info --text="Aborting."
        exit 1
    fi

    mapfile -t DISKS < <(lsblk -nlpo NAME,SIZE,TYPE | awk '$3=="disk"{print $1","$2}')
    DISK_LIST=()
    for disk in "${DISKS[@]}"; do
        IFS=',' read -r NAME SIZE <<< "$disk"
        DISK_LIST+=("$NAME" "$SIZE")
    done

    BOOT_DISK_AUTO="/dev/$(lsblk -no PKNAME "$ROOT_PART")"
    BOOT_DISK=$(zenity --list --title="Select Full Disk to Boot" \
        --column="Disk" --column="Size" "${DISK_LIST[@]}" \
        --text="Auto-detected disk: $BOOT_DISK_AUTO\nUEFI will be prepared on this disk")
    if [ -z "$BOOT_DISK" ]; then
        zenity --error --text="No disk selected. Exiting."
        exit 1
    fi

    QEMU_DRIVE_ARGS="-drive file=$BOOT_DISK,format=raw,if=$DRIVE_IF"
elif [ "$BOOT_MODE" = "image" ]; then
    IMAGE_TYPE=$(zenity --list \
        --title="Image Type" \
        --text="What type of image dump is this?" \
        --column="Type" --column="Description" \
        "full"      "Full disk dump - single image with all partitions" \
        "separate"  "Separate images - one for boot, one for root")

    if [ -z "$IMAGE_TYPE" ]; then
        zenity --error --text="No image type selected. Exiting."
        exit 1
    fi

    if [ "$IMAGE_TYPE" = "full" ]; then
        PICK_METHOD=$(zenity --list \
            --title="Select Image" \
            --text="How would you like to provide the image path?" \
            --column="Method" \
            "Browse for file" \
            "Type path manually")

        if [ "$PICK_METHOD" = "Browse for file" ]; then
            BOOT_DISK=$(zenity --file-selection \
                --title="Select Full Disk Image" \
                --file-filter="Disk Images | *.img *.iso *.dd *.raw *" )
        else
            BOOT_DISK=$(zenity --entry \
                --title="Image Path" \
                --text="Enter full path to image file:")
        fi

        if [ -z "$BOOT_DISK" ] || [ ! -f "$BOOT_DISK" ]; then
            zenity --error --text="Image file not found: $BOOT_DISK"
            exit 1
        fi

        QEMU_DRIVE_ARGS="-drive file=$BOOT_DISK,format=raw,if=$DRIVE_IF"
    elif [ "$IMAGE_TYPE" = "separate" ]; then
        PICK_METHOD=$(zenity --list \
            --title="Select Boot Image" \
            --text="How would you like to provide the BOOT image path?" \
            --column="Method" \
            "Browse for file" \
            "Type path manually")

        if [ "$PICK_METHOD" = "Browse for file" ]; then
            BOOT_IMG=$(zenity --file-selection \
                --title="Select Boot Partition Image" \
                --file-filter="Disk Images | *.img *.iso *.dd *.raw *")
        else
            BOOT_IMG=$(zenity --entry \
                --title="Boot Image Path" \
                --text="Enter full path to boot partition image:")
        fi

        if [ -z "$BOOT_IMG" ] || [ ! -f "$BOOT_IMG" ]; then
            zenity --error --text="Boot image not found: $BOOT_IMG"
            exit 1
        fi

        PICK_METHOD=$(zenity --list \
            --title="Select Root Image" \
            --text="How would you like to provide the ROOT image path?" \
            --column="Method" \
            "Browse for file" \
            "Type path manually")

        if [ "$PICK_METHOD" = "Browse for file" ]; then
            ROOT_IMG=$(zenity --file-selection \
                --title="Select Root Partition Image" \
                --file-filter="Disk Images | *.img *.iso *.dd *.raw *")
        else
            ROOT_IMG=$(zenity --entry \
                --title="Root Image Path" \
                --text="Enter full path to root partition image:")
        fi

        if [ -z "$ROOT_IMG" ] || [ ! -f "$ROOT_IMG" ]; then
            zenity --error --text="Root image not found: $ROOT_IMG"
            exit 1
        fi

        zenity --question --title="Confirm Images" \
            --text="Boot image: $BOOT_IMG\nRoot image: $ROOT_IMG\n\nContinue?"
        if [ $? -ne 0 ]; then
            zenity --info --text="Aborting."
            exit 1
        fi

        QEMU_DRIVE_ARGS="-drive file=$BOOT_IMG,format=raw,if=$DRIVE_IF \
  -drive file=$ROOT_IMG,format=raw,if=$DRIVE_IF"
    fi
fi

OVMF_VARS_RUNTIME="$(mktemp /tmp/OVMF_VARS.XXXXXX.fd)"
trap cleanup EXIT

zenity --info --text="Preparing UEFI variables..."
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_RUNTIME"
chmod 600 "$OVMF_VARS_RUNTIME"

zenity --info --text="Starting virtiofs daemon for $SHARE_DIR..."
rm -f "$VIRTIOFSD_SOCK"

"$VIRTIOFSD_BIN" \
    --socket-path="$VIRTIOFSD_SOCK" \
    --shared-dir="$SHARE_DIR" \
    --cache=auto &
VIRTIOFSD_PID=$!

sleep 1

if [ ! -S "$VIRTIOFSD_SOCK" ]; then
    zenity --error --text="virtiofsd failed to start.\nChecked path:\n$VIRTIOFSD_BIN"
    exit 1
fi

ROOT_DEV=$([ "$DRIVE_IF" = "virtio" ] && echo "/dev/vda" || echo "/dev/sda")
zenity --info \
    --title="GRUB Rescue Commands (if needed)" \
    --text="Interface: $DRIVE_IF — root device will be $ROOT_DEV\n\nIf QEMU drops to grub rescue>, type these 4 commands:\n\n    set root=(hd1)\n    set prefix=(hd1)/boot/grub\n    insmod normal\n    normal\n\nNote: use hd0 instead of hd1 if booting a full disk image.\n\nIf you land in emergency shell with UUID error, run:\n    mount '$ROOT_DEV' /sysroot\n    chroot /sysroot\n    sed -i 's#root=UUID=[^ ]*#root=$ROOT_DEV#' /boot/grub/grub.cfg\n    exit\n    reboot\n\nClick OK to launch QEMU."

echo "Launching QEMU..."
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 4 \
  -cpu host \
  -object memory-backend-memfd,id=mem,size=4G,share=on \
  -numa node,memdev=mem \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS_RUNTIME" \
  $QEMU_DRIVE_ARGS \
  -boot order=c \
  -vga virtio \
  -chardev socket,id=char0,path="$VIRTIOFSD_SOCK" \
  -device vhost-user-fs-pci,chardev=char0,tag=share \
  -device virtio-serial \
  -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 \
  -chardev spicevmc,id=spicechannel0,name=vdagent \
  -spice port="$SPICE_PORT",disable-ticketing=on \
  -device e1000,netdev=net0 \
  -netdev user,id=net0 \
  -display gtk,zoom-to-fit=on
