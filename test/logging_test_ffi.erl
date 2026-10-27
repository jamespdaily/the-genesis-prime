%% Reads and sets the logger's primary level, for the logging test.
-module(logging_test_ffi).
-export([primary_level/0, set_primary_level/1]).

primary_level() ->
    #{level := Level} = logger:get_primary_config(),
    Level.

set_primary_level(Level) ->
    ok = logger:set_primary_config(level, Level),
    nil.
