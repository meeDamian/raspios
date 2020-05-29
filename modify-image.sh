#!/usr/bin/env sh

set -e

show_help() {
  cat << EOF >&2
modify-image.sh v1.0.1

Modify Raspberry Pi OS Lite image to recognize, and run 'firstboot.sh' placed in '/boot/'.

Usage: ./modify-image.sh COMMAND
       ./modify-image.sh create [DIR] [URL]

Where COMMAND is one of: help, url, version.

The 'create' COMMAND goal is:

  0. Change to DIR (if specified)
  1. Download most recent Raspberry Pi OS Lite image
       (unless direct URL to another release specified)
  2. Modify that image with:
  3.   Install /etc/systemd/system/firstboot.service
  4.   Enable it by creating a symlink to it at:
         /etc/systemd/system/multi-user.target.wants/
  5. Compress & check-sum the result
  6. Save it with '-firstboot' suffix

For the exact explanation 'cat' this file and read top ⬇ bottom :).

Examples:

  ./modify-image.sh  help          # Shows the very thing you're reading
  ./modify-image.sh  version       # Fetches, and returns latest Raspberry Pi OS version
  ./modify-image.sh  create        # Create firstboot flavor of Raspberry Pi OS in current directory
  ./modify-image.sh  create /tmp   # Create firstboot flavor of Raspberry Pi OS in /tmp

  # And to create release of ex. Raspberry Pi OS Lite dated 2017-04-10 in /tmp, run:
  ./modify-image.sh  create /tmp https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2017-04-10/2017-04-10-raspbian-jessie-lite.zip

github: github.com/meeDamian/raspios/

EOF
}

# Exit, after showing help, on no arguments or 'help' passed
if [ "$#" -le 0 ] || [ "$1" = "help" ]; then
	show_help
	shift && exit 0 || exit 1
fi

# Define utility fns
_log() { >&2 printf "$*\n"; }           # print all arguments to stderr
log() { _log "\n$*…"; }                 # print start of new section
log_err() { _log "\n\t-> ERR: $*\n"; }  # print section's error
log_ok() { _log "\t-> ${*:-ok}"; }      # print passed section status update, or "ok"
missing_deps() {
	for d in "$@"; do
		test -x "$(command -v "$d")" || echo "$d"
	done | tr '\n' ' '
}

# Exit error, if `curl` is not installed & available
missing="$(missing_deps curl)"
if [ -n "$missing" ]; then
	_log "\nChecking dependencies…\n\n\t-> ERR: Missing: $missing\n"
	exit 1
fi

# This link always redirects to latest release
LATEST_RASPIOS="https://downloads.raspberrypi.org/raspios_lite_armhf_latest"

# Uncomment below, if you prefer Raspberry Pi OS Desktop over Lite
#LATEST_RASPIOS="https://downloads.raspberrypi.org/raspios_armhf_latest"

# Return direct URL to the latest Raspberry Pi OS image
get_last_url() {
	curl -ILs  -o /dev/null  -w "%{url_effective}"  "$LATEST_RASPIOS"
}

# Exit error, if unable to get direct URL to latest release
if ! URL="$(get_last_url)"; then
	_log "\n\tERR: Unable to figure out latest version\n";
	exit 1
fi

# Exit after returning URL to Raspberry Pi OS's latest release
if [ "$1" = "url" ]; then
	echo "$URL"
	exit 0
fi

# Take URL, return filename
extract_filename() { basename "$1"; }

# Take URL, return version (fmt: YYYY-MM-DD)
extract_version() {
	extract_filename "$1" | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'
}

# Exit after returning Raspberry Pi OS's latest version
if [ "$1" = "version" ]; then
	extract_version "$URL"
	exit 0
fi

# Exit error, if 1st argument is anything other than 'create' at this point
if [ "$1" != "create" ]; then
	_log "\n\tERR: Unknown command: '$1'\n";
	show_help
	exit 1
fi


log "Checking dependencies"
missing="$(missing_deps curl file gpg grep sha256sum zip unzip wget)"
if [ -n "$missing" ]; then
	log_err "Missing: $missing"
	exit 1
