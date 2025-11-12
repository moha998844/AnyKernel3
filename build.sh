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
)

export KCFLAGS="-Wno-incompatible-function-pointer-types"

# This is required, audio will not work otherwise
export TARGET_PRODUCT=vili

configure() {
  make "${BUILD_OPTIONS[@]}" \
        vendor/lahaina-qgki_defconfig \
        vendor/debugfs.config \
        vendor/xiaomi_QGKI.config \
        vendor/vili_QGKI.config \
        lord.config
}

build_image() {
  make "${BUILD_OPTIONS[@]}"
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

  cp "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina-v2.1.dtb" dtb

  ./place-modules.sh "${OUT}/modules_install/lib/modules"/* modules/vendor/lib/modules "/vendor/lib/modules"

  find modules -name "*.ko" -exec llvm-strip --strip-unneeded -g {} \;

  rm -f "lord-$ZIPPREFIX-anykernel.zip"

  zip -r "lord-$ZIPPREFIX-anykernel.zip" * -x *anykernel.zip place-modules.sh mkdtboimg.py .gitignore .build-placeholder *.txt
}


if [ ! -e .build-placeholder ]; then
  echo "Be in anykernel dir"
  exit 1
fi

configure

[ "$BUILD" = 1 ] && (build_image && build_modules && modules_install)

[ "$ANYKERNEL" = 1 ] && make_anykernel


# Build command
# BUILD=1 ANYKERNEL=1 ZIPPREFIX=test ./build.sh
