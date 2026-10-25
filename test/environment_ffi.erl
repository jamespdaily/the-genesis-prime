-module(environment_ffi).
-export([get/1]).

%% The value of an environment variable, or an error when it is not set.
get(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
