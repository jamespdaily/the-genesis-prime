-module(store_ffi).
-export([put/2, erase/1]).

%% Writes a persistent term, the Gleam way: nil for done.
-spec put({reference(), binary()}, tuple()) -> nil.
put(Key, Table) ->
    persistent_term:put(Key, Table),
    nil.

%% Erases a persistent term, whether it was written or not.
-spec erase({reference(), binary()}) -> nil.
erase(Key) ->
    persistent_term:erase(Key),
    nil.
