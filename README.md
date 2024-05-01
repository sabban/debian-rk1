# debian-rk1

# Debian image builder script for turing rk1

## Prerequisites

To get a fully functional images one has to put debian image in the `packages` directory:
* linux image package
* linux header package
* u-boot package
* rockchip-firmware

Those can be build using scripts available at https://github.com/Joshua-Riek/ubuntu-rockchip or its ppa.

## Usage

sudo USER=user SSH_PUB_KEY_FILE=/home/user/.ssh/id_rsa.pub sh script.sh

To move data to nvme, there's a script `/usr/bin/nvme-install.sh`
