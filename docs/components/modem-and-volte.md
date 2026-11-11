# Modem, SMS and VoLTE

T-Mobile US has no 2G/3G network, so on this carrier a phone without VoLTE
can't make calls. The FP6 modem doesn't run IMS for mainline Linux; the IMS client has to
run on the host. That client is Catcrafts' **[imsd]**.

## How it works

- The modem (Qualcomm, QMI over QRTR) is driven by ModemManager. `qcom-modem-setup`
  selects the SIM application, and the NetworkManager profile brings up mobile
  data on `qmapmux0.0`.
- imsd brings up a second bearer on profile 2 (APN `ims`) through
  ModemManager. It reads the P-CSCF addresses from the network's PCO over QMI and
  registers over SIP. The security associations are set up with `ip xfrm`
  (IPsec ESP, hmac-sha-1-96/aes-cbc), the transport is TCP, and it plays and
  records AMR/AMR-WB call audio through PipeWire (`pw-play`/`pw-record`).
- **imsd-ofono** (`imsd-ofonod`) presents imsd as an oFono modem on the system
  bus. GNOME Calls' `ofono` provider drives it, so calls work on Phosh.
  `imsd-ofono` sets GNOME Calls' `autoload-plugins` to `['ofono']`. It conflicts
  with a real `ofono`; Mobian doesn't ship one.
- SMS go over NAS/SGs on LTE (ModemManager), not over IMS. MMS work with
  mmsd-tng and Chatty.
- imsd (the IMS bearer) and `fp6-lte-pin` (its `gdbus monitor`) both depend on
  how ModemManager behaves on D-Bus. After a major ModemManager upgrade, check
  that calls register and that the allowed modes still get pinned.

## Results on T-Mobile US

- Registration on LTE with a combined `cs-ps` attach. Data: IPv6, plus IPv4 via
  464XLAT.
- IMS REGISTERED, calls both ways, AMR-WB, 0 late frames, 0 drops.
- SMS and MMS both ways.
- **First US carrier verified with imsd.** Catcrafts' verified list is European.

What we found along the way:

