FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /work

# Cài các dependency cần thiết để build Buildroot + thao tác ảnh ext4
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git cpio rsync \
    python3 python3-distutils \
    bc bison flex libncurses-dev \
    wget xz-utils unzip \
    device-tree-compiler u-boot-tools \
    qemu-utils qemu-system-arm \
    e2fsprogs genext2fs dosfstools parted curl \
    ca-certificates \
    git \
    sudo \
    file \
    && rm -rf /var/lib/apt/lists/*

# tạo user builder (không bắt buộc)
RUN useradd -m builder && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER builder
ENV HOME=/home/builder
WORKDIR /work

CMD ["bash"]
