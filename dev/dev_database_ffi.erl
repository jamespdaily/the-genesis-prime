%% A transaction on a pool with the deadline its caller names
%% (`genesis_prime/dev_database`). `pog.transaction` checks its connection out
%% with no options, and a checkout that names no deadline is dropped by the pool
%% after 5,000 ms, however many statements the transaction still has to run; pog
%% has no way to name another. This checks the connection out with the deadline
%% and runs pog's own steps on it (`begin`, the work, `commit` or `rollback`, each
%% through pog's `query_extended`, so each failure is the query error pog gives).
%% The queries pog runs on the pool from the same process run on that connection.
-module(dev_database_ffi).
-export([transaction/3]).

%% Runs `Work(Db)` in one transaction on a connection of the pool `Db` is
%% (pog's `{pool, Name}`), checked out for `DeadlineMs`. `Work` gives `{ok, Value}`
%% to commit or `{error, Error}` to roll back. Gives `{ok, Value}`,
%% `{error, {undone, Error}}`, `{error, no_connection}` when the pool had none,
%% `{error, {failed, QueryError}}` when `begin`, `commit` or the rollback failed,
%% or `{error, not_a_pool}` for a single connection.
transaction({pool, Pool} = Db, DeadlineMs, Work) ->
    case pgo:checkout(Pool, [{timeout, DeadlineMs}]) of
        {ok, Ref, Conn} ->
            try
                pgo:with_conn(Conn, fun() -> run(Conn, Db, Work) end)
            after
                pgo:checkin(Ref, Conn)
            end;
        {error, _} ->
            {error, no_connection}
    end;
transaction({single_connection, _}, _DeadlineMs, _Work) ->
    {error, not_a_pool}.

run(Conn, Db, Work) ->
    case pog_ffi:query_extended(Conn, <<"begin">>) of
        {ok, _} -> work(Conn, Db, Work);
        {error, Error} -> {error, {failed, Error}}
    end.

work(Conn, Db, Work) ->
    try Work(Db) of
        {ok, _} = Done ->
            case pog_ffi:query_extended(Conn, <<"commit">>) of
                {ok, _} -> Done;
                {error, Error} -> {error, {failed, Error}}
            end;
        {error, Error} ->
            case pog_ffi:query_extended(Conn, <<"rollback">>) of
                {ok, _} -> {error, {undone, Error}};
                {error, Failed} -> {error, {failed, Failed}}
            end
    catch
        Class:Reason:Stacktrace ->
            pog_ffi:query_extended(Conn, <<"rollback">>),
            erlang:raise(Class, Reason, Stacktrace)
    end.
