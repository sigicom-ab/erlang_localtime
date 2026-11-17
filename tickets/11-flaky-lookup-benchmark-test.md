# lookup_benchmark_test asserts wall-clock time in the normal suite

**File:** `test/localtime_transitions_tests.erl:302`
**Severity:** medium (flaky CI)

## Problem
`lookup_benchmark_test/0` fails if `utc_to_local/2` takes 50 µs per call or more. Timing depends on the machine and
its load.

## Scenario
`rebar3 eunit` on a loaded CI runner, under `rebar3 cover`, or on a slow machine goes over 50 µs. `make check` then
fails although the code is correct.

## Suggested fix
Keep the `?debugFmt` output and drop the assertion, or make it much looser. Alternatively, run the assertion only
when an environment variable is set (e.g. `LOCALTIME_BENCH=1`).

## Acceptance
- [ ] `rebar3 cover` / `rebar3 eunit --cover` pass reliably.
- [ ] The benchmark number is still printed.
