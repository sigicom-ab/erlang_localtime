# utc_state recomputes the rule transitions for every candidate offset

**File:** `src/localtime_dst.erl:53-70` (`utc_state/2`), `src/localtime_dst.erl:80-86` (`local_states/2`)
**Severity:** low (efficiency)

## Problem
`utc_state/2` builds and sorts the DST transitions for 3 years on every call. `local_states/2` calls it once per
candidate offset (up to 4) for instants at most 26 h apart, so it computes the same transitions up to 4 times.
Ticket 08 already names this as the remaining cost.

## Suggested fix
Compute the sorted transitions once in `local_states/2` (for the years the candidate instants cover) and pass them to
an internal `utc_state/3`. Optionally compute only the year and its neighbour instead of always three years.

## Acceptance
- [ ] `local_offsets/2` benchmark on Europe/Stockholm and America/Santiago improves.
- [ ] Results unchanged (full-scan test and zdump oracle pass).
