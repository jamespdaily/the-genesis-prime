-module(fixture_tables_ffi).
-export([after_body/2]).

%% Runs Body, then Cleanup, also when Body crashes, so the tables a crashing
%% test body loaded are unloaded and the failure that shows is the body's.
after_body(Body, Cleanup) ->
    try
        Body()
    after
        Cleanup()
    end.
