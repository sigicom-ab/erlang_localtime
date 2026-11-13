%% Tests of the library against the committed include/tz_database.hrl.
%% They need no downloads and always run.
%%
%% Known transitions are real-world facts: they only need to change when a
%% jurisdiction changes a rule for a date that is already covered.  Add a
%% line to known_transitions_test_/0 (or fixed_offsets_test_/0) for every
%% new rule change worth pinning down.

-module(localtime_transitions_tests).

-include_lib("eunit/include/eunit.hrl").
-include("tz_database.hrl").
-include("tz_index.hrl").

%% ===================================================================
%% Known transitions
%% ===================================================================

%% {Zone, first UTC second in the new state, {OffsetBefore, AbbrBefore},
%%  {OffsetAfter, AbbrAfter}}; offsets in minutes east of UTC.
known_transitions_test_() ->
   [transition(Z, U, B, A) || {Z, U, B, A} <-
     [{"Europe/Stockholm",   {{2026,3,29},{1,0,0}},   {60,"CET"},     {120,"CEST"}},
      {"Europe/Stockholm",   {{2026,10,25},{1,0,0}},  {120,"CEST"},   {60,"CET"}},
      {"Europe/Kyiv",        {{2026,3,29},{1,0,0}},   {120,"EET"},    {180,"EEST"}},
      {"Europe/Kyiv",        {{2026,10,25},{1,0,0}},  {180,"EEST"},   {120,"EET"}},
      %% Irish law has negative DST (IST in summer is standard time).
      {"Europe/Dublin",      {{2026,3,29},{1,0,0}},   {0,"GMT"},      {60,"IST"}},
      {"Europe/Dublin",      {{2026,10,25},{1,0,0}},  {60,"IST"},     {0,"GMT"}},
      {"America/New_York",   {{2026,3,8},{7,0,0}},    {-300,"EST"},   {-240,"EDT"}},
      {"America/New_York",   {{2026,11,1},{6,0,0}},   {-240,"EDT"},   {-300,"EST"}},
      %% First Sunday of April / September at 00:00 local.
      {"America/Santiago",   {{2026,4,5},{3,0,0}},    {-180,"-03"},   {-240,"-04"}},
      {"America/Santiago",   {{2026,9,6},{4,0,0}},    {-240,"-04"},   {-180,"-03"}},
      %% Saturday 23:00 / Sunday 00:00 local (01:00 UTC).
      {"America/Nuuk",       {{2026,3,29},{1,0,0}},   {-120,"-02"},   {-60,"-01"}},
      {"America/Nuuk",       {{2026,10,25},{1,0,0}},  {-60,"-01"},    {-120,"-02"}},
      {"Australia/Sydney",   {{2026,4,4},{16,0,0}},   {660,"AEDT"},   {600,"AEST"}},
      {"Australia/Sydney",   {{2026,10,3},{16,0,0}},  {600,"AEST"},   {660,"AEDT"}},
      %% 30-minute DST.
      {"Australia/Lord_Howe",{{2026,4,4},{15,0,0}},   {660,"+11"},    {630,"+1030"}},
      {"Australia/Lord_Howe",{{2026,10,3},{15,30,0}}, {630,"+1030"},  {660,"+11"}},
      {"Africa/Cairo",       {{2026,4,23},{22,0,0}},  {120,"EET"},    {180,"EEST"}},
      {"Africa/Cairo",       {{2026,10,29},{21,0,0}}, {180,"EEST"},   {120,"EET"}},
      {"Asia/Jerusalem",     {{2026,3,27},{0,0,0}},   {120,"IST"},    {180,"IDT"}},
      {"Asia/Jerusalem",     {{2026,10,24},{23,0,0}}, {180,"IDT"},    {120,"IST"}},
      {"Asia/Gaza",          {{2026,3,28},{0,0,0}},   {120,"EET"},    {180,"EEST"}},
      {"Asia/Gaza",          {{2026,10,23},{23,0,0}}, {180,"EEST"},   {120,"EET"}},
      %% 2-hour DST.
      {"Antarctica/Troll",   {{2026,3,29},{1,0,0}},   {0,"+00"},      {120,"+02"}},
      {"Antarctica/Troll",   {{2026,10,25},{1,0,0}},  {120,"+02"},    {0,"+00"}},
      %% Cuba does not fall back on 2026-11-01; next fall back is 2027-11-07.
      {"America/Havana",     {{2026,3,8},{5,0,0}},    {-300,"CST"},   {-240,"CDT"}},
      {"America/Havana",     {{2027,11,7},{5,0,0}},   {-240,"CDT"},   {-300,"CST"}},
      %% Morocco: Ramadan 2026, then permanent +00 from 2026-09-20.
      {"Africa/Casablanca",  {{2026,2,15},{2,0,0}},   {60,"+01"},     {0,"+00"}},
      {"Africa/Casablanca",  {{2026,3,22},{2,0,0}},   {0,"+00"},      {60,"+01"}},
      {"Africa/Casablanca",  {{2026,9,20},{1,0,0}},   {60,"+01"},     {0,"+00"}},
      %% British Columbia: last spring forward, then permanent -07 (MST).
      {"America/Vancouver",  {{2026,3,8},{10,0,0}},   {-480,"PST"},   {-420,"PDT"}},
      {"America/Vancouver",  {{2026,11,1},{9,0,0}},   {-420,"PDT"},   {-420,"MST"}}]].

