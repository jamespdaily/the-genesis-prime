-module(genesis_prime_login_ffi).
-export([
    mod_pow/3,
    parse_xml/1,
    rc4_start/1,
    rc4_crypt/2
]).

%% Base to the power of Exponent modulo Modulus, as whole numbers.
-spec mod_pow(integer(), integer(), integer()) -> integer().
mod_pow(Base, Exponent, Modulus) ->
    crypto:bytes_to_integer(crypto:mod_pow(Base, Exponent, Modulus)).

%% The root element of an XML body as {element, Name, Text, Children}, with
%% names and text as binaries, or why the bytes are not one. The caller has
%% refused a body with a document type, which xmerl would expand; xmerl_sax_parser
%% makes no atoms from the names it reads.
-spec parse_xml(binary()) -> {ok, tuple()} | {error, not_well_formed}.
parse_xml(Body) ->
    try xmerl_sax_parser:stream(Body, [{event_fun, fun event/3}, {event_state, []}]) of
        {ok, Stack, _Rest} -> root(Stack);
        _ -> {error, not_well_formed}
    catch
        _:_ -> {error, not_well_formed}
    end.

%% The parser's state is the stack of open elements, innermost first, each
%% {Name, Text, Children} with the children newest first, and the finished root
%% once the stack is empty.
event({startElement, _Uri, _Local, {_Prefix, Qualified}, _Attributes}, _Location, Stack) ->
    [{unicode:characters_to_binary(Qualified), [], []} | Stack];
event({characters, Characters}, _Location, [{Name, Text, Children} | Stack]) ->
    [{Name, [Text, Characters], Children} | Stack];
event({endElement, _Uri, _Local, _Qualified}, _Location, [Open]) ->
    {done, close(Open)};
event({endElement, _Uri, _Local, _Qualified}, _Location, [Open, {Name, Text, Children} | Stack]) ->
    [{Name, Text, [close(Open) | Children]} | Stack];
event(_Other, _Location, State) ->
    State.

close({Name, Text, Children}) ->
    {element, Name, unicode:characters_to_binary(Text), lists:reverse(Children)}.

root({done, Root}) -> {ok, Root};
root(_) -> {error, not_well_formed}.

%% An RC4 stream under Key, whose state OTP's crypto holds.
-spec rc4_start(binary()) -> {ok, term()} | {error, unsupported}.
rc4_start(Key) ->
    try crypto:crypto_init(rc4, Key, true) of
        State -> {ok, State}
    catch
        error:notsup -> {error, unsupported};
        error:{notsup, _, _} -> {error, unsupported}
    end.

%% The bytes ciphered with the stream's next bytes.
-spec rc4_crypt(term(), binary()) -> binary().
rc4_crypt(State, Bytes) ->
    crypto:crypto_update(State, Bytes).
