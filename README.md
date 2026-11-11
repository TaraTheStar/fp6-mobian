# Mobian on the Fairphone (Gen. 6)

Kernel packaging, device glue, a Debian package of the imsd VoLTE daemon, and
image recipe changes. With them, Mobian (Debian forky + Phosh) runs as a daily
phone on the Fairphone (Gen. 6) (Qualcomm SM7635 "Milos"). Calls, SMS, MMS and
data work on T-Mobile US over LTE/VoLTE, with full-disk encryption.

This is a community port, not an official Mobian device. Most of the hardware
support comes from other people's work: [milos-mainline], [Catcrafts]
(kernel, audio, imsd), and Mobian's own tooling. This repository connects those
pieces for Debian/Mobian and records what it took.

> **Before you touch a phone, read [docs/reproduce.md](docs/reproduce.md).**
> On the FP6, `fastboot flash boot` erases the modem's NV data (calibration,
> cellular, eSIM), and the `boot` partition carries AVB data that a careless
> `dd` destroys. The install procedure here avoids both. All of it is at your
> own risk, with no warranty (see [Licences](#licences)).

## Why

I've used a PinePhone since the BraveHeart Edition, and my PinePhone Pro is
showing its age. The Fairphone (Gen. 6) is where much of the work on phone
freedom is now happening: the FSF's [LibrePhone](https://librephone.fsf.org/)
project chose it as the device on which to liberate the firmware. And I wanted
to carry my Mobian install over to the new hardware rather than start again.

## Documentation

| Document | What it covers |
|---|---|
| [docs/overview.md](docs/overview.md) | Hardware status matrix, how the pieces fit together |
| [docs/reproduce.md](docs/reproduce.md) | Build everything and install it, with the safety rules |
| [docs/upstreaming.md](docs/upstreaming.md) | Where each piece belongs upstream, in order of effort and value |
| [docs/components/](docs/components/) | One note per component: what it does, why, origin, licence, testing |

## Repository layout

| Path | Contents |
|---|---|
| `docs/` | this documentation |
| `kernel/` | the patch series and the script that rebuilds it from upstream, `milos.config`, packaging changes against Mobian's `qcom-linux` |
| `packaging/fp6-mobian-support/` | the device glue package (Debian source package) |
| `packaging/imsd/` | `debian/` for imsd, imsd-ofono, imsd-plasma |
| `patches/mobian-recipes/` | image recipe changes, as patches against upstream |
| `patches/droid-juicer/` | the FP6 firmware extraction config |
| `tools/` | host-side helpers: boot image decoder, log collector, redaction filter, topology build, kconfig and series tools, build containers |

## Licences

The repository as a whole is **AGPL-3.0-or-later** ([LICENSE](LICENSE)). The
exception is anything meant to be merged somewhere else: it carries the
licence of the project it's going to, so it can be merged without
relicensing.

| Path | Licence | Why |
|---|---|---|
| `docs/`, `tools/`, everything not listed below | AGPL-3.0-or-later | |
| `kernel/` | GPL-2.0 | Linux |
| `packaging/fp6-mobian-support/` (our files) | GPL-3.0-or-later | its parts go to qcom-phone-utils, qcom-support (GPL-3+) and mobian-tweaks |
| `packaging/fp6-mobian-support/` (files from Catcrafts' fp6-img) | GPL-3.0-only (device tweaks), BSD-3-Clause (audio) | as received; listed in its `debian/copyright` |
| `packaging/imsd/` | GPL-3.0-only | imsd's licence; Debian packaging follows upstream |
| `patches/mobian-recipes/` | GPL-3.0 | mobian-recipes |
| `patches/droid-juicer/` | MIT | droid-juicer |

Each file says which applies (SPDX header, or `debian/copyright` for packages).

No firmware, partition images or other vendor files are distributed here.
They are extracted on the phone itself, from the phone's own partitions.

[milos-mainline]: https://github.com/milos-mainline/linux
[Catcrafts]: https://forgejo.catcrafts.net/Catcrafts
