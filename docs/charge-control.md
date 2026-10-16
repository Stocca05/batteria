# Charge control on macOS 26/27 — findings

All findings below were reproduced empirically on an Apple Silicon Mac running
macOS 27 (Tahoe), and cross-checked against a disassembly study of a commercial
battery utility.

## The old SMC keys are gone

The historically documented SMC charge-control keys — `CH0B`, `CH0C`, `CH0I`,
`BCLM`, `BFCL`, `ACEN`, `CHWA` — **do not exist anymore** on this generation.
A read-only probe over the AppleSMC user client returns "key not found" for all
of them. `CHIE` (`hex_`, 1 byte) and `CHTE` (`ui32`) exist but their write
semantics are undocumented, and SMC writes are root-only anyway:

```
writeKey("CHIE", same value) -> kIOReturnNotPrivileged (0xE00002C1)
```

## The native mechanism: PowerUI MCL

macOS now performs charge limiting in a userspace daemon, reachable through the
private `PowerUI` framework:

```
/System/Library/PrivateFrameworks/PowerUI.framework
class PowerUISmartChargeClient   (initWithClientName:)
```

Relevant methods (Objective-C type encodings from the live runtime):

| Selector | Encoding | Notes |
|---|---|---|
| `setMCLLimit:error:` | `B28@0:8C16^@20` | set target % |
| `getMCLLimitWithError:` | `C24@0:8^@16` | read target % |
| `isMCLCurrentlyEnabled:` | `Q24@0:8^@16` | 0/1; **sync variant works** |
| `enableMCL:` / `disableMCL:` | `B24@0:8^@16` | disable ⇒ target 100, enabled=0 |
| `temporarilyEnableCharging:` | `B24@0:8^@16` | one-shot top-up to 100 |
| `temporarilyDisableMCL:` | `B24@0:8^@16` | |
| `temporarilyOverrideMCLTargetSoC:error:` | `B28@0:8C16^@20` | **rejects < 80 too** |
| `availableChargeLimitsWithError:` | | returns 80, 85, 90, 95, 100 |
| `enableSmartCharging:` / `disableSmartCharging:` | | Apple optimized charging (OBC) |
| `isSmartChargingCurrentlyEnabled:` | `Q24@0:8^@16` | |
| `status` | `@16@0:8` | dictionary: checkpoints, OBC predictions, timeline |

### Verified semantics

- setting the limit **enables** the feature implicitly; setting `100` turns
  `isMCLCurrentlyEnabled` back to 0
- `enableMCL:` alone re-applies the last stored target
- values below 80 are refused:

```
setMCLLimit(75)  -> PowerUISmartChargingErrorDomain error 4
temporarilyOverrideMCLTargetSoC(75) -> error 4 as well
```

- the `*WithHandler:` variants exist for nearly every API but their handlers
  never fire; use the synchronous `error:` variants
- all of this works **without root** and without any entitlement, from a plain
  signed-at-build-time CLI binary
- state persists while no client process is running; a third-party watcher
  process can still overwrite it (the analysed utility re-applies its own
  configuration within a few seconds while it runs)

### Capability checks

`isMCLSupported` / `isOBCSupported` / `isDEoCSupported` report per-machine
support (DEoC is unsupported on the test machine). There is also a documented
OS gate inside the utility: PowerUI paths require macOS 26 or newer.

## What still requires root

- **limits below 80%** (SMC path; write denied for non-root)
- **discharge / calibration** (need charging to be stopped at the SMC level)
- **sleep-when-closed** (`IOPMrootDomain` user client, selector 0xC)
- any SMC write

A privileged helper (LaunchDaemon, installed once with admin rights) would be
required — the same architecture the analysed utility uses.