| Finding | Effect | Handling |
|---|---|---|
| **5G SA** registers packet-only | no SMS path (imsd doesn't advertise SMS over IP), data stalls | pin the modem to LTE (`fp6-lte-pin`) |
| The network's PCO lists several P-CSCFs, and the first one may never answer the unprotected REGISTER ("no 401") | imsd always took the first, exited, restarted with the same list, forever | patch 0002 |
| A fresh REGISTER soon after a failed one got refused with 401 | imsd's registration recovery then holds fresh registrations: 21 min at first, growing ×1.5 per step up to 60 min. The holds live in `/run/imsd.holds`, so a reboot clears them | keep upstream's `RestartSec=120`, don't shorten it; don't restart imsd right after it registered |
| Call audio: imsd's default `GAIN=10` (+20 dB) amplified the speaker echo | far end heard an echo | patch 0003 + `fp6-audio.conf` |
| `pw-record` kept running with the mic open after every call | privacy and battery | patch 0004 |
| ModemManager 1.24.2 segfaulted 3× while the IMS bearer and data came up together | IMS took longer to come up | not reproduced once both are up; Catcrafts runs a 1.25.95 snapshot |
| `qcom-modem-setup` fails with an empty AID when there's no SIM | log noise only | qcom-phone-utils |
| The SIM reports `sim-pin2` / FDN "enabled lock" | none | ignore |
| The first SMS after one boot failed (`WmsMessageDeliveryFailure`), and the retry worked | minor | watch |

## Packaging (Debian toolchain only)

**Source:** [imsd] v1.1.0, GPL-3.0-only.
**Packages:** `imsd` (daemon, helpers, systemd unit, D-Bus and polkit policy),
`imsd-ofono` (GNOME Calls), `imsd-plasma` (Plasma Dialer; built, not tested).
**Upstream target:** the patches to Catcrafts; the packaging to Debian (ITP, Section net).

Upstream builds only with Crafter.Build: a Flatpak toolchain with clang 23 that
fetches git repositories at build time. Debian needs an offline build with its own compiler.

### Patches

| Patch | What | Scope | Tested |
|---|---|---|---|
| 0001 CMake build | mirrors `project.cpp`: `imsd-core` and `imsd-bus` module libraries, five executables, eight test suites. `import std` comes from building libc++'s own `std.cppm` (found through `libc++.modules.json`) as an ordinary module library, so CMake's experimental `import std` gate isn't needed. The house lint rules (fetched at build time) aren't run | generic | 0 warnings; 8/8 tests on amd64 and arm64 |
| 0002 P-CSCFs that didn't answer go last | `ims-pdn-up.sh --stopped` runs as `ExecStopPost=`. When imsd exited non-zero after a fresh registration to a discovered P-CSCF, that address is recorded in `/var/lib/imsd/pcscf-bad`, with sequence numbers rather than times (the clock may be wrong early in boot), keeping the last 16. Each bring-up orders the PCO list: unrecorded addresses first, in PCO order, then recorded ones, least recently failed first, so a list where everything fails still cycles. An admin-set `PCSCF=` is never recorded | generic, any carrier | dead first P-CSCF → restart after 120 s → second P-CSCF → REGISTERED |
| 0003 call audio targets | `IMSD_PLAY_TARGET`/`IMSD_REC_TARGET` → `--target`, `IMSD_PLAY_CHANNEL`/`IMSD_REC_CHANNEL` → `--channel-map` for `pw-play`/`pw-record`. Unset: unchanged behaviour | generic | calls |
| 0004 SIGTERM before SIGKILL | as root the helpers run as `sudo -u <user> pw-*`, and sudo can't relay SIGKILL, so killing it left the tool running. Now SIGTERM, then SIGKILL after 1 s | generic **bug fix** | mic released after calls |

The record is per address and survives reboots because the PCO's P-CSCF list
changes from boot to boot. Rotating within one list failed for that reason.

0002 is a shell-level fix. Upstream might prefer the daemon to try the next
P-CSCF itself instead of exiting.

### Debian toolchain notes

`debian/rules`:
- builds with `clang++-22 -stdlib=libc++` everywhere, so the std module and its
  users share one configuration;
- `hardening=+all,-fortify`, because `_FORTIFY_SOURCE` turns glibc's `printf` family into
  internal-linkage inline wrappers, which libc++'s `std` module can't export;
- `override_dh_dwz`: dwz fails on the DWARF clang emits;
- passes `-DIMSD_LIBCXX_MODULES_JSON=/usr/lib/llvm-22/lib/libc++.modules.json`,
  because the multiarch copy of that file contains relative paths that only
  resolve from `/usr/lib/llvm-22/lib`. This also breaks CMake's own
  `import std` detection. **Debian bug to file** (llvm-toolchain-22).

In CMake, only the include paths and libraries come from pkg-config. Its
`-pthread` compile flag would not match the shared `std.pcm`, and clang
refuses to load a mismatched module.

### Before an upload

- `imsd-plasma` doesn't install upstream's `/etc/skel` autostart override (a
  lintian error); its `README.Debian` has the per-account step instead.
- The version is `1.1.0-1`, still `UNRELEASED`; `Forwarded: not-yet` on all
  patches until they're sent.
- Sending 0001 to Catcrafts would make a separate Debian build system unnecessary.
- Rebuilt from `packaging/imsd/` the binaries are byte-identical to the
  `1.1.0-0~fp6test6` packages on the phone; only comments, the changelog and
  the copyright file changed.

## Device configuration for imsd (in fp6-mobian-support)

`imsd.service.d/fp6-audio.conf`:

```
Environment=IMSD_PLAY_TARGET=ec_sink IMSD_REC_TARGET=ec_source
Environment=IMSD_PLAY_CHANNEL=FL IMSD_REC_CHANNEL=FL
Environment=GAIN=1.5
```

- `ec_sink`/`ec_source` are the WebRTC echo canceller's nodes
  ([audio.md](audio.md)). Only call audio goes through them; music doesn't.
- `FL` playback = the top speaker (amplifier L), used as the earpiece. The bottom
  speaker stays silent during calls.
- `FL` capture = the mic's channel. FR of the capture is empty, and a mono downmix
  halved the level. Mono at `GAIN=1.5` measures the same as `GAIN=3` with the downmix.
- Override in `/etc/imsd.env` (`EnvironmentFile=` takes precedence).

## fp6-lte-pin

ModemManager doesn't persist allowed modes, and the modem or the Settings
panel switched them back to 3g/4g/5g once. `fp6-lte-pin.service` (`WantedBy`/`PartOf`
ModemManager) watches ModemManager with `gdbus monitor`. When a modem appears,
changes state or changes its current modes, it re-applies
`mmcli --set-allowed-modes=$FP6_ALLOWED_MODES`:

- default `4g`; configured in `/etc/default/fp6-lte-pin`; empty = do nothing;
- only sets a combination the modem lists as supported;
- at most one successful set a minute, plus one queued recheck, so it can't
  hammer the modem if a set doesn't stick.

Tested on T-Mobile US: switched `2g,3g,4g,5g / 5g` to `allowed: 4g` about 70 s after boot.

**This is a carrier workaround, not device support.** Where 5G SA carries SMS
or VoLTE is fine on 5G, it costs speed for nothing. Upstream, it should be opt-in.
The real fixes are SMS over IP in imsd and 5G SA data in newer ModemManager.

[imsd]: https://forgejo.catcrafts.net/Catcrafts/imsd
