#!/bin/sh

hy_run_timeout() {
	secs="$1"
	shift
	"$@" &
	pid=$!
	( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
	watcher=$!
	wait "$pid" 2>/dev/null
	kill "$watcher" 2>/dev/null
}

i=0
svc=""
while [ "$i" -lt 10 ]; do
	svc=$(connmanctl services 2>/dev/null | sed -n 's/^\*[A-Za-z]* .*[[:space:]]\([^[:space:]]*\)$/\1/p' | head -n1)
	[ -n "$svc" ] && break
	i=$((i + 1))
	sleep 1
done

if [ -n "$svc" ]; then
	hy_run_timeout 10 connmanctl disconnect "$svc" >/dev/null 2>&1
	sleep 1
	hy_run_timeout 10 connmanctl connect "$svc" >/dev/null 2>&1
fi
