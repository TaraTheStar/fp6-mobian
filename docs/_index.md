# Mobian on the Fairphone (Gen. 6)

Debian forky and Phosh as a daily phone on the Fairphone (Gen. 6): calls, SMS,
MMS and data over LTE/VoLTE, with full-disk encryption.

> **Before you touch a phone, read [the install page](reproduce.md).** On the
> FP6, `fastboot flash boot` erases the modem's NV data (calibration, cellular,
> eSIM), and the `boot` partition carries AVB data that a careless `dd`
> destroys. The install procedure avoids both. All of it is at your own risk,
> with no warranty.

This is a community port, not an official Mobian device. It covers kernel
packaging, device glue, a Debian package of the imsd VoLTE daemon, and changes
to the image recipes for the Qualcomm SM7635 "Milos". It's tested on T-Mobile
US. Most of the hardware support is other people's work:
[milos-mainline](https://github.com/milos-mainline/linux),
[Catcrafts](https://forgejo.catcrafts.net/Catcrafts) (kernel, audio, imsd),
and Mobian's own tooling. This project connects those pieces for Debian and
records what it took.

## Where to start

| I want to… | Read |
|---|---|
| See what works and what doesn't | [Overview](overview.md) |
| Install it on my phone | [Install](reproduce.md) |
| Understand one piece: kernel, boot, modem, audio… | [Components](components/) |
| Help get it into Debian, Mobian and upstream | [Upstreaming](upstreaming.md) |
| Read the patches and packaging | [Source on GitHub](https://github.com/TaraTheStar/fp6-mobian) |
| Know why this exists | [Why, in the README](https://github.com/TaraTheStar/fp6-mobian#why) |

## Licence

The repository is AGPL-3.0-or-later. Anything meant to be merged elsewhere
carries the licence of the project it's going to; the
[README](https://github.com/TaraTheStar/fp6-mobian#licences) has the table. No
firmware, partition images or other vendor files are distributed: they are
extracted on the phone itself, from its own partitions.
