%% Tests for the time zone database generator (db/tz_gen.erl) against the
%% committed include/tz_database.hrl.  Library behaviour is tested in
%% localtime_transitions_tests.erl.
%%
%% These tests use the tz release named in the header of the committed
%% database, and need its tzdata, the zoneinfo compiled from it and the
%% locally built zdump.  Prepare them with `make -C db test` (which also runs
%% the suite).  Without them these tests are skipped.

-module(tz_gen_tests).

-include_lib("eunit/include/eunit.hrl").
-include("tz_database.hrl").

-define(TIMEOUT, 600).
-define(ORACLE_FROM, 2026).
-define(ORACLE_TO, 2030).

%% ===================================================================
%% Generator tests (need downloads)
%% ===================================================================

tz_gen_test_() ->
   case missing_downloads() of
      [] ->
         {setup, fun generate_committed/0,
          fun(Gen) ->
             {timeout, ?TIMEOUT,
              [{"include/tz_database.hrl is up to date", fun() -> up_to_date(Gen) end},
               {"every Zone and Link is present", fun completeness/0},
               {"library agrees with zdump 2026-2030", {timeout, ?TIMEOUT, fun zdump_oracle/0}}]}
          end};
      Missing ->
         {"SKIPPED generator tests, missing: " ++ string:join(Missing, ", ") ++
          " (run `make -C db test`)", fun() -> ok end}
   end.

%% -------------------------------------------------------------------
%% 1. The committed include file is what the generator produces.
%% -------------------------------------------------------------------

up_to_date({Db, Ex}) ->
   ?assertEqual(Db, ?tz_database),
   ?assertEqual(Ex, ?tz_exceptions).

%% -------------------------------------------------------------------
%% 2. Every Zone and Link name in the tzdata sources is present.
%% -------------------------------------------------------------------

completeness() ->
   Names = source_names(filename:join(root(), "db/" ++ tzdata())),
   ?assert(length(Names) > 590),
   ?assertEqual([], [N || N <- Names, not maps:is_key(N, ?tz_database)]).


source_names(Dir) ->
   Files = ["africa", "antarctica", "asia", "australasia", "etcetera", "europe",
            "northamerica", "southamerica", "backward"],
   lists:usort(
     lists:append(
       [[binary_to_list(N) || L <- binary:split(element(2, {ok, _} = file:read_file(filename:join(Dir, F))),
                                                <<"\n">>, [global]),
                              N <- name_of(string:lexemes(hd(binary:split(L, <<"#">>)), " \t"))]
        || F <- Files])).

name_of([<<"Zone">>, N | _]) -> [N];
name_of([<<"Link">>, _, N | _]) -> [N];
name_of(_) -> [].

%% -------------------------------------------------------------------
%% 5. zdump oracle: for every zone and every transition in 2026-2030 the
%%    library (with the committed database) gives zdump's offset and
%%    abbreviation on both sides, and local_to_utc inverts utc_to_local.
%% -------------------------------------------------------------------

zdump_oracle() ->
   Names = maps:keys(?tz_database),
   oracle(Names, ?ORACLE_FROM, ?ORACLE_TO, 100).

oracle(Names, From, To, MinZones) ->
   Transitions = zdump_transitions(Names, From, To),
   ?assert(maps:size(Transitions) > MinZones),
   Failures = lists:append([check_zone(N, maps:get(N, Transitions, []), From, To) || N <- Names]),
   ?assertEqual([], lists:sublist(Failures, 20)).

check_zone(Name, Transitions, From, To) ->
   Tz = maps:get(Name, ?tz_database),
   Samples = [{T - 1, Before} || {T, Before, _} <- Transitions] ++
             [{T, After} || {T, _, After} <- Transitions] ++
             [{T + 3600, After} || {T, _, After} <- Transitions] ++
             monthly_samples(Transitions, Tz, From, To),
   [{Name, calendar:gregorian_seconds_to_datetime(U), Problem}
    || {U, Expected} <- Samples, Problem <- check_sample(Tz, U, Expected)].

%% The database stores whole minutes; sub-minute offsets are rounded.
check_sample(Tz = {Name, _, _, _, _, _, _, _, _}, U, {OffSec, Abbr}) ->
   Off = round(OffSec / 60) * 60,
   Utc = calendar:gregorian_seconds_to_datetime(U),
   Local = calendar:gregorian_seconds_to_datetime(U + Off),
   {GotOff, {GotAbbr, _}} = localtime_dst:utc_offset(Utc, Tz),
   Back = localtime:local_to_utc(Local, Name),
   [{offset, {expected, Off div 60, Abbr}, {got, GotOff, GotAbbr}}
    || {GotOff * 60, GotAbbr} =/= {Off, Abbr}] ++
   [{utc_to_local, Local, localtime:utc_to_local(Utc, Name)}
    || localtime:utc_to_local(Utc, Name) =/= Local] ++
   [{local_to_utc, Local, Back}
    || not (Back =:= Utc orelse (is_list(Back) andalso lists:member(Utc, Back)))].

%% Noon UTC on the 1st of each month, with zdump's state at that time.
monthly_samples(Transitions, {_, {Std, _}, _, StdMin, _, _, _, _, _} = Tz, From, To) ->
   Initial = case Transitions of
                [{_, Before, _} | _] -> Before;
                [] -> fixed_state(Tz, StdMin, Std)
             end,
   [{U, state_at(U, Initial, Transitions)}
    || Y <- lists:seq(From, To), M <- lists:seq(1, 12),
       U <- [calendar:datetime_to_gregorian_seconds({{Y, M, 1}, {12, 0, 0}})]].

