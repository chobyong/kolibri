#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
#  HIM Education — Build Bootable Debian 13 ISO with preseed baked in
#
#  Usage:
#    sudo bash build-iso.sh                 # build ISO only
#    sudo bash build-iso.sh /dev/sdb        # build + write to USB
#
#  Requirements:
#    apt-get install xorriso isolinux syslinux-utils cpio gzip
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_ISO="${SCRIPT_DIR}/debian-base.iso"
PRESEED="${SCRIPT_DIR}/preseed.cfg"
PROVISION="${SCRIPT_DIR}/provision.sh"
OUT_ISO="${SCRIPT_DIR}/him-edu-debian13.iso"
BUILD_DIR="/tmp/him-iso-build"
WORK_DIR="${BUILD_DIR}/iso-work"
TARGET_DEV="${1:-}"

log()  { echo -e "\n\033[1;34m[ISO]\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  err "Run as root: sudo bash build-iso.sh [/dev/sdX]"
  exit 1
fi

[ -f "$BASE_ISO" ] || { err "Base ISO not found: $BASE_ISO"; exit 1; }
[ -f "$PRESEED"  ] || { err "preseed.cfg not found: $PRESEED";  exit 1; }

# Install tools if needed
for pkg in xorriso isolinux syslinux-utils cpio gzip; do
  dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || apt-get install -y "$pkg"
done

log "Preparing build directory..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# ─── Extract ISO ─────────────────────────────────────────────────────────────
log "Extracting base ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$WORK_DIR" 2>/dev/null
chmod -R u+w "$WORK_DIR"
ok "ISO extracted to $WORK_DIR"

# ─── Bake preseed into initrd ─────────────────────────────────────────────────
log "Baking preseed.cfg into initrd..."

INITRD_PATH=""
for candidate in \
    "$WORK_DIR/install.amd/initrd.gz" \
    "$WORK_DIR/install/initrd.gz" \
    "$WORK_DIR/d-i/initrd.gz"; do
  [ -f "$candidate" ] && INITRD_PATH="$candidate" && break
done

[ -z "$INITRD_PATH" ] && { err "initrd.gz not found in ISO"; exit 1; }
ok "Found initrd at: $INITRD_PATH"

INITRD_DIR=$(dirname "$INITRD_PATH")
INITRD_WORK="${BUILD_DIR}/initrd-work"
rm -rf "$INITRD_WORK"
mkdir -p "$INITRD_WORK"

# Extract initrd (may be gzip or uncompressed cpio)
cd "$INITRD_WORK"
if file "$INITRD_PATH" | grep -q "gzip"; then
  gunzip -c "$INITRD_PATH" | cpio -id --quiet 2>/dev/null
else
  cpio -id --quiet < "$INITRD_PATH" 2>/dev/null
fi
ok "initrd extracted"

# Inject preseed.cfg at root of initrd (Debian installer auto-finds it here)
cp "$PRESEED" "$INITRD_WORK/preseed.cfg"

# Also inject provision.sh so the late_command can copy it
if [ -f "$PROVISION" ]; then
  cp "$PROVISION" "$INITRD_WORK/provision.sh"
  chmod +x "$INITRD_WORK/provision.sh"
  ok "provision.sh injected into initrd"
fi
ok "preseed.cfg injected into initrd"

# Repack initrd
log "Repacking initrd..."
find . | cpio -o -H newc --quiet | gzip -9 > "$INITRD_PATH"
cd - > /dev/null
ok "initrd repacked"

# ─── Patch boot config to auto-load preseed ──────────────────────────────────
log "Patching boot loader configuration..."

# Common preseed kernel parameters
PRESEED_PARAMS="auto=true priority=critical preseed/file=/preseed.cfg"

# GRUB (EFI) — grub.cfg
GRUBCFG=""
for g in \
    "$WORK_DIR/boot/grub/grub.cfg" \
    "$WORK_DIR/EFI/boot/grub.cfg"; do
  [ -f "$g" ] && GRUBCFG="$g" && break
done

if [ -n "$GRUBCFG" ]; then
  # Backup
  cp "$GRUBCFG" "${GRUBCFG}.orig"
  # Reduce timeout to 5s, set default to first entry
  sed -i 's/^set timeout=.*/set timeout=5/' "$GRUBCFG" || true
  sed -i 's/^set default=.*/set default=0/' "$GRUBCFG" || true
  # Inject preseed params into all linux/linuxefi lines (after the kernel path)
  sed -i "s|\(linux[[:space:]]\+\)\([^ ]*\)|\1\2 ${PRESEED_PARAMS}|g" "$GRUBCFG" || true
  ok "grub.cfg patched: $GRUBCFG"
fi

# ISOLINUX (BIOS) — txt.cfg / isolinux.cfg
for ISOCFG in \
    "$WORK_DIR/isolinux/txt.cfg" \
    "$WORK_DIR/isolinux/isolinux.cfg" \
    "$WORK_DIR/isolinux/adgtk.cfg"; do
  [ -f "$ISOCFG" ] || continue
  cp "$ISOCFG" "${ISOCFG}.orig"
  sed -i "s|append |append ${PRESEED_PARAMS} |g" "$ISOCFG"
  ok "isolinux cfg patched: $ISOCFG"
done

# ─── Get original ISO metadata for xorriso ───────────────────────────────────
log "Reading ISO metadata..."
VOLID=$(xorriso -indev "$BASE_ISO" -report_system_area plain 2>/dev/null \
  | grep "Volume id" | sed "s/.*: '\(.*\)'/\1/" || echo "HIM-EDU-DEBIAN13")

MBR_FILE="${BUILD_DIR}/mbr.img"
EFI_IMG="${BUILD_DIR}/efi.img"

# Extract MBR and EFI images from the original ISO for hybrid boot
xorriso -indev "$BASE_ISO" \
  -boot_image any show_status 2>&1 | grep -q "appended" && \
  dd if="$BASE_ISO" bs=1 count=432 of="$MBR_FILE" 2>/dev/null || \
  cp /usr/lib/ISOLINUX/isohdpfx.bin "$MBR_FILE" 2>/dev/null || \
  cp /usr/lib/syslinux/mbr/isohdpfx.bin "$MBR_FILE" 2>/dev/null || \
  true

# ─── Build new ISO ────────────────────────────────────────────────────────────
log "Building new ISO: $OUT_ISO"

# Find isolinux bin and cat files
ISOLINUX_BIN=""
BOOT_CAT=""
for b in "$WORK_DIR/isolinux/isolinux.bin"; do
  [ -f "$b" ] && ISOLINUX_BIN="$b" && break
done
for c in "$WORK_DIR/isolinux/boot.cat" "$WORK_DIR/boot.cat"; do
  [ -f "$c" ] && BOOT_CAT="$c" && break
done

# Find EFI boot image
EFI_BOOT=""
for e in \
    "$WORK_DIR/boot/grub/efi.img" \
    "$WORK_DIR/EFI/boot/bootx64.efi"; do
  [ -f "$e" ] && EFI_BOOT="$e" && break
done

XORRISO_ARGS=(
  xorriso -as mkisofs
  -quiet
  -r
  -J
  --joliet-long
  -V "HIM-EDU-DEBIAN13"
  -o "$OUT_ISO"
)

# BIOS boot (isolinux)
if [ -n "$ISOLINUX_BIN" ]; then
  ISO_REL_ISOLINUX="${ISOLINUX_BIN#${WORK_DIR}/}"
  ISO_REL_BOOTCAT="${BOOT_CAT#${WORK_DIR}/}"
  XORRISO_ARGS+=(
    -b "$ISO_REL_ISOLINUX"
    -c "$ISO_REL_BOOTCAT"
    -no-emul-boot
    -boot-load-size 4
    -boot-info-table
  )
fi

# EFI boot (grub)
if [ -f "$WORK_DIR/boot/grub/efi.img" ]; then
  XORRISO_ARGS+=(
    -eltorito-alt-boot
    -e "boot/grub/efi.img"
    -no-emul-boot
    -isohybrid-gpt-basdat
  )
elif [ -f "$WORK_DIR/EFI/boot/bootx64.efi" ]; then
  XORRISO_ARGS+=(
    -eltorito-alt-boot
    -e "EFI/boot/bootx64.efi"
    -no-emul-boot
  )
fi

# MBR for USB hybrid boot
if [ -f "$MBR_FILE" ]; then
  XORRISO_ARGS+=( -isohybrid-mbr "$MBR_FILE" )
fi

XORRISO_ARGS+=( "$WORK_DIR" )

"${XORRISO_ARGS[@]}"
ok "ISO built: $OUT_ISO ($(du -sh "$OUT_ISO" | cut -f1))"

# ─── Write to USB (optional) ──────────────────────────────────────────────────
if [ -n "$TARGET_DEV" ]; then
  log "Writing ISO to $TARGET_DEV ..."

  # Safety checks
  if [ ! -b "$TARGET_DEV" ]; then
    err "$TARGET_DEV is not a block device"
    exit 1
  fi

  # Confirm it's not a system disk
  ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
  ROOT_DISK="/dev/${ROOT_DISK}"
  if [ "$TARGET_DEV" = "$ROOT_DISK" ] || [ "$TARGET_DEV" = "/dev/sda" ]; then
    err "Refusing to write to system disk $TARGET_DEV !"
    exit 1
  fi

  # Unmount any partitions on target
  lsblk -lno NAME "$TARGET_DEV" | tail -n +2 | while read -r part; do
    umount "/dev/$part" 2>/dev/null || true
  done

  ISO_SIZE=$(stat -c%s "$OUT_ISO")
  ISO_MB=$(( ISO_SIZE / 1024 / 1024 ))
  log "Writing ${ISO_MB} MB to $TARGET_DEV (this may take a few minutes)..."
  dd if="$OUT_ISO" of="$TARGET_DEV" bs=4M status=progress oflag=sync
  sync
  ok "Written to $TARGET_DEV"
  log "USB is ready. Boot target machine from $TARGET_DEV."
  log "Install will run automatically — no keyboard input required."
  log "First-boot provisioning runs via him-provision.service."
else
  log "ISO ready: $OUT_ISO"
  log "To write to USB:  sudo dd if=$OUT_ISO of=/dev/sdX bs=4M status=progress oflag=sync"
fi

echo ""
echo "========================================="
echo "  HIM Education ISO Build Complete"
echo "  Output: $OUT_ISO"
[ -n "$TARGET_DEV" ] && echo "  Written to: $TARGET_DEV"
echo "========================================="