fi

log_ok


# Start a subshell to avoid change-directory side-effect
(
	# Change dir to $2, if passed and not URL
	if [ -n "$2" ] && [ "${2#http*://}" = "$2" ]; then
		cd "$2"; shift
	fi

	# Use specific URL, if provided
	if [ -n "$2" ] && [ "${2#http*://}" != "$2" ]; then
		URL="$2"
	fi


	# Extract filename.zip from the URL
	original_zip="$(extract_filename "$URL")"

	log "Downloading"  "$original_zip to $(pwd)"
	if ! wget -cq "$URL" "$URL.sig" "$URL.sha256"; then
		log_err "FAILED"
		exit 1
	fi
	log_ok


	log "Verifying"  "$original_zip"
	if ! out="$(sha256sum -c "$original_zip.sha256")"; then
		log_err "Checksum doesn't match:" "$out"
		exit 1
	fi
	log_ok "Checksum ok"

	raspios_key="54C3DD610D9D1B4AF82A37758738CD6B956F460C"
	if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "$raspios_key"; then
		log_err "Unable to fetch GPG key"
		exit 1
	fi
	log_ok "GPG key fetched"

	if ! gpg --verify "$original_zip.sig"; then
		echo "Signature verification failed"
		exit 1
	fi
	log_ok "Signature valid"


	# Create temporary DIR, and make sure it's removed upon EXIT
	temp_dir="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf $temp_dir" EXIT

	# Get extracted name & full, temporary path to extraced image
	original_img="${original_zip%.zip}.img"
	temp_img="$temp_dir/$original_img"

	log "Inflating"  "$original_zip"
	if ! out="$(unzip -n "$original_zip" -d "$temp_dir/")"; then
		log_err "$out"
		exit 1
	fi
	log_ok "$original_zip extracted to $temp_dir"


	log "Scanning image"  "$original_img"
	startsector="$(file "$temp_img" | grep -Eo 'startsector [[:digit:]]+' | cut -d' ' -f2 | sort -nr | head -n1)"
	if [ -z "$startsector" ]; then
		echo "Can't find start sector of the last partition…"
		exit 1
	fi
	log_ok "Start sector: $startsector"


	mount_dir=/mnt/raspios
	mkdir -p "$mount_dir"

	log "Mounting"  "$original_img at $mount_dir"
	if ! out="$(mount -o "loop,offset=$((startsector * 512))" "$temp_img" "$mount_dir")"; then
		echo "Unable to mount: $out"
		return 1
	fi
	log_ok


	os_path=etc/systemd/system

	log "Installing services"
	for  service  in firstboot firstboot-script; do
		service_file="$service.service"
		service_src="$(pwd)/$service_file"

		# Change $service_src, when running in Docker
		[ -f "/data/$service_file" ] && service_src="/data/$service_file"

		cp "$service_src" "$mount_dir/$os_path/"
		log_ok "$service installed at /$os_path/$service_file"

		# Another subshell to avoid cd (we (need (to (go (deeper(!))))))
		(
			cd "$mount_dir/$os_path/multi-user.target.wants/"
			ln -s "/$os_path/$service_file" .
			log_ok "$service enabled as /$os_path/multi-user.target.wants/$service_file"
		)

	done


	log "Unmounting" "$mount_dir"
	umount "$mount_dir"
	log_ok


	firstboot_img="${original_img%.img}-firstboot.img"

	log "Renaming & moving" "$original_img"
	mv "$temp_img" "./$firstboot_img"
	log_ok "Renamed to $firstboot_img"


	firstboot_zip="${firstboot_img%.img}.zip"

	log "Deflating"  "$firstboot_img"
	zip "$firstboot_zip" "$firstboot_img"
	log_ok "Compressed to $firstboot_zip"


	firstboot_sha256="$firstboot_zip.sha256"

	log "Creating checksum"  "of $firstboot_zip"
	sha256sum "$firstboot_zip" > "$firstboot_sha256"
	log_ok "$(cat "$firstboot_sha256")"
	log_ok "Saved as $firstboot_sha256"
)
