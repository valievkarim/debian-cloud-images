#!/bin/bash
# Build a Debian armhf cloud image on an amd64/arm64 host.
#
#   ./build-armhf-debian-image.sh [RELEASE]
#
# RELEASE defaults to bookworm; trixie, forky and sid also work.

set -o nounset
set -o errexit -o pipefail
set -o xtrace
trap 'trap - INT; kill -s INT "$$"' INT

RELEASE="${1:-bookworm}"

apt-get update

# apt-utils supplies apt-ftparchive, which hooks/repository.LOCALDEBS needs;
# without it the localdebs apt source is broken and the dist-upgrade in
# hooks/updatebase.BASE fails.
apt-get install --no-install-recommends -y \
  apt-utils binfmt-support ca-certificates debsums dosfstools \
  fai-server fai-setup-storage fdisk make python3 python3-httpx \
  python3-libcloud python3-marshmallow python3-pytest python3-yaml \
  qemu-user-static qemu-utils sudo udev

# armhf is a foreign architecture here, so debootstrap and the FAI chroot rely
# on transparent qemu-user emulation.  Check the kernel state directly rather
# than update-binfmts' own database: on a runner where the handler is already
# registered (out-of-band, or by an earlier job) 'update-binfmts --display'
# fails even though emulation works fine.
mountpoint -q /proc/sys/fs/binfmt_misc || mount -t binfmt_misc none /proc/sys/fs/binfmt_misc
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
  update-binfmts --enable qemu-arm
fi
cat /proc/sys/fs/binfmt_misc/qemu-arm
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-arm
# The F (fix-binary) flag opens the interpreter at registration time, which is
# what makes it reachable from inside the FAI chroot.
grep -qE '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-arm

make "image_${RELEASE}_generic_armhf"

qemu-img convert -p -c -f raw -O qcow2 \
  "image_${RELEASE}_generic_armhf.raw" \
  "image_${RELEASE}_generic_armhf.qcow2"
