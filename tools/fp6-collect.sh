#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Run ON THE PHONE as root. Read-only: it collects state and logs, nothing else.
# The tarball contains device identifiers (IMSI, IMEI, serials, MACs, UUIDs):
# keep it private, or pipe what you share through redact.sh.
#   scp tools/fp6-collect.sh mobian@10.66.0.1:/tmp/
#   ssh -t mobian@10.66.0.1 sudo sh /tmp/fp6-collect.sh
#   scp mobian@10.66.0.1:/tmp/fp6-logs-*.tar.gz .
out=/tmp/fp6-logs-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
run() { name=$1; shift; { echo "\$ $*"; "$@"; } >"$out/$name.txt" 2>&1; }

run uname        uname -a
run cmdline      cat /proc/cmdline
run dmesg        dmesg
run journal      journalctl -b --no-pager
run journal-prev journalctl -b -1 --no-pager
run boots        journalctl --list-boots --no-pager
run failed       systemctl --failed --no-pager
run lsmod        lsmod
run lsblk        lsblk -o NAME,SIZE,FSTYPE,UUID,PARTLABEL,MOUNTPOINTS
run diversions   dpkg-divert --list
run slot         qbootctl -x
run guard        journalctl --no-pager -g 'fp6 guard|zz-qcom-bootimg|droid-juicer'
run juicer       sh -c 'cat /var/lib/droid-juicer/status.json; echo; find /lib/firmware/updates -type f | sort'
run remoteproc   sh -c 'for r in /sys/class/remoteproc/*; do echo "$r $(cat $r/name) $(cat $r/firmware) $(cat $r/state)"; done'
run drm          sh -c 'for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status)"; done'
run input        cat /proc/bus/input/devices
run sound        sh -c 'cat /proc/asound/cards; aplay -l; arecord -l'
run net          sh -c 'ip -br addr; nmcli dev; rfkill list'
run modem        sh -c 'mmcli -L; mmcli -m any'
run iio          sh -c 'for d in /sys/bus/iio/devices/iio:device*; do echo "$d $(cat $d/name)"; done'
run video        sh -c 'ls -l /dev/video* /dev/media* 2>&1; cam -l'
run gpu          sh -c 'ls -l /dev/dri; cat /sys/kernel/debug/dri/*/name 2>/dev/null'
run thermal      sh -c 'for t in /sys/class/thermal/thermal_zone*; do echo "$(cat $t/type) $(cat $t/temp)"; done'
run power        sh -c 'for p in /sys/class/power_supply/*; do echo "== $p"; cat $p/uevent; done'

tar -C /tmp -czf "$out.tar.gz" "$(basename "$out")"
chown "${SUDO_USER:-mobian}": "$out.tar.gz" 2>/dev/null
echo "wrote $out.tar.gz"
