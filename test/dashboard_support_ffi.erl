-module(dashboard_support_ffi).
-export([free_port/0, bound_addresses/1, accepts/1, open/2, connect_and_send/2, read_reply/1, has_bytes/1,
         read_text_frame/1, close/1, process_alive/1, closes/1, os_pid/0, suspend/1, resume/1,
         queued_calls/1]).

%% A loopback port the system chose: listens on port 0 and closes the socket
%% again, so nothing listens on the port that is returned. The dashboard's
%% server package does not report the port it bound, so a test names the port.
-spec free_port() -> inet:port_number().
free_port() ->
    {ok, Listen} = gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(Listen),
    ok = gen_tcp:close(Listen),
    Port.

%% The local addresses, as text, of this VM's TCP sockets whose local port is
%% `Port`: the listening socket and the connections it accepted. A socket
%% bound to every address would show `0.0.0.0`.
-spec bound_addresses(inet:port_number()) -> [binary()].
bound_addresses(Port) ->
    lists:usort([
        list_to_binary(inet:ntoa(Address))
     || Socket <- erlang:ports(),
        erlang:port_info(Socket, name) =:= {name, "tcp_inet"},
        {ok, {Address, LocalPort}} <- [inet:sockname(Socket)],
        LocalPort =:= Port
    ]).

%% Whether a connection to the loopback address and port is accepted. A local
%% connection to an address nothing listens on is refused at once.
-spec accepts(inet:port_number()) -> boolean().
accepts(Port) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], infinity) of
        {ok, Socket} ->
            ok = gen_tcp:close(Socket),
            true;
        {error, _} ->
            false
    end.

%% Connects to the loopback port, sends the request bytes and reads the answer's
%% head and as much body as its content-length says. The socket stays open for
%% a websocket that was upgraded, and the bytes the server wrote after the head
%% (its first frame, when it wrote the frame before this read ran) stay on the
%% socket for `read_text_frame`. A read waits for the server to write: it ends
%% with the bytes, not with a time.
-spec open(inet:port_number(), binary()) ->
    {port(), integer(), [{binary(), binary()}], binary()}.
open(Port, Request) ->
    read_reply(connect_and_send(Port, Request)).

%% Connects to the loopback port and sends the request bytes, without reading.
-spec connect_and_send(inet:port_number(), binary()) -> port().
connect_and_send(Port, Request) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], infinity),
    ok = gen_tcp:send(Socket, Request),
    Socket.

%% Reads the answer to a request already sent: its head, and its body as `open`
%% reads it.
-spec read_reply(port()) -> {port(), integer(), [{binary(), binary()}], binary()}.
read_reply(Socket) ->
    {Head, Rest} = read_head(Socket, <<>>),
    [StatusLine | HeaderLines] = binary:split(Head, <<"\r\n">>, [global]),
    [_Version, Status | _] = binary:split(StatusLine, <<" ">>, [global]),
    Headers = [header(Line) || Line <- HeaderLines],
    Length =
        case lists:keyfind(<<"content-length">>, 1, Headers) of
            {_, Value} -> binary_to_integer(Value);
            false -> 0
        end,
    Body =
        case binary_to_integer(Status) of
            101 ->
                ok = gen_tcp:unrecv(Socket, Rest),
                <<>>;
            _ -> read_body(Socket, Rest, Length)
        end,
    {Socket, binary_to_integer(Status), Headers, Body}.

%% Whether the server has already written bytes on the connection: they are
%% left on the socket for the next read. A write the server finished before
%% this call is there, since the loopback delivers a write as it is made, so the
%% answer is a fact about the server's writes so far, not a wait.
-spec has_bytes(port()) -> boolean().
has_bytes(Socket) ->
    case gen_tcp:recv(Socket, 0, 0) of
        {ok, Bytes} ->
            ok = gen_tcp:unrecv(Socket, Bytes),
            true;
        {error, timeout} ->
            false
    end.

%% Holds a factory supervisor so that a call to it stays in its mailbox, and
%% lets it go again. The factory's value is Gleam's `{supervisor, Handle}`, the
%% handle being its registered name or its pid.
-spec suspend({supervisor, atom() | pid()}) -> nil.
suspend({supervisor, Handle}) ->
    ok = sys:suspend(Handle),
    nil.

-spec resume({supervisor, atom() | pid()}) -> nil.
resume({supervisor, Handle}) ->
    ok = sys:resume(Handle),
    nil.

%% How many messages wait in the mailbox of a factory supervisor.
-spec queued_calls({supervisor, atom() | pid()}) -> integer().
queued_calls({supervisor, Handle}) ->
    Pid =
        case is_pid(Handle) of
            true -> Handle;
            false -> whereis(Handle)
        end,
    {message_queue_len, Length} = process_info(Pid, message_queue_len),
    Length.

read_head(Socket, Seen) ->
    case binary:split(Seen, <<"\r\n\r\n">>) of
        [Head, Rest] ->
            {Head, Rest};
        [_] ->
            {ok, More} = gen_tcp:recv(Socket, 0, infinity),
            read_head(Socket, <<Seen/binary, More/binary>>)
    end.

read_body(_Socket, Have, Length) when byte_size(Have) >= Length ->
    binary:part(Have, 0, Length);
read_body(Socket, Have, Length) ->
    {ok, More} = gen_tcp:recv(Socket, 0, infinity),
    read_body(Socket, <<Have/binary, More/binary>>, Length).

header(Line) ->
    [Name, Value] = binary:split(Line, <<":">>),
    {string:lowercase(Name), string:trim(Value)}.

%% The payload of the next websocket text frame the server sends (unmasked, with
%% a 7-bit, 16-bit or 64-bit length), after the upgrade's head. A frame whose
%% first byte is not 0x81 (FIN and the text opcode: a close, a binary frame, or
%% the bytes of an HTTP answer written on the upgraded connection) is not read
%% further: the result is the byte that came, so a stream that holds no frame
%% fails the test at once instead of waiting for one.
-spec read_text_frame(port()) -> {ok, binary()} | {error, 0..255}.
read_text_frame(Socket) ->
    {ok, <<First:8>>} = gen_tcp:recv(Socket, 1, infinity),
    case First of
        16#81 ->
            {ok, <<Length:8>>} = gen_tcp:recv(Socket, 1, infinity),
            Size =
                case Length of
                    126 ->
                        {ok, <<Long:16>>} = gen_tcp:recv(Socket, 2, infinity),
                        Long;
                    127 ->
                        {ok, <<Huge:64>>} = gen_tcp:recv(Socket, 8, infinity),
                        Huge;
                    _ ->
                        Length
                end,
            {ok, Payload} = gen_tcp:recv(Socket, Size, infinity),
            {ok, Payload};
        _ ->
            {error, First}
    end.

-spec close(port()) -> nil.
close(Socket) ->
    _ = gen_tcp:close(Socket),
    nil.

%% Whether the operating-system process is alive: `kill -0` finds it.
-spec process_alive(integer()) -> boolean().
process_alive(OsPid) ->
    os:cmd("kill -0 " ++ integer_to_list(OsPid) ++ " 2>&1") =:= [].

%% Reads from the connection until the server closes it, whatever it sends
%% first: true when the close came. A read waits for the server to write or
%% close: it ends with the bytes or the close, not with a time.
-spec closes(port()) -> boolean().
closes(Socket) ->
    case gen_tcp:recv(Socket, 0, infinity) of
        {ok, _} -> closes(Socket);
        {error, closed} -> true;
        {error, _} -> true
    end.

%% The operating-system process id of this VM.
-spec os_pid() -> integer().
os_pid() ->
    list_to_integer(os:getpid()).
