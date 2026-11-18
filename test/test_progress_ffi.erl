-module(test_progress_ffi).
-export([started/2, ended/2]).

%% One line per event, appended with one write, so tests on different schedulers or in
%% different VMs sharing the file never mix their lines:
%%   start ID SECONDS NAME
%%   end ID
%% ID is the VM's operating system process and a number of that VM, so two tests never
%% share one. SECONDS is the wall clock's seconds, which ./check subtracts from its own.
started(File, Name) ->
    Id = iolist_to_binary([os:getpid(), $., integer_to_list(erlang:unique_integer([positive]))]),
    append(File, [<<"start ">>, Id, $\s, integer_to_list(erlang:system_time(second)), $\s, Name, $\n]),
    Id.

ended(File, Id) ->
    append(File, [<<"end ">>, Id, $\n]),
    nil.

append(File, Line) ->
    ok = file:write_file(File, Line, [append, raw]).
