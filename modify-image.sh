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

# Takes $original_zip, and verifies consistency, and signature of image
verify() {
	original_zip="$1"

	log "Verifying image…"

	if ! out="$(sha256sum -c "$original_zip.sha256")"; then
		echo "Checksum doesn't match:" "$out"
		return 1
	fi
	log_ok "Checksum ok"

	if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "$RASPBIAN_KEY"; then
		echo "Unable to fetch GPG key"
		return 1
	fi
	log_ok "GPG key fetched"

	if ! gpg --verify "$original_zip.sig"; then
		echo "Signature verification failed"
		return 1
	fi

	log_ok "Valid signature"
}

mount_image() {
	original_image="$1"

	log "Mounting ${original_image}…"

	startsector="$(file "$original_image" | grep -Eo 'startsector [[:digit:]]+' | cut -d' ' -f2 | sort -nr | head -n1)"
	if [ -z "$startsector" ]; then
		echo "Unable to find start sector of the last partition…"
		return 1
	fi

	log_ok "Found startsector: $startsector"

	mount_dir=/mnt/raspbian/

	mkdir -p "$mount_dir"
	if ! out="$(mount -o "loop,offset=$((startsector*512))" "$original_image" "$mount_dir")"; then
		echo "Unable to mount: $out"
		return 1
	fi

	log_ok "$original_image mounted at $mount_dir"
}

install_firstrun() {
	file=firstboot.service
	path=/mnt/raspbian/etc/systemd/system

	log "Installing firstboot.service…"

	cp "/data/$file" "$path/"
	log_ok "Installed at ${path#/mnt/raspbian}/$file"

	(
		cd "$path/multi-user.target.wants"
		ln -s "/etc/systemd/system/$file" .
		log_ok "Enabled as ${path#/mnt/raspbian}/multi-user.target.wants/$file"
	)
}

all() {
	url="$(get_last_url)"
	original_zip="$(extract_filename "$url")"

	download "$url"
	if ! out="$(verify "$original_zip")"; then
		log_err "Verification failed: $out"
		exit 1
	fi

	original_image="${original_zip%.zip}.img"

	log "Inflating…"
	unzip -n "$original_zip"
	log_ok "$original_zip unzipped into"
	log_ok "$original_image"

	if ! out="$(mount_image "$original_image")"; then
		log_err "Mounting failed: $out"
		exit 1
	fi

	install_firstrun

	log "Unmounting /mnt/raspbian…"
	umount /mnt/raspbian
	log_ok

	firstboot_image="${original_image%.img}-firstboot.img"

	log "Renaming…"
	mv "$original_image" "$firstboot_image"
	log_ok "$original_image renamed to"
	log_ok "$firstboot_image"

	firstboot_zip="${firstboot_image%.img}.zip"
	log "Deflating…"
	zip "$firstboot_zip" "$firstboot_image"
	log_ok "$firstboot_image zipped into"
	log_ok "$firstboot_zip"

	firstboot_checksum="$firstboot_zip.sha256"
	log "Creating checksum file…"
	sha256sum "$firstboot_zip" > "$firstboot_checksum"
	log_ok "$(cat "$firstboot_checksum")"
	log_ok "$firstboot_checksum"
}


case "$1" in
version)
  extract_version "$(get_last_url)"
	exit 0
	;;

magic|*)
	if ! has_deps curl file gpg grep sha256sum zip unzip wget; then
		exit 1
	fi

	(
		cd "${2:-$(pwd)}"
		all
	)
	;;
esac