%% Zones with no transitions from the given instants on.
fixed_offsets_test_() ->
   Year = [{{2026,1,15},{12,0,0}}, {{2026,7,15},{12,0,0}},
           {{2040,1,15},{12,0,0}}, {{2040,7,15},{12,0,0}}],
   [at(Z, U, State) || {Z, Times, State} <-
     [{"America/Coyhaique", Year, {-180,"-03"}},
      {"Asia/Tehran",       Year, {210,"+0330"}},
      %% POSIX sign convention: Etc/GMT+1 is UTC-1.
      {"Etc/GMT+1",         Year, {-60,"-01"}},
      {"Etc/GMT-14",        Year, {840,"+14"}},
      {"Etc/UTC",           Year, {0,"UTC"}},
      {"America/Havana",    [{{2026,11,15},{12,0,0}}, {{2027,1,15},{12,0,0}}], {-240,"CDT"}},
      {"Africa/Casablanca", [{{2027,4,1},{12,0,0}}, {{2040,1,15},{12,0,0}}, {{2040,7,15},{12,0,0}}], {0,"+00"}},
      {"America/Vancouver", [{{2027,1,15},{12,0,0}}, {{2027,7,15},{12,0,0}}, {{2040,1,15},{12,0,0}}], {-420,"MST"}}],
      U <- Times].

%% Sub-minute offsets are rounded (Monrovia -00:44:30 until 1972).
monrovia_rounded_test() ->
   ?assertMatch({-45, {"MMT", _}}, localtime_dst:utc_offset({{1971,1,1},{12,0,0}}, tz("Africa/Monrovia"))),
   ?assertEqual({0, {"GMT", "GMT"}}, localtime_dst:utc_offset({{1973,1,1},{12,0,0}}, tz("Africa/Monrovia"))).

%% Removed upstream; America/Regina replaces it.
east_saskatchewan_removed_test() ->
   ?assertEqual(false, maps:is_key("Canada/East-Saskatchewan", ?tz_database)).

