# local_offsets/2 recomputes exception offsets on every call

**File:** `src/localtime_dst.erl:101` (`local_offsets/2`, `exception_offsets/1`)
**Severity:** low (efficiency)

## Problem
Every `local_to_utc`, `tz_name`, `tz_shift` and `check` call rebuilds and usorts the full list of exception
offsets for the zone. It then calls `utc_offset/2` once per candidate, and each of those calls scans the exception
list linearly again. For zones with many periods (for example Africa/Casablanca, with Ramadan periods to 2046),
that is about 150 tuples walked and sorted several times per call.

## Suggested fix
Have `tz_gen` emit the distinct offsets per zone once (for example a `?tz_exception_offsets` map, or a field
alongside the periods). Look them up with `maps:get` instead of recomputing them.
