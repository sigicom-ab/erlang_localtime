# db/Makefile: zic/zdump rule can run twice in parallel builds

**File:** `db/Makefile:74-75`
**Severity:** low (build tooling)

## Problem
`$(ZIC) $(ZDUMP): | $(TZCODE)/Makefile` lists two separate targets. When both are missing, make runs the recipe
`$(MAKE) -C $(TZCODE) zic zdump` once per target.

## Scenario
`make -C db -j4 TZ_VERSION=2026f` starts two concurrent sub-makes in `build/tzcode2026f`. They race on the same
object files and binaries, which can leave a corrupt or half-linked `zic`/`zdump`.

## Suggested fix
Use a grouped target (`$(ZIC) $(ZDUMP) &: | $(TZCODE)/Makefile`, GNU make 4.3+), or build both through one stamp
file such as `$(TZCODE)/.tools-stamp`.

## Acceptance
- [ ] `make -C db -j8 tools TZ_VERSION=...` from a clean `build/` runs the tzcode build once.
