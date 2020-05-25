#!/usr/bin/env sh

## This is an example script that:
#    1. Installs Tor
#    2. Sets up a stealth Tor Hidden Service for ssh access
#    3. Copies `hostname` to `/boot/` (necessary to access)
#    4. Halts RBP when done (unless `/boot/nohalt` exists)

set -e

RET_COUNT=20

retry() {
	delay=${RET_DELAY:-10} # seconds
	count=${RET_COUNT:-3}

	_s=s
	until $*; do
		>&2 printf "'%s' failed (exit=%s)" "$1" "$?"
		if [ $((count-=1)) = 0 ]; then
			>&2 printf "\n"
			return 1
		fi

		[ "$count" = 1 ] && _s=
		>&2 printf ", retry in %ss (%s more time%s)…\n\n" "$delay" "$count" "$_s"
		sleep "$delay"
	done
}

do_tor() {
	retry apt-get install -y tor

	retry test -f /etc/tor/torrc || exit 1

	cat << EOF >> /etc/tor/torrc
HiddenServiceDir /var/lib/tor/ssh/
HiddenServiceVersion 2
HiddenServicePort 22 127.0.0.1:22
HiddenServiceAuthorizeClient stealth ssh
EOF

	retry systemctl restart tor
	retry systemctl restart tor@default

	RET_COUNT=10 retry cp /var/lib/tor/ssh/hostname /boot/
}

retry apt-get update

do_tor

RET_COUNT=100 RET_DELAY=5 retry test -f /boot/nohalt || halt

exit 0
