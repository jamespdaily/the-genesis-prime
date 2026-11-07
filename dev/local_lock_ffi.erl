%% A lock on one node whose waiters are woken when the holder lets go.
%%
%% Kernel's global:trans makes a waiter sleep a random time that doubles on each
%% try, up to 8 seconds, and never wakes it when the lock is released, so a
%% waiter can return seconds after the holder ended.
%%
%% The lock is a registered name. The holder registers a gate process under it;
%% the gate ends when the holder releases or ends, and a waiter monitors the
%% gate, so it wakes when the name is free.
-module(local_lock_ffi).
-export([with_lock/2]).

%% Runs Fun while holding the lock Name and returns what Fun returns. A caller
%% that finds the lock held waits for its holder to end and tries again. The
%% lock is not re-entrant: a Fun that takes the same Name again waits forever.
%% Name is an atom the caller made from a small fixed set, since atoms are never
%% collected.
with_lock(Name, Fun) when is_atom(Name) ->
    Caller = self(),
    Gate = spawn(fun() -> gate(Caller) end),
    try register(Name, Gate) of
        true ->
            try Fun() after Gate ! release end
    catch
        error:badarg ->
            exit(Gate, kill),
            wait_for_holder(Name),
            with_lock(Name, Fun)
    end.

%% Holds the name for the caller until it releases or ends.
gate(Caller) ->
    Monitor = monitor(process, Caller),
    receive
        release -> ok;
        {'DOWN', Monitor, process, Caller, _Reason} -> ok
    end.

%% Waits until the process that holds the name has ended. A name that is free
%% by now needs no wait.
wait_for_holder(Name) ->
    case whereis(Name) of
        undefined ->
            ok;
        Holder ->
            Monitor = monitor(process, Holder),
            receive
                {'DOWN', Monitor, process, Holder, _Reason} -> ok
            end
    end.
