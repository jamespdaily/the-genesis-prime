%% What the movement load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_moves): the message queue of each map and how often its
%% process was found running, sampled by a process of its own in the server's
%% node. Nothing is traced: a call trace on the map's functions and a trace of
%% when its process is scheduled in and out each made a map that keeps up at 200
%% players fall behind, so the run samples and does not trace.
%%
%% The period is 10 ms. That is often enough that a queue that builds over a
%% second shows in about a hundred samples, and rare enough that the sampler's
%% own work (two process_info calls a tick) is far below the map's: a shorter
%% period would measure the sampler. A sample finds the process running when its
%% status is running, runnable or garbage_collecting, so the share of such
%% samples is the share of the time the process wanted a scheduler.
-module(load_moves_ffi).
-export([start_probe/1, stop_probe/0]).

-define(EVERY_MS, 10).
-define(ANSWER_MS, 30000).

%% Runs in the server's node: starts sampling the maps the map supervisor
%% (named `Supervisor`) runs.
start_probe(Supervisor) ->
    Probe = spawn(fun() -> probe(Supervisor, 0, 0, 0, 0) end),
    persistent_term:put(load_moves_probe, Probe),
    nil.

%% Runs in the server's node: stops the sampling and gives the longest message
%% queue any map showed, the sum of the longest queue of each sample, how many
%% samples were taken and how many of them found a map running. A probe that
%% does not answer within thirty seconds (the machine is saturated by the run it
%% measures) is an error, never zeros.
stop_probe() ->
    Probe = persistent_term:get(load_moves_probe),
    Probe ! {stop, self()},
    receive {probed, Result} -> Result
    after ?ANSWER_MS -> error(the_probe_did_not_answer)
    end.

probe(Supervisor, Longest, Sum, Samples, Running) ->
    receive
        {stop, From} -> From ! {probed, {Longest, Sum, Samples, Running}}
    after ?EVERY_MS ->
        Maps = maps(Supervisor),
        Queue = lists:max([0 | [queue(Pid) || Pid <- Maps]]),
        Found = case lists:any(fun running/1, Maps) of
                    true -> 1;
                    false -> 0
                end,
        probe(Supervisor, max(Longest, Queue), Sum + Queue, Samples + 1, Running + Found)
    end.

%% The maps the supervisor runs now: none before the first is started.
maps(Supervisor) ->
    try supervisor:which_children(Supervisor) of
        Children -> [Pid || {_Id, Pid, _Type, _Modules} <- Children, is_pid(Pid)]
    catch
        exit:_ -> []
    end.

queue(Pid) ->
    case erlang:process_info(Pid, message_queue_len) of
        {message_queue_len, Length} -> Length;
        undefined -> 0
    end.

running(Pid) ->
    case erlang:process_info(Pid, status) of
        {status, Status} -> lists:member(Status, [running, runnable, garbage_collecting]);
        undefined -> false
    end.
