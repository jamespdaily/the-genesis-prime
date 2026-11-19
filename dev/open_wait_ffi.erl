%% The process dictionary holds, in a test's body process, for each slot (a
%% one-time build, a wait, or a wait that can no longer end), the two functions
%% that tell the test something is open and has ended, the waits the process is
%% inside (innermost first, each with a reference that tells one wait from
%% another of the same name), the count of inputs the server has taken, and for
%% each wait the count its last empty look saw. A process without them just runs it.
-module(open_wait_ffi).
-export([named/2, report_to/3, reported/3, judge_with/1, looked_without_finding/0]).

report_to(Slot, Opened, Closed) ->
    put({open_wait_report, Slot}, {Opened, Closed}),
    nil.

named(What, Wait) ->
    Entry = {What, make_ref()},
    Outer = waits(),
    put(open_wait_inside, [Entry | Outer]),
    try
        reported(wait, What, Wait)
    after
        erase({open_wait_warned, element(2, Entry)}),
        erase({open_wait_looked, element(2, Entry)}),
        put(open_wait_inside, Outer)
    end.

waits() ->
    case get(open_wait_inside) of
        undefined -> [];
        Waits -> Waits
    end.

judge_with(TakenInputs) ->
    put(open_wait_judge, TakenInputs),
    nil.

%% A look at a socket found nothing. Inputs is the count of inputs the server has
%% taken. The innermost wait keeps the count its last empty look saw; it is
%% hopeless, and told to the test's owner (slot hopeless) once, when this look
%% sees the same count as the last one and the count is not 0. The first look of
%% a wait has none to compare with, and a wait's marks end with it.
looked_without_finding() ->
    case {get(open_wait_judge), waits()} of
        {undefined, _} ->
            nil;
        {_, []} ->
            nil;
        {TakenInputs, [{What, Wait} | _]} ->
            case get({open_wait_warned, Wait}) of
                true ->
                    nil;
                undefined ->
                    Inputs = TakenInputs(),
                    Before = get({open_wait_looked, Wait}),
                    put({open_wait_looked, Wait}, Inputs),
                    case Before =:= Inputs andalso Inputs =/= 0 of
                        false ->
                            nil;
                        true ->
                            put({open_wait_warned, Wait}, true),
                            told_hopeless(What)
                    end
            end
    end.

told_hopeless(What) ->
    case get({open_wait_report, hopeless}) of
        undefined ->
            nil;
        {Opened, _Closed} ->
            Opened(What),
            nil
    end.

%% Runs Run, and tells the test that owns this process, when this process is its
%% body, that What is open in Slot until Run ends, by its return or by a crash.
reported(Slot, What, Run) ->
    case get({open_wait_report, Slot}) of
        undefined ->
            Run();
        {Opened, Closed} ->
            Opened(What),
            try
                Run()
            after
                Closed()
            end
    end.
