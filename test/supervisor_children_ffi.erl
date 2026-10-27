-module(supervisor_children_ffi).
-export([in_start_order/1, settings_in_start_order/1]).

%% `supervisor:which_children/1` lists the newest child first, so the list is
%% reversed; the test `the_children_of_a_planted_supervisor_read_back_in_the_order_they_started_test`
%% checks that against the starts of planted children.
-spec in_start_order(pid()) -> [pid()].
in_start_order(Supervisor) ->
    lists:reverse([
        Child
     || {_Id, Child, _Type, _Modules} <- supervisor:which_children(Supervisor),
        is_pid(Child)
    ]).

%% The restart and shutdown settings of each running child, oldest first, as
%% the supervisor's child specs hold them; a shutdown of infinity is none.
-spec settings_in_start_order(pid()) -> [{child_settings, atom(), none | {some, non_neg_integer()}}].
settings_in_start_order(Supervisor) ->
    lists:reverse([
        begin
            {ok, #{restart := Restart, shutdown := Shutdown}} =
                supervisor:get_childspec(Supervisor, Id),
            {child_settings, Restart, shutdown(Shutdown)}
        end
     || {Id, Child, _Type, _Modules} <- supervisor:which_children(Supervisor),
        is_pid(Child)
    ]).

shutdown(infinity) -> none;
shutdown(Milliseconds) when is_integer(Milliseconds) -> {some, Milliseconds}.
