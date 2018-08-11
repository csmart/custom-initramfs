#!/bin/bash

if grep -q debug <<< "$@"; then
	set -o xtrace
fi

set -o errexit
set -o pipefail
set -o nounset

#---------
# VARIABLES
#----------

# Defaults, can be overridden with env or args
ARCH=""
OVERLAY=""
OVERLAY_DST=""
INIT="true"
PRINTK="false"
TTY_DEV="hvc0 tty0"
CURPWD="$(pwd)"
DIR="/tmp/$(date +%-s%N)"
CACHE_DIR="${HOME}/.cache/initramfs"
CLEAN="true"
WGET="wget -q"
#URLs of scripts and files
rcS_url="https://raw.githubusercontent.com/buildroot/buildroot/master/package/initscripts/init.d/rcS"
rcK_url="https://raw.githubusercontent.com/buildroot/buildroot/master/package/initscripts/init.d/rcK"
network_url="https://raw.githubusercontent.com/buildroot/buildroot/master/package/ifupdown-scripts/S40network"
urandom_url="https://raw.githubusercontent.com/buildroot/buildroot/master/package/initscripts/init.d/S20urandom"
passwd_url="https://raw.githubusercontent.com/buildroot/buildroot/master/system/skeleton/etc/passwd"
shadow_url="https://raw.githubusercontent.com/buildroot/buildroot/master/system/skeleton/etc/shadow"
group_url="https://raw.githubusercontent.com/buildroot/buildroot/master/system/skeleton/etc/group"
fstab_url="https://raw.githubusercontent.com/buildroot/buildroot/76fc9275f14ec295b0125910464969bfa7441b85/package/skeleton-sysv/skeleton/etc/fstab"
inittab_url="https://raw.githubusercontent.com/buildroot/buildroot/master/package/busybox/inittab"

# Get the distro we're running on
ID=""
source /etc/os-release 2>/dev/null

#----------
# FUNCTIONS
#----------

# Print usage and quit
usage() {
	cat << EOF
	Usage: $0 --arch <string> [options]

	Required options:
	--arch <string>		architecture, e.g. arm, ppc64, ppc64le, i386, x86_64

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
EOF
	exit 1
}

#------------------------
# PARSE COMMAND LINE ARGS
#------------------------

CMD_LINE=$(getopt -o a:c:d:ht:o:O:i: --longoptions arch:,noclean,debug,dir:,help,printk,tty:,overlay:,overlay-dst:,noinit -n "$0" -- "$@")
eval set -- "${CMD_LINE}"

while true ; do
	case "${1}" in
		-a|--arch)
			ARCH="${2}"
			shift 2
			;;
		--noclean)
			CLEAN="false"
			shift
			;;
		--debug)
			set -x
			shift
			;;
		-d|--dir)
			DIR="${2}"
			shift 2
			;;
		-o|--overlay)
			OVERLAY="${2}"
			shift 2
			;;
		-o|--overlay-dst)
			OVERLAY_DST="${2}"
			shift 2
			;;
		--noinit)
			INIT="false"
			shift
			;;
		--printk)
			PRINTK="true"
			shift
			;;
		-t|--tty)
			TTY_DEV="${2}"
			shift 2
			;;
		-h|--help)
			usage
			;;
		--)
			shift
			break
			;;
		*)
			usage
			;;
	esac
done

[[ "$(type rpm2cpio 2>/dev/null)" ]] || { echo "Please install rpm2cpio" ; exit 1 ; }
[[ "$(type xz 2>/dev/null)" ]] || { echo "Please install xz" ; exit 1 ; }

