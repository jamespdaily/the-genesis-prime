%% What the walking load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_walk): one sample of the world's processes, and the size of
%% a term. Nothing is traced: a sample reads the counters the runtime keeps.
-module(load_walk_ffi).
-export([sample/1, term_bytes/1, literal_bytes/0]).

%% One sample of the creatures: how many the creature supervisor
%% (`CreatureSupervisor`, its name) runs, the memory of their processes in bytes,
%% and the node's total memory in bytes. The map's queue and busy share are
%% sampled every 10 ms by load_moves_ffi, not here.
sample(CreatureSupervisor) ->
    Creatures = pids(CreatureSupervisor),
    {length(Creatures), lists:sum([memory(Pid) || Pid <- Creatures]), erlang:memory(total)}.

%% The bytes the VM holds for its literal area, where persistent terms live: the
%% size of every carrier of the literal allocator.
literal_bytes() ->
    {ok, {_, Carriers}} = instrument:carriers(#{allocator_types => [literal_alloc]}),
    lists:sum([Size || {literal_alloc, _InPool, Size, _Unused, _Blocks, _Stats} <- Carriers]).

%% The size of a term on a process heap, in bytes (`erts_debug:flat_size/1` words).
term_bytes(Term) ->
    erts_debug:flat_size(Term) * erlang:system_info(wordsize).

pids(Supervisor) ->
    try supervisor:which_children(Supervisor) of
        Children -> [Pid || {_Id, Pid, _Type, _Modules} <- Children, is_pid(Pid)]
    catch
        exit:_ -> []
    end.

memory(Pid) ->
    case process_info(Pid, memory) of
        {memory, Bytes} -> Bytes;
        undefined -> 0
    end.
