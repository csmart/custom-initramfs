This uses Busybox static binary from Fedora's RPM to create a simple initramfs.

```bash
$ ./create_initramfs.sh --help

	Usage: ./create_initramfs.sh --arch <string> [options]

	Required options:
	--arch <string>		architecture, e.g. aarch64, arm, ppc64, ppc64le, i386, x86_64

	Options:
	--dir <dir>		directory to use for building and output of initramfs
	--debug			enable set -x
	--noclean		don't clean the build directory (we clean by default)
	--noinit		don't use busybox init system, boot to /bin/sh instead
	--overlay <dir>		files to copy over top of initramfs filesystem
	--overlay-dst <dir>	dir to copy overlay files into on initramfs, defaults to /
	--printk		enable printk on console
	--tty <string>		the tty(s) to run getting on, defaults to "tty0 hvc0"
	--help			show this help message

	Short Options:
	-a <string>		Same as --arch
	-d <dir>		Same as --dir
	-o <dir>		Same as --overlay
	-O <dir>		Same as --overlay-dst
	-t <string>		Same as --tty
	-h			Same as --help
```