%% America/Santiago around the 2026 transitions (#1).
santiago_dst_test_() ->
   Tz = "America/Santiago",
   Cases = [
      {"Apr 4 2026 12:00 (Sat, before DST end) is UTC-3",   {{2026,4,4},{12, 0,0}}, {{2026,4,4},{15, 0,0}}},
      {"Apr 5 2026 12:00 (Sun, DST end) is UTC-4",          {{2026,4,5},{12, 0,0}}, {{2026,4,5},{16, 0,0}}},
      {"Sep 5 2026 12:00 (Sat, before DST start) is UTC-4", {{2026,9,5},{12, 0,0}}, {{2026,9,5},{16, 0,0}}},
      {"Sep 6 2026 12:00 (Sun, DST start) is UTC-3",        {{2026,9,6},{12, 0,0}}, {{2026,9,6},{15, 0,0}}},
      {"Apr 7 2026 10:30 in range is UTC-4",                {{2026,4,7},{10,30,0}}, {{2026,4,7},{14,30,0}}},
      {"Apr 7 2026 11:00 in range is UTC-4",                {{2026,4,7},{11, 0,0}}, {{2026,4,7},{15, 0,0}}},
      {"Apr 7 2026 12:00 in range is UTC-4",                {{2026,4,7},{12, 0,0}}, {{2026,4,7},{16, 0,0}}},
      {"Apr 7 2026 13:00 in range is UTC-4",                {{2026,4,7},{13, 0,0}}, {{2026,4,7},{17, 0,0}}}
   ],
   [{Desc, [?_assertEqual(Local, localtime:utc_to_local(Utc, Tz)),
            ?_assertEqual(Utc,   localtime:local_to_utc(Local, Tz))]} || {Desc, Local, Utc} <- Cases].

%% -------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

%% Offset and abbreviation on both sides of the transition, utc_to_local,
%% and local_to_utc around the gap (spring forward) or overlap (fall back).
transition(Zone, UtcDT, {OffB, AbbrB}, {OffA, AbbrA}) ->
   U = secs(UtcDT),
   Shift = (OffA - OffB) * 60,
   Local = fun(S, Off) -> dt(S + Off * 60) end,
   LocalChecks =
      if Shift > 0 ->   % local [U+OffB, U+OffA) does not exist
            [?_assertEqual(time_not_exists, localtime:local_to_utc(Local(U, OffB), Zone)),
             ?_assertEqual(dt(U), localtime:local_to_utc(Local(U, OffA), Zone))];
         Shift < 0 ->   % local [U+OffA, U+OffB) happens twice
            [?_assertEqual([dt(U + Shift), dt(U)],
                           lists:sort(localtime:local_to_utc(Local(U, OffA), Zone))),
             ?_assertEqual(dt(U - Shift), localtime:local_to_utc(Local(U, OffB), Zone))];
         true ->
            [?_assertEqual(dt(U), localtime:local_to_utc(Local(U, OffA), Zone))]
      end,
   {lists:flatten(io_lib:format("~s ~p", [Zone, UtcDT])),
    [?_assertMatch({OffB, {AbbrB, _}}, localtime_dst:utc_offset(dt(U - 1), tz(Zone))),
     ?_assertMatch({OffA, {AbbrA, _}}, localtime_dst:utc_offset(dt(U), tz(Zone))),
     ?_assertEqual(Local(U - 1, OffB), localtime:utc_to_local(dt(U - 1), Zone)),
     ?_assertEqual(Local(U, OffA), localtime:utc_to_local(dt(U), Zone)),
     %% Well clear of the transition, local_to_utc inverts utc_to_local.
     ?_assertEqual(dt(U - 3 * 3600), localtime:local_to_utc(Local(U - 3 * 3600, OffB), Zone)),
     ?_assertEqual(dt(U + 3 * 3600), localtime:local_to_utc(Local(U + 3 * 3600, OffA), Zone))
     | LocalChecks]}.

at(Zone, UtcDT, {Off, Abbr}) ->
   {lists:flatten(io_lib:format("~s ~p", [Zone, UtcDT])),
    [?_assertMatch({Off, {Abbr, _}}, localtime_dst:utc_offset(UtcDT, tz(Zone))),
     ?_assertEqual(dt(secs(UtcDT) + Off * 60), localtime:utc_to_local(UtcDT, Zone))]}.

tz(Zone) ->
   {Zone, _, _, _, _, _, _, _, _} = maps:get(Zone, ?tz_database).

secs(DT) -> calendar:datetime_to_gregorian_seconds(DT).
dt(S) -> calendar:gregorian_seconds_to_datetime(S).

%% ===================================================================
%% Rule times outside 0..23 hours
%% ===================================================================

%% Asia/Jerusalem: Friday before last Sunday = day after 4th Thursday, 02:00.
jerusalem_hour_26_test() ->
   Tz = {"T/Jerusalem",{"IST","IST"},{"IDT","IDT"},120,60,{4,thu,mar},{26,0},{last,sun,oct},{2,0}},
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,3,27},{1,59,59}}, Tz)),
   ?assertEqual(time_not_exists, localtime_dst:check({{2026,3,27},{2,0,0}}, Tz)),
   ?assertEqual(is_in_dst,       localtime_dst:check({{2026,3,27},{3,0,0}}, Tz)),
   ?assertEqual(ambiguous_time,  localtime_dst:check({{2026,10,25},{1,30,0}}, Tz)),
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,10,25},{2,0,0}}, Tz)).

