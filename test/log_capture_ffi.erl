-module(log_capture_ffi).
-export([add/1, remove/1, log/2]).

%% The Gleam types of test/log_capture.gleam:
%%   Event(level, text, from, metadata) is {event, Level, Text, From, Metadata}
%%   Handle(id)                         is {handle, Id}
%%   Field: Whole(N) is {whole, N}, Fraction(F) is {fraction, F},
%%          Text(T) is {text, T}, Fields(D) is {fields, D}
%% A Gleam subject is {subject, Pid, Tag}, and a message sent to it is
%% {Tag, Message}.

%% Adds a logger handler that sends every line it is given, as an event, to
%% the subject. Returns the handle that removes it.
add(Subject) ->
    Id = list_to_atom("log_capture_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = logger:add_handler(Id, ?MODULE, #{level => all, config => #{subject => Subject}}),
    {handle, Id}.

remove({handle, Id}) ->
    _ = logger:remove_handler(Id),
    nil.

%% The handler callback of logger: runs in the process that wrote the line.
%% A handler that fails is removed by logger, so a failure here is caught and
%% leaves the line uncaptured. A handler whose receiver has ended removes
%% itself, from a process of its own, as logger does not allow it from inside
%% the callback.
log(#{level := Level, msg := Msg, meta := Meta}, #{id := Id, config := #{subject := {subject, Pid, Tag}}}) ->
    case is_process_alive(Pid) of
        true ->
            try
                From = maps:get(pid, Meta, self()),
                Pid ! {Tag, {event, atom_to_binary(Level), text(Msg), From, fields(Meta)}}
            catch
                _:_ -> ok
            end;
        false ->
            spawn(fun() -> logger:remove_handler(Id) end)
    end,
    ok.

text({string, Text}) -> unicode:characters_to_binary(Text);
text({report, _}) -> <<"report">>;
text({Format, Arguments}) when is_list(Format) ->
    try unicode:characters_to_binary(io_lib:format(Format, Arguments))
    catch _:_ -> <<>>
    end;
text(_) -> <<>>.

%% The metadata entries whose values the Gleam side reads: whole numbers,
%% floats, texts and maps of them. Others, such as a pid or a mfa, are left out.
fields(Map) ->
    maps:from_list([{key(Key), Field}
                    || {Key, Value} <- maps:to_list(Map),
                       {ok, Field} <- [field(Value)]]).

field(Value) when is_integer(Value) -> {ok, {whole, Value}};
field(Value) when is_float(Value) -> {ok, {fraction, Value}};
field(Value) when is_binary(Value) -> {ok, {text, Value}};
field(Value) when is_map(Value) -> {ok, {fields, fields(Value)}};
field(_) -> error.

key(Key) when is_atom(Key) -> atom_to_binary(Key);
key(Key) -> Key.
