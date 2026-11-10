%% The process dictionary holds, in a test's body process, for each slot (a
%% one-time build, or a wait), the two functions that tell the test something
%% is open and has ended. A process without them just runs it.
-module(open_wait_ffi).
-export([named/2, report_to/3, reported/3]).

report_to(Slot, Opened, Closed) ->
    put({open_wait_report, Slot}, {Opened, Closed}),
    nil.

named(What, Wait) ->
    reported(wait, What, Wait).

%% Runs Run, and tells the test that owns this process, when this process is its
%% body, that What is open in Slot until Run ends, by its return or by a crash.
reported(Slot, What, Run) ->
    case get({open_wait_report, Slot}) of
        undefined ->
            Run();
        {Opened, Closed} ->
            Opened(What),
            try
                Run()
            after
                Closed()
            end
    end.
