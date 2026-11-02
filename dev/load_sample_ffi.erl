%% What the load run's sampler reads from the node (genesis_prime/load_sample)
%% and no Gleam library exposes: every process's mailbox and heap, the
%% schedulers' wall time, the Ranch listeners' connection counts, the store
%% supervisor's workers, the microsecond clock, and a logger handler that counts
%% the warning and error lines.
-module(load_sample_ffi).
-export([scan/0, scheduler_time/0, connections/1, workers/1, microseconds/0,
         memory/0, run_queue/0, start/0, log_lines/0, log/2]).

%% The processes with messages waiting, each with its mailbox length and its
%% heap in words, and the largest heap of any process. The sampler's own
%% process is left out.
scan() ->
    lists:foldl(
        fun(Pid, {Waiting, Largest}) ->
            case process_info(Pid, [message_queue_len, total_heap_size]) of
                [{message_queue_len, Queued}, {total_heap_size, Heap}] ->
                    More = case Queued > 0 of
                               true -> [{Pid, Queued, Heap, describe(Pid)} | Waiting];
                               false -> Waiting
                           end,
                    {More, max(Largest, Heap)};
                undefined -> {Waiting, Largest}
            end
        end,
        {[], 0},
        processes() -- [self()]).

%% What a process is, as one line: its registered name, its initial call and
%% the function it is in.
describe(Pid) ->
    Info = case process_info(Pid, [registered_name, initial_call, current_function]) of
               undefined -> [];
               Found -> Found
           end,
    unicode:characters_to_binary(io_lib:format("~0p", [Info])).

%% The schedulers' wall time, none when `start` has not enabled it.
wall_time() ->
    case erlang:statistics(scheduler_wall_time) of
        undefined -> [];
        Times -> Times
    end.

%% The wall time the online normal schedulers have been busy and have passed,
%% in microseconds, summed: two readings give the share of the cores in use
%% between them. A scheduler taken offline keeps counting, so it is left out.
scheduler_time() ->
    Online = erlang:system_info(schedulers_online),
    Times = [Time || {Id, _, _} = Time <- wall_time(),
                     Id =< Online],
    {lists:sum([Active || {_, Active, _} <- Times]),
     lists:sum([Total || {_, _, Total} <- Times])}.

%% How many connections the Ranch listener holds.
connections(Listener) ->
    length(ranch:procs(Listener, connections)).

%% How many workers the store's factory supervisor has running.
workers(Store) ->
    proplists:get_value(active, supervisor:count_children(Store)).

microseconds() ->
    erlang:monotonic_time(microsecond).

memory() ->
    erlang:memory(total).

run_queue() ->
    erlang:statistics(total_run_queue_lengths).

%% Starts what the samples need: the schedulers' wall time, counted for as long
%% as the process that enabled it lives (a call that enabled it and ended would
%% switch it off and reset it), so a process of its own keeps it on; and the
%% count of the lines logged at warning level or above, from now on.
start() ->
    spawn(fun() ->
                       erlang:system_flag(scheduler_wall_time, true),
                       receive stop -> ok end
                   end),
    erlang:yield(),
    wait_for_wall_time(),
    Counter = counters:new(1, []),
    persistent_term:put({?MODULE, lines}, Counter),
    ok = logger:add_handler(load_sample_lines, ?MODULE, #{config => Counter}),
    nil.

wait_for_wall_time() ->
    case erlang:statistics(scheduler_wall_time) of
        undefined -> erlang:yield(), wait_for_wall_time();
        _ -> ok
    end.

%% The lines counted so far, 0 when no counting has started.
log_lines() ->
    case persistent_term:get({?MODULE, lines}, none) of
        none -> 0;
        Counter -> counters:get(Counter, 1)
    end.

%% The logger handler's callback.
log(#{level := Level}, #{config := Counter}) ->
    case lists:member(Level, [warning, error, critical, alert, emergency]) of
        true -> counters:add(Counter, 1, 1);
        false -> ok
    end.
