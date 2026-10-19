#!/bin/bash
# Build a Debian armhf cloud image on an amd64/arm64 host.
#
#   ./build-armhf-debian-image.sh [RELEASE]
#
# RELEASE defaults to bookworm; trixie, forky and sid also work.
#
# Tested in Docker (needs privileged for loop devices, binfmt_misc and mounts,
# plus the host /dev so udev-created partition nodes are visible):
#
#   docker run --rm --privileged -v /dev:/dev \
#     -v "$PWD:/work" -w /work debian:trixie ./build-armhf-debian-image.sh bookworm

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
  # On trixie qemu-user ships systemd binfmt.d fragments instead of
  # update-binfmts definitions, and the systemd-binfmt helper may be missing
  # from a minimal container, so 'update-binfmts --enable qemu-arm' fails with
  # "not in database of installed binary formats".  Try each registration
  # method in turn, falling back to writing the kernel register interface
  # directly with the static interpreter.
  if [ -e /usr/share/binfmts/qemu-arm ] && update-binfmts --enable qemu-arm; then
    true
  elif [ -x /lib/systemd/systemd-binfmt ] && /lib/systemd/systemd-binfmt; then
    true
  elif [ -x /usr/lib/systemd/systemd-binfmt ] && /usr/lib/systemd/systemd-binfmt; then
    true
  elif command -v systemd-binfmt >/dev/null 2>&1 && systemd-binfmt; then
    true
  else
    # C opens the interpreter on behalf of the chroot credentials, F
    # (fix-binary) opens it at registration time so it stays reachable
    # inside the FAI chroot.
    printf '%s' ':qemu-arm:M::\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:CF' > /proc/sys/fs/binfmt_misc/register
  fi
fi
cat /proc/sys/fs/binfmt_misc/qemu-arm
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-arm
# The F (fix-binary) flag opens the interpreter at registration time, which is
# what makes it reachable from inside the FAI chroot.
grep -qE '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-arm

# official rather than the default dev type: dev adds TYPE_DEV, which enables
# passwordless root autologin on tty1 and the serial console.  Convenient for
# a throwaway VM, wrong for a board whose serial header is reachable.
make BUILD_TYPE="${BUILD_TYPE:-official}" "image_${RELEASE}_generic_armhf"

qemu-img convert -p -c -f raw -O qcow2 \
  "image_${RELEASE}_generic_armhf.raw" \
  "image_${RELEASE}_generic_armhf.qcow2"
