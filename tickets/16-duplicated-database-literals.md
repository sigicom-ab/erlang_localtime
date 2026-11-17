# Database literals duplicated across modules and Link names

**File:** `src/localtime.erl:8`, `src/localtime_dst.erl:8` (`-include("tz_database.hrl")`), `include/tz_database.hrl`
**Severity:** low (memory / size)

## Problem
- `tz_database.hrl` (about 17k lines, `?tz_database` and `?tz_exceptions`) is included in both `localtime` and
  `localtime_dst`. Each beam file has its own copy of the large map literals in its literal pool.
- Every Link name has its own copy of its target zone's tuple and full exception list.

## Cost
Load-time memory and beam size are about doubled, and the generated file is much larger than it needs to be.

## Suggested fix
Access the maps from a single module (e.g. only `localtime_dst`, with `localtime` calling a lookup function). Have the
generator emit Links as aliases (a `?tz_links` map, or entries in `tz_index`) that are resolved to the canonical zone
before lookup.

## Acceptance
- [ ] The database literals are compiled into one module only.
- [ ] Links resolve to their target, and the tests still pass for all Link names (`completeness`, zdump oracle).
