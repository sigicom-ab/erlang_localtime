# db/Makefile: FORCE=1 / TZ_VERSION do not force regeneration

**File:** `db/Makefile:59-61`
**Severity:** high (build tooling)
**Status:** fixed.

## Problem
`$(OUT)` is an ordinary file target whose prerequisites are only `tz_gen.erl`, `$(ZONEINFO)/.stamp` and `$(ZDUMP)`.
`FORCE=1` only skips the "already at latest" check; it does not make make rebuild the target.

## Reproduction
1. `make -C db test` (this builds `build/zoneinfo-2026f/.stamp`)
2. Touch or check out `include/tz_database.hrl` so it is newer than the stamp
3. `make -C db FORCE=1` prints "nothing to be done"; nothing is regenerated

## Suggested fix
Add a phony FORCE prerequisite to `$(OUT)` when `FORCE` is set, or call `$(MAKE) -B generate ...`.

## Acceptance
- [x] `make -C db FORCE=1` always rewrites `include/tz_database.hrl`.
- [x] `make -C db TZ_VERSION=<other release>` regenerates, also when the output is newer than its prerequisites.

## Fix
`$(OUT)` is in `.PHONY` (`db/Makefile:37`). The `generate` target now always rewrites the file.
The `all` target still decides whether to call `generate`, so `make -C db` does nothing when the database is at
the latest release.
