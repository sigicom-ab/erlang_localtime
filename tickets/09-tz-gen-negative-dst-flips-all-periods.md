# tz_gen inverts isdst for every exception period of a negative-DST zone

**File:** `db/tz_gen.erl:122` (`convert_zone/5`, `negative_dst/1`, `exception_term/2`)
**Severity:** medium (correctness of the DST flag)
**Status:** fixed (2026-11-17).

## Problem
`negative_dst(Posix)` depends only on the zone's current footer. When it is true, the generator inverts zdump's
isdst flag for every exception period of the zone. That includes periods from before the zone used negative DST.

## Scenario
Europe/Dublin from 1970-01-01 to 1971-10-31 used IST as all-year standard time (zdump isdst=0). The period is emitted
with `IsDst = true`, so `localtime_dst:check({{1970,1,15},{12,0,0}}, "Europe/Dublin")` returns `is_in_dst` for a
winter date.

## Suggested fix
Invert the flag only for periods where the zone actually used negative DST. For example, invert a period only when
its offset is the larger of the two offsets of the negative rule in effect at the time, or check zdump's isdst
against the period's offset relative to the neighbouring standard offset. If the 1970-71 Dublin flag is meant to be
`true`, document that and pin it with a test.

## Acceptance
- [x] Decide on and document the intended DST flag for Dublin 1970-1971.
- [x] A test in `test/localtime_transitions_tests.erl` pins `check/2` for Dublin in Jan 1970 and in Jan 1980.

## Fix
Decision: from 1968-10-27 to 1971-10-31 Ireland kept IST all year as standard time (zdump isdst=0, no negative
DST yet), so that period is **not** daylight time.

`db/tz_gen.erl`: `exception_term/2` no longer inverts every flag. The new `dst_flags/2` does the conversion per
zdump state, and only for zones whose footer has negative DST:
- an isdst=1 state with a lower offset than an adjacent isdst=0 state (winter GMT) becomes `false`;
- an isdst=0 state with such a negative pair on **both** sides (summer IST) becomes `true`;
- every other state keeps zdump's flag.

So that the first state in the window has a known previous neighbour, zdump now reads `?CONTEXT_YEARS` (5) years
before the window. The extra transitions are used only for classification. `clip_timeline/2` cuts the timeline to
the window as before, so window behaviour (including an empty timeline meaning "footer exact") is unchanged.

Regenerated `include/tz_database.hrl` (same version, date and window). The only change is 3 periods each in
`Europe/Dublin` and `Eire` (1970-01-01 .. 1971-10-31 IST: `true` -> `false`). `tz_index.hrl` is unchanged.
`make -C db test` passes: 380 tests, 0 failures, including "include/tz_database.hrl is up to date" and the zdump
oracle.

## Remaining
Summer 1970 and summer 1971 in Dublin still report `is_in_dst`. In those months the yearly rule (IST = daylight)
agrees with zdump on offset and abbreviation, so no exception is emitted and the rule's flag is used. Ticket 10
fixes that.
