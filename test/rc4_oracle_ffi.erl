-module(rc4_oracle_ffi).
-export([encrypt/2]).

%% The bytes OTP's crypto gives when RC4 under Key ciphers Data in one call:
%% the oracle the Gleam RC4 is compared with.
-spec encrypt(binary(), binary()) -> binary().
encrypt(Key, Data) ->
    crypto:crypto_one_time(rc4, Key, Data, true).
