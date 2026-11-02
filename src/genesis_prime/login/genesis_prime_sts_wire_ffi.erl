%% The scan for the blank line that ends an STS head (genesis_prime/login/
%% sts_wire). Gleam's bit_array has no search, and OTP's binary:match scans
%% the bytes once without building the head a byte at a time.
-module(genesis_prime_sts_wire_ffi).

-export([find/3]).

%% Where the first Pattern starts in the first Within bytes of Bytes, a pattern
%% that ends past them being no match. Bytes is a binary of whole bytes, as
%% every socket read and every slice of one is. Result(Int, Nil).
find(Bytes, Pattern, Within) ->
    case binary:match(Bytes, Pattern,
                      [{scope, {0, min(byte_size(Bytes), Within)}}]) of
        {Start, _Length} -> {ok, Start};
        nomatch -> {error, nil}
    end.
