# Tools

Host-side helpers, mostly read-only analysis. Python tools run with `python3 -I`.

## Phone

| Tool | What |
|---|---|
| `fp6-build.sh` | build everything on the host: checks the host, then the kernel, imsd, fp6-mobian-support and the image, in one work directory. Resumes after a failure. See [../reproduce.md](../reproduce.md#1-build) |
| `fp6-phone.sh` | the checks around the install, read-only on partitions: back up the NV partitions and `boot_a` and verify the copy, check the AVB data and image size before writing `boot`, the NV check after the install, the first-boot checks. The writes themselves stay manual |
| `bootimg-info.py` | decode an Android boot image header (v0–v2) with no external tools: sizes, addresses, page size, os_version and patch level, cmdline, DTB magic |
| `fp6-collect.sh` | run on the phone as root: collect logs and state (journal, dmesg, remoteprocs, firmware status, sound, modem, sensors, cameras, power) into a tarball. Read-only. **The output contains device identifiers**; review it before sharing |
| `redact.sh` | `sed` filter that masks identifiers in command output: phone numbers, IMSI/ICCID/IMEI/EID fields, SIP/tel URIs, MAC addresses, serial fields, global IPv6 prefixes, and any run of 7+ digits. Errs on the side of masking. Install it on the phone too, and pipe output through it on both ends before pasting logs anywhere |

## Kernel series and config

| Tool | What |
|---|---|
| `export-catcrafts-series.sh` | linearize a merge-based tree into an ordered patch series and prove the result matches the merged tree |
| `replicate-graph.py` | rebuild a forge's commit range, merges included, in a local repo from per-commit patches and merge diffs |
| `catcrafts-order.py` | topological order of the non-merge commits of such a range |
| `resolve.py`, `splice-ref.py` | resolve conflict blocks during the rebase: pick a side, or splice the matching region from the reference tree (used for the re-placed DTS hunks) |
| `run-olddefconfig.sh` | resolve Mobian's layered kconfig fragments with `olddefconfig` in a network-less container, with the source tree mounted read-only |
| `cfgdiff.py` | classify a fragment's lines against the lower layers: redundant, override, new |
| `fragcheck.py` | requested vs. resolved symbols; diff against a reference config |
| `kdefault.py` | whether each `CONFIG_` symbol exists in a kernel tree or is added by a patch directory |
| `dt-driver-check.py` | map every DT compatible in the FP6/Milos DTS to its driver's Kconfig symbol |
| `check-debs.sh` | inspect built kernel debs: metadata, DTB, key modules, a fragment check against the config actually used and a reference config |

`kernel/regen.sh` and `kernel/make-fixups.sh` rebuild the series from upstream;
see [kernel.md](kernel.md#rebuilding-the-series-from-upstream).

## Audio

| Tool | What |
|---|---|
| `build-topology.sh` | build the FP6 AudioReach topology from Catcrafts' audioreach-topology at a pinned commit, in a container without network, and check it against a pinned sha256 |

## Build containers

All Debian forky:

| File | For |
|---|---|
| `Containerfile.debbuild` | cross-building the kernel package (gcc, rustc, bindgen) |
| `Containerfile.imsd` | imsd (clang/libc++ 22, CMake, ninja), run as arm64 under qemu |
| `Containerfile.debos` | the image (debos + extras) |
| `Containerfile.kconfig` | `olddefconfig` only |
| `Containerfile.tplg` | AudioReach topology (m4, alsatplg) |

## Privacy when testing a phone

A phone under test leaks identifiers in ordinary logs: the IMSI and phone number in
ModemManager and imsd, SIP identities in IMS traces, the IMEI, the eUICC EID,
serial numbers, MAC addresses, WiFi network names. When you share logs or work
with someone else on a device:
- don't run identity queries (`qmicli --dms-get-ids`, `mmcli` SIM details,
  `--uim-get-card-status`) unless you need them;
- never share an imsd `DUMP_SIP=1` trace;
- pipe everything through `redact.sh`, on the phone and again on the host;
- keep NV backups, partition dumps and built images private.