%% Asia/Gaza: Saturday 02:00 after the 4th Thursday (50 hours).
gaza_hour_50_test() ->
   Tz = {"T/Gaza",{"EET","EET"},{"EEST","EEST"},120,60,{4,thu,mar},{50,0},{4,thu,oct},{50,0}},
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,3,28},{1,59,59}}, Tz)),
   ?assertEqual(time_not_exists, localtime_dst:check({{2026,3,28},{2,30,0}}, Tz)),
   ?assertEqual(is_in_dst,       localtime_dst:check({{2026,3,28},{3,0,0}}, Tz)),
   %% 4th Thursday of Oct 2026 is the 22nd -> Saturday 24th 02:00 EEST.
   ?assertEqual(is_in_dst,       localtime_dst:check({{2026,10,24},{0,59,59}}, Tz)),
   ?assertEqual(ambiguous_time,  localtime_dst:check({{2026,10,24},{1,0,0}}, Tz)),
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,10,24},{2,0,0}}, Tz)).

%% America/Nuuk: -1:00 on the last Sunday = Saturday 23:00.
nuuk_negative_hour_test() ->
   Tz = {"T/Nuuk",{"-02","-02"},{"-01","-01"},-120,60,{last,sun,mar},{-1,0},{last,sun,oct},{0,0}},
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,3,28},{22,59,59}}, Tz)),
   ?assertEqual(time_not_exists, localtime_dst:check({{2026,3,28},{23,30,0}}, Tz)),
   ?assertEqual(is_in_dst,       localtime_dst:check({{2026,3,29},{0,0,0}}, Tz)),
   ?assertEqual(ambiguous_time,  localtime_dst:check({{2026,10,24},{23,30,0}}, Tz)),
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,10,25},{0,0,0}}, Tz)).

%% America/Santiago: Sun>=2 expressed as first Saturday + 24h.  In 2030
%% September 1st is a Sunday, which a {1,sun,sep} rule gets wrong.
santiago_hour_24_test() ->
   Tz = {"T/Santiago",{"-04","-04"},{"-03","-03"},-240,60,{1,sat,sep},{24,0},{1,sat,apr},{24,0}},
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2030,9,1},{12,0,0}}, Tz)),
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2030,9,7},{23,59,0}}, Tz)),
   ?assertEqual(time_not_exists, localtime_dst:check({{2030,9,8},{0,30,0}}, Tz)),
   ?assertEqual(is_in_dst,       localtime_dst:check({{2030,9,8},{1,0,0}}, Tz)),
   ?assertEqual(ambiguous_time,  localtime_dst:check({{2026,4,4},{23,30,0}}, Tz)),
   ?assertEqual(is_not_in_dst,   localtime_dst:check({{2026,4,5},{0,0,0}}, Tz)).

%% A UTC instant is never ambiguous.
utc_to_local_single_value_test() ->
   ?assertEqual({{2026,10,25},{2,30,0}}, localtime:utc_to_local({{2026,10,25},{0,30,0}}, "Europe/Stockholm")),
   ?assertEqual({{2026,10,25},{2,30,0}}, localtime:utc_to_local({{2026,10,25},{1,30,0}}, "Europe/Stockholm")).

