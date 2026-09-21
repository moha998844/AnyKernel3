#!/bin/bash

set -e

# Set correct path
export PATH="\((realpath ../../clang-r547379/bin):\)PATH"

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
  # Injection automatique des correctifs de symboles faibles pour LTO avant la configuration
  if [ -f "drivers/staging/qcacld-3.0/components/ipa/dispatcher/src/wlan_ipa_obj_mgmt_api.c" ]; then
    sed -i 's/bool ipa_is_ready(void)/bool __attribute__((weak)) ipa_is_ready(void)/g' drivers/staging/qcacld-3.0/components/ipa/dispatcher/src/wlan_ipa_obj_mgmt_api.c
  fi
  if [ -f "drivers/staging/qca-wifi-host-cmn/utils/nlink/src/wlan_nlink_srv.c" ]; then
    sed -i 's/void \*nl80211hdr_put/void \*__attribute__((weak)) nl80211hdr_put/g' drivers/staging/qca-wifi-host-cmn/utils/nlink/src/wlan_nlink_srv.c
  fi

  make "${BUILD_OPTIONS[@]}" \
        vendor/lahaina-qgki_defconfig \
        vendor/debugfs.config \
        vendor/xiaomi_QGKI.config \
        vendor/vili_QGKI.config \
        vendor/change.config \
        vendor/ksu.config 
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

  cat "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina-v2.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahaina-v2.1.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahainap.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahainap-v2.dtb" \
      "${OUT}/arch/arm64/boot/dts/vendor/qcom/lahainap-v2.1.dtb" > dtb

  local zipname="lord-${ZIPPREFIX:-build}-anykernel.zip"

  rm -f "$zipname"

  zip -r "$zipname" * -x *.zip place-modules.sh mkdtboimg.py .gitignore .build-placeholder *.txt standard-vendor-load.txt anykernel-aosp.sh anykernel-miui.sh anykernel-aosp-tmp.sh bootlog.txt vendor_boot_stock_patched.img

  echo ">> Output: $zipname"
}

configure

[ "$BUILD" = 1 ] && (build_image && build_modules && modules_install)

[ "$ANYKERNEL" = 1 ] && make_anykernel
