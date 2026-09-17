#!/bin/bash

set -e

# Set correct path
export PATH="$(realpath ../../clang-r547379/bin):$PATH"

export KROOT="$(realpath ../)"

export OUT="${KROOT}/out"

export BUILD_OPTIONS=(
    -C "${KROOT}"
    O="${OUT}"
    -j$(nproc --all)
    ARCH=arm64
    CC=clang
    CROSS_COMPILE=aarch64-linux-gnu-
    LLVM=1
    LLVM_IAS=1
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    STRIP=llvm-strip
    LOCALVERSION=""
)

export KCFLAGS="-Wno-incompatible-function-pointer-types -Wno-unused-function -Wno-error=unused-function"

export TARGET_PRODUCT=vili

configure() {
  make "${BUILD_OPTIONS[@]}" \
        vendor/lahaina-qgki_defconfig \
        vendor/debugfs.config \
        vendor/xiaomi_QGKI.config \
        vendor/vili_QGKI.config \
        vendor/change2.config
}

build_image() {
  make "${BUILD_OPTIONS[@]}" Image dtbs
}

build_modules() {
  make "${BUILD_OPTIONS[@]}" modules
}

modules_install() {
  rm -rf "${OUT}/modules_install"
  make "${BUILD_OPTIONS[@]}" modules_install INSTALL_MOD_PATH=modules_install
}


make_anykernel() {
  rm -rf {Image,dtb,dtb.img,dtbo.img,modules/vendor/lib/modules,modules/system/lib/modules}

  mkdir -p modules/{system,vendor}/lib/modules

  cp "${OUT}/arch/arm64/boot/Image" Image

  python mkdtboimg.py create dtbo.img --page_size=4096 "${OUT}/arch/arm64/boot/dts/vendor/qcom/vili-sm8350-overlay.dtbo"

  ./place-modules.sh "${OUT}/modules_install/lib/modules"/* modules/vendor/lib/modules "/vendor/lib/modules"

  find modules -name "*.ko" -exec llvm-strip --strip-unneeded -g {} \;

  # Concatenate every lahaina variant (v1, v2, v2.1, plus lahainap siblings)
  # into a single multi-DTB blob. Qcom's bootloader walks the concatenated
  # stream, matches on SoC/board ID from each DTB's root compatibility, and
  # picks the right one for the device. Shipping only one variant breaks
  # boot on ROMs that expect a different revision — Titanic does this too
  # (8 MB dtb with 17 fragments), ours was previously only 479 KB with one.
  cat "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina-v2.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina-v2.1.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahainap.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahainap-v2.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahainap-v2.1.dtb" > dtb

  local zipname="change2-$(date +%Y%m%d-%H%M).zip"

  rm -f "$zipname"

  zip -r "$zipname" * -x *.zip place-modules.sh mkdtboimg.py .gitignore .build-placeholder *.txt standard-vendor-load.txt anykernel-aosp.sh anykernel-miui.sh anykernel-aosp-tmp.sh bootlog.txt vendor_boot_stock_patched.img

  echo ">> Output: $zipname"
}


configure

[ "$BUILD" = 1 ] && (build_image && build_modules && modules_install)

[ "$ANYKERNEL" = 1 ] && make_anykernel


# Build command
# BUILD=1 ANYKERNEL=1 ./build.sh
