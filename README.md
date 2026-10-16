# Batteria

A menu bar app + CLI to control the **native battery charge limit** on modern macOS
(26/27 "Tahoe") through the private `PowerUISmartChargeClient` API — the same
mechanism the system uses for its built-in charge limiting.

Built as an **independent reverse-engineering study & clean-room reimplementation**:
the behaviour was discovered by analysing a commercially licensed third-party
battery utility with disassembly tooling, then reimplemented from scratch, and
every API interaction was verified empirically on real hardware.

> **Disclaimer** — Educational / research project. Not affiliated with, endorsed by,
> or derived from the source code of AlDente or AppHouseKitchen. No proprietary code,
> assets or decompiled output from any third-party app is included in this repository.
> Uses undocumented Apple private frameworks: not suitable for the App Store,
> use at your own risk.

## Features

**CLI (`bin/batteria`)**

```
batteria status        # battery state + charge limit
batteria limits        # available limits (80, 85, 90, 95, 100)
batteria limit 80      # set + enable the charge limit
batteria enable        # re-enable the current limit
batteria disable       # disable the limit (charges to 100)
batteria pause         # temporarily charge to 100%
batteria watch         # live monitoring
```

**Menu bar app (`bin/Batteria.app`)** — click the icon for a dashboard:

- battery art with percentage, state and time remaining
- stats: cycle count, health, capacity (mAh), SMC battery temperature, power (W)
- charge limit slider (80–100%) + "keep limit active" toggle
- one-shot "charge to 100%" top-up
- **Sailing Mode**: cycles the battery between `limit-5%` and `limit` while plugged
  (requires a limit ≥ 85% — the native limiter refuses targets below 80)
- **Heat Protection**: above a configured temperature, stops charging by lowering
  the limit to the next step below the current charge
- **Apple Optimized Charging (OBC)** on/off toggle
- launch at login
- the dashboard flags features that would require a privileged (root) helper:
  limits below 80%, calibration, discharge, sleep-when-closed

## How it works

| Piece | Technique |
|---|---|
| Charge limit | `dlopen` of `/System/Library/PrivateFrameworks/PowerUI.framework`, class `PowerUISmartChargeClient` (`setMCLLimit:error:`, `enableMCL:`, `disableMCL:`, `temporarilyEnableCharging:`, `isMCLCurrentlyEnabled:`, …) |
| Battery data | IOKit `AppleSmartBattery` + `IOPowerSources` |
| Battery temperature | read-only AppleSMC (`TB0T`, `flt`/`sp78` decoding) |
| Charting/limits engine | plain AppKit (NSPopover dashboard, 30 s control loop) |

Notable findings documented in [`docs/`](docs/):

- on macOS 27 the legacy SMC charge-control keys (`CH0B`, `CH0C`, `CH0I`, `BCLM`)
  **no longer exist**; charge control moved to the PowerUI MCL daemon
- MCL accepts only 80/85/90/95/100; values below 80 are rejected with
  `PowerUISmartChargingErrorDomain` error 4 — even through the undocumented
  `temporarilyOverrideMCLTargetSoC:` path
- SMC **writes** require root (`kIOReturnNotPrivileged`), SMC reads don't
- the `*WithHandler:` variants of MCL calls never invoke their handler; the
  synchronous variants work

## Requirements

- Apple Silicon Mac, macOS 26.4+ (developed on macOS 27)
- Xcode Command Line Tools (`clang`)

## Build

```bash
./build.sh          # -> bin/batteria (CLI) + bin/Batteria.app (menu bar)
open bin/Batteria.app
```

## Project layout

```
src/batteria.m        CLI: status/limits/limit/enable/disable/pause/watch
src/BatteriaApp.m     menu bar app + dashboard (AppKit)
src/MCLClient.h       facade over the private PowerUISmartChargeClient class
src/BatteryInfo.h     IOKit battery telemetry helpers
src/SMCTemp.h         read-only SMC battery temperature
tools/                small stand-alone probes used during the study
docs/                 technical notes (charge control, methodology)
```

## Methodology

The original utility was disassembled with **Hopper** (scripted via its CLI),
its Objective-C and Swift components were mapped, and candidate private APIs
were then exercised against the live system with small probe programs
(see `tools/`): method list introspection via the Objective-C runtime,
selector/type-encoding dumps, set/read-back matrices, error-domain capture.
Every claim in `docs/` was reproduced on the actual machine.

No decompiled output, strings dumps, or assets from the analysed app are
redistributed here — only original code and factual notes.

## License

MIT — see [LICENSE](LICENSE).
