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
        vendor/vili_QGKI.config

  # In case any =m survived the merge, flip to =y for true monolithic.
  local CFG="${OUT}/.config"
  local m_count="$(grep -c '=m$' "${CFG}" || true)"
  if [ "${m_count}" -gt 0 ]; then
    echo ">> flipping ${m_count} stragglers =m → =y"
    sed -i 's/=m$/=y/' "${CFG}"
    make "${BUILD_OPTIONS[@]}" olddefconfig
    # Second pass for any Kconfig deps that re-introduced =m
    local m_after="$(grep -c '=m$' "${CFG}" || true)"
    if [ "${m_after}" -gt 0 ]; then
      sed -i 's/=m$/=y/' "${CFG}"
      make "${BUILD_OPTIONS[@]}" olddefconfig
    fi
  fi

  local final_y=$(grep -c '=y$' "${CFG}")
  local final_m=$(grep -c '=m$' "${CFG}")
  echo ">> final: ${final_y} built-in, ${final_m} modules"
}

build_image() {
  make "${BUILD_OPTIONS[@]}" Image dtbs
}


make_anykernel() {
  rm -rf {Image,dtb,dtb.img,dtbo.img,modules/vendor/lib/modules,modules/system/lib/modules}

  mkdir -p modules/{system,vendor}/lib/modules

  cp "${OUT}/arch/arm64/boot/Image" Image

  python mkdtboimg.py create dtbo.img --page_size=4096 "${OUT}/arch/arm64/boot/dts/vendor/qcom/vili-sm8350-overlay.dtbo"

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

  local zipname="RED-vili-AOSP-$(date +%Y%m%d-%H%M).zip"

  rm -f "$zipname"

  zip -r "$zipname" * -x *.zip place-modules.sh mkdtboimg.py .gitignore .build-placeholder *.txt standard-vendor-load.txt anykernel-aosp.sh anykernel-miui.sh anykernel-aosp-tmp.sh bootlog.txt vendor_boot_stock_patched.img

  echo ">> Output: $zipname"
}


configure

[ "$BUILD" = 1 ] && build_image

[ "$ANYKERNEL" = 1 ] && make_anykernel


# Build command
# BUILD=1 ANYKERNEL=1 ./build.sh
