%% What the movement load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_moves): the message queue of each map and how often its
%% process was found running, sampled by a process of its own in the server's
%% node. Nothing is traced, so the probe adds only its own process_info calls to the
%% map's work: a trace of the map's calls or of when it is scheduled in and out would
%% add to the map's work for every call or switch.
%%
%% The period is 10 ms. That is often enough that a queue that builds over a
%% second shows in about a hundred samples, and rare enough that the sampler's
%% own work (two process_info calls a tick) is far below the map's: a shorter
%% period would measure the sampler. A sample finds the process running when its
%% status is running, runnable or garbage_collecting, so the share of such
%% samples is the share of the time the process wanted a scheduler.
%%
%% Besides the longest queue and the sums, the probe keeps each sample's time and queue
%% (the longest of the maps) and the reductions the maps had spent by then, the memory of
%% the map with the longest queue found so far, and, while a queue is over COMPOSE_OVER
%% messages, the names of the messages waiting in that map: at most COMPOSE_MOST times a run
%% and COMPOSE_EVERY_MS apart, since copying thousands of messages out of the map costs the
%% map time.
-module(load_moves_ffi).
-export([start_probe/1, stop_probe/0]).

-define(EVERY_MS, 10).
-define(ANSWER_MS, 30000).
-define(COMPOSE_OVER, 1000).
-define(COMPOSE_MOST, 6).
-define(COMPOSE_EVERY_MS, 500).

%% What the probe holds between samples.
-record(held, {supervisor, started_ms, longest = 0, sum = 0, samples = 0, running = 0,
               series = [], taken = [], last_taken_ms = -?COMPOSE_EVERY_MS,
               peak_memory = 0, reductions = []}).

%% Runs in the server's node: starts sampling the maps the map supervisor
%% (named `Supervisor`) runs.
start_probe(Supervisor) ->
    Probe = spawn(fun() ->
        probe(#held{supervisor = Supervisor, started_ms = erlang:monotonic_time(millisecond)})
    end),
    persistent_term:put(load_moves_probe, Probe),
    nil.

%% Runs in the server's node: stops the sampling and gives the load_queue.Probe:
%% the longest message queue any map showed, the sum of the longest queue of each
%% sample, how many samples were taken and how many of them found a map running, the
%% samples as {ms since the start, longest queue}, the messages taken from the map
%% as {taken, ms, queue, kind names}, the memory in bytes of the map when its queue
%% was longest and each sample's {ms since the start, reductions the maps had spent
%% together}. A probe that does not
%% answer within thirty seconds (the machine is saturated by the run it measures) is an
%% error, never zeros.
stop_probe() ->
    Probe = persistent_term:get(load_moves_probe),
    Probe ! {stop, self()},
    receive {probed, Result} -> Result
    after ?ANSWER_MS -> error(the_probe_did_not_answer)
    end.

probe(Held) ->
    receive
        {stop, From} -> From ! {probed, result(Held)}
    after ?EVERY_MS ->
        probe(sampled(Held))
    end.

result(#held{longest = Longest, sum = Sum, samples = Samples, running = Running,
             series = Series, taken = Taken, peak_memory = Memory, reductions = Reductions}) ->
    {probe, Longest, Sum, Samples, Running, lists:reverse(Series), lists:reverse(Taken),
     Memory, lists:reverse(Reductions)}.

