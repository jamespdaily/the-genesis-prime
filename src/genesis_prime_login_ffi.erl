-module(genesis_prime_login_ffi).
-export([
    mod_pow/3,
    rc4_start/1,
    rc4_crypt/2
]).

%% Base to the power of Exponent modulo Modulus, as whole numbers.
-spec mod_pow(integer(), integer(), integer()) -> integer().
mod_pow(Base, Exponent, Modulus) ->
    crypto:bytes_to_integer(crypto:mod_pow(Base, Exponent, Modulus)).

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
