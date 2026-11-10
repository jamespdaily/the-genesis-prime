%% The process dictionary holds, in a test's body process, the two functions
%% that tell the test a wait is open and has ended. A process without them just
%% runs the wait.
-module(open_wait_ffi).
-export([named/2, report_to/2]).

report_to(Opened, Closed) ->
    put(open_wait_report, {Opened, Closed}),
    nil.

named(What, Wait) ->
    case get(open_wait_report) of
        undefined ->
            Wait();
        {Opened, Closed} ->
            Opened(What),
            try
                Wait()
            after
                Closed()
            end
    end.
