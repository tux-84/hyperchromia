#!/bin/sh
set -e

SEED=/usr/share/hyperchromia/factory-seed/hyperhdr
DATA=/data/hyperhdr

mkdir -p "$DATA/bin" "$DATA/lib" "$DATA/.config/HyperHDR" "$DATA/backups"

if [ ! -s "$DATA/bin/hyperhdr" ]; then
	cp -a "$SEED/bin/." "$DATA/bin/"
	cp -a "$SEED/lib/." "$DATA/lib/"
	sync
fi

mkdir -p /data/hyperchromia
if [ ! -f /data/hyperchromia/state/firstboot-done ] && [ ! -f /data/hyperchromia/firstboot.conf ]; then
	cp /usr/share/hyperchromia/factory-seed/firstboot.conf /data/hyperchromia/firstboot.conf
	chmod 600 /data/hyperchromia/firstboot.conf
	sync
fi
