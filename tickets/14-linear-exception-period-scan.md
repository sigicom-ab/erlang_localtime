# Exception period lookups scan the list linearly

**File:** `src/localtime_dst.erl:104-127` (`exception/2`, `find_period/2`, `exception_offsets/2`, `window_offsets/3`)
**Severity:** low (efficiency)

## Problem
The periods are sorted, but `find_period/2` and `window_offsets/3` walk the list from the start on every lookup.
For present-day dates in a zone whose exceptions are all in the past, that means the whole list.
`local_states/2` repeats the walk once per candidate offset.

## Scenario
America/Winnipeg has 114 periods. Every `utc_to_local`/`local_to_utc` call for 2026 scans about 100 tuples, up to
4 times per `local_to_utc`.

## Suggested fix
Have the generator emit each zone's periods as a tuple (or `{StartsTuple, PeriodsTuple}`) and binary-search it.
Alternatively, emit a per-zone index keyed by year. Ticket 08's benchmark table is the baseline.

## Acceptance
- [ ] Lookup cost does not depend on the number of periods (benchmark Winnipeg in 1971 and in 2040).
- [ ] `exception_window_matches_full_scan_test_` and the zdump oracle still pass.