%% No transitions in the window: the zone has a fixed offset.
fixed_state(_Tz, StdMin, Std) -> {StdMin * 60, Std}.

state_at(U, Initial, Transitions) ->
   lists:foldl(fun({T, _, After}, _) when T =< U -> After; (_, Acc) -> Acc end,
               Initial, Transitions).

%% #{Name => [{UtcSecs, {OffBefore, AbbrBefore}, {OffAfter, AbbrAfter}}]}
zdump_transitions(Names, From, To) ->
   Dir = filename:join([root(), "db", zoneinfo()]) ++ "/",
   Out = run(zdump(), ["-V", "-c", integer_to_list(From) ++ "," ++ integer_to_list(To + 1)
                       | [Dir ++ N || N <- Names]], root()),
   Lines = [parse_zdump(string:lexemes(L, " ")) || L <- string:split(Out, "\n", all)],
   pair_up([{string:prefix(P, Dir), U, S} || {P, U, S} <- Lines], #{}).

%% "<path> Sun Mar 29 00:59:59 2026 UT = Sun Mar 29 00:59:59 2026 GMT isdst=0 gmtoff=0"
parse_zdump([P, _, Mon, Day, Time, Year, "UT", "=", _, _, _, _, _, Abbr, _, "gmtoff=" ++ Off]) ->
   [H, Mi, S] = [list_to_integer(X) || X <- string:split(Time, ":", all)],
   M = length(lists:takewhile(fun(X) -> X =/= Mon end,
                              ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"])) + 1,
   {P, calendar:datetime_to_gregorian_seconds({{list_to_integer(Year), M, list_to_integer(Day)}, {H, Mi, S}}),
    {list_to_integer(Off), Abbr}};
parse_zdump(_) -> skip.

pair_up([{N, T1, S1}, {N, T2, S2} | Rest], Acc) when T2 =:= T1 + 1 ->
   pair_up(Rest, maps:update_with(N, fun(L) -> L ++ [{T2, S1, S2}] end, [{T2, S1, S2}], Acc));
pair_up([_ | Rest], Acc) -> pair_up(Rest, Acc);
pair_up([], Acc) -> Acc.

%% ===================================================================
%% Downloads and helpers
%% ===================================================================

root() ->
   Src = proplists:get_value(source, ?MODULE:module_info(compile)),
   filename:dirname(filename:dirname(Src)).

%% Paths under db/ for the release the committed database was generated from.
tzdata() -> "tzdata" ++ version().
zoneinfo() -> "build/zoneinfo-" ++ version().
zdump_rel() -> "build/tzcode" ++ version() ++ "/zdump".
zdump() -> filename:join([root(), "db", zdump_rel()]).

missing_downloads() ->
   [P || P <- ["db/" ++ zdump_rel(), "db/" ++ zoneinfo() ++ "/.stamp", "db/" ++ tzdata() ++ "/africa"],
         not filelib:is_regular(filename:join(root(), P))].

%% Regenerate with the version and exception window recorded in the
%% committed header, so the comparison does not depend on today's date.
generate_committed() ->
   {From, To} = committed_window(),
   Db = filename:join(root(), "db"),
   Out = filename:join(Db, "build/test-tz_database-" ++ version() ++ ".hrl"),
   run(os:find_executable("escript"),
       ["tz_gen.erl", "--version", version(), "--tzdata", tzdata(),
        "--zoneinfo", zoneinfo(), "--zdump", zdump_rel(), "-o", Out,
        "--from", integer_to_list(From), "--to", integer_to_list(To)], Db),
   parse_db(Out).

%% "%% version 2026f on 2026-11-12; exceptions cover 1970-2046.  Do not edit."
version() ->
   [V] = committed_header("version (\\S+) on "),
   V.

committed_window() ->
   [F, T] = committed_header("exceptions cover (\\d+)-(\\d+)"),
   {list_to_integer(F), list_to_integer(T)}.

committed_header(Re) ->
   {ok, Bin} = file:read_file(filename:join(root(), "include/tz_database.hrl")),
   {match, Captured} = re:run(Bin, Re, [{capture, all_but_first, list}]),
   Captured.


run(Exe, Args, Cwd) ->
   Port = open_port({spawn_executable, Exe},
                    [{args, Args}, {cd, Cwd}, exit_status, stream, use_stdio, stderr_to_stdout]),
   collect(Port, []).

collect(Port, Acc) ->
   receive
      {Port, {data, D}} -> collect(Port, [D | Acc]);
      {Port, {exit_status, 0}} -> lists:append(lists:reverse(Acc));
      {Port, {exit_status, S}} -> error({command_failed, S, lists:append(lists:reverse(Acc))})
   end.

%% {TzDatabase, TzExceptions} from a tz_database.hrl file.
parse_db(File) ->
   {ok, Bin} = file:read_file(File),
   {define_term(Bin, "tz_database"), define_term(Bin, "tz_exceptions")}.

define_term(Bin, Macro) ->
   case string:split(Bin, "-define(" ++ Macro ++ ",") of
      [_, Rest] ->
         [Body | _] = string:split(Rest, "}).", leading),
         {ok, Toks, _} = erl_scan:string(unicode:characters_to_list(Body) ++ "}."),
         {ok, Term} = erl_parse:parse_term(Toks),
         Term;
      [_] -> #{}
   end.
