# local_offsets/2 recomputes exception offsets on every call

**File:** `src/localtime_dst.erl:80-86` (`local_states/2`), `src/localtime_dst.erl:113-127` (`exception_offsets/2`)
**Severity:** low (efficiency)
**Status:** fixed (2026-11-16).

## Problem
Every `local_to_utc`, `tz_name`, `tz_shift` and `check` call rebuilt and usorted the full list of exception
offsets for the zone. It then called `utc_state/2` once per distinct candidate. If no exception period contained
the time, each `utc_state/2` call calculated the DST transitions for 3 years.

Data: 414 zones have exception periods. The maximum is 114 periods (America/Winnipeg). The maximum is 4 distinct
candidates (Australia/Lord_Howe, Europe/Vilnius).

## Fix
`exception_offsets/2` now takes the local time. It returns only the offsets of the periods that overlap
`[Local - 15 h, Local + 13 h]`. UTC offsets are between -12 h and +14 h, plus 1 h margin.
`window_offsets/3` stops at the first period that starts after the window. The data format and `tz_gen` did not change.

A generated `?tz_exception_offsets` map would remove only the list cost. The extra `utc_state/2` calls would stay.

## Result
Time per `local_offsets/2` call at 2020-06-15 12:00 local, compiled modules, OTP 26. "Old" is the code from `HEAD`
before the fix.

| Zone | Old | New |
|---|---|---|
| America/Winnipeg | 3.21 µs | 1.47 µs |
| Australia/Lord_Howe | 7.21 µs | 3.81 µs |
| Europe/Vilnius | 8.46 µs | 4.45 µs |
| Europe/Stockholm | 4.73 µs | 4.52 µs |
| America/Santiago | 5.06 µs | 4.05 µs |
| Asia/Gaza | 4.64 µs | 3.80 µs |
| Africa/Casablanca | 1.83 µs | 1.47 µs |

Equivalence: old and new `local_offsets/2` gave the same result for every sample in a scan from 1970 to 2046
(step 43 min) in all 7 zones in the table. There were 0 differences. The scan used a throwaway script, not a
committed test.

The remaining cost is the extra `utc_state/2` calls. A later ticket can address this.

## Acceptance
- [x] Benchmark shows a gain. It measured `local_offsets/2`, which is the part of `local_to_utc/2` that changed.
- [x] `make -C db test` (zdump oracle) and `rebar3 eunit` pass. 375 tests, 0 failures.
- [x] Tests in `test/localtime_transitions_tests.erl` cover local times near period edges:
      `exception_period_edges_test_/0` (Lord_Howe, Vilnius) and `exception_window_matches_full_scan_test_/0`
      (full-scan comparison around every period edge in all 414 zones that have exception periods).
      The full-scan test takes approximately 9 s.
