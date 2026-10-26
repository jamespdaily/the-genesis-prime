-module(login_clock_ffi).
-export([new/0, read/1, set/2]).

%% A clock at 0, held in an atomics array so every process of a test reads it.
new() ->
    atomics:new(1, [{signed, true}]).

read(Clock) ->
    atomics:get(Clock, 1).

set(Clock, Milliseconds) ->
    atomics:put(Clock, 1, Milliseconds),
    nil.
