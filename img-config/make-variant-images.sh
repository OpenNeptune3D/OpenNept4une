#!/usr/bin/env bash
# make-variant-images.sh: make the ZNP-K1 release images from ONE finished
# image, without rebuilding.
#
# The Armbian build variants (./run.sh n4|n4plus|n4-v1.4|n4plus-v2.3) only
# differ in fdtfile= in armbianEnv.txt: every image ships all ZNP-K1 DTBs.
# So build, configure and clean one image (dev-image-cleanup.sh), dump the
# eMMC, then run this on the dump to write a copy per target:
#
#   variant  (n4, n4plus, n4-v1.4, n4plus-v2.3): sets the DTB only. The model,
#            motor current, toolhead and probe are asked on first setup.
#   model    (e.g. N4Pro-1.2A-v1.1-tribbon): also writes that model line to
#            .OpenNept4une.txt, and the DTB that goes with its PCB version.
#            install_printer_cfg then builds the matching printer.cfg without
#            asking for the model (only the probe, if any, is still asked).
#
# Both files live on the FAT boot partition (partition 1), which is edited in
# place with mtools: no root, no mounting, the root filesystem is untouched.
#
# Runs on Linux and macOS (bash 3.2+, BSD or GNU tools). Run it with bash,
# not zsh: bash make-variant-images.sh ...
# Needs: mtools; xz with --xz.  macOS: brew install mtools xz
#
# Usage: make-variant-images.sh [--out-dir DIR] [--version VER] [--xz] [--force] IMAGE.img [TARGET...]

set -euo pipefail
export MTOOLS_SKIP_CHECK=1

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

# Must match config/boards/znp-k1.conf in Armbian-ZNP-K1-build.
VARIANTS="n4 n4plus n4-v1.4 n4plus-v2.3"
variant_dtb() {
  case "$1" in
    n4) echo rk3328-znp-k1-v1x.dtb ;;
    n4plus) echo rk3328-znp-k1-v2x.dtb ;;
    n4-v1.4) echo rk3328-znp-k1-n4-v1.4.dtb ;;
    n4plus-v2.3) echo rk3328-znp-k1-n4plus-n4max-v2.3.dtb ;;
    *) return 1 ;;
  esac
}
# PCB version (as asked by set-printer-model.sh) -> the release DTB for it.
# Keep in sync with set_board_dtb() in set-printer-model.sh.
pcb_dtb() {
  case "$1" in
    1.0|1.1) echo rk3328-znp-k1-v1x.dtb ;;
    1.4) echo rk3328-znp-k1-n4-v1.4.dtb ;;
    2.0) echo rk3328-znp-k1-v2x.dtb ;;
    2.3) echo rk3328-znp-k1-n4plus-n4max-v2.3.dtb ;;
  esac
}
model_name() {
  case "$1" in n4) echo N4 ;; n4pro) echo N4Pro ;; n4plus) echo N4Plus ;; n4max) echo N4Max ;; esac
}
# Release file names (without .img), as on the GitHub releases page.
variant_file() {
  case "$1" in
    n4) echo "Neptune4+Pro-$2-ZNP-K1-V1.x" ;;
    n4-v1.4) echo "Neptune4+Pro-$2-ZNP-K1-V1.4-USB-C" ;;
    n4plus) echo "Neptune4-Plus+Max-$2-ZNP-K1-V2.0" ;;
    n4plus-v2.3) echo "Neptune4-Plus+Max-$2-ZNP-K1-V2.3-USB-C" ;;
  esac
}
# Toolhead in a model-line file name: ribbon or USB-C.
toolhead_file() { if [[ "$1" == "usbc" ]]; then echo USB-C; else echo ribbon; fi; }
model_file_prefix() {
  case "$1" in n4) echo Neptune4 ;; n4pro) echo Neptune4-Pro ;; n4plus) echo Neptune4-Plus ;; n4max) echo Neptune4-Max ;; esac
}

