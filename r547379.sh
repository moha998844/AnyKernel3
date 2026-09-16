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

  # In case any =m survived the merge, flip to =y for true monolithic —
  # EXCEPT the vendor driver families below, which ship duplicate/competing
  # implementations that only coexist as separate .ko files. Forcing these
  # to =y links two conflicting symbol sets into the same vmlinux.o:
  #   - GOODIX fingerprint: goodix_ta and goodix_tee both define gf_* /
  #     netlink_* symbols; only one is loaded per device at runtime.
  #   - QCACLD/CNSS/WLAN: the vendor WLAN driver's own nl80211 compat shim
  #     collides with net/wireless/nl80211.c when built in.
  #   - IPA: qcacld's IPA offload path and platform ipa_fmwk both define
  #     ipa_is_ready when built in.
  local CFG="${OUT}/.config"
  local KEEP_MODULAR_REGEX='CONFIG_.*(GOODIX|QCACLD|CNSS|WLAN|IPA).*'
  local m_count="$(grep -cE '=m$' "${CFG}" || true)"
  if [ "${m_count}" -gt 0 ]; then
    echo ">> flipping stragglers =m -> =y (excluding WLAN/fingerprint/IPA families)"
    grep -E '=m$' "${CFG}" | grep -vE "${KEEP_MODULAR_REGEX}" | cut -d= -f1 \
      | while read -r sym; do sed -i "s/^${sym}=m\$/${sym}=y/" "${CFG}"; done
    make "${BUILD_OPTIONS[@]}" olddefconfig
    # Second pass for any Kconfig deps that re-introduced =m, same exclusion
    grep -E '=m$' "${CFG}" | grep -vE "${KEEP_MODULAR_REGEX}" | cut -d= -f1 \
      | while read -r sym; do sed -i "s/^${sym}=m\$/${sym}=y/" "${CFG}"; done
    make "${BUILD_OPTIONS[@]}" olddefconfig
  fi

  local final_y=$(grep -c '=y$' "${CFG}")
  local final_m=$(grep -c '=m$' "${CFG}")
  echo ">> final: ${final_y} built-in, ${final_m} modules"
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

  local zipname="RED-vili-AOSP-$(date +%Y%m%d-%H%M).zip"

  rm -f "$zipname"

  zip -r "$zipname" * -x *.zip place-modules.sh mkdtboimg.py .gitignore .build-placeholder *.txt standard-vendor-load.txt anykernel-aosp.sh anykernel-miui.sh anykernel-aosp-tmp.sh bootlog.txt vendor_boot_stock_patched.img

  echo ">> Output: $zipname"
}


configure

[ "$BUILD" = 1 ] && (build_image && build_modules && modules_install)

[ "$ANYKERNEL" = 1 ] && make_anykernel


# Build command
# BUILD=1 ANYKERNEL=1 ./build.sh