sampled(#held{supervisor = Supervisor, started_ms = Started} = Held) ->
    Maps = maps(Supervisor),
    Ms = erlang:monotonic_time(millisecond) - Started,
    {Queue, Busiest} = longest_queue(Maps),
    Found = case lists:any(fun running/1, Maps) of
                true -> 1;
                false -> 0
            end,
    Composed = composed(Held, Ms, Queue, Busiest),
    Remembered = remembered_peak(Composed, Queue, Busiest),
    Remembered#held{
        longest = max(Held#held.longest, Queue),
        sum = Held#held.sum + Queue,
        samples = Held#held.samples + 1,
        running = Held#held.running + Found,
        series = [{Ms, Queue} | Held#held.series],
        reductions = [{Ms, lists:sum([reductions(Pid) || Pid <- Maps])} | Held#held.reductions]
    }.

%% The names of the messages in the busiest map when its queue is long enough, as
%% often as the cap allows.
composed(#held{taken = Taken, last_taken_ms = Last} = Held, Ms, Queue, Busiest) ->
    Allowed = Queue > ?COMPOSE_OVER andalso length(Taken) < ?COMPOSE_MOST
              andalso Ms - Last >= ?COMPOSE_EVERY_MS andalso is_pid(Busiest),
    case Allowed of
        true ->
            case erlang:process_info(Busiest, messages) of
                {messages, Messages} ->
                    Held#held{taken = [{taken, Ms, Queue, [kind(Message) || Message <- Messages]} | Taken],
                              last_taken_ms = Ms};
                undefined ->
                    Held
            end;
        false ->
            Held
    end.

%% The memory of the busiest map when its queue is the longest seen.
remembered_peak(#held{longest = Longest} = Held, Queue, Busiest) when Queue > Longest, is_pid(Busiest) ->
    case erlang:process_info(Busiest, memory) of
        {memory, Memory} -> Held#held{peak_memory = Memory};
        undefined -> Held
    end;
remembered_peak(Held, _Queue, _Busiest) ->
    Held.

%% A message's kind: the variant a Gleam custom type is, the first element of its tuple,
%% followed by the variants of what it wraps while the second element is one too (a shell's
%% `Told(Snapshot(..))` is "told/snapshot"), at most three deep. A message sent through a Gleam
%% subject is {Tag, Message} with a reference as its tag, and is named by its Message.
kind(Message) ->
    iolist_to_binary(lists:join(<<"/">>, names(Message, 3))).

names(_Message, 0) ->
    [];
names({Tag, Message}, Depth) when is_reference(Tag) ->
    names(Message, Depth);
names(Message, Depth) when is_tuple(Message), tuple_size(Message) > 0, is_atom(element(1, Message)) ->
    Name = atom_to_binary(element(1, Message)),
    case tuple_size(Message) > 1 of
        true -> [Name | names_inside(element(2, Message), Depth - 1)];
        false -> [Name]
    end;
names(Message, _Depth) when is_atom(Message) ->
    [atom_to_binary(Message)];
names(_Message, _Depth) ->
    [<<"other">>].

%% The kinds inside a wrapper's second element: none unless it is a variant itself.
names_inside({Tag, Message}, Depth) when is_reference(Tag) ->
    names_inside(Message, Depth);
names_inside(Inside, Depth) when is_tuple(Inside), tuple_size(Inside) > 0, is_atom(element(1, Inside)) ->
    names(Inside, Depth);
names_inside(_Inside, _Depth) ->
    [].

%% The maps the supervisor runs now: none before the first is started.
maps(Supervisor) ->
    try supervisor:which_children(Supervisor) of
        Children -> [Pid || {_Id, Pid, _Type, _Modules} <- Children, is_pid(Pid)]
    catch
        exit:_ -> []
    end.

%% The longest queue of the maps and the map that has it, none for no map.
longest_queue(Maps) ->
    lists:foldl(
        fun(Pid, {Longest, _} = Best) ->
            case queue(Pid) of
                Length when Length > Longest -> {Length, Pid};
                _ -> Best
            end
        end,
        {0, none},
        Maps).

queue(Pid) ->
    case erlang:process_info(Pid, message_queue_len) of
        {message_queue_len, Length} -> Length;
        undefined -> 0
    end.

reductions(Pid) ->
    case erlang:process_info(Pid, reductions) of
        {reductions, Count} -> Count;
        undefined -> 0
    end.

running(Pid) ->
    case erlang:process_info(Pid, status) of
        {status, Status} -> lists:member(Status, [running, runnable, garbage_collecting]);
        undefined -> false
    end.