usage() {
  cat <<'EOF'
Make the ZNP-K1 release images from one finished image (no rebuild).

Usage: bash make-variant-images.sh [options] IMAGE.img [TARGET...]

TARGET is a build variant or a model line; default: all four variants.
  Variants (DTB only, model asked on first setup):
    n4           Neptune 4 / 4 Pro, ZNP-K1 V1.x        rk3328-znp-k1-v1x.dtb
    n4plus       Neptune 4 Plus / Max, ZNP-K1 V2.0     rk3328-znp-k1-v2x.dtb
    n4-v1.4      Neptune 4 / 4 Pro, V1.4 (USB-C)       rk3328-znp-k1-n4-v1.4.dtb
    n4plus-v2.3  Neptune 4 Plus / Max, V2.3 (USB-C)    rk3328-znp-k1-n4plus-n4max-v2.3.dtb
  Model lines (preset .OpenNept4une.txt, DTB from the PCB version):
    N4-<0.8|1.2>A-v<1.0|1.1|1.4>-t<ribbon|usbc>       e.g. N4-1.2A-v1.1-tribbon
    N4Pro-<0.8|1.2>A-v<1.0|1.1|1.4>-t<ribbon|usbc>    e.g. N4Pro-0.8A-v1.4-tusbc
    N4Plus-v<2.0|2.3>-t<ribbon|usbc>                  e.g. N4Plus-v2.3-tusbc
    N4Max-v<2.0|2.3>-t<ribbon|usbc>

Output names (VER from the IMAGE name, e.g. OpenNept4une-v0.1.8.img -> v0.1.8):
    n4           Neptune4+Pro-VER-ZNP-K1-V1.x.img
    n4-v1.4      Neptune4+Pro-VER-ZNP-K1-V1.4-USB-C.img
    n4plus       Neptune4-Plus+Max-VER-ZNP-K1-V2.0.img
    n4plus-v2.3  Neptune4-Plus+Max-VER-ZNP-K1-V2.3-USB-C.img
    model line   e.g. Neptune4-Pro-VER-ZNP-K1-V1.1-1.2A-ribbon.img

Options:
  --out-dir DIR  Where to write the images (default: next to IMAGE).
  --version VER  Release version for the names (default: the vX.Y.Z in IMAGE).
  --xz           Compress each image with xz (the .img is replaced by .img.xz).
  --force        Overwrite existing output files.
  -h, --help     Show this help.

IMAGE must be an uncompressed .img (xz -dk IMAGE.img.xz first).
Needs mtools (macOS: brew install mtools xz).
EOF
}

