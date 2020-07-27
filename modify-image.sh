#!/bin/sh -e

VERSION=v1.0.2
NAME="${0##*/}"

GH_URL=https://github.com/meeDamian/raspios

show_version() { echo "$NAME $VERSION"; }
show_help() {
	EXAMPLE_URL=https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2017-04-10/2017-04-10-raspbian-jessie-lite.zip

	cat <<EOF >&2
$(show_version)

Modify  Raspberry Pi OS Lite  image with support for  /boot/firstboot.sh  script.

Usage: ./$NAME explain | help
       ./$NAME version | url  [VARIANT]
       ./$NAME create  [DIR]  [VARIANT]

Where VARIANT is one of:
  lite      - Use minimal Raspberry Pi OS as a base of the image (default)
  desktop   - Use desktop Raspberry Pi OS as a base of the image
  full      - Use full    Raspberry Pi OS as a base of the image
  https://… - Use custom  Raspberry Pi OS (or Raspbian) from URL as a base of the image
              ex: $EXAMPLE_URL

EOF

	[ -n "$1" ] && cat <<EOF >&2
The 'create' COMMAND tries:

  0. Change to DIR (if specified)
  1. Download most recent Raspberry Pi OS Lite image
       (unless direct URL to another release specified)
  2. Modify that image with:
  3.   Install /etc/systemd/system/firstboot.service
  4.   Enable it by creating a symlink to it at:
         /etc/systemd/system/multi-user.target.wants/
  5. Compress & check-sum the result
  6. Save it with '-firstboot' suffix

For the exact explanation 'cat $0', and read top ⬇ bottom :).

EOF

	cat <<EOF >&2
Examples:
  ./$NAME  version      # Fetch & return latest Raspberry Pi OS version
  ./$NAME  create       # Create firstboot flavor of latest Raspberry Pi OS in current directory
  ./$NAME  create /tmp  # Create firstboot flavor of latest Raspberry Pi OS in /tmp

  URL=$EXAMPLE_URL
  ./$NAME  create "\$URL"  # Create firstboot flavor of Raspberry Pi OS using image from \$URL as base

github: $GH_URL

EOF
}

L=/dev/stderr

# Define logging functions
Log()  { printf   "%b\n" "$*" | sed "s|^|[$(date +%T)] |g" >"$L" ;} # Print all arguments
Step() { Log           "\n$*…"      ;} # Start of new section
OK()   { Log       "\t-> ${*:-ok}"  ;} # Print OK on progress
_err() { Log "\n\t-> ERR: $*\n"     ;} # Print section's error

Error()     { _err "$*"; exit 1 ;} # Print section's error and exit
need_help() { _err "Unknown command '$1'" ; show_help; exit 1 ;} # Print input error, followed by help


case "$1" in
create)      show_version ;;     # Start 'create' mode by printing script's version
version|url) L=/dev/null  ;;     # Disable logging for 'version' and 'url' modes
*) case "${1#--}"         in     # Exit after handling anything other than 'start', 'url', or 'version'
	-v|version) show_version   ;;  # Print *script's* version
	-h|h[ea]lp) show_help      ;;  # Print help
	-H|explain) show_help true ;;  # Print help PLUS explanation on what the script does

	'') show_help     ; exit 1 ;;  # Error out with help on no arguments passed
	*)  need_help "$1"; exit 1 ;;  # Error out on unknown argument
	esac

	exit 0
	;;
esac

start="$(date +%s)"

check_deps() {
	ies=ies; [ "$#" -eq "1" ] && ies=y
	Step "Checking $# dependenc$ies"

	for d in "$@"; do
		[ -x "$(command -v "$d")" ] || Error "Missing: $d"
	done

	OK
}

# Exit error, if `curl` is not installed & available
check_deps curl

resolve_url() { curl -ILs  -o /dev/null  -w "%{url_effective}"  "$1"; }
raspios_url() { resolve_url "https://downloads.raspberrypi.org/raspios${1:+_$1}_armhf_latest"; }

# If 3rd argument passed, it can be $variant only
variant="$3"

# 2nd argument can be either VARIANT or DIR
case "$2" in
lite|full|desktop|http*://*) variant="$2" ;;
*) dir="$2" ;;
esac

# On 'create' make sure destination dir exists, and is writeable
if [ "$1" = "create" ]; then
	dir="${dir:-$(pwd)/images}"
	dir="/${dir#//}"

	Step "Checking destination:"  "${dir%/}/"

	if [ -d "$dir" ]; then
		OK 'exists'
	fi

	if [ ! -d "$dir" ]; then
		parent="$(dirname "$dir")"

		if [ ! -d "$parent" ] || [ ! -w "$parent" ];  then
			Error "Destination doesn't exist and can't be created"
		fi

		mkdir "$dir"
		OK 'created'
	fi

	if [ ! -w "$dir" ]; then
		Error "Destination directory is not writeable"
	fi

	OK 'is writeable'
