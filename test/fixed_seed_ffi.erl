%% The process dictionary of a test's body process holds its name and the record
%% `fixed_seed` makes of it. A count of connections is an atomics array, since a
%% listener's connections count it from their own processes. A body's seed lines
%% are rows of an ETS table the body's `owned_test.run` makes: an insert is whole
%% when it returns, no message is left in anyone's mailbox, and a seed told after
%% the table was dropped is told to nothing.
-module(fixed_seed_ffi).
-export([node_environment/0, put_body/2, get_body/0, new_counter/0, next/1,
         new_log/0, drop_log/1, log_line/2, log_seed_name/2, log_contents/1]).

%% The environment a node the test starts is given, so its settings are seeded
%% under the test's name: the name's variable, or nothing outside a test body.
node_environment() ->
    case get(fixed_seed_name) of
        undefined -> [];
        Name -> [{"GENESIS_TEST_NAME", binary_to_list(Name)}]
    end.

put_body(Name, Body) ->
    put(fixed_seed_name, Name),
    put(fixed_seed_body, Body),
    nil.

get_body() ->
    case get(fixed_seed_body) of
        undefined -> {error, nil};
        Body -> {ok, Body}
    end.

new_counter() -> atomics:new(1, []).

next(Counter) -> atomics:add_get(Counter, 1, 1).

new_log() ->
    ets:new(fixed_seed_log, [public, ordered_set]).

drop_log(Log) ->
    try ets:delete(Log) catch error:badarg -> ok end,
    nil.

log_line(Log, Line) ->
    try ets:insert(Log, {{line, erlang:unique_integer([monotonic])}, Line})
    catch error:badarg -> ok
    end,
    nil.

log_seed_name(Log, Name) ->
    try ets:insert(Log, {seed_name, Name}) catch error:badarg -> ok end,
    nil.

%% The seed name the body gave (empty when none) and the lines told, in the order told.
log_contents(Log) ->
    Name = case ets:lookup(Log, seed_name) of
               [{seed_name, Given}] -> Given;
               [] -> <<>>
           end,
    Lines = [Line || {{line, _}, Line} <- ets:tab2list(Log)],
    {Name, Lines}.