die()  { printf '%b\n' "${R}ERROR: $*${NC}" >&2; exit 1; }
info() { printf '   %s\n' "$*"; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# Absolute path of a file whose directory exists (no GNU realpath -m on macOS).
abspath() { printf '%s/%s' "$(cd -- "$(dirname -- "$1")" && pwd -P)" "$(basename -- "$1")"; }
# Unsigned little-endian integer of N (4 or 8) bytes at OFFSET in FILE.
read_le() {
  od -An -v -t u1 -j "$2" -N "$3" -- "$1" | awk '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END { v = 0; for (i = n - 1; i >= 0; i--) v = v * 256 + b[i]; printf "%.0f\n", v }'
}
# Files macOS writes to a FAT volume as soon as it is mounted (the eMMC is
# usually plugged into a Mac to be imaged). Lists them on the image IMG@@OFF.
macos_junk() {
  mdir -/ -a -b -i "$1" :: 2>/dev/null | sed 's|/$||' \
    | grep -E '^::/(\.fseventsd|\.Spotlight-V100|\.Trashes|\.TemporaryItems)$|/\.DS_Store$|/\._[^/]*$' || true
}
strip_macos_junk() {
  local p
  macos_junk "$1" | while IFS= read -r p; do
    case "$p" in
      ::/.fseventsd/*|::/.Spotlight-V100/*|::/.Trashes/*|::/.TemporaryItems/*) ;;  # gone with its folder
      ::/.fseventsd|::/.Spotlight-V100|::/.Trashes|::/.TemporaryItems) mdeltree -i "$1" "$p" ;;
      *) mdel -i "$1" "$p" ;;
    esac
  done
}
# Copy without using extra disk where the filesystem allows it.
copy_image() {
  cp -c -- "$1" "$2" 2>/dev/null \
    || cp --reflink=auto --sparse=always -- "$1" "$2" 2>/dev/null \
    || cp -- "$1" "$2"
}

OUT_DIR=""
XZ="false"
FORCE="false"
IMAGE=""
VERSION=""
TARGETS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) [[ -n "${2:-}" ]] || die "--out-dir needs a directory"; OUT_DIR="$2"; shift ;;
    --out-dir=?*) OUT_DIR="${1#--out-dir=}" ;;
    --version) [[ -n "${2:-}" ]] || die "--version needs a value, e.g. v0.1.8"; VERSION="$2"; shift ;;
    --version=?*) VERSION="${1#--version=}" ;;
    --xz) XZ="true" ;;
    --force) FORCE="true" ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "Unknown option: $1" ;;
    *) if [[ -z "$IMAGE" ]]; then IMAGE="$1"; else TARGETS="$TARGETS $1"; fi ;;
  esac
  shift
done
[[ -n "$IMAGE" ]] || { usage >&2; exit 1; }
[[ -n "${TARGETS// /}" ]] || TARGETS="$VARIANTS"

for c in mcopy mtype mdir mdel mdeltree od awk; do
  command -v "$c" >/dev/null 2>&1 || die "$c not found (install mtools; macOS: brew install mtools)"
done
if [[ "$XZ" == "true" ]]; then command -v xz >/dev/null 2>&1 || die "xz not found"; fi
[[ "$IMAGE" != *.xz ]] || die "$IMAGE is compressed; run: xz -dk $IMAGE"
[[ -f "$IMAGE" ]] || die "$IMAGE not found"
OUT_DIR="${OUT_DIR:-$(dirname -- "$IMAGE")}"
mkdir -p -- "$OUT_DIR"
BASE="$(basename -- "$IMAGE")"; BASE="${BASE%.img}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(printf '%s\n' "$BASE" | grep -oE 'v[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
  [[ -n "$VERSION" ]] || die "No version (like v0.1.8) in '$BASE'; rename the image or pass --version v0.1.8"
fi
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || die "Bad --version '$VERSION'"
IMAGE_ABS="$(abspath "$IMAGE")"

# ------------------------------------------------------------------
# Resolve every target before writing anything: dtb, model line, file
# ------------------------------------------------------------------
PLAN=()   # "target|dtb|model line|output"
for t in $TARGETS; do
  lc="$(lower "$t")"
  flag=""
  if dtb="$(variant_dtb "$lc")"; then
    name="$(variant_file "$lc" "$VERSION")"
  elif [[ "$lc" =~ ^(n4|n4pro)-(0\.8|1\.2)a-v(1\.0|1\.1|1\.4)-t(ribbon|usbc)$ ]]; then
    flag="$(model_name "${BASH_REMATCH[1]}")-${BASH_REMATCH[2]}A-v${BASH_REMATCH[3]}-t${BASH_REMATCH[4]}"
    dtb="$(pcb_dtb "${BASH_REMATCH[3]}")"
    name="$(model_file_prefix "${BASH_REMATCH[1]}")-$VERSION-ZNP-K1-V${BASH_REMATCH[3]}-${BASH_REMATCH[2]}A-$(toolhead_file "${BASH_REMATCH[4]}")"
  elif [[ "$lc" =~ ^(n4plus|n4max)-v(2\.0|2\.3)-t(ribbon|usbc)$ ]]; then
    flag="$(model_name "${BASH_REMATCH[1]}")-v${BASH_REMATCH[2]}-t${BASH_REMATCH[3]}"
    dtb="$(pcb_dtb "${BASH_REMATCH[2]}")"
    name="$(model_file_prefix "${BASH_REMATCH[1]}")-$VERSION-ZNP-K1-V${BASH_REMATCH[2]}-$(toolhead_file "${BASH_REMATCH[3]}")"
  else
    die "Unknown target '$t'. See --help for variants and model lines."
  fi
  out="$OUT_DIR/$name.img"
  [[ "$(abspath "$out")" != "$IMAGE_ABS" ]] || die "Target '$t' would overwrite $IMAGE itself; use --out-dir"
  if [[ "$FORCE" != "true" ]]; then
    for f in "$out" "$out.xz"; do
      [[ ! -e "$f" ]] || die "$f exists (use --force to overwrite)"
    done
  fi
  PLAN+=("$t|$dtb|$flag|$out")
done

# ------------------------------------------------------------------
# Boot partition (partition 1) offset, from the MBR or GPT
# ------------------------------------------------------------------
[[ "$(read_le "$IMAGE" 510 2)" == "43605" ]] || die "$IMAGE has no partition table (no 55AA boot signature)"
if [[ "$(read_le "$IMAGE" 450 1)" == "238" ]]; then   # 0xEE: protective MBR, so GPT
  entries_lba="$(read_le "$IMAGE" $((512 + 72)) 8)"
  START="$(read_le "$IMAGE" $((entries_lba * 512 + 32)) 8)"
else
  START="$(read_le "$IMAGE" 454 4)"
fi
[[ "$START" =~ ^[0-9]+$ && "$START" -gt 0 ]] || die "Could not find partition 1 in $IMAGE"
OFFSET=$(( START * 512 ))
mdir -i "$IMAGE@@$OFFSET" ::/armbianEnv.txt >/dev/null 2>&1 \
  || die "No armbianEnv.txt on partition 1 of $IMAGE (not an Armbian ZNP-K1 image?)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/variant-images.XXXXXX")"
CURRENT_OUT=""
cleanup() {
  if [[ -n "$CURRENT_OUT" ]]; then rm -f -- "$CURRENT_OUT"; fi   # half-written image
  rm -rf -- "$TMP"
}
trap cleanup EXIT

printf '%b\n' "${C}Source: $IMAGE (boot partition at byte $OFFSET)${NC}"
printf '   now: %s\n' "$(mtype -i "$IMAGE@@$OFFSET" ::/armbianEnv.txt | grep '^fdtfile=' || echo 'no fdtfile=')"
if mdir -i "$IMAGE@@$OFFSET" ::/.OpenNept4une.txt >/dev/null 2>&1 \
   && mtype -i "$IMAGE@@$OFFSET" ::/.OpenNept4une.txt | grep -qiE '^n4|^probe='; then
  printf '%b\n' "   ${Y}Source has a model/probe line in .OpenNept4une.txt; it is removed from every copy.${NC}"
fi
if [[ -n "$(macos_junk "$IMAGE@@$OFFSET")" ]]; then
  printf '%b\n' "   ${Y}Boot partition has macOS files (Spotlight/fseventsd/._*); they are removed from every copy:${NC}"
  macos_junk "$IMAGE@@$OFFSET" | sed 's/^/     /'
fi

# ------------------------------------------------------------------
# Write each target
# ------------------------------------------------------------------
for p in "${PLAN[@]}"; do
  IFS='|' read -r t dtb flag out <<<"$p"
  img="$out@@$OFFSET"
  printf '\n%b\n' "${C}== $t -> $(basename -- "$out") ==${NC}"

  CURRENT_OUT="$out"
  rm -f -- "$out" "$out.xz"
  copy_image "$IMAGE" "$out"

  mdir -i "$img" "::/dtb/rockchip/$dtb" >/dev/null 2>&1 \
    || die "$dtb is not in this image's /boot/dtb/rockchip"
  strip_macos_junk "$img"

  # armbianEnv.txt: point fdtfile at this target's DTB
  mtype -i "$img" ::/armbianEnv.txt > "$TMP/env.in"
  grep -q '^fdtfile=' "$TMP/env.in" || die "armbianEnv.txt has no fdtfile= line"
  sed "s|^fdtfile=.*|fdtfile=rockchip/$dtb|" "$TMP/env.in" > "$TMP/armbianEnv.txt"
  mcopy -o -D o -i "$img" "$TMP/armbianEnv.txt" ::/armbianEnv.txt

  # .OpenNept4une.txt: drop any model/probe line, then add this target's model
  : > "$TMP/flag.in"
  if mdir -i "$img" ::/.OpenNept4une.txt >/dev/null 2>&1; then
    mtype -i "$img" ::/.OpenNept4une.txt > "$TMP/flag.in"
  fi
  grep -viE '^n4|^probe=' "$TMP/flag.in" > "$TMP/.OpenNept4une.txt" || true
  if [[ -n "$flag" ]]; then printf '%s\n' "$flag" >> "$TMP/.OpenNept4une.txt"; fi
  mcopy -o -D o -i "$img" "$TMP/.OpenNept4une.txt" ::/.OpenNept4une.txt

  # Read both back from the new image
  info "$(mtype -i "$img" ::/armbianEnv.txt | grep '^fdtfile=')"
  info "model: $(mtype -i "$img" ::/.OpenNept4une.txt | grep -iE '^n4' || echo '(asked on first setup)')"

  if [[ "$XZ" == "true" ]]; then
    info "compressing..."
    xz -T0 -f -- "$out"
    out="$out.xz"
  fi
  CURRENT_OUT=""
  printf '%b\n' "   ${G}$out${NC}"
done

printf '\n%b\n' "${G}Done. Test each image on its board (see ZNP-K1.md, \"Test on hardware\").${NC}"
