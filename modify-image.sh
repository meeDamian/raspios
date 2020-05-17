#!/usr/bin/env sh

set -e

LATEST_RASPBIAN="https://downloads.raspberrypi.org/raspbian_lite_latest"
RASPBIAN_KEY="54C3DD610D9D1B4AF82A37758738CD6B956F460C"

log() {
	>&2 printf "$*\n"
}
log_err() {
	log "\n\t-> ERR: $*\n"
}
log_ok() {
	log "\t-> ${*:-ok}" # if nothing passed, write "ok"
}

# Takes dependencies, as arguments, and checks if they're installed.
has_deps() {
	fmt='ERR: Required dependency "%s" is missing\n'

	exists() {
		test -x "$(command -v "$1")"
	}

	# shellcheck disable=SC2059
	for c in "$@"; do
		exists "$c" || { >&2 printf "$fmt" "$c"; return 1; }
	done
}

get_last_url() {
	curl -ILs  -o /dev/null  -w "%{url_effective}"  "$LATEST_RASPBIAN"
}

# Takes URL, returns filename
extract_filename() {
	basename "$1"
}

# Takes URL, returns version
extract_version() {
	extract_filename "$1" | grep -Eo '\d{4}-\d{2}-\d{2}'
}

# Takes $url downloads `.zip`, `.zip.sha256`, and `.zip.sig`
download() {
	url="$1"
	log "Downloading $(extract_filename "$url") to $(pwd)…"
	wget -cq "$url" "$url.sig" "$url.sha256"
	log_ok
}

# Takes $file_name, and verifies consistency, and signature of image
verify() {
	file_name="$1"

	log "Verifying image…"

	if ! out="$(sha256sum -c "$file_name.sha256")"; then
		echo "Checksum doesn't match:" "$out"
		return 1
	fi
	log_ok "Checksum ok"

	if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "$RASPBIAN_KEY"; then
		echo "Unable to fetch GPG key"
		return 1
	fi
	log_ok "GPG key fetched"

	if ! gpg --verify "$file_name.sig"; then
		echo "Signature verification failed"
		return 1
	fi

	log_ok "Valid signature"
}

mount_ext4() {
	image_name="${1%.zip}.img"

	log "Mounting ${image_name}…"

	startsector="$(file "$image_name" | grep -Eo 'startsector \d+' | cut -d' ' -f2 | sort -nr | head -n1)"
	if [ -z "$startsector" ]; then
		log_err "Unable to find start sector of the last partition…"
		return 1
	fi

	log_ok "Found startsector: $startsector"

	mkdir -p /mnt/
	mount -o "loop,offset=$((startsector*512))" "$image_name" /mnt/raspbian/
	ls -la /mnt/raspbian/
}

all() {
	dir="${1:-$(pwd)}"

	(
		cd "$dir"

		url="$(get_last_url)"
		file_name="$(extract_filename "$url")"

		download "$url"
		if ! out="$(verify "$file_name")"; then
			log_err "Verification failed: $out"
			exit 1
		fi

		log "Inflating…"
		unzip -n "$file_name"

		mount_ext4 "$file_name"
	)
}

if ! has_deps grep wget gpg sha256sum unzip; then
	exit 1
fi

all "${1:-$(pwd)}"
