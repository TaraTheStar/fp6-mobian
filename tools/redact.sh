#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Mask personal identifiers in command output before it leaves the phone:
# phone numbers, IMSI/ICCID/IMEI/EID, SIP/tel identities, device serial, MAC addresses. Errs on the side of
# masking (long byte counts get masked too).
exec sed -E \
  -e 's/((imsi|msisdn|impu|impi|iccid|imei|eid|own[ _-]?numbers?|phone[ _-]?number|caller[ _-]?id|remote[ _-]?(party|number)|number)[^:=\n]{0,16}[:=][[:space:]]*)[^[:space:],;]+/\1<redacted>/Ig' \
  -e 's/((serialno|serial[ _-]?number|wifimac|btmac|bdaddr|mac[ _-]?addr(ess)?)[^:=[:space:]]{0,8}[:=][[:space:]]*)[^[:space:],;]+/\1<redacted>/Ig' \
  -e 's/\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b/<mac>/Ig' \
  -e 's/(sips?|tel):[^[:space:]>;,"'"'"']*/\1:<redacted>/Ig' \
  -e 's/\b(2[0-9a-f]{3}):[0-9a-f:]{6,}/\1:<v6>/Ig' \
  -e 's/\+?[0-9][0-9 ().-]{8,}[0-9]/<num>/g' \
  -e 's/[0-9]{7,}/<num>/g'
