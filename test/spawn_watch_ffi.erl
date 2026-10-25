-module(spawn_watch_ffi).
-export([begin_watch/0, unsupervised/2, tree/1]).

%% Traces every process the caller starts, and every process those start, with
%% a tracer process of its own that is linked to the caller. Only spawns made by
%% the caller's own tree are seen, so tests running side by side do not meet.
begin_watch() ->
    Tracer = spawn_link(fun() -> tracer([]) end),
    1 = erlang:trace(self(), true, [procs, set_on_spawn, {tracer, Tracer}]),
    Tracer.

%% The processes started since begin_watch that are alive, are not the caller
%% and are not in the supervisor's tree.
unsupervised(Tracer, Supervisor) ->
    Ref = make_ref(),
    Tracer ! {collect, self(), Ref},
    Spawned =
        receive
            {Ref, Pids} -> Pids
        end,
    Tracer ! stop,
    InTree = tree(Supervisor),
    Self = self(),
    lists:usort([
        Pid
     || Pid <- Spawned,
        Pid =/= Self,
        not lists:member(Pid, InTree),
        is_process_alive(Pid)
    ]).

%% The supervisor and every process under it, found through its children.
tree(Supervisor) ->
    Children = supervisor:which_children(Supervisor),
    lists:flatmap(
        fun
            ({_Id, Pid, supervisor, _Modules}) when is_pid(Pid) -> tree(Pid);
            ({_Id, Pid, _Type, _Modules}) when is_pid(Pid) -> [Pid];
            ({_Id, _Other, _Type, _Modules}) -> []
        end,
        Children
    ) ++ [Supervisor].

tracer(Spawned) ->
    receive
        {trace, _Parent, spawn, Child, _Function} ->
            tracer([Child | Spawned]);
        {collect, From, Ref} ->
            Delivered = erlang:trace_delivered(all),
            receive
                {trace_delivered, all, Delivered} -> ok
            end,
            From ! {Ref, drain(Spawned)},
            tracer(Spawned);
        stop ->
            ok;
        _Other ->
            tracer(Spawned)
    end.

drain(Spawned) ->
    receive
        {trace, _Parent, spawn, Child, _Function} -> drain([Child | Spawned]);
        {trace, _, _, _} -> drain(Spawned);
        {trace, _, _, _, _} -> drain(Spawned)
    after 0 -> Spawned
    end.
