-module(table_load_cost_ffi).
-export([total_memory/0, collect_all/0, resident_bytes/0, getenv/1]).

%% The bytes of memory the runtime reports in all, from `erlang:memory(total)`.
-spec total_memory() -> non_neg_integer().
total_memory() ->
    erlang:memory(total).

%% Garbage collects every process, so what is measured next is what is held.
-spec collect_all() -> nil.
collect_all() ->
    lists:foreach(fun erlang:garbage_collect/1, erlang:processes()),
    nil.

%% The bytes of memory this VM holds in the operating system, from `ps`.
-spec resident_bytes() -> non_neg_integer().
resident_bytes() ->
    Output = os:cmd("ps -o rss= -p " ++ os:getpid()),
    list_to_integer(string:trim(Output)) * 1024.

%% The value of an environment variable, or an error when it is not set.
-spec getenv(binary()) -> {ok, binary()} | {error, nil}.
getenv(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