%% America/Winnipeg: CST/CDT history, permanent -05 (EST) from 2026-11-01.
winnipeg_test_() ->
   W = "America/Winnipeg",
   [?_assertEqual({'-',5,0}, localtime:tz_shift({{1975,7,1},{12,0,0}}, W)),
    ?_assertEqual({"CDT","CDT"}, localtime:tz_name({{1975,7,1},{12,0,0}}, W)),
    ?_assertEqual({'-',6,0}, localtime:tz_shift({{2025,1,15},{12,0,0}}, W)),
    ?_assertEqual({"CST","CST"}, localtime:tz_name({{2025,1,15},{12,0,0}}, W)),
    ?_assertEqual({'-',5,0}, localtime:tz_shift({{2025,7,1},{12,0,0}}, W)),
    ?_assertEqual({"CDT","CDT"}, localtime:tz_name({{2025,7,1},{12,0,0}}, W)),
    ?_assertEqual({{2025,1,15},{6,0,0}}, localtime:utc_to_local({{2025,1,15},{12,0,0}}, W)),
    %% Last spring forward.
    ?_assertEqual(time_not_exists, localtime:local_to_utc({{2026,3,8},{2,30,0}}, W)),
    %% No fall back on 2026-11-01: 01:30 is no longer ambiguous.  tzdata
    %% renames CDT to EST at 02:00 local without changing the offset.
    ?_assertEqual({{2026,11,1},{6,30,0}}, localtime:local_to_utc({{2026,11,1},{1,30,0}}, W)),
    ?_assertEqual({"CDT","CDT"}, localtime:tz_name({{2026,11,1},{1,30,0}}, W)),
    ?_assertEqual({"EST","EST"}, localtime:tz_name({{2026,11,1},{2,30,0}}, W)),
    ?_assertEqual({'-',5,0}, localtime:tz_shift({{2026,11,1},{1,30,0}}, W)),
    ?_assertEqual({'-',5,0}, localtime:tz_shift({{2027,7,1},{12,0,0}}, W)),
    ?_assertEqual({"EST","EST"}, localtime:tz_name({{2027,7,1},{12,0,0}}, W)),
    %% Beyond the exception window the footer applies.
    ?_assertEqual({'-',5,0}, localtime:tz_shift({{2050,1,1},{12,0,0}}, W)),
    ?_assertEqual({"EST","EST"}, localtime:tz_name({{2050,1,1},{12,0,0}}, W))].

%% Lookup cost on the zones with the most exception periods.  The threshold
%% is the point at which a binary-searched transition table would be needed.
lookup_benchmark_test() ->
   Zones = ["Asia/Gaza", "America/Santiago", "America/Winnipeg", "Europe/Stockholm"],
   Times = [{{Y, 6, 15}, {12, 0, 0}} || Y <- lists:seq(1970, 2046)],
   N = length(Zones) * length(Times),
   {Us, _} = timer:tc(fun() -> [localtime:utc_to_local(T, Z) || Z <- Zones, T <- Times] end),
   PerCall = Us / N,
   ?debugFmt("utc_to_local: ~.1f us/call over ~b calls", [PerCall, N]),
   ?assert(PerCall < 50).

%% ===================================================================
%% Committed database (always run)
%% ===================================================================

committed_database_sanity_test() ->
   %% Every zone is keyed by its own name.
   ?assertEqual([], [K || K := T <- ?tz_database, element(1, T) =/= K]),
   Names = maps:keys(?tz_database),
   ?assertEqual([], [T || _ := T = {_, {S, _}, D, _, _, _, _, _, _} <- ?tz_database,
                          lists:member($%, S) orelse
                          (D =/= undef andalso lists:member($%, element(1, D)))]),
   %% Every abbreviation is indexed (tz_index.hrl rebuilt after the database).
   Abbrs = lists:usort(lists:append([[S | [element(1, D) || D =/= undef]]
                                     || _ := {_, {S, _}, D, _, _, _, _, _, _} <- ?tz_database])),
   ?assertEqual([], [A || A <- Abbrs, not maps:is_key(A, ?tz_index)]),
   %% A zone name always resolves to itself, even when it is also an
   %% abbreviation ("CET", "UTC", ...).
   ?assertEqual([], [N || N <- Names, localtime:get_timezone(N) =/= N]),
   %% Every exception belongs to a known zone.
   ?assertEqual([], [N || N := _ <- ?tz_exceptions, not maps:is_key(N, ?tz_database)]).

