# Test suite needs OTP 26 (map comprehensions) without saying so

**File:** `test/localtime_transitions_tests.erl:310` (and nearby lines in `committed_database_sanity_test/0`)
**Severity:** low (compatibility)

## Problem
The tests use map comprehension generators (`K := T <- Map`), which need OTP 26 or later. The library code does
not need OTP 26, and `rebar.config` states no minimum OTP version.

## Scenario
On OTP 24 or 25, `rebar3 eunit` fails with a syntax error when it compiles the test module.

## Suggested fix
Use `maps:to_list/1` / `maps:fold/3` in the tests, or state the minimum OTP version
(`{minimum_otp_vsn, "26"}` in `rebar.config` and a note in the README).

## Acceptance
- [ ] `rebar3 eunit` passes on the oldest supported OTP version, or that version is stated and enforced.
