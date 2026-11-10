-module(driven_time_test_ffi).
-export([answered_get_state/1]).

%% Answers a sys:get_state request the way a process that has no state to give does,
%% and says whether the message was one. The request is {system, From, get_state}.
answered_get_state({system, From, get_state}) ->
    gen:reply(From, {ok, nil}),
    true;
answered_get_state(_Other) ->
    false.
