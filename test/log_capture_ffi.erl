-module(log_capture_ffi).
-export([install/0, receive_from/1, stop_receiving/1, log/2]).

%% The Gleam types of test/log_capture.gleam:
%%   Event(level, text, from, metadata, formatted) is
%%     {event, Level, Text, From, Metadata, Formatted}
%%   Field: Whole(N) is {whole, N}, Fraction(F) is {fraction, F},
%%          Text(T) is {text, T}, Fields(D) is {fields, D}
%% A Gleam subject is {subject, Pid, Tag}, and a message sent to it is
%% {Tag, Message}.

-define(HANDLER, log_capture_handler).
-define(RECEIVERS, log_capture_receivers).

%% Adds the one logger handler of the run, and the table of the subjects that
%% receive what it captures. The table belongs to a process of its own that
%% lives as long as the node. Logger's own handler changes are not safe to
%% make while another process changes the level (a handler change writes back
%% the primary configuration it read before it started), so a test never adds
%% or removes a handler: it registers a subject.
install() ->
    Owner = spawn(fun() ->
                          ets:new(?RECEIVERS, [named_table, public, set]),
                          receive stop -> ok end
                  end),
    wait_for_table(Owner),
    ok = logger:add_handler(?HANDLER, ?MODULE, #{level => all, config => #{}}),
    nil.

wait_for_table(Owner) ->
    case ets:whereis(?RECEIVERS) of
        undefined ->
            true = is_process_alive(Owner),
            timer:sleep(1),
            wait_for_table(Owner);
        _ ->
            ok
    end.

%% Sends every line logged from now on to the subject.
receive_from({subject, _Pid, Tag} = Subject) ->
    ets:insert(?RECEIVERS, {Tag, Subject}),
    nil.

stop_receiving({subject, _Pid, Tag}) ->
    ets:delete(?RECEIVERS, Tag),
    nil.

%% The handler callback of logger: runs in the process that wrote the line.
%% It sends the line, as an event, to each registered subject whose process is
%% alive and forgets the others. A failure here is caught, because logger
%% removes a handler that fails.
log(#{level := Level, msg := Msg, meta := Meta} = LogEvent, _Config) ->
    try
        case ets:tab2list(?RECEIVERS) of
            [] ->
                ok;
            Receivers ->
                Event = {event, atom_to_binary(Level), text(Msg),
                         maps:get(pid, Meta, self()), fields(Meta),
                         formatted(LogEvent)},
                lists:foreach(fun({Tag, {subject, Pid, _} = Subject}) ->
                                      case is_process_alive(Pid) of
                                          true -> Pid ! {Tag, Event};
                                          false -> stop_receiving(Subject)
                                      end
                              end, Receivers)
        end
    catch
        _:_ -> ok
    end,
    ok.

%% The line the node's default handler writes for the event: the event run
%% through the formatter the default handler is configured with. Empty when
%% the node has no default handler.
formatted(Event) ->
    try
        {ok, #{formatter := {Module, Config}}} = logger:get_handler_config(default),
        unicode:characters_to_binary(Module:format(Event, Config))
    catch
        _:_ -> <<>>
    end.

text({string, Text}) -> unicode:characters_to_binary(Text);
text({report, _}) -> <<"report">>;
text({Format, Arguments}) when is_list(Format) ->
    try unicode:characters_to_binary(io_lib:format(Format, Arguments))
    catch _:_ -> <<>>
    end;
text(_) -> <<>>.

%% The metadata entries whose values the Gleam side reads: whole numbers,
%% floats, texts (binaries, or printable lists, which is how logger's own
%% formatter reads a text) and maps of them. Others, such as a pid or a mfa,
%% are left out.
fields(Map) ->
    maps:from_list([{key(Key), Field}
                    || {Key, Value} <- maps:to_list(Map),
                       {ok, Field} <- [field(Value)]]).

field(Value) when is_integer(Value) -> {ok, {whole, Value}};
field(Value) when is_float(Value) -> {ok, {fraction, Value}};
field(Value) when is_binary(Value) -> {ok, {text, Value}};
field(Value) when is_map(Value) -> {ok, {fields, fields(Value)}};
field(Value) when is_list(Value) ->
    case io_lib:printable_unicode_list(Value) of
        true -> {ok, {text, unicode:characters_to_binary(Value)}};
        false -> error
    end;
field(_) -> error.

key(Key) when is_atom(Key) -> atom_to_binary(Key);
key(Key) -> Key.
