-module(log_ffi).
-export([emit/4, configure/1]).

%% The Gleam types of src/genesis_prime/telemetry/log.gleam, as Gleam
%% represents them:
%%   Level: error_level, warning_level, info_level, debug_level
%%   Who(account, actor, place, message, peer) is
%%     {who, Account, Actor, Place, Message, Peer},
%%     each an Option: {some, Value} or none
%%   Actor: {character, Id} or {unit, Id}
%%   Place: {process, Name} or {map, Id}
%%   Message: {named, Name, Number} or {numbered, Number}
%%   Number: {count, Integer} or {ratio, Float}
%% Each constructor's name is the metadata key of its value, except a named
%% message, whose name and number are `message_name` and `message_number`.
%% The peer is a text under `peer`.

%% Writes a line through logger at the level, with the metadata of who and
%% where, and the numbers, when there are any, as one map under `numbers`.
-spec emit(error_level | warning_level | info_level | debug_level,
           tuple(), binary(), #{binary() => {count, integer()} | {ratio, float()}}) -> nil.
emit(Level, Who, Text, Numbers) ->
    logger:log(level(Level), Text, metadata(Who, Numbers)),
    nil.

%% Sets logger's primary level: debug when the argument is true, info
%% otherwise. It also sets the formatter of the default handler to write each
%% line on one line with its level, its text and every metadata key this
%% module sets, as `key=value`, because logger's own formatter writes the text
%% alone. A node with no default handler is left as it is.
-spec configure(boolean()) -> nil.
configure(Debug) ->
    Level = case Debug of
                true -> debug;
                false -> info
            end,
    ok = logger:set_primary_config(level, Level),
    _ = logger:update_handler_config(
          default, formatter,
          {logger_formatter, #{single_line => true, template => template()}}),
    nil.

%% The metadata keys `metadata/2` sets, in the order a line prints them.
keys() ->
    [account, character, unit, process, map, message_name, message_number,
     peer, numbers].

%% The template of the default handler's formatter: the time, the level, the
%% text, each key the line has as ` key=value`, and the end of the line.
template() ->
    [time, " ", level, " ", msg]
    ++ [{Key, [" ", atom_to_list(Key), "=", Key], []} || Key <- keys()]
    ++ ["\n"].

level(error_level) -> error;
level(warning_level) -> warning;
level(info_level) -> info;
level(debug_level) -> debug.

metadata({who, Account, Actor, Place, Message, Peer}, Numbers) ->
    maps:from_list(account(Account) ++ actor(Actor) ++ place(Place)
                   ++ message(Message) ++ peer(Peer) ++ numbers(Numbers)).

account({some, Id}) -> [{account, Id}];
account(none) -> [].

actor({some, {character, Id}}) -> [{character, Id}];
actor({some, {unit, Id}}) -> [{unit, Id}];
actor(none) -> [].

place({some, {process, Name}}) -> [{process, text(Name)}];
place({some, {map, Id}}) -> [{map, Id}];
place(none) -> [].

message({some, {named, Name, Number}}) ->
    [{message_name, text(Name)}, {message_number, Number}];
message({some, {numbered, Number}}) -> [{message_number, Number}];
message(none) -> [].

peer({some, Address}) -> [{peer, text(Address)}];
peer(none) -> [].

numbers(Numbers) when map_size(Numbers) =:= 0 -> [];
numbers(Numbers) ->
    [{numbers, maps:map(fun(_Name, {count, Count}) -> Count;
                           (_Name, {ratio, Ratio}) -> Ratio
                        end, Numbers)}].

%% A text as a string, the form logger's formatter writes as itself in a
%% template; a binary it writes as `<<"...">>`.
text(Text) ->
    unicode:characters_to_list(Text).
