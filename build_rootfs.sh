#!/usr/bin/env bash
set -euo pipefail
export WORKDIR=/work
export BR_DIR=${BR_DIR:-$WORKDIR/buildroot}
export BUILDROOT_TAG=${BUILDROOT_TAG:-2024.02.1}   # ví dụ; đổi nếu cần
export BOARD_DEFCONFIG=${BOARD_DEFCONFIG:-beaglebone_defconfig}
export OUTPUT_IMAGES_DIR="$BR_DIR/output/images"

cd $WORKDIR

# 1) clone buildroot nếu chưa có
if [ ! -d "$BR_DIR" ]; then
  git clone --depth 1 https://git.buildroot.net/buildroot $BR_DIR
  # nếu muốn tag cụ thể:
  if [ -n "$BUILDROOT_TAG" ]; then
    cd $BR_DIR
    git fetch --tags
    git checkout $BUILDROOT_TAG || true
  fi
fi

cd $BR_DIR

# 2) chọn defconfig (BeagleBone defconfig thường đã cấu hình tạo ext4)
make $BOARD_DEFCONFIG

# (nếu muốn đảm bảo ext4 ON, uncomment đoạn dưới để bật IN-CONFIG)
# sed -i 's/^# BR2_TARGET_ROOTFS_EXT4 is not set/BR2_TARGET_ROOTFS_EXT4=y/' .config || true
# make olddefconfig

# 3) build toàn bộ (toolchain + rootfs)
make -j$(nproc)

# 4) Kiểm tra xem Buildroot đã tạo rootfs.ext4 chưa
if [ -f "$OUTPUT_IMAGES_DIR/rootfs.ext4" ]; then
  echo "✅ Buildroot đã tạo rootfs.ext4 -> $OUTPUT_IMAGES_DIR/rootfs.ext4"
  cp "$OUTPUT_IMAGES_DIR/rootfs.ext4" "$WORKDIR/rootfs.ext4"
  exit 0
fi

# 5) Nếu không có file ext4, đóng gói manual từ output/target
TARGET_DIR="$BR_DIR/output/target"
IMG="$WORKDIR/rootfs.ext4"
IMG_SIZE_MB=${IMG_SIZE_MB:-128}   # tuỳ chỉnh

echo "Tạo ảnh ext4 thủ công: $IMG (${IMG_SIZE_MB}M)"
fallocate -l ${IMG_SIZE_MB}M $IMG || dd if=/dev/zero of=$IMG bs=1M count=${IMG_SIZE_MB}

# format ext4
sudo mkfs.ext4 -F $IMG

# mount, copy files (cần quyền root)
tmpmnt=$(mktemp -d)
sudo mount -o loop $IMG $tmpmnt
sudo rsync -aHAX --numeric-ids --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ $TARGET_DIR/ $tmpmnt/
# tạo device nodes nếu cần (Buildroot thường đã có dev)
# sync & unmount
sync
sudo umount $tmpmnt
rmdir $tmpmnt

echo "✅ Tạo xong rootfs.ext4 -> $IMG"
cp $IMG $WORKDIR/rootfs.ext4
