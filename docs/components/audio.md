# Audio

**Lives in:** `fp6-mobian-support` (UCM, topology, echo-cancel, imsd drop-in), the kernel
(`catcrafts/` WCD9378 codec patches, sound DT), and droid-juicer (amp config blob).
**Upstream target:** UCM → [alsa-ucm-conf]; topology source → [audioreach-topology];
topology binary → linux-firmware; echo-cancel → milos-support or mobian-tweaks.

## Signal path

- **Playback:** `MultiMedia1` → `SEN_MI2S_RX` → two Awinic AW88261 amplifiers
  (L = top speaker, also the earpiece; R = bottom speaker).
- **Capture:** bottom mic AMIC1 → WCD9378 ADC1 → SoundWire → TX macro DEC0 →
  `TX_CODEC_DMA_TX_3` → `MultiMedia2`.
- The sound card model is `MILOS-Fairphone-Gen6`, set by a `catcrafts/` DT patch. The
  kernel requests `qcom/milos/<model>-tplg.bin`, and UCM matches the same name.
  Catcrafts' image also installs the topology and UCM under the card's older
  name, "Fairphone (Gen. 6)", for kernels that predate the rename; with one
  kernel here, that isn't needed.

## Files

| File | Origin | Licence |
|---|---|---|
| `MILOS-Fairphone-Gen6-tplg.bin` | **built from source** by `tools/build-topology.sh`: Catcrafts' audioreach-topology, branch `fp6` (commit `76e1078`), `cmake && make` with m4 + alsatplg on Debian forky (`tools/Containerfile.tplg`), checked against a pinned sha256. Byte-identical to Catcrafts' shipped binary; not kept in git | BSD-3-Clause |
| UCM `conf.d/milos/MILOS-Fairphone-Gen6.conf` | fp6-img `ucm-milos-fp6.conf` (commit `41f6fb4`), verbatim | BSD-3-Clause |
| UCM `Fairphone/fp6/HiFi.conf` | fp6-img `HiFi.conf` (commit `41f6fb4`), verbatim | BSD-3-Clause |
| `50-fp6-echo-cancel.conf` | fp6-img `50-echo-cancel.conf` (commit `41f6fb4`), modified | BSD-3-Clause |
| `aw88261_acf.bin` | amp tuning, proprietary; extracted by droid-juicer from `vendor` | not distributed |

The UCM's mic section handles two kernel drivers: with the WCD9378 codec driver
the codec controls exist and get set; with Catcrafts' SDCA-class prototype
driver the codec powers up by itself and only the TX macro half applies.

## Echo cancellation for calls

`libpipewire-module-echo-cancel` with WebRTC creates `ec_sink` (call playback; also
the AEC reference) and `ec_source` (mic minus the speaker signal). Changes from
Catcrafts' version:

- **Not the defaults.** Only imsd's call audio is routed through them (imsd
  patch 0003 + `imsd.service.d/fp6-audio.conf`), so music and other
  apps are untouched.
- capture/playback are pinned to the UCM's hardware nodes
  (`alsa_input.platform-sound.HiFi__Mic__source`,
  `alsa_output.platform-sound.HiFi__Speaker__sink`), so it can't loop into itself.
- **No `node.dont-fallback`:** PipeWire loads the module before WirePlumber has
  created the ALSA nodes. With dont-fallback the streams fail ("defined target
  not found") and the module unloads itself.
- Moved from `/etc` to `/usr/share/pipewire/pipewire.conf.d/` as a packaged default.

No WirePlumber fragment: per Catcrafts, `api.alsa.use-acp=false` breaks node
creation, and ACP reads the UCM verbs fine.

## Tested

- Speakers: `speaker-test`, music.
- Mic: a speaker → mic loopback picked up a 1 kHz tone more than 50 dB above
  the noise; `arecord -D hw:0,1`.
- Calls: earpiece only, the far end hears clearly, a slight echo remains.

## Known issues and open ends

- **Amp blob ordering:** the amps request `aw88261_acf.bin` only at card init
  and never retry. On the very first boot, before droid-juicer has run, there's
  no sound card. A late rebind leaves *capture* dead until the next boot
  (WCD9378 TX sequencer). droid-juicer's first-boot reboot covers this.
- Residual echo. Ideas: the WebRTC `extended_filter`/`delay_agnostic` options,
  the amplifier's `receiver` profile during calls, a lower call volume.
- No earpiece/speaker switching in calls yet: the call always uses the top
  speaker as the earpiece.

[alsa-ucm-conf]: https://github.com/alsa-project/alsa-ucm-conf
[audioreach-topology]: https://github.com/linux-msm/audioreach-topology
