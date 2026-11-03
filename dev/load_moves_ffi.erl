%% What the movement load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_moves): the time and the number of calls of the map's
%% move function, which the VM counts for a function it is asked to trace the
%% calls of (erlang:trace_pattern with call_time, in processes started while
%% `erlang:trace(new, true, [call, ...])` is on); how long the map's process
%% ran, from the VM's own trace of when it was scheduled in and out; and the
%% longest message queue the map showed, sampled by a process of its own.
%%
%% The queue is sampled every 10 ms. That is often enough that a queue that
%% builds over a second shows in about a hundred samples, and rare enough that
%% the sampler's own work (one process_info call a tick) is far below the map's:
%% a shorter period would measure the sampler.
-module(load_moves_ffi).
-export([start_probe/0, stop_probe/0]).

-define(MOVED, {genesis_prime@world_map@map, moved, 5}).
-define(EVERY_MS, 10).
-define(ANSWER_MS, 5000).

%% Runs in the server's node: counts the calls of the map's `moved` and the
%% time each takes, from now, and starts sampling the map's message queue and
%% timing how long the map's process runs.
start_probe() ->
    {module, _} = code:ensure_loaded(genesis_prime@world_map@map),
    erlang:trace_pattern(?MOVED, false, [local, call_time]),
    1 = erlang:trace_pattern(?MOVED, true, [local, call_time]),
    Sink = spawn(fun() -> sink(#{}) end),
    erlang:trace(new, true, [call, {tracer, Sink}]),
    Probe = spawn(fun() -> probe(Sink, [], undefined, 0, 0, 0) end),
    persistent_term:put(load_moves_probe, {Probe, Sink}),
    nil.

%% The VM counts a function's call time only in a process that has the call
%% trace flag, and sends that process's tracer a message for each call, which
%% this tracer drops. For a process the probe asked to be told when it runs
%% (`running`), it adds up the time between each schedule-in and the schedule-out
%% after it: the time the process was on a scheduler, in microseconds.
sink(Running) ->
    receive
        {trace_ts, Pid, in, _Where, At} ->
            sink(Running#{Pid => {At, busy(Pid, Running)}});
        {trace_ts, Pid, out, _Where, At} ->
            case Running of
                #{Pid := {In, Busy}} when In =/= undefined ->
                    sink(Running#{Pid => {undefined, Busy + microseconds(At - In)}});
                _ ->
                    sink(Running)
            end;
        {busy, From} ->
            From ! {busy, lists:sum([Busy || {_In, Busy} <- maps:values(Running)])},
            sink(Running);
        _ ->
            sink(Running)
    end.

busy(Pid, Running) ->
    case Running of
        #{Pid := {_In, Busy}} -> Busy;
        _ -> 0
    end.

microseconds(Native) ->
    erlang:convert_time_unit(Native, native, microsecond).

%% Runs in the server's node: stops the sampling and gives the calls counted,
%% the microseconds they took in all, the longest message queue the map showed,
%% the sum of the queues seen, how many samples were taken, the microseconds the
%% map's process ran and the microseconds since the probe first saw it. A probe
%% or tracer that does not answer within five seconds is an error, never zeros.
stop_probe() ->
    {Probe, Sink} = persistent_term:get(load_moves_probe),
    Probe ! {stop, self()},
    {Longest, Sum, Samples, Since} =
        receive {probed, Result} -> Result
        after ?ANSWER_MS -> error(the_probe_did_not_answer)
        end,
    Sink ! {busy, self()},
    Busy =
        receive {busy, Microseconds} -> Microseconds
        after ?ANSWER_MS -> error(the_tracer_did_not_answer)
        end,
    {call_time, Times} = erlang:trace_info(?MOVED, call_time),
    erlang:trace(new, false, [call]),
    exit(Sink, kill),
    Calls = lists:sum([Count || {_Pid, Count, _S, _Us} <- Times]),
    Micros = lists:sum([S * 1000000 + Us || {_Pid, _Count, S, Us} <- Times]),
    Window = case Since of
                 undefined -> 0;
                 _ -> erlang:monotonic_time(microsecond) - Since
             end,
    {Calls, Micros, Longest, Sum, Samples, Busy, Window}.

%% Every tick: the longest queue of the processes that ran the traced function,
%% and, for one the probe has not met, the request to be told when it runs.
%% `Since` is when the first such process was met.
probe(Sink, Known, Since, Longest, Sum, Samples) ->
    receive
        {stop, From} -> From ! {probed, {Longest, Sum, Samples, Since}}
    after ?EVERY_MS ->
        Maps = maps_running(),
        New = [Pid || Pid <- Maps, not lists:member(Pid, Known)],
        lists:foreach(fun(Pid) -> watch_running(Pid, Sink) end, New),
        Queue = lists:max([0 | [queue(Pid) || Pid <- Maps]]),
        probe(Sink, Maps ++ Known, since(Since, New),
              max(Longest, Queue), Sum + Queue, Samples + 1)
    end.

since(undefined, []) -> undefined;
since(undefined, _New) -> erlang:monotonic_time(microsecond);
since(Since, _New) -> Since.

%% Asks the VM to send the sink a message each time the process is scheduled in
%% or out, with a monotonic timestamp. The sink is the process's tracer already.
watch_running(Pid, Sink) ->
    erlang:trace(Pid, true, [running, monotonic_timestamp, {tracer, Sink}]).

%% The processes that ran the traced function.
maps_running() ->
    case erlang:trace_info(?MOVED, call_time) of
        {call_time, Times} when is_list(Times) -> [Pid || {Pid, _, _, _} <- Times];
        _ -> []
    end.

queue(Pid) ->
    case erlang:process_info(Pid, message_queue_len) of
        {message_queue_len, Length} -> Length;
        undefined -> 0
    end.
