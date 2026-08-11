# Spike results — desaturation (2026-08-11, macOS 26.5.2 / Xcode 26.2)

Two prototypes, each: ramp effect in, hold, ramp out, across all displays.

## A — private CABackdropLayer + CAFilter(colorSaturate)  ← WINNER

- `spike/a-backdrop/` — run: `./proto-a [rampDown] [hold] [rampUp]`
- True gradual desaturation. Smooth ramp on all 3 displays, no flicker.
- `CABackdropLayer` and `CAFilter` both resolve via `NSClassFromString`; `windowServerAware` settable.
- Risk: private API, may break in a future macOS release → keep B as fallback backend.

## B — public overlay window + gamma contrast reduction

- `spike/b-overlay/` — run: `./proto-b [rampIn] [hold] [rampOut]`
- Works, fully public API, but reads as a gray wash rather than draining color.
  Judged clearly worse than A by eye.
- Gamma changes auto-revert on process exit (good safety property) and are
  invisible in screenshots/recordings (applied at scan-out).

## Decision

`Desaturating` protocol with two backends: `BackdropDesaturator` (primary, A),
`OverlayDesaturator` (fallback, B). Runtime-detect A's private classes; fall back to B
if they ever stop resolving.
