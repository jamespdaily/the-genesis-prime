-module(supervisor_children_ffi).
-export([in_start_order/1]).

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
