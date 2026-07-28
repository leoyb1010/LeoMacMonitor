# Contributing to LeoMacMonitor

Thanks for helping! The single most useful contribution right now is **verifying or fixing
the per-chip temperature sensor keys** — read on.

## Quick start

Requires macOS 14+ on Apple Silicon and the Xcode toolchain. **Always use `xcrun`** (a plain
`swift` from swiftly won't match the SDK and fails with `Failed to build module 'Foundation'`):

```bash
xcrun swift build                 # build everything
xcrun swift run LeoMacMonitor      # the GUI (dashboard + menu bar)
xcrun swift run -q leomac-cli     # data-layer probe (no sudo)
xcrun swift test                  # unit tests (pure value/math logic)
```

No `sudo` is ever required, and **nothing leaves your Mac** — no outbound network calls, no
telemetry. Keep it that way (PRs that phone home, even for "anonymous stats", won't be merged).

## ⭐ Contributing temperature sensor keys (most wanted)

LeoMacMonitor shows real **per-unit** temperatures (E-Core / P-Core / GPU / Memory) by reading
**curated SMC FourCC keys per chip generation**. The keys are near-arbitrary and change every
generation, so they're hand-maintained in
[`Sources/LeoMacMonitorCore/SensorCatalog.swift`](Sources/LeoMacMonitorCore/SensorCatalog.swift).

**Status:** the **M1** table is validated on real hardware (M1 Max). **M2–M5 are adapted from
[Stats](https://github.com/exelban/stats) but NOT yet verified** on-device. If you have an
M2/M3/M4/M5 (especially Pro / Max / Ultra / base variants), please confirm or correct them.

### How to verify your chip (one command)

```bash
xcrun swift run -q leomac-cli --sensors
sysctl hw.model machdep.cpu.brand_string
```

`--sensors` prints, for your detected generation, every curated key with the value it reads
back (or `— (not present)`), then the raw HID sensor list. Example on an M1 Max:

```
=== curated SMC keys — generation: m1 ===
  Tp01  P-Core 1   57.2 C
  Tg05  GPU 1      57.1 C
  ...
  → 18/18 curated keys read back
```

**What to check:**
- Do the **counts** match your chip? (e.g. an 8-GPU-core M3 Pro shouldn't have GPU 1–10.)
- Do values look **plausible** (~30–100 °C under light load), and rise on the right unit when
  you load it? (`yes > /dev/null &` heats CPU; a GPU/LLM load heats GPU.)
- Any key reading `— (not present)` that *should* exist → it's wrong/missing for your model.

### How to fix the table

Open an issue (or PR) titled e.g. **"Sensor keys: M3 Pro"** and paste:
1. the full `--sensors` output, and
2. the `sysctl` line (your exact model + brand string).

To edit it yourself, find your generation in `SensorCatalog.swift` and adjust the
`cpu(...) / gpu(...) / mem(...)` key→name pairs, then:

```bash
xcrun swift test --filter SensorClassificationTests   # catalog-shape tests must still pass
xcrun swift run -q leomac-cli --sensors               # confirm your keys read back
```

Variants need no special-casing — keys absent on a given die simply don't read back and are
skipped, so it's safe to list every key a generation can have.

## Coding conventions

- **English only** in code and all app-facing text (labels, menus, tooltips, units). Design
  docs may be other languages; shipped strings may not.
- **File header** on every source file (name / created / updated / developer / overview / notes).
  Bump `Updated:` when you change a file.
- **Layer separation:** `LeoMacMonitorCore` must not `import SwiftUI` — it's the UI-independent
  data layer shared by the app, the CLI, and tests. Keep private-API calls isolated in
  `CIOReport` behind safe Swift wrappers.
- **Adapted code** (e.g. NeoAsitop, Stats — both MIT) must be credited in the file's Notes.
- Prefer adding a **pure function + a test** over logic buried in a hardware-coupled sampler
  (see `Bottleneck`, `BandwidthSampler.classify`, `BatterySampler.healthPercent` for the pattern).

## Pull requests

- Branch from `main`, keep the diff focused, and make sure `xcrun swift build` and
  `xcrun swift test` both pass.
- Describe what you changed and (for sensor keys) on which exact Mac model you verified it.

This is a private-API app, so it can't ship on the App Store — see the README for why.
