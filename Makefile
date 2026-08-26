# path to the config space shoud be absolute, see fai.conf(5)

DESTDIR = .
# dev adds TYPE_DEV: root autologin on tty1 and serial, GRUB_TIMEOUT=5.
# Override with BUILD_TYPE=official for an image matching the published ones.
BUILD_TYPE = dev

help:
	@echo "To run this makefile, run:"
	@echo "   make image_<DIST>_<CLOUD>_<ARCH>"
	@echo "  WHERE <DIST> is bullseye, bookworm, trixie, sid"
	@echo "    And <CLOUD> is azure, ec2, gce, generic, genericcloud, nocloud"
	@echo "    And <ARCH> is amd64, arm64, armhf, ppc64el, riscv64, s390x"
	@echo "Set DESTDIR= to write images to given directory."

image_%:
	umask 022; \
	./bin/debian-cloud-images build \
	  $(subst _, ,$*) \
	  --build-id manual \
	  --build-type $(BUILD_TYPE) \
	  --version $(shell date '+%Y%m%d%H%M') \
	  --localdebs \
	  --output $(DESTDIR) \
	  --override-name $@

clean:
	rm -rf image_*.*
