#!/usr/bin/env sh

set -e

show_help() {
  cat << EOF >&2
modify-image.sh v1.0.0

Modify Raspbian Lite image to recognize, and run 'firstboot.sh' placed in '/boot/'.

Usage: ./modify-image COMMAND [DIR]

Where COMMAND is one of: version, help, or create.

The 'create' COMMAND goal is:

  1. Download most recent Raspbian image into DIR/ (if not there already)
  2. And in that image:
  3. Install /etc/systemd/system/firstboot.service
  4. Enable it with a symlink to it at /etc/systemd/system/multi-user.target.wants/
  5. Save it modified, compressed, and check-summed with '-firstboot' suffix

For the exact explanation, 'cat' this file and read top ⬇ bottom :).

Examples:

  ./scripts/download  help          # Shows the very thing you're reading
  ./scripts/download  version       # Fetches, and returns latest Raspbian version
  ./scripts/download  create        # Create firstboot flavor of Raspbian in current directory

github: github.com/meeDamian/raspbian/

EOF
}

# If no arguments, or 'help' passed, show_help and exit
if [ "$#" -le 0 ] || [ "$1" = "help" ]; then
	show_help
	shift && exit 0 || exit 1
fi

# Define some simple utility fns
_log() { >&2 printf "$*\n"; }
log() { _log "\n$*…"; }
log_err() { _log "\n\t-> ERR: $*\n"; }
log_ok() { _log "\t-> ${*:-ok}"; }  # if nothing passed, write "ok"
missing_deps() {
	for d in "$@"; do
		test -x "$(command -v "$d")" || echo "$d"
	done | tr '\n' ' '
}

# Check if `curl` is intalled, and available
missing="$(missing_deps curl)"
if [ -n "$missing" ]; then
	_log "\nChecking dependencies…\n\n\t-> ERR: Missing: $missing\n"
	exit 1
fi


LATEST_RASPBIAN="https://downloads.raspberrypi.org/raspbian_lite_latest"

# Returns direct URL to the latest Raspbian image
get_last_url() {
	curl -ILs  -o /dev/null  -w "%{url_effective}"  "$LATEST_RASPBIAN"
}

# Takes URL, returns filename
extract_filename() {
	basename "$1"
}

# Takes URL, returns version
extract_version() {
	extract_filename "$1" | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'
}

# Get latest Raspbian URL
if ! URL="$(get_last_url)"; then
	_log "\n\tERR: Unable to figure out latest version\n";
	exit 1
fi

# Only return latest Raspbian version, and exit
if [ "$1" = "version" ]; then
	extract_version "$URL"
	exit 0
fi

# 'help' & 'check' are already handled.  Anything other than 'create' is an error.
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

# Start a subshell
(
	# If $DIR provided, try to `cd` into it
	[ -n "$2" ] && cd "$2"

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

	raspbian_key="54C3DD610D9D1B4AF82A37758738CD6B956F460C"
	if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "$raspbian_key"; then
		log_err "Unable to fetch GPG key"
		exit 1
	fi
	log_ok "GPG key fetched"

	if ! gpg --verify "$original_zip.sig"; then
		echo "Signature verification failed"
		exit 1
	fi
	log_ok "Signature valid"


	original_img="${original_zip%.zip}.img"

	log "Inflating"  "$original_zip"
	if ! out="$(unzip -n "$original_zip")"; then
		log_err "$out"
		exit 1
	fi
	log_ok "$original_img created"


	log "Scanning image"  "$original_img"
	startsector="$(file "$original_img" | grep -Eo 'startsector [[:digit:]]+' | cut -d' ' -f2 | sort -nr | head -n1)"
	if [ -z "$startsector" ]; then
		echo "Can't find start sector of the last partition…"
		exit 1
	fi
	log_ok "Start sector: $startsector"


	mount_dir=/mnt/raspbian
	mkdir -p "$mount_dir"

	log "Mounting"  "$original_img at $mount_dir"
	if ! out="$(mount -o "loop,offset=$((startsector * 512))" "$original_img" "$mount_dir")"; then
		echo "Unable to mount: $out"
		return 1
	fi
	log_ok


	service_file=firstboot.service
	os_path=/etc/systemd/system
	service_src="$(pwd)/$service_file"
	[ -f "/data/$service_file" ] && service_src="/data/$service_file"

	log "Installing service"  "$service_file"
	cp "$service_src" "$mount_dir$os_path/"
	log_ok "Installed at $os_path/$service_file"

	(
		cd "$mount_dir$os_path/multi-user.target.wants/"
		ln -s "$os_path/$service_file" .
		log_ok "Enabled as $os_path/multi-user.target.wants/$service_file"
	)


	log "Unmounting" "$mount_dir"
	umount "$mount_dir"
	log_ok


	firstboot_img="${original_img%.img}-firstboot.img"

	log "Renaming" "$original_img"
	mv "$original_img" "$firstboot_img"
	log_ok "Renamed to $firstboot_img"


	firstboot_zip="${firstboot_img%.img}.zip"

	log "Deflating"  "$firstboot_img"
	zip "$firstboot_zip" "$firstboot_img"
	log_ok "Compressed to $firstboot_zip"


	firstboot_sha256="$firstboot_zip.sha256"

	log "Creating checksum"  "of $firstboot_zip]"
	sha256sum "$firstboot_zip" > "$firstboot_sha256"
	log_ok "$(cat "$firstboot_sha256")"
	log_ok "Saved as $firstboot_sha256"
)
