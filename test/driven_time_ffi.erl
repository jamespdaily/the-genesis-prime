-module(driven_time_ffi).
-export([taken_or_ended/1]).

%% Waits until Pid answers sys:suspend, which a process does after taking every
%% message that was in its mailbox before the request, and then lets it go on
%% (sys:resume), or until Pid ends: the call monitors Pid, so an ended process gives
%% an exit of the shape {Reason, {sys, Function, Arguments}} (noproc, normal, a
%% crash) and no message is left behind. The request is not sys:get_state, which
%% copies the process's whole state to the caller: it took about 0.7 ms for each of
%% the tutorial path's 69 participants, where this takes about 3 microseconds.
taken_or_ended(Pid) ->
    try
        ok = sys:suspend(Pid, infinity),
        ok = sys:resume(Pid, infinity),
        nil
    catch
        exit:{_Reason, {sys, _Function, _Arguments}} -> nil
    end.
