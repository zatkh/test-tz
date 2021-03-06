#!/bin/bash
BUILDPATH="$PWD/build"

sudo apt-get update
sudo apt-get install -y --force-yes \
    build-essential git android-tools-adb android-tools-fastboot autoconf \
	automake bc bison build-essential cscope curl device-tree-compiler \
	expect flex ftp-upload gdisk iasl libattr1-dev libc6:i386 libcap-dev \
	libfdt-dev libftdi-dev libglib2.0-dev libhidapi-dev libncurses5-dev \
	libpixman-1-dev libssl-dev libstdc++6:i386 libtool libz1:i386 make \
	mtools netcat python-crypto python-serial python-wand unzip uuid-dev \
	xdg-utils xterm xz-utils zlib1g-dev 

#get qemu
git clone --depth=1 https://github.com/qemu/qemu.git -b v2.12.0
#get edk2
git clone https://github.com/tianocore/edk2.git
cd edk2 && git checkout 1ea08a3dcdd61c7481ec78ad8b8037ee6ca45402
cd $BUILDPATH


make toolchains -j$(nproc)
#just to make sure there is no cached config file in the repo
make clean
make ta-targets=ta_arm64 run -j$(nproc)
# two opened terminals, one NW the other SW
# in the NW one type: root for login
# then type tests (or other examples in optee_example dir)
# check the results in the both terminals

