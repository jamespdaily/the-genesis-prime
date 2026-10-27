-module(genesis_prime_login_ffi).
-export([
    mod_pow/3
]).

%% Base to the power of Exponent modulo Modulus, as whole numbers.
-spec mod_pow(integer(), integer(), integer()) -> integer().
mod_pow(Base, Exponent, Modulus) ->
    crypto:bytes_to_integer(crypto:mod_pow(Base, Exponent, Modulus)).
