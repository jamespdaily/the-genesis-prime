-module(generate_messages_ffi).
-export([plain_arguments/0]).

plain_arguments() ->
    [unicode:characters_to_binary(Argument) || Argument <- init:get_plain_arguments()].
