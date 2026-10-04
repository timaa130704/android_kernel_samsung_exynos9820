#!/usr/bin/env bash
#
# Non-interactive kernel build for CI. The in-repo build.sh is interactive
# (read -p prompts, hardcoded ~/Android/ToolChain path, gh release calls), so
# it cannot run unattended. This script does one device, one pass, no prompts.
#
# Usage:
#   ci/build-kernel.sh --device beyond1lte [--mode full|verify] [--slot 1|0]
#
# Modes:
#   verify  defconfig + modules_prepare + build ONLY drivers/kernelsu/
#           ~15 min / ~6 GB. Does not link the kernel, but it DOES run all of
#           ReSukiSU's Kbuild hook gates (inline_hook_check.mk), which is where
#           a 4.14 port actually breaks. Good enough for GitHub-hosted runners.
#   full    complete Image + AnyKernel3 zip. Needs ~40 GB free and hours of CPU.
#
# Toolchain resolution order:
#   1. $CLANG_DIR          - path to an already-extracted clang (self-hosted)
#   2. $CLANG_URL          - tarball to download and extract
#   3. clang already on PATH
#
set -euo pipefail

DEVICE=""
MODE="full"
SLOT="1"
OUT_BASE=""
AK3_REPO="${AK3_REPO:-https://github.com/Lordify97/AnyKernel.git}"

# clang 12 - same major version the tree's build.config.universal9820 asks for
# (CLANG_VERSION=clang-4691093, which AOSP has since pruned from its prebuilts).
DEFAULT_CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android13-release/clang-r450784d.tar.gz"

die() { echo "::error::$*" >&2; exit 1; }
step() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEVICE="$2"; shift 2 ;;
        --mode)   MODE="$2";   shift 2 ;;
        --slot)   SLOT="$2";   shift 2 ;;
        --out)    OUT_BASE="$2"; shift 2 ;;
        --toolchain-url) CLANG_URL="$2"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$DEVICE" ] || die "--device is required"
case "$DEVICE" in
    beyond0lte|beyond1lte|beyond2lte|beyondx|d1|d1x|d2s|d2x|f62) ;;
    *) die "unknown device '$DEVICE' (expected one of beyond0lte beyond1lte beyond2lte beyondx d1 d1x d2s d2x f62)" ;;
esac
case "$MODE" in full|verify) ;; *) die "--mode must be 'full' or 'verify'" ;; esac

KERNEL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_BASE="${OUT_BASE:-$KERNEL_DIR/out}"
OUT_DIR="$OUT_BASE/$DEVICE"
DEFCONFIG="exynos9820-${DEVICE}_defconfig"

[ -f "$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG" ] || die "no defconfig $DEFCONFIG"
[ -e "$KERNEL_DIR/drivers/kernelsu/Kbuild" ] || die "drivers/kernelsu is not populated - run: git submodule update --init --recursive"

# --------------------------------------------------------------------------
step "Environment"
# --------------------------------------------------------------------------
echo "kernel dir : $KERNEL_DIR"
echo "device     : $DEVICE ($DEFCONFIG)"
echo "mode       : $MODE"
echo "slot       : $SLOT"
echo "disk free  : $(df -BG1 "$KERNEL_DIR" | awk 'NR==2{print $4}')"

export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-ci}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github-actions}"

if [ -n "${CC:-}" ]; then
    echo "using caller CC=$CC"
elif command -v ccache >/dev/null 2>&1; then
    export CC="ccache clang"; export CXX="ccache clang++"
    echo "using ccache"
else
    export CC="clang"; export CXX="clang++"
fi

# --------------------------------------------------------------------------
step "Toolchain"
# --------------------------------------------------------------------------
CLANG_BIN=""
if [ -n "${CLANG_DIR:-}" ] && [ -x "$CLANG_DIR/bin/clang" ]; then
    CLANG_BIN="$CLANG_DIR/bin"
elif command -v clang >/dev/null 2>&1; then
    CLANG_BIN="$(dirname "$(command -v clang)")"
else
    URL="${CLANG_URL:-$DEFAULT_CLANG_URL}"
    CACHE="${TOOLCHAIN_CACHE:-$HOME/.cache/kernel-toolchain}"
    mkdir -p "$CACHE"
    if [ ! -x "$CACHE/clang/bin/clang" ]; then
        echo "downloading toolchain: $URL"
        curl -fSL --retry 3 -o "$CACHE/toolchain.tar.gz" "$URL" \
            || die "toolchain download failed. Override with --toolchain-url or set CLANG_DIR."
        rm -rf "$CACHE/clang"; mkdir -p "$CACHE/clang"
        tar -xzf "$CACHE/toolchain.tar.gz" -C "$CACHE/clang" \
            || die "toolchain extract failed"
        [ -x "$CACHE/clang/bin/clang" ] || die "archive did not contain bin/clang"
    fi
    CLANG_BIN="$CACHE/clang/bin"
