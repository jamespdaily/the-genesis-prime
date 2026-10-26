-module(pool_started_ffi).
-export([await/2]).

%% Whether the pool registered as Name has started within WithinMs
%% milliseconds. The pool's own processes are pgo's (pgo_pool.erl,
%% pgo_pool_sup.erl): the pool, whose supervisor holds the connection
%% supervisor, the connection starter and the type server. A gen_statem or
%% gen_server answers a system request only between events, so `sys:get_state`
%% on a process returns once the event it is in has ended: the starter's first
%% event starts every connection and then calls the type server, which loads
%% the types through a connection, and a connection's first event opens it.
%% Every one of them has answered when the pool has started, and a pool whose
%% database is away never does.
-spec await(atom(), non_neg_integer()) -> boolean().
await(Name, WithinMs) ->
    Deadline = erlang:monotonic_time(millisecond) + WithinMs,
    case whereis(Name) of
        undefined -> false;
        Pool ->
            try started(Pool, Deadline)
            catch exit:_ -> false
            end
    end.

started(Pool, Deadline) ->
    idle(Pool, Deadline),
    Sup = pool_supervisor(Pool),
    Children = supervisor:which_children(Sup),
    idle(child(connection_starter, Children), Deadline),
    ConnectionSup = child(connection_sup, Children),
    Connections = [Pid || {_, Pid, _, _} <- supervisor:which_children(ConnectionSup),
                          is_pid(Pid)],
    lists:foreach(fun(Pid) -> idle(Pid, Deadline) end, Connections),
    true.

%% Returns when the process is between events, and exits when that takes past
%% the deadline or the process is gone.
idle(Pid, Deadline) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    _ = sys:get_state(Pid, Remaining),
    ok.

%% The supervisor the pool process started and is linked to.
pool_supervisor(Pool) ->
    {links, Links} = process_info(Pool, links),
    [Sup] = [Pid || Pid <- Links, is_pid(Pid),
                    proc_lib:translate_initial_call(Pid) =:= {supervisor, pgo_pool_sup, 1}],
    Sup.

child(Id, Children) ->
    {Id, Pid, _, _} = lists:keyfind(Id, 1, Children),
    Pid.
