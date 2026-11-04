%% What the walking load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_walk): one sample of the world's processes, and the size of
%% a term. Nothing is traced: a sample reads the counters the runtime keeps.
-module(load_walk_ffi).
-export([sample/2, term_bytes/1]).

%% One sample: the longest message queue of any map, whether any map's process was
%% found running (1) or not (0), how many creatures the creature supervisor runs,
%% the memory of those creatures' processes in bytes, and the node's total memory
%% in bytes. `MapSupervisor` and `CreatureSupervisor` are the supervisors' names.
sample(MapSupervisor, CreatureSupervisor) ->
    Maps = pids(MapSupervisor),
    Creatures = pids(CreatureSupervisor),
    Queue = lists:max([0 | [queue(Pid) || Pid <- Maps]]),
    Running = case lists:any(fun running/1, Maps) of
                  true -> 1;
                  false -> 0
              end,
    Memory = lists:sum([memory(Pid) || Pid <- Creatures]),
    {Queue, Running, length(Creatures), Memory, erlang:memory(total)}.

%% The size of a term on a process heap, in bytes (`erts_debug:flat_size/1` words).
term_bytes(Term) ->
    erts_debug:flat_size(Term) * erlang:system_info(wordsize).

pids(Supervisor) ->
    try supervisor:which_children(Supervisor) of
        Children -> [Pid || {_Id, Pid, _Type, _Modules} <- Children, is_pid(Pid)]
    catch
        exit:_ -> []
    end.

queue(Pid) ->
    case process_info(Pid, message_queue_len) of
        {message_queue_len, Length} -> Length;
        undefined -> 0
    end.

memory(Pid) ->
    case process_info(Pid, memory) of
        {memory, Bytes} -> Bytes;
        undefined -> 0
    end.

running(Pid) ->
    case process_info(Pid, status) of
        {status, running} -> true;
        {status, runnable} -> true;
        {status, garbage_collecting} -> true;
        _ -> false
    end.
