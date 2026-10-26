-module(supervisor_flags_ffi).
-export([read/1]).

%% The supervisor's flags as the Gleam record `Flags(strategy, intensity,
%% period)`, which is the tuple {flags, Strategy, Intensity, Period}, with the
%% strategy as the atom of the Gleam variant (one_for_one, one_for_all or
%% rest_for_one). `supervisor` keeps its flags in the record
%% #state{name, strategy, children, dynamics, intensity, period, ...}
%% (lib/stdlib/src/supervisor.erl of OTP 29.1.2), so they are elements 3, 6
%% and 7 of the state; a state of any other shape is an error, not a guess.
-spec read(pid()) ->
    {flags, one_for_one | one_for_all | rest_for_one, non_neg_integer(),
        pos_integer()}.
read(Supervisor) ->
    case sys:get_state(Supervisor) of
        State when element(1, State) =:= state,
                   (element(3, State) =:= one_for_one
                    orelse element(3, State) =:= one_for_all
                    orelse element(3, State) =:= rest_for_one),
                   is_integer(element(6, State)),
                   is_integer(element(7, State)) ->
            {flags, element(3, State), element(6, State), element(7, State)};
        Other ->
            error({unexpected_supervisor_state, Other})
    end.
