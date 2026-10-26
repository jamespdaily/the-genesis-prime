-module(fake_clock_ffi).
-export([new/1, read/1, advance/2]).

%% An atomics array of one signed integer, so the owner's process reads what
%% the test process wrote.
-spec new(integer()) -> atomics:atomics_ref().
new(Start) ->
    Ref = atomics:new(1, [{signed, true}]),
    atomics:put(Ref, 1, Start),
    Ref.

-spec read(atomics:atomics_ref()) -> integer().
read(Ref) ->
    atomics:get(Ref, 1).

-spec advance(atomics:atomics_ref(), integer()) -> nil.
advance(Ref, Milliseconds) ->
    atomics:add(Ref, 1, Milliseconds),
    nil.
