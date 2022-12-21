#!/bin/sh -e

OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_DL="https://downloads.cdn.openwrt.org"

OPENWRT_VER=22.03.2
FULL_TARGET=${1:-x86/64}

TARGET="$(echo "$FULL_TARGET" | cut -s -d/ -f1)"
SUBTARGET="$(echo "$FULL_TARGET" | cut -s -d/ -f2)"

[ -z "$TARGET" -o -z "$SUBTARGET" ] && {
  echo Invalid target \""$FULL_TARGET"\"
  exit 1
}

git clone --depth=1 -b v${OPENWRT_VER} ${OPENWRT_REPO} openwrt-${OPENWRT_VER}
cd openwrt-${OPENWRT_VER}

TARGET_URL="${OPENWRT_DL}/releases/${OPENWRT_VER}/targets/${TARGET}/${SUBTARGET}"
SHA256SUMS="$(wget -O - "${TARGET_URL}/sha256sums")"

TOOLCHAIN_STRING="$(echo "$SHA256SUMS" | grep ".*openwrt-toolchain.*tar.xz")"
TOOLCHAIN_FILE=$(echo "$TOOLCHAIN_STRING" | sed -n -e 's/.*\(openwrt-toolchain.*\).tar.xz/\1/p')
#TOOLCHAIN_SHA256=$(echo "$TOOLCHAIN_STRING" | cut -d ' ' -f 1)

LLVM_STRING="$(echo "$SHA256SUMS" | grep ".*llvm-bpf.*tar.xz")"
LLVM_FILE=$(echo "$LLVM_STRING" | sed -n -e 's/.*\(llvm-bpf.*.tar.xz\)/\1/p')

KERNEL_STRING="$(echo "$SHA256SUMS" | grep ".*packages/kernel.*ipk")"
KERNEL_VERMAGIC=$(echo "$KERNEL_STRING" | sed -n -e 's/.*kernel_[^-]*-[^-]*-\([^_]*\)_.*.ipk/\1/p')

echo Official kernel vermagic $KERNEL_VERMAGIC

wget -O - ${TARGET_URL}/${TOOLCHAIN_FILE}.tar.xz | tar --xz -xf -
wget -O - ${TARGET_URL}/${LLVM_FILE} | tar --xz -xf -

git apply ../openwrt-${OPENWRT_VER}-fullcone.patch

./scripts/feeds update -a

git -C feeds/luci apply "$(realpath -- ../luci-app-firewall-fullcone.patch)"

./scripts/feeds install -a

wget -O .config ${TARGET_URL}/config.buildinfo
sed -i 's/CONFIG_BPF_TOOLCHAIN_BUILD_LLVM/CONFIG_BPF_TOOLCHAIN_PREBUILT/g' .config

./scripts/ext-toolchain.sh \
  --toolchain ${TOOLCHAIN_FILE}/toolchain-* \
  --overwrite-config \
  --config ${TARGET}/${SUBTARGET}

make toolchain/install -j$(nproc)
make target/compile -j$(nproc)

CURR_VERMAGIC=$(cat build_dir/target-*/linux-*/linux-*/.vermagic)
[ "$CURR_VERMAGIC" = "$KERNEL_VERMAGIC" ] || {
  echo Current kernel vermagic not equal with OpenWrt official kernel
  exit 1
}

make package/linux/compile -j$(nproc)

make package/nft-fullcone/compile -j$(nproc)
make package/libnftnl/compile -j$(nproc)
make package/nftables/compile -j$(nproc)
make package/firewall4/compile -j$(nproc)
make package/luci-app-firewall/compile -j$(nproc)
