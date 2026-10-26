-module(genesis_prime_ffi).
-export([environment_variable/1]).

%% The value of an operating-system environment variable, or {error, nil}
%% when it is not set.
-spec environment_variable(binary()) -> {ok, binary()} | {error, nil}.
environment_variable(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
