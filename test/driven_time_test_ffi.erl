-module(driven_time_test_ffi).
-export([system_request/1, answer/1]).

%% What a system message asks of a process that has no state to give: to suspend, to
%% resume, or something else, which is not a request the barrier makes. The request
%% is {system, From, suspend} or {system, From, resume}.
system_request({system, _From, suspend}) -> suspend;
system_request({system, _From, resume}) -> resume;
system_request(_Other) -> unknown.

%% Answers the request, as a process does that takes it and goes on.
answer({system, From, _Request}) ->
    gen:reply(From, ok),
    nil.
