%% What the movement load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_moves): the time and the number of calls of the map's
%% move function, which the VM counts for a function it is asked to trace the
%% calls of (erlang:trace_pattern with call_time, in processes started while
%% `erlang:trace(new, true, [call, ...])` is on), and the longest message queue
%% the map showed, sampled by a process of its own.
-module(load_moves_ffi).
-export([start_probe/0, stop_probe/0]).

-define(MOVED, {genesis_prime@world_map@map, moved, 5}).
-define(EVERY_MS, 10).

%% Runs in the server's node: counts the calls of the map's `moved` and the
%% time each takes, from now, and starts sampling the map's message queue.
start_probe() ->
    {module, _} = code:ensure_loaded(genesis_prime@world_map@map),
    erlang:trace_pattern(?MOVED, false, [local, call_time]),
    1 = erlang:trace_pattern(?MOVED, true, [local, call_time]),
    Sink = spawn(fun sink/0),
    erlang:trace(new, true, [call, {tracer, Sink}]),
    Probe = spawn(fun() -> probe(0, 0, 0) end),
    persistent_term:put(load_moves_probe, {Probe, Sink}),
    nil.

%% The VM counts a function's call time only in a process that has the call
%% trace flag, and sends that process's tracer a message for each call; this
%% tracer drops them.
sink() ->
    receive _ -> sink() end.

%% Runs in the server's node: stops the sampling and gives the calls counted,
%% the microseconds they took in all, the longest message queue the map showed,
%% the sum of the queues seen and how many samples were taken.
stop_probe() ->
    {Probe, Sink} = persistent_term:get(load_moves_probe),
    Probe ! {stop, self()},
    {Longest, Sum, Samples} = receive {probed, Result} -> Result after 5000 -> {0, 0, 0} end,
    {call_time, Times} = erlang:trace_info(?MOVED, call_time),
    erlang:trace(new, false, [call]),
    exit(Sink, kill),
    Calls = lists:sum([Count || {_Pid, Count, _S, _Us} <- Times]),
    Micros = lists:sum([S * 1000000 + Us || {_Pid, _Count, S, Us} <- Times]),
    {Calls, Micros, Longest, Sum, Samples}.

probe(Longest, Sum, Samples) ->
    receive
        {stop, From} -> From ! {probed, {Longest, Sum, Samples}}
    after ?EVERY_MS ->
        Queue = lists:max([0 | [queue(Pid) || Pid <- maps_running()]]),
        probe(max(Longest, Queue), Sum + Queue, Samples + 1)
    end.

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
