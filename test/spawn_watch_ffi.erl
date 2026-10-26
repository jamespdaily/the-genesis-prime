-module(spawn_watch_ffi).
-export([begin_watch/0, unsupervised/2, tree/1]).

%% Traces every process the caller starts, and every process those start, with
%% a tracer process of its own that is linked to the caller. Only spawns made by
%% the caller's own tree are seen, so tests running side by side do not meet.
begin_watch() ->
    Tracer = spawn_link(fun() -> tracer([]) end),
    1 = erlang:trace(self(), true, [procs, set_on_spawn, {tracer, Tracer}]),
    Tracer.

%% The processes started since begin_watch that are alive, are not the caller,
%% are not in the supervisor's tree and were not started, through OTP's
%% proc_lib, by a process that is.
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
        not started_under(Pid, InTree),
        is_process_alive(Pid)
    ]).

%% Whether a process is under a supervisor of its own that a worker of the tree
%% started, as the database pool starts one. The pool is a worker, so it has no
%% children to ask for, but the supervisor it started records the pool as its
%% parent, and each process that supervisor starts records the supervisor. A
%% process is owned when it is a supervisor whose parent is a worker of the
%% tree, or when its parent is a supervisor that is owned. A stray started by
%% a worker or by a supervisor of the tree is not owned, since a supervisor's
%% children are in the tree already, and neither is one started by a plain
%% spawn, which records no parent.
started_under(Pid, InTree) ->
    case parent(Pid) of
        undefined ->
            false;
        Parent ->
            (is_supervisor(Pid) andalso lists:member(Parent, InTree) andalso
                not is_supervisor(Parent)) orelse
                (is_supervisor(Parent) andalso not lists:member(Parent, InTree) andalso
                    started_under(Parent, InTree))
    end.

%% The process that started this one through proc_lib, which records its
%% ancestors, nearest first, by pid or by registered name.
parent(Pid) ->
    case dictionary_entry(Pid, '$ancestors') of
        {ok, [Nearest | _]} when is_pid(Nearest) -> Nearest;
        {ok, [Nearest | _]} when is_atom(Nearest) -> whereis(Nearest);
        _ -> undefined
    end.

%% Whether proc_lib records the process as started by the supervisor behaviour.
is_supervisor(Pid) ->
    case dictionary_entry(Pid, '$initial_call') of
        {ok, {supervisor, _Module, _Arity}} -> true;
        _ -> false
    end.

dictionary_entry(Pid, Key) ->
    case process_info(Pid, dictionary) of
        {dictionary, Dictionary} ->
            case lists:keyfind(Key, 1, Dictionary) of
                {Key, Value} -> {ok, Value};
                false -> error
            end;
        undefined ->
            error
    end.

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
