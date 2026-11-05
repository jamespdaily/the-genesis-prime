%% A transaction on a pool with the deadline its caller names
%% (`genesis_prime/dev_database`). `pog.transaction` checks its connection out
%% with no options, and a checkout that names no deadline is dropped by the pool
%% after 5,000 ms, however many statements the transaction still has to run; pog
%% has no way to name another. `pgo:transaction/2` takes the deadline, and the
%% queries pog runs on the pool from the same process run on its connection.
-module(dev_database_ffi).
-export([transaction/3]).

%% Runs `Work(Db)` in one transaction on a connection of the pool `Db` is
%% (pog's `{pool, Name}`), checked out for `DeadlineMs`. `Work` gives `{ok, Value}`
%% to commit or `{error, Error}` to roll back. Gives `{ok, Value}`,
%% `{error, {undone, Error}}` or `{error, no_connection}` when the pool had none.
transaction({pool, Pool} = Db, DeadlineMs, Work) ->
    Options = #{pool => Pool, pool_options => [{timeout, DeadlineMs}]},
    try pgo:transaction(fun() -> commit_or_undo(Work(Db)) end, Options) of
        {ok, _} = Done -> Done;
        {error, _} -> {error, no_connection}
    catch
        throw:{undone, Error} -> {error, {undone, Error}}
    end.

%% A throw makes pgo roll the transaction back before it passes the throw on.
commit_or_undo({ok, _} = Done) -> Done;
commit_or_undo({error, Error}) -> throw({undone, Error}).