fi


Step "Determining URL${variant:+" from: '$variant'"}"
case "$variant" in
http*://*.zip) url="$variant"                  ;;
http*://*)     url="$(resolve_url "$variant")" ;;
desktop)       url="$(raspios_url)"            ;;
full)          url="$(raspios_url full)"       ;;
*)             url="$(raspios_url lite)"       ;;
esac
OK "$url"

# Take URL, return version (fmt: YYYY-MM-DD)
version() { basename "$1" | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'; }

case "$1" in
url)     echo    "$url"; exit 0 ;;
version) version "$url"; exit 0 ;;
esac

check_deps curl file gpg grep sha256sum zip unzip wget

cd "$dir"

# Extract filename.zip from the $url
original_zip="$(basename "$url")"

Step "Downloading"  "$original_zip to $(pwd)"
if ! wget -cq "$url" "$url.sig" "$url.sha256"; then
	Error "FAILED"
fi
OK

Step "Verifying"  "$original_zip"
if ! out="$(sha256sum -c "$original_zip.sha256")"; then
	Error "Checksum doesn't match:" "$out"
fi
OK "Checksum ok"

raspios_key="54C3DD610D9D1B4AF82A37758738CD6B956F460C"
if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "$raspios_key"; then
	Error "Unable to fetch GPG key"
fi
OK "GPG key fetched"

if ! gpg --verify "$original_zip.sig"; then
	Error "Signature verification failed"
fi
OK "Signature valid"

# Create temporary DIR, and make sure it's removed upon EXIT
temp_dir="$(mktemp -d)"
cleanup() { rm -rf "$temp_dir"; }
trap cleanup EXIT

# Get extracted name & full, temporary path to extracted image
original_img="${original_zip%.zip}.img"
temp_img="$temp_dir/$original_img"

Step "Inflating"  "$original_zip"
if ! out="$(unzip -n "$original_zip" -d "$temp_dir/")"; then
	Error "$out"
fi
OK "$original_zip extracted to $temp_dir"

Step "Scanning image"  "$original_img"
startsector="$(file "$temp_img" | grep -Eo 'startsector [[:digit:]]+' | cut -d' ' -f2 | sort -nr | head -n1)"
if [ -z "$startsector" ]; then
	Error "Can't find start sector of the last partition…"
fi
OK "Start sector: $startsector"


mount_dir=/mnt/raspios
mkdir -p "$mount_dir"

Step "Mounting"  "$original_img at $mount_dir"
if ! out="$(mount -o "loop,offset=$((startsector * 512))" "$temp_img" "$mount_dir")"; then
	Error "Unable to mount: $out"
fi
OK


os_path=etc/systemd/system

Step "Installing services"
for  service  in firstboot firstboot-script; do
	service_file="$service.service"
	service_src="$(pwd)/$service_file"

	# Change $service_src, when running in Docker
	if [ -f "/data/$service_file" ]; then
		service_src="/data/$service_file"
	fi

	cp "$service_src" "$mount_dir/$os_path/"
	OK "$service installed at /$os_path/$service_file"

	# Run in (subshell) to avoid changing directory (we (need (to (go (deeper(!))))))
	(
		cd "$mount_dir/$os_path/multi-user.target.wants/"
		ln -s "/$os_path/$service_file" .
		OK "$service enabled as /$os_path/multi-user.target.wants/$service_file"
	)
done


Step "Unmounting" "$mount_dir"
umount "$mount_dir"
OK


firstboot_img="${original_img%.img}-firstboot.img"

Step "Renaming & moving" "$original_img"
mv "$temp_img" "./$firstboot_img"
OK "Renamed to $firstboot_img"


firstboot_zip="${firstboot_img%.img}.zip"

Step "Deflating"  "$firstboot_img"
zip -mT "$firstboot_zip" "$firstboot_img"
OK "Compressed to $firstboot_zip"


firstboot_sha256="$firstboot_zip.sha256"

Step "Creating checksum"  "of $firstboot_zip"
sha256sum "$firstboot_zip" > "$firstboot_sha256"
OK "$(cat "$firstboot_sha256")"
OK "Saved as $firstboot_sha256"


fin="$(date +%s)"
duration="$((fin - start))"

Log "\nAll done"
OK "Took $((duration / 60))min $((duration % 60))sec"
