-module(play_service_support_ffi).
-export([os_pid/0]).

%% The operating-system process id of this VM: a process a lock owner record
%% can name that is alive for the whole test.
-spec os_pid() -> integer().
os_pid() ->
    list_to_integer(os:getpid()).
