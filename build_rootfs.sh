#!/usr/bin/env bash
set -euo pipefail
# Tăng thời gian chờ và cấp thêm quyền sudo cho CI để tránh lỗi
export WORKDIR=/work
export BUILDROOT_TAG=${BUILDROOT_TAG:-2024.02.1} # Change if needed
export BOARD_DEFCONFIG=${BOARD_DEFCONFIG:-beaglebone_defconfig}

# Định nghĩa tên thư mục và file tải về
export BR_TARBALL="buildroot-$BUILDROOT_TAG.tar.gz"
export BR_URL="https://buildroot.net/downloads/$BR_TARBALL"

# Thư mục gốc Buildroot sẽ là /work/buildroot-2024.02.1 (sau khi giải nén)
# Ta sẽ đặt BR_DIR bằng tên thư mục sau giải nén để đảm bảo chính xác
export BR_DIR="$WORKDIR/buildroot-$BUILDROOT_TAG" 
export OUTPUT_IMAGES_DIR="$BR_DIR/output/images"

cd $WORKDIR

# --- FIX: VOLUME PERMISSION DENIED ---
# Cấp quyền sở hữu thư mục làm việc cho user đang thực thi script để cho phép wget/tar ghi file.
export CURRENT_USER_ID=$(id -u)
export CURRENT_GROUP_ID=$(id -g)
echo "Fixing permissions for mounted volume. Current UID: $CURRENT_USER_ID, GID: $CURRENT_GROUP_ID"
# Thay đổi quyền sở hữu thư mục mount cho người dùng hiện tại
sudo chown -R $CURRENT_USER_ID:$CURRENT_GROUP_ID $WORKDIR || true 
# Dùng chmod 777 như biện pháp dự phòng để đảm bảo quyền ghi
sudo chmod -R 777 $WORKDIR || true 
# -------------------------------------

# 1) Tải và giải nén Buildroot nếu chưa có
if [ ! -d "$BR_DIR" ]; then
  echo "Tải Buildroot $BUILDROOT_TAG từ $BR_URL..."
  # Cần curl hoặc wget trong Dockerfile! (Giả định đã có)
  wget "$BR_URL" -O "$BR_TARBALL"
  
  echo "Giải nén..."
  tar xvf "$BR_TARBALL"
  
  # Đổi tên thư mục giải nén để khớp với BR_DIR nếu cần
  if [ ! -d "$BR_DIR" ]; then
    echo "Lỗi giải nén: Không tìm thấy thư mục $BR_DIR"
    exit 1
  fi
  
  rm -f "$BR_TARBALL"
fi

# CHUYỂN VÀO THƯ MỤC GỐC BUILDROOT ĐỂ CHẠY MAKE
echo "Changing directory to Buildroot root: $BR_DIR"
cd $BR_DIR

# --- DEBUG STEP: Verify content and location ---
echo "--- DEBUG: Current location and contents before make ---"
pwd
# Lệnh này phải hiển thị Makefile và configs/
ls -F | head -n 10
echo "--- END DEBUG ---"
# -----------------------------------------------

# 2) chọn defconfig (make sẽ tự động tìm file trong configs/)
echo "Cấu hình Buildroot với $BOARD_DEFCONFIG..."
make $BOARD_DEFCONFIG

# (Các bước cấu hình tùy chọn khác...)

# 3) build toàn bộ (toolchain + rootfs)
echo "Starting build with $(nproc) threads..."
make -j$(nproc)

# 4) Kiểm tra và sao chép rootfs.ext4
if [ -f "$OUTPUT_IMAGES_DIR/rootfs.ext4" ]; then
  echo "✅ Buildroot generated rootfs.ext4 -> $OUTPUT_IMAGES_DIR/rootfs.ext4"
  cp "$OUTPUT_IMAGES_DIR/rootfs.ext4" "$WORKDIR/rootfs.ext4"
  exit 0
fi

# 5) Nếu không có file ext4, đóng gói manual từ output/target (Giữ nguyên)
TARGET_DIR="$BR_DIR/output/target"
IMG="$WORKDIR/rootfs.ext4"
IMG_SIZE_MB=${IMG_SIZE_MB:-128}  # tuỳ chỉnh

echo "Tạo ảnh ext4 thủ công: $IMG (${IMG_SIZE_MB}M)"
fallocate -l ${IMG_SIZE_MB}M $IMG || dd if=/dev/zero of=$IMG bs=1M count=${IMG_SIZE_MB}

# format ext4
sudo mkfs.ext4 -F $IMG

# mount, copy files (cần quyền root)
tmpmnt=$(mktemp -d)
sudo mount -o loop $IMG $tmpmnt
sudo rsync -aHAX --numeric-ids --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ $TARGET_DIR/ $tmpmnt/
# sync & unmount
sync
sudo umount $tmpmnt
rmdir $tmpmnt

echo "✅ Tạo xong rootfs.ext4 -> $IMG"
cp $IMG "$WORKDIR/rootfs.ext4"
