# Reverse-engineering methodology

Goal: understand how a commercial macOS battery utility performs charge limiting
on macOS 27, and rebuild the capability from scratch. Nothing from the analysed
binary is redistributed — this document describes the *process*.

## 1. Static analysis

- Disassembled the target app bundle with **Hopper**, driven from its CLI so the
  whole workflow stayed scriptable (snapshot the binary once, then decompile
  individual procedures).
- Mapped the Objective-C side (class list, selectors, string references) and the
  embedded Swift side (name-mangled symbols).
- Key insight from a string/data-table sweep: the utility picks one of several
  backends depending on the OS version and machine (legacy SMC keys vs a new
  mechanism) — the same SMC keys it uses on older systems do **not exist** on
  this machine, which pointed to a different control path.

## 2. Dynamic verification

Static hypotheses were validated with small probe programs (all in `tools/`):

1. **API discovery** — `dlopen` the private framework and enumerate the class
   with `class_copyMethodList`, printing selectors and type encodings
   (`tools/powerui_methods.m`). This reveals much more than the handful of calls
   the target app uses.
2. **Setter/read-back matrices** — for every interesting setter, apply a value
   and re-read state, capturing `NSError` domain/code. This is how the
   "80–100 only" rule and error 4 were pinned down, and how the
   set-100-implies-disable semantics were found.
3. **Selector hygiene** — Objective-C selectors include their colons:
   `enableMCL:` works, `enableMCL` does not exist. Type encodings (`B24@0:8^@16`)
   give exact signatures without headers.
4. **Handler vs sync variants** — started with `*WithHandler:` callbacks; the
   handlers never fired. Synchronous `error:` variants are reliable.
5. **SMC probing** — a read-only AppleSMC client confirmed which legacy keys are
   gone, and a same-value write test established the privilege requirement
   without changing any hardware state.
6. **Watchdog observation** — with the analysed app running, external limit
   changes were reverted within seconds; with it (and its helper) fully
   terminated, changes persisted. A/B tests across processes isolated the
   behaviour.

## 3. Reimplementation

- Clean-room ObjC code in `src/`, using only findings from steps 1–2.
- Every interaction re-tested from the new binaries (`docs/charge-control.md`).
- Feature loop (Sailing / Heat guard) built on top of the verified primitives,
  respecting the platform constraint that targets below 80% are impossible
  without a root helper.

## 4. Lessons worth sharing

- Prefer runtime introspection over guessing private APIs: `class_copyMethodList`
  gives the full surface, and encodings avoid calling-convention bugs.
- Always verify against live state with error-domain capture; private APIs fail
  silently or with cryptic codes.
- Distinguish "cannot do it because of permissions" from "cannot do it at all"
  (SMC read vs write) — it decides the whole architecture.
- Document constraints (like "80–100 only") as first-class facts: they are the
  most valuable output of the study.
