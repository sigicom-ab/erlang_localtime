# localtime_dst:check/2 gets DST backwards in historical periods

**File:** `src/localtime_dst.erl:38`
**Severity:** high (correctness, verified)
**Status:** done in `ac3b7ab`.

## Problem
`check/2` returns `is_not_in_dst` only when the offset equals the zone's *current* `Shift`.
For any exception period whose standard offset is not the current one, the result is reversed.

## Reproduction
```erlang
localtime_dst:check({{2020,1,15},{12,0,0}}, "America/Winnipeg").  %% is_in_dst      (winter CST -360, wrong)
localtime_dst:check({{2020,7,15},{12,0,0}}, "America/Winnipeg").  %% is_not_in_dst  (summer CDT -300, wrong)
```
Winnipeg's current rule is permanent -05 (Shift = -300) from 2026-11-01. The same applies to any zone whose
historical standard offset is not its current one (Moscow, Gaza, ...).

## Suggested fix
Have `tz_gen` record each exception period's DST flag (zdump reports `isdst=`). Then classify by that flag,
or by the rule that was in effect at that time, not by comparing against the current `Shift`.

## Acceptance
- [x] The two calls above return `is_not_in_dst` and `is_in_dst`.
- [x] A test pins this down in `test/localtime_transitions_tests.erl`.