fi
export PATH="$CLANG_BIN:$PATH"
echo "clang: $("$CLANG_BIN/clang" --version | head -1)"

# --------------------------------------------------------------------------
step "Configuring ($DEFCONFIG)"
# --------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
make -C "$KERNEL_DIR" O="$OUT_DIR" "$DEFCONFIG" LLVM=1
make -C "$KERNEL_DIR" O="$OUT_DIR" olddefconfig LLVM=1

# --------------------------------------------------------------------------
step "Checking the config actually kept the root solution"
# --------------------------------------------------------------------------
# A silently-dropped CONFIG_KSU_SUSFS means the choice fell back to the
# tracepoint hook, which cannot work on 4.14 - the build would then die in
# Kbuild with a much less obvious error. Fail here instead.
for sym in CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_THREAD_INFO_IN_TASK; do
    if grep -qx "${sym}=y" "$OUT_DIR/.config"; then
        echo "ok   $sym=y"
    else
        echo "MISSING $sym (value: $(grep -E "^${sym}=" "$OUT_DIR/.config" || echo '<unset>'))"
    fi
done
grep -qx 'CONFIG_KSU_SUSFS=y' "$OUT_DIR/.config" \
    || die "CONFIG_KSU_SUSFS was not kept. Check the defconfig and the ReSukiSU Kconfig dependencies (needs 64BIT + THREAD_INFO_IN_TASK)."

# --------------------------------------------------------------------------
if [ "$MODE" = "verify" ]; then
    step "Verify mode: preparing headers"
    make -C "$KERNEL_DIR" O="$OUT_DIR" modules_prepare LLVM=1

    step "Verify mode: compiling drivers/kernelsu/ only"
    # This is the whole point of verify mode: ReSukiSU's Kbuild runs
    # inline_hook_check.mk / susfs_compat.mk here and hard-errors on any
    # missing or leftover hook, before a single kernel .o is compiled.
    make -C "$KERNEL_DIR" O="$OUT_DIR" -j"$(nproc)" LLVM=1 drivers/kernelsu/
    echo "::notice::ReSukiSU compiled and all hook gates passed."
    exit 0
fi

# --------------------------------------------------------------------------
step "Building kernel (-j$(nproc))"
# --------------------------------------------------------------------------
make -C "$KERNEL_DIR" O="$OUT_DIR" -j"$(nproc)" LLVM=1

IMAGE="$OUT_DIR/arch/arm64/boot/Image"
[ -f "$IMAGE" ] || die "build finished but $IMAGE is missing"

# --------------------------------------------------------------------------
step "Packaging AnyKernel3"
# --------------------------------------------------------------------------
AK3="$KERNEL_DIR/AnyKernel"
if [ ! -d "$AK3" ]; then
    git clone --depth 1 "$AK3_REPO" "$AK3"
fi
rm -f "$AK3/Image"
cp "$IMAGE" "$AK3/Image"

KVER="$(sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"$/\1/p' "$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG")"
KVER="$(printf '%s' "$KVER" | grep -oE 'v[0-9]+(\.[0-9]+)*' || true)"
[ -n "$KVER" ] || KVER="custom"
RSUKU_VER="$(git -C "$KERNEL_DIR/KernelSU" describe --tags --always 2>/dev/null || echo unknown)"

KS="$AK3/anykernel.sh"
sed -i "s|^device\.name1=.*|device.name1=$DEVICE|" "$KS"
sed -i "s|^kernel\.string=.*|kernel.string=$KVER-ReSukiSu-$RSUKU_VER|" "$KS"
sed -i "s|^IS_SLOT_DEVICE=.*|IS_SLOT_DEVICE=$SLOT;|" "$KS"
sed -i "s|^supported\.versions=.*|supported.versions=14 - 16|" "$KS"

grep -E '^(device\.name1|kernel\.string|IS_SLOT_DEVICE|supported\.versions)=' "$KS"

ZIP_NAME="FrEeRuNnErKeRnEl-${DEVICE}-${KVER}-ReSukiSu-AnyKernel3.zip"
mkdir -p "$OUT_BASE/packages"
rm -f "$OUT_BASE/packages/$ZIP_NAME"
( cd "$AK3" && zip -r9 "$OUT_BASE/packages/$ZIP_NAME" * -x '.git/*' 'README.md*' >/dev/null )

echo "::notice::Built $ZIP_NAME"
echo "SZ=$(stat -c%s "$OUT_BASE/packages/$ZIP_NAME")"