# Architecture

```
┌─────────────────────┐   ┌──────────────────────┐
│ bin/batteria (CLI)  │   │ bin/Batteria.app     │
│ status/limit/enable │   │ status item + popover│
└─────────┬───────────┘   └──────────┬───────────┘
          │        both use the same headers
          ▼                          ▼
┌────────────────────────────────────────────────┐
│ src/MCLClient.h   facade over PowerUISmart-    │
│                   ChargeClient (dlopen+objc)   │
│ src/BatteryInfo.h IOKit AppleSmartBattery +    │
│                   IOPowerSources telemetry     │
│ src/SMCTemp.h     read-only AppleSMC (TB0T)    │
└────────────────────────────────────────────────┘
```

`MCLClient` is a compile-time facade: the methods are declared on an
`@interface` that exists only as a type for message dispatch; instances are
created at runtime:

```c
static inline MCLClient *MCLMakeClient(NSString *name) {
    dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
    Class cls = objc_getClass("PowerUISmartChargeClient");
    return [[cls alloc] initWithClientName:name];
}
```

## The app

`BatteriaApp.m` is a single-file AppKit app (accessory / `LSUIElement`):

- **Status item** shows battery % and a `+` while charging; refreshed every 5 s.
- **Dashboard** (NSPopover, transient) built programmatically with
  `NSStackView`/`NSGridView`: a custom-drawn battery header, a stats grid,
  the limit slider, feature toggles, a disabled "root required" section.
- **Control loop** every 30 s implements:

```
Sailing   : while plugged and limit ≥ 85:
              at limit  -> set limit-5   (battery drifts down)
              at limit-5 -> restore limit (charges back up)
Heat guard: while charging and temp ≥ threshold:
              limit := next 5% step ≤ current SoC  (stops charging)
            once cooled (thr-2) restore previous limit
```

- preferences live in `NSUserDefaults` (`sailEnabled`, `heatEnabled`,
  `heatThreshold`, `userLimit`); launch-at-login writes
  `~/Library/LaunchAgents/local.batteria.plist`.
- headless modes for testing: `--dump` (state to stdout) and `--uitest`
  (shows and closes the popover automatically).

## Telemetry sources

| Value | Source |
|---|---|
| charge % | `CurrentCapacity` / `MaxCapacity` (AppleSmartBattery) |
| charging state | `IsCharging`, `FullyCharged`, `ExternalConnected` |
| cycles | `CycleCount` |
| health | `AppleRawMaxCapacity` / `DesignCapacity` |
| capacity mAh | `AppleRawCurrentCapacity` / `AppleRawMaxCapacity` |
| time remaining | `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey` |
| power (W) | `abs(Amperage × Voltage) / 1e6` (battery-side, instantaneous) |
| temperature | SMC key `TB0T` (`flt` or `sp78` decoding) |

## Notes on reading SMC

The AppleSMC user client accepts `IOConnectCallStructMethod` with selector 2
(`KERNEL_INDEX_SMC`), command byte 9 (`READ_KEYINFO`) then 5 (`READ_BYTES`).
Data types are space-padded fourcc (`"flt "`, `"sp78"`, `"ui8 "`, …) —
remember to trim before comparing. Reads need no privileges; writes return
`kIOReturnNotPrivileged`.