# Get a busybox RPM from Fedora
if [[ "${ARCH}" == "ppc64" ]] ; then
	pkg=busybox-1.26.2-3.fc27.ppc64.rpm
	pkgurl=${pkgurl:-https://dl.fedoraproject.org/pub/fedora-secondary/releases/23/Everything/ppc64/os/Packages/b/}${pkg}
elif [[ "${ARCH}" == "ppc64le" ]] ; then
	pkg=busybox-1.26.2-3.fc27.ppc64le.rpm
	pkgurl=https://dl.fedoraproject.org/pub/fedora-secondary/releases/28/Everything/ppc64le/os/Packages/b/$pkg
elif [[ "${ARCH}" == "i386" ]] ; then
	pkg=busybox-1.22.1-4.fc23.i686.rpm
	pkgurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/23/Everything/i386/os/Packages/b/${pkg}
elif [[ "${ARCH}" == "x86_64" ]] ; then
	busybox-1.26.2-3.fc27.x86_64.rpm
	pkgurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/28/Everything/x86_64/os/Packages/b/${pkg}
elif [[ "${ARCH}" == "arm" ]] ; then
	pkg=busybox-1.26.2-3.fc27.armv7hl.rpm
	pkgurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/28/Everything/armhfp/os/Packages/b/${pkg}
else
	usage
fi

#-------------
# DO THE BUILD
#-------------

# Prepare work dir
mkdir -p "${DIR}" "${CACHE_DIR}" && cd "${DIR}"

echo "Downloading busybox..."
# Get pre-build static busybox from Fedora
${WGET} -c ${pkgurl} -O "${CACHE_DIR}/${pkg}" || { echo "Failed to download the busybox RPM" ; exit 1 ; }
cp "${CACHE_DIR}/${pkg}" .

# Extract rpm to get busybox binary
if [[ "${ID}" == "arch" ]]; then
	rpm2cpio ${pkg} |xv -d |cpio -idm 2>/dev/null
else
	rpm2cpio ${pkg} |cpio -idm 2>/dev/null
fi

# Create initramfs file structure
mkdir -p "${DIR}/initramfs/"{bin,dev,etc,proc,run,sbin,sys,tmp}
[[ "${INIT}" == "true" ]] && mkdir -p "${DIR}/initramfs/etc/init.d"

# Copy busybox into our initramfs
cp -a "${DIR}/sbin/busybox" "${DIR}/initramfs/bin/busybox"
chmod a+x "${DIR}/initramfs/bin/busybox"

# Create our base init script
cat > "${DIR}/initramfs/init" << EOF
#!/bin/busybox sh

# Create utils links to busybox
/bin/busybox --install -s /bin
/bin/busybox --install -s /sbin

# devfs required for getty
mount -t devtmpfs none /dev
EOF


# init needs to executable
chmod a+x "${DIR}/initramfs/init"

if [[ "${INIT}" == "false" ]]; then
	# No init system, so we need to set up a few more mounts
	echo "mount -t proc proc /proc" >> "${DIR}/initramfs/init"
	echo "mount -t sysfs sysfs /sys" >> "${DIR}/initramfs/init"
	if [[ "${PRINTK}" != "true" ]]; then
		{
			echo "# Silence kernel output"
			echo "echo 0 > /proc/sys/kernel/printk"
			echo "clear"
		} >> "${DIR}/initramfs/init"
	fi
	# Just execute a shell
	{
		echo "echo SYSTEM BOOTED ; /bin/sh"
		echo "umount -a 2>/dev/null"
		echo "poweroff -f"
	} >> "${DIR}/initramfs/init"
else
	# Run busybox instead of sh as init
	echo 'exec /bin/init $*' >> "${DIR}/initramfs/init"

	echo "Downloading init scripts..."
	# Get our init start script
	${WGET} ${rcS_url} -O "${DIR}/initramfs/etc/init.d/rcS" || { echo "Failed to download the system scripts" ; exit 1 ; }
	chmod a+x "${DIR}/initramfs/etc/init.d/rcS"

	# Get our init kill sript
	${WGET} ${rcK_url} -O "${DIR}/initramfs/etc/init.d/rcK" || { echo "Failed to download the system scripts" ; exit 1 ; }
	chmod a+x "${DIR}/initramfs/etc/init.d/rcK"

	# Get basic startup files
	${WGET} ${network_url} -O "${DIR}/initramfs/etc/init.d/S40network" || { echo "Failed to download the system scripts" ; exit 1 ; }
	mkdir -p "${DIR}/initramfs/etc/network"
	touch "${DIR}/initramfs/etc/network/interfaces"
	${WGET} ${urandom_url} -O "${DIR}/initramfs/etc/init.d/S20urandom" || { echo "Failed to download the system scripts" ; exit 1 ; }

	# Disable printk
	if [[ "${PRINTK}" != "true" ]] ; then
		cat > "${DIR}/initramfs/etc/init.d/S10printk" << \EOF
		#!/bin/sh

		case "$1" in
			start|"")
				echo 0 > /proc/sys/kernel/printk
				clear
				;;
		esac
EOF
	fi
	chmod a+x "${DIR}/initramfs/etc/init.d/"*

	# Get busybox inittab
	${WGET} ${inittab_url} -O "${DIR}/initramfs/etc/inittab" || { echo "Failed to download the system scripts" ; exit 1 ; }
	for tty in $(echo "${TTY_DEV}" | tr ' ' '\n' |sort |uniq); do
		echo "${tty}::respawn:/sbin/getty -L ${tty} 115200 vt100" >> "${DIR}/initramfs/etc/inittab"
	done

	# Get basic passwd and shadow files
	echo "Downloading system files..."
	${WGET} ${passwd_url} -O "${DIR}/initramfs/etc/passwd" || { echo "Failed to download the system scripts" ; exit 1 ; }
	${WGET} ${shadow_url} -O "${DIR}/initramfs/etc/shadow" || { echo "Failed to download the system scripts" ; exit 1 ; }
	${WGET} ${group_url} -O "${DIR}/initramfs/etc/group" || { echo "Failed to download the system scripts" ; exit 1 ; }
	${WGET} ${fstab_url} -O "${DIR}/initramfs/etc/fstab" || { echo "Failed to download the system scripts" ; exit 1 ; }

	# set a hostname based on ARCH
	echo "${ARCH}" > "${DIR}/initramfs/etc/hostname"
fi

# Copy over anything from overlay into initramfs
if [[ "${OVERLAY}" != "" ]]; then
	if [[ -d "${OVERLAY}" ]]; then
		echo "Copying in files from ${OVERLAY}"
		mkdir -p "${DIR}/initramfs/${OVERLAY_DST}"
		cp -a "${OVERLAY}/." "${DIR}/initramfs/${OVERLAY_DST}/"
	else
		echo "Your specified overlay directory doesn't seem to be correct, skipping."
	fi
fi

# Create initramfs image
echo "Creating initramfs..."
cd "${DIR}/initramfs"
find . | cpio -H newc -o > "${DIR}/initramfs-${ARCH}.cpio" 2>/dev/null
gzip -qf "${DIR}/initramfs-${ARCH}.cpio"
cd "${CURPWD}"

# Clean if we're meant to
[[ "${CLEAN}" == "true" ]] && rm -Rf "${DIR:?}"/{initramfs,busybox*rpm,usr,sbin}


# Notify of completion
echo -e "\nCreated initramfs at ${DIR}/initramfs-${ARCH}.cpio.gz\n"
