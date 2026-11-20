#!/usr/bin/env escript
%% -*- erlang -*-
%%! -noshell
%%
%% Generates include/tz_database.hrl for erlang_localtime from a zic-compiled
%% IANA time zone database.
%%
%% For every Zone and Link name in the tzdata sources, the POSIX TZ string
%% stored in the footer of the compiled TZif file is parsed and converted to
%% one erlang_localtime tuple (see the header written by header/6).  Each
%% zone is then cross-checked against zdump over a window of years; wherever
%% the single yearly rule does not describe the zone (history before the
%% current rule, Morocco's Ramadan suspensions, ...), the deviating periods
%% are emitted as explicit exceptions in ?tz_exceptions.
%%
%% Usage:
%%   escript tz_gen.erl --tzdata DIR --zoneinfo DIR --zdump PATH
%%                      [--version V] [--from YEAR] [--to YEAR]
%%                      [--date YYYY-MM-DD] [-o FILE]
%%
%% The window defaults to 1970 .. (year of --date, default today) + 20.
%%
%% The functions parse_posix_tz/1, footer_to_tuple/1 and the timeline helpers
%% are exported for the tests in test/tz_gen_tests.erl.

-module(tz_gen).
-mode(compile).

-export([main/1, generate/1, zone_names/1, read_footer/1, parse_posix_tz/1,
         posix_to_tuple/1, rule_transitions/3, format_tuple/1]).

-define(SOURCES, ["africa", "antarctica", "asia", "australasia", "etcetera",
                  "europe", "northamerica", "southamerica", "backward"]).
-define(DEFAULT_FROM, 1970).   % results before this year are unsupported
-define(DEFAULT_SPAN, 20).     % exceptions run to generation year + span

%% ===================================================================
%% Command line
%% ===================================================================

main(Args) ->
    try
        Opts = parse_args(Args, #{}),
        {Text, Problems} = generate(Opts),
        case maps:get(out, Opts, undefined) of
            undefined -> io:put_chars(Text);
            Out -> ok = file:write_file(Out, Text)
        end,
        [io:format(standard_error, "tz_gen: ~ts~n", [P]) || P <- Problems],
        halt(0)
    catch
        throw:{usage, Msg} ->
            io:format(standard_error, "tz_gen: ~ts~n", [Msg]),
            halt(2);
        Class:Reason:Stack ->
            io:format(standard_error, "tz_gen: ~p:~p~n~p~n", [Class, Reason, Stack]),
            halt(1)
    end.

parse_args([], Opts) ->
    [maps:is_key(K, Opts) orelse throw({usage, "missing --" ++ atom_to_list(K)})
     || K <- [tzdata, zoneinfo, zdump]],
    Opts;
parse_args(["--tzdata", D | T], O)   -> parse_args(T, O#{tzdata => D});
parse_args(["--zoneinfo", D | T], O) -> parse_args(T, O#{zoneinfo => D});
parse_args(["--zdump", P | T], O)    -> parse_args(T, O#{zdump => P});
parse_args(["--version", V | T], O)  -> parse_args(T, O#{version => V});
parse_args(["--from", Y | T], O)     -> parse_args(T, O#{from => list_to_integer(Y)});
parse_args(["--to", Y | T], O)       -> parse_args(T, O#{to => list_to_integer(Y)});
parse_args(["--date", D | T], O)     -> parse_args(T, O#{date => parse_date(D)});
parse_args(["-o", F | T], O)         -> parse_args(T, O#{out => F});
parse_args([A | _], _)               -> throw({usage, "unknown argument " ++ A}).

parse_date([Y1, Y2, Y3, Y4, $-, M1, M2, $-, D1, D2]) ->
    {list_to_integer([Y1, Y2, Y3, Y4]), list_to_integer([M1, M2]), list_to_integer([D1, D2])};
parse_date(D) -> throw({usage, "bad --date " ++ D}).

%% ===================================================================
%% Generation
%% ===================================================================

%% Returns {FileText, Problems}.
generate(Opts) ->
    {Today, _} = calendar:universal_time(),
    Date = maps:get(date, Opts, Today),
    {Y0, _, _} = Date,
    From = maps:get(from, Opts, ?DEFAULT_FROM),
    To = maps:get(to, Opts, Y0 + ?DEFAULT_SPAN),
    Names = zone_names(maps:get(tzdata, Opts)),
    ZoneInfo = maps:get(zoneinfo, Opts),
    Actual = zdump_timelines(maps:get(zdump, Opts), ZoneInfo, Names, From, To),
    Results = [convert_zone(Name, ZoneInfo, maps:get(Name, Actual), From, To) || Name <- Names],
    Tuples = [T || {T, _, _} <- Results],
    Exceptions = [{Name, Ex} || {{Name, _, _, _, _, _, _, _, _}, Ex, _} <- Results, Ex =/= []],
    Problems = lists:append([P || {_, _, P} <- Results]),
    Summary = io_lib:format("~b zones carry exception periods ~b-~b",
                            [length(Exceptions), From, To]),
    Text = [header(maps:get(version, Opts, "unknown"), Date, {From, To}, Summary, Problems),
            "-define(tz_database,\n   #{\n",
            lists:join(",\n", ["      " ++ format_tuple(element(1, T)) ++ " =>\n         "
                                ++ format_tuple(T) || T <- Tuples]),
            "\n   }).\n\n",
            exceptions_text(Exceptions)],
    {unicode:characters_to_binary(Text), Problems}.

%% A zone is always represented by its TZif footer rule, which by definition
%% describes the zone after the window (and before it, where nothing better
%% is known).  Every period in the window where zdump disagrees with the
%% footer becomes an exception, including periods that differ only in the
%% DST flag.  The flag is zdump's isdst, read from the rearguard form of the
%% data (see db/Makefile).  Returns {Tuple, Exceptions, Problems}.
convert_zone(Name, ZoneInfo, Transitions, From, To) ->
    Footer = read_footer(filename:join(ZoneInfo, Name)),
    Posix = parse_posix_tz(Footer),
    Tuple = setelement(1, posix_to_tuple(Posix), Name),
    W = window(From, To),
    ActualTimeline = clip_timeline(Transitions, W),
    (ActualTimeline =/= [] orelse element(1, Posix) =/= dst)
        orelse error({empty_zdump_timeline, Name}),
    Diff = timeline_diff(ActualTimeline, predicted_timeline(Tuple, From, To), W),
    Problems =
        [lists:flatten(io_lib:format(
           "~ts: offset ~ts (~ts) from ~ts rounded to ~b min",
           [Name, fmt_offset(Off), Abbr, fmt_secs(A), round_minutes(Off)]))
         || {A, _, Off, Abbr, _} <- Diff, Off rem 60 =/= 0],
    {Tuple, [exception_term(D) || D <- Diff], Problems}.

%% Turns [{UtcSecs, Before, After}] into a timeline for the window [WStart,
%% WEnd) (see below).  Only transitions in the window count: with none, the
%% result is [] (the footer is exact for the whole window).
clip_timeline(Ts, {WStart, WEnd}) ->
    case [T || {U, _, _} = T <- Ts, U >= WStart, U < WEnd] of
        [] -> [];
        [{_, {Off0, Abbr0, Dst0}, _} | _] = InWindow ->
            [{WStart, Off0, Abbr0, Dst0} |
             [{T, Off, Abbr, Dst} || {T, _, {Off, Abbr, Dst}} <- InWindow]]
    end.

fmt_secs(S) ->
    {{Y, Mo, D}, {H, Mi, Se}} = calendar:gregorian_seconds_to_datetime(S),
    io_lib:format("~4..0b-~2..0b-~2..0bT~2..0b:~2..0b:~2..0bZ", [Y, Mo, D, H, Mi, Se]).

fmt_offset(Off) ->
    Sign = if Off < 0 -> "-"; true -> "+" end,
    A = abs(Off),
    io_lib:format("~s~2..0b:~2..0b:~2..0b", [Sign, A div 3600, A rem 3600 div 60, A rem 60]).

%% ===================================================================
%% tzdata sources: Zone and Link names
%% ===================================================================

zone_names(TzData) ->
    Names = lists:flatmap(
              fun(F) ->
                      {ok, Bin} = file:read_file(filename:join(TzData, F)),
                      Lines = string:split(Bin, "\n", all),
                      lists:filtermap(fun source_name/1, Lines)
              end, ?SOURCES),
    lists:usort(Names).

source_name(Line) ->
    case string:lexemes(strip_comment(Line), " \t") of
        [<<"Zone">>, Name | _] -> {true, binary_to_list(Name)};
        [<<"Link">>, _Target, Name | _] -> {true, binary_to_list(Name)};
        _ -> false
    end.

strip_comment(Line) ->
    hd(string:split(Line, "#")).

%% ===================================================================
%% TZif footer and POSIX TZ strings
%% ===================================================================

%% The footer of a TZif v2+ file is "\n" POSIX-TZ "\n" at the very end.
read_footer(File) ->
    {ok, Bin} = file:read_file(File),
    <<"TZif", Ver, _/binary>> = Bin,
    Ver >= $2 orelse error({no_footer, File}),
    Body = binary:part(Bin, 0, byte_size(Bin) - 1),
    {Pos, 1} = lists:last(binary:matches(Body, <<"\n">>)),
    binary_to_list(binary:part(Body, Pos + 1, byte_size(Body) - Pos - 1)).

%% Parses a POSIX TZ string (with the RFC 8536 extension allowing rule
%% times from -167 to 167 hours) into
%%   {std, Abbr, UtcOffsetSec}  or
%%   {dst, StdAbbr, StdOffSec, DstAbbr, DstOffSec, StartRule, EndRule}
%% where Rule = {{Month, Week, WeekDay}, TimeSec}, Week 5 = last,
%% WeekDay 0 = Sunday.  UTC offsets are east-positive (POSIX is west-positive).
parse_posix_tz("") ->
    error(empty_footer);
parse_posix_tz(S0) ->
    {Std, S1} = abbr(S0),
    {StdOff, S2} = posix_offset(S1),
    case S2 of
        "" -> {std, Std, StdOff};
        _ ->
            {Dst, S3} = abbr(S2),
            {DstOff, S4} = case S3 of
                               [$, | _] -> {StdOff + 3600, S3};
                               _ -> posix_offset(S3)
                           end,
            [$, | S5] = S4,
            {Start, [$, | S6]} = posix_rule(S5),
            {End, ""} = posix_rule(S6),
            {dst, Std, StdOff, Dst, DstOff, Start, End}
    end.

abbr([$< | S]) ->
    {A, [$> | Rest]} = lists:splitwith(fun(C) -> C =/= $> end, S),
    {A, Rest};
abbr(S) ->
    {A, Rest} = lists:splitwith(fun(C) -> (C >= $A andalso C =< $Z) orelse
                                              (C >= $a andalso C =< $z) end, S),
    length(A) >= 3 orelse error({bad_abbr, S}),
    {A, Rest}.

posix_offset(S) ->
    {Secs, Rest} = hms(S),
    {-Secs, Rest}.

%% [+-]hh[:mm[:ss]] -> {Seconds, Rest}
hms([$- | S]) -> {V, R} = hms(S), {-V, R};
hms([$+ | S]) -> hms(S);
hms(S) ->
    {H, R1} = digits(S),
    {M, Sec, Rest} =
        case R1 of
            [$: | T1] ->
                {M0, R2} = digits(T1),
                case R2 of
                    [$: | T2] -> {S0, R3} = digits(T2), {M0, S0, R3};
                    _ -> {M0, 0, R2}
                end;
            _ -> {0, 0, R1}
        end,
    {H * 3600 + M * 60 + Sec, Rest}.

digits(S) ->
    {D, Rest} = lists:splitwith(fun(C) -> C >= $0 andalso C =< $9 end, S),
    D =/= [] orelse error({expected_digits, S}),
    {list_to_integer(D), Rest}.

posix_rule([$M | S]) ->
    {Mon, [$. | S1]} = digits(S),
    {Week, [$. | S2]} = digits(S1),
    {Day, S3} = digits(S2),
    {Time, Rest} = case S3 of
                       [$/ | T] -> hms(T);
                       _ -> {7200, S3}
                   end,
    true = Mon >= 1 andalso Mon =< 12 andalso Week >= 1 andalso Week =< 5
        andalso Day >= 0 andalso Day =< 6,
    {{{Mon, Week, Day}, Time}, Rest};
posix_rule(S) ->
    error({unsupported_rule_form, S}).

%% ===================================================================
%% Conversion to the erlang_localtime tuple
%% ===================================================================

posix_to_tuple({std, Abbr, Off}) ->
    fixed_tuple({Off, Abbr});
posix_to_tuple({dst, Std, StdOff, Dst, DstOff, _, _}) when DstOff < StdOff ->
    %% Negative DST (Europe/Dublin in the main form of tzdata).  The zoneinfo
    %% must be compiled from the rearguard form (see db/Makefile), where the
    %% DST flags of zdump and the footer agree with erlang_localtime's
    %% positive shift.
    error({negative_dst_footer, Std, StdOff, Dst, DstOff});
posix_to_tuple({dst, Std, StdOff, Dst, DstOff, {StartDay, StartT}, {EndDay, EndT}}) ->
    {undefined, {Std, Std}, {Dst, Dst}, minutes(StdOff), minutes(DstOff - StdOff),
     day_term(StartDay), hm(StartT), day_term(EndDay), hm(EndT)}.

fixed_tuple({Off, Abbr}) ->
    {undefined, {Abbr, Abbr}, undef, minutes(Off), 0, undef, {0, 0}, undef, {0, 0}}.

minutes(Sec) when Sec rem 60 =:= 0 -> Sec div 60;
minutes(Sec) -> error({not_whole_minutes, Sec}).

%% Hours may be negative or >= 24 (extended POSIX rule times).
hm(Sec) ->
    Min = minutes(Sec),
    H = Min div 60, M = Min rem 60,
    case M < 0 of
        true -> {H - 1, M + 60};
        false -> {H, M}
    end.

day_term({Mon, Week, Day}) ->
    {case Week of 5 -> last; _ -> Week end,
     element(Day + 1, {sun, mon, tue, wed, thu, fri, sat}),
     element(Mon, {jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec})}.

%% ===================================================================
%% Timelines: [{UtcGregorianSeconds, OffsetSec, Abbr, IsDst}] sorted, each entry
%% being a transition to that state.  The first entry is the state in
%% effect at the window start.
%% ===================================================================

window(From, To) ->
    {gsecs({From, 1, 1}, 0), gsecs({To + 1, 1, 1}, 0)}.

gsecs(Date, Secs) ->
    calendar:datetime_to_gregorian_seconds({Date, {0, 0, 0}}) + Secs.

%% Transitions predicted by an erlang_localtime tuple for years From..To.
predicted_timeline({_, {Std, _}, undef, StdMin, _, _, _, _, _}, From, _To) ->
    {WStart, _} = window(From, From),
    [{WStart, StdMin * 60, Std, false}];
predicted_timeline(Tuple, From, To) ->
    {WStart, _} = window(From, To),
    All = lists:append([rule_transitions(Tuple, Y, utc) || Y <- lists:seq(From - 1, To + 1)]),
    {Before, After} = lists:partition(fun(E) -> element(1, E) =< WStart end, lists:sort(All)),
    {_, Off, Abbr, Dst} = lists:last(Before),
    [{WStart, Off, Abbr, Dst} | After].

%% The two transitions of Year as [{UtcSecs, NewOffsetSec, NewAbbr, IsDst}],
%% IsDst in the tuple's convention (the higher offset is daylight time).
rule_transitions({_, {Std, _}, {Dst, _}, StdMin, DstMin, StartDay, {SH, SM}, EndDay, {EH, EM}},
                 Year, utc) ->
    Start = gsecs(rule_date(StartDay, Year), (SH * 60 + SM - StdMin) * 60),
    End = gsecs(rule_date(EndDay, Year), (EH * 60 + EM - StdMin - DstMin) * 60),
    [{Start, (StdMin + DstMin) * 60, Dst, true}, {End, StdMin * 60, Std, false}].

%% Independent implementation of {Nth|last, Weekday, Month} -> date.
rule_date({Nth, Wd, Mon}, Year) ->
    M = index(Mon, [jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec]),
    D = index(Wd, [mon, tue, wed, thu, fri, sat, sun]),
    case Nth of
        last ->
            Last = calendar:last_day_of_the_month(Year, M),
            LastWd = calendar:day_of_the_week(Year, M, Last),
            {Year, M, Last - ((LastWd - D + 7) rem 7)};
        N when is_integer(N), N >= 1, N =< 4 ->
            FirstWd = calendar:day_of_the_week(Year, M, 1),
            {Year, M, 1 + ((D - FirstWd + 7) rem 7) + 7 * (N - 1)}
    end.

index(X, L) -> length(lists:takewhile(fun(Y) -> Y =/= X end, L)) + 1.

%% Runs zdump once for all names and returns #{Name => Transitions}, each
%% transition being {UtcSecs, Before, After} with states {OffsetSec, Abbr,
%% IsDst} as zdump reports them, in the window From .. To; clip_timeline/2
%% turns them into a timeline.
%% Zones are passed as absolute TZif paths: zdump does not reliably honour
%% TZDIR (it silently falls back to the system database for plain names).
zdump_timelines(Zdump, ZoneInfo, Names, From, To) ->
    Dir = filename:absname(ZoneInfo) ++ "/",
    Args = ["-V", "-c", integer_to_list(From) ++ "," ++ integer_to_list(To + 1)
            | [Dir ++ N || N <- Names]],
    Port = open_port({spawn_executable, Zdump},
                     [{args, Args}, exit_status, binary, stream, use_stdio]),
    Out = collect(Port, []),
    {CStart, CEnd} = window(From, To),
    %% zdump prints the path as UTF-8 bytes; Dir is a list of codepoints.
    DirBin = unicode:characters_to_binary(Dir),
    %% One {Zone, UtcSecs, {OffsetSec, Abbr, IsDst}} per zdump transition.
    %% Lines that do not match are skipped silently.
    Parsed = [{N, U, L}
              || Line <- string:split(Out, "\n", all),
                 {N, Rest} <- [zdump_zone(Line, DirBin)],
                 {U, L} <- [zdump_line(string:lexemes(Rest, " "))]],
    Parsed =/= [] orelse error({zdump_unparsable, length(Names), byte_size(Out)}),
    ByZone = lists:foldl(fun({N, U, L}, Acc) ->
                                 maps:update_with(N, fun(V) -> [{U, L} | V] end, [{U, L}], Acc)
                         end, maps:from_list([{N, []} || N <- Names]), Parsed),
    maps:map(fun(_, Rev) -> zdump_transitions(lists:reverse(Rev), CStart, CEnd) end, ByZone).

%% Splits a zdump line into {ZoneName, RestOfLine}.  The directory prefix is
%% removed by an exact match, so spaces in the path do not matter.  Zone names
%% contain no spaces.
zdump_zone(Line, Dir) ->
    case string:prefix(Line, Dir) of
        nomatch -> skip;
        Tail ->
            case string:split(Tail, " ") of
                [Name, Rest] -> {binary_to_list(Name), Rest};
                _ -> skip
            end
    end.

collect(Port, Acc) ->
    receive
        {Port, {data, D}} -> collect(Port, [D | Acc]);
        {Port, {exit_status, 0}} -> iolist_to_binary(lists:reverse(Acc));
        {Port, {exit_status, S}} -> error({zdump_failed, S})
    end.

%% "Sun Mar 29 00:59:59 2026 UT = Sun Mar 29 00:59:59 2026 GMT isdst=0 gmtoff=0"
zdump_line([_, Mon, Day, Time, Year, <<"UT">>, <<"=">>, _, _, _, _, _, Abbr,
            <<"isdst=", IsDst/binary>>, <<"gmtoff=", Off/binary>>]) ->
    try
        [H, Mi, S] = [binary_to_integer(X) || X <- string:split(Time, ":", all)],
        Date = {binary_to_integer(Year),
                index(binary_to_atom(string:lowercase(Mon)),
                      [jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec]),
                binary_to_integer(Day)},
        {gsecs(Date, H * 3600 + Mi * 60 + S),
         {binary_to_integer(Off), binary_to_list(Abbr), binary_to_integer(IsDst) =/= 0}}
    catch _:_ -> skip
    end;
zdump_line(_) -> skip.

%% zdump -v prints each transition as a pair (t-1, t), plus far-past and
%% far-future sentinel lines (-v only; -V omits them, and is ~30x faster).
%% Returns the transitions in [CStart, CEnd) as [{UtcSecs, Before, After}].
zdump_transitions(Entries0, CStart, CEnd) ->
    transitions([E || {U, _} = E <- Entries0, is_integer(U), U >= CStart - 1, U < CEnd]).

transitions([{T1, S1}, {T2, S2} | Rest]) when T2 =:= T1 + 1 ->
    [{T2, S1, S2} | transitions(Rest)];
transitions([_ | Rest]) -> transitions(Rest);
transitions([]) -> [].

%% Periods inside the window where Actual differs from Predicted in offset,
%% abbreviation or DST flag, as [{StartSecs, EndSecs, OffsetSec, Abbr, IsDst}]
%% with Actual's state.  An empty Actual timeline means zdump saw no
%% transitions; then the footer is exact.
timeline_diff([], _, _) -> [];
timeline_diff(Actual, Predicted, {_, WEnd}) ->
    Points = lists:usort([element(1, E) || E <- Actual ++ Predicted, element(1, E) < WEnd]
                         ++ [WEnd]),
    Pieces = [{A, B, state_at(Actual, A), state_at(Predicted, A)}
              || {A, B} <- lists:zip(lists:droplast(Points), tl(Points))],
    coalesce([{A, B, Off, Abbr, Dst}
              || {A, B, {Off, Abbr, Dst} = S, P} <- Pieces, S =/= P]).

%% {OffsetSec, Abbr, IsDst} at T.
state_at(Timeline, T) ->
    {_, Off, Abbr, Dst} = lists:last([E || E <- Timeline, element(1, E) =< T]),
    {Off, Abbr, Dst}.

coalesce([{A, B, O, Ab, D}, {B, C, O, Ab, D} | Rest]) -> coalesce([{A, C, O, Ab, D} | Rest]);
coalesce([X | Rest]) -> [X | coalesce(Rest)];
coalesce([]) -> [].

%% Gregorian seconds are emitted directly so the library need not convert
%% datetimes on every lookup.  Sub-minute offsets (Monrovia until 1972) are
%% rounded; convert_zone/5 reports them.
exception_term({A, B, Off, Abbr, IsDst}) ->
    {A, B, round_minutes(Off), Abbr, IsDst}.

round_minutes(Sec) -> round(Sec / 60).

%% ===================================================================
%% Output
%% ===================================================================

format_tuple(T) ->
    lists:flatten(io_lib:print(T, 1, 1000000, -1)).

%% Each period is followed by a comment with its bounds as dates, so the file
%% stays readable even though the terms hold gregorian seconds.
exceptions_text(Exceptions) ->
    ["% Periods (UTC, [Start, End)) where a zone deviates from its yearly rule.\n"
     "% #{TimeZoneName => [{UtcStartGregorianSecs, UtcEndGregorianSecs, UtcOffsetMin, Abbr, IsDst}]}\n"
     "-define(tz_exceptions,\n   #{\n",
     lists:join(
       "\n",
       [["      ", format_tuple(Name), " =>\n        [",
         with_separators([{format_tuple(E), period_comment(E)} || E <- Ex],
                         ",", "\n         ", ZoneEnd)]
        || {{Name, Ex}, ZoneEnd} <- lists:zip(Exceptions, zone_ends(length(Exceptions)))]),
     "\n   }).\n"].

zone_ends(0) -> [];
zone_ends(N) -> lists:duplicate(N - 1, "],") ++ ["]"].

%% Joins [{Text, Comment}] putting Sep after every item but the last (which
%% gets Last), before the item's comment, so comments never swallow commas.
with_separators(Items, Sep, NewLine, Last) ->
    N = length(Items),
    lists:join(NewLine,
               [[Text, case I of N -> Last; _ -> Sep end, Comment]
                || {I, {Text, Comment}} <- lists:zip(lists:seq(1, N), Items)]).

period_comment({A, B, _, _, _}) ->
    ["  % ", fmt_secs(A), " .. ", fmt_secs(B)].

header(Version, {Y, M, D}, {From, To}, Summary, Problems) ->
    io_lib:format(
      "%% @author  Dmitry S. Melnikov (dmitryme@gmail.com)\n"
      "%%          Gabriel Tholsgård (gabriel.tholsgard@gmail.com)\n"
      "%% @copyright 2010 Dmitry S. Melnikov\n"
      "%%                 Gabriel Tholsgård\n"
      "\n"
      "-author(\"Dmitry Melnikov <dmitryme@gmail.com>, Gabriel Tholsgård <gabriel.tholsgard@gmail.com>\").\n"
      "\n"
      "%% Automatically generated by db/tz_gen.erl from the time zone database\n"
      "%% version ~ts on ~4..0b-~2..0b-~2..0b; exceptions cover ~b-~b.  Do not edit.\n"
      "%% Results for dates before ~b are unsupported (the yearly rule is used).\n"
      "%% ~ts.\n"
      "%%\n"
      "%% Problems:\n~ts"
      "\n"
      "% #{TimeZoneName => {TimeZoneName, {StdAbbr, StdName}, {DstAbbr, DstName}, StdMin, DstMin, DstStartDay, DstStartTime, DstEndDay, DstEndTime}}\n"
      "%   TimeZoneName = String(), TimeZone name, MUST be unique. It is a key\n"
      "%   StdName = {String(), String()}, name and abbreviations of timezone before daylight shift\n"
      "%   DstName = {String(), String()}, name and abbreviations of timezone after daylight shift\n"
      "%   StdMin = Integer(), GMT offset in minutes. W/o daylight savings\n"
      "%   DstMin = Integer(), daylight saving. Adjustment for GMT offset, when daylight saving is on\n"
      "%   DstStartDay = {NthWeekday, Weekday, Month}, daylight saving transition rule. Can be undef if no daylight saving rule specified\n"
      "%     NthWeekday = Integer() | 'last', 1(first week),2(second week),3(...),4(...),'last'(last week)\n"
      "%     Weekday = atom(),  sun,mon,tue,wed,thu,fri,sat\n"
      "%     Month = atom(),  jan,feb,mar,apr,may,jun,jul,aug,sep,oct,nov,dec\n"
      "%   DstStartTime = {Hour, Min} - local standard time of the transition, counted from\n"
      "%     midnight of DstStartDay\n"
      "%     Hour = Integer(), may be negative or >= 24 (e.g. {26,0} = 02:00 the next day)\n"
      "%     Min = Integer(), [0..59]\n"
      "%   DstEndDay = {NthWeekday, Weekday, Month} - transition back to std. Can be undef if no daylight saving rule specified\n"
      "%   DstEndTime = {Hour, Min} - local daylight time of transition to std, same range as DstStartTime.\n"
      "% }\n"
      "\n",
      [Version, Y, M, D, From, To, From, Summary,
       case Problems of
           [] -> "%%   none\n";
           _ -> [["%%   ", P, "\n"] || P <- Problems]
       end]).
