# Sensors and cameras

## Sensors

**Kernel:** IIO drivers for all sensors, on I²C/SPI buses owned by the
application processor. Several chip variants come from `catcrafts/`:
ICM-42631 fallback, SPL07-003 in `dps310`, STK36C61 in `stk3310`, the proximity
near level, the magnetometer bus.

**Userspace** (`fp6-mobian-support`, files from Catcrafts' fp6-device-tweaks, GPL-3.0-only):

| File | Why |
|---|---|
| `modules-load.d/fp6-imu.conf` | `inv-icm42600-spi` isn't autoloaded |
| `81-fp6-accel-poll.rules` | `inv_icm42600` registers no IIO trigger but exposes `scan_elements/`. iio-sensor-proxy 3.9 then tags the accelerometer for both buffer and poll mode, tries buffer first, fails, and doesn't fall back. The result: `HasAccelerometer` true, orientation stuck at "undefined". The rule forces poll mode |
| `91-fp6-no-ssc-sensors.rules` | nothing serves Qualcomm's sensor core (SSC) here, but iio-sensor-proxy still tags `fastrpc-adsp` for its libssc drivers. The libssc compass probe then blocks for about 100 s inside sensor discovery. A proximity claim in that window leaves proximity dead, and a second claim crashes the daemon. The rule drops the tags |
| `iio-sensor-proxy.service.d/fp6-restart.conf` | restart on failure (safety net) |

**Upstream:** the two iio-sensor-proxy bugs (no fallback from buffer to poll
mode; the claim race during libssc discovery) are generic and belong in
iio-sensor-proxy. The rules are the workaround until then.

**Tested:** all four sensor chips probe and appear in IIO (ICM-42631,
QMC6308, SPL07-003, STK36C61). Not yet checked one by one: auto-rotate, light
and proximity through `monitor-sensor`, proximity blanking during calls,
compass and barometer readings.

## Cameras

| Camera | Sensor | State |
|---|---|---|
| Main | Sony IMX896 (LYT-700C), C-PHY, DW9784 OIS/AF | streams via libcamera and PipeWire, 720p and 1080p |
| Ultra-wide | OmniVision OV13B10 | streams, same |
| Front | Samsung S5KKD1 (CCI1, address 0x3d) | **no driver anywhere**; the DT only has a comment |

Kernel support is all `catcrafts/` (CAMSS for milos, C-PHY, both sensor
drivers, DW9784, the rotation fix).

**Limits:**
- **One sensor at a time:** both sensors share one CAMSS media device, and
  switching cameras in GNOME Snapshot shows a black screen. Reopening Snapshot
  works. Confirmed: the ultra-wide fails to preroll while the main camera
  streams. Inferred, not confirmed: Snapshot opens the new camera before
  closing the old one. If that's the cause, the fix belongs in Snapshot or the
  PipeWire libcamera plugin.
- **Image quality:** Debian's libcamera 0.7.2 lacks the 16 patches Catcrafts
  carries on the same version: sensor helpers and properties for IMX896 and
  OV13B10, softISP autofocus, an AWB clamp. Without them the ultra-wide is soft
  and auto-exposure is weak. Some of those patches are already upstream merge
  requests by others.
- **Front camera:** a new driver. The FP5's S5KJN1 driver is the closest template.

**Upstream:** libcamera (sensor helpers, softISP AF); Snapshot (close
before open, once the cause is confirmed); Linux (an S5KKD1 driver; posting the `catcrafts/` camera patches).
