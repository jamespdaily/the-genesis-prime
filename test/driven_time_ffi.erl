-module(driven_time_ffi).
-export([taken_or_ended/1]).

%% Waits until Pid answers sys:get_state, which a process does after taking every
%% message that was in its mailbox before the request, or until Pid ends: the call
%% monitors Pid, so an ended process gives an exit of the shape {Reason, {sys,
%% get_state, Arguments}} (noproc, normal, a crash) and no message is left behind.
taken_or_ended(Pid) ->
    try sys:get_state(Pid, infinity) of
        _State -> nil
    catch
        exit:{_Reason, {sys, get_state, _Arguments}} -> nil
    end.
