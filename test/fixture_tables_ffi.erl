-module(fixture_tables_ffi).
-export([after_body/2, pack/1, unpack/1]).

%% Runs Body, then Cleanup, also when Body crashes, so the tables a crashing
%% test body loaded are unloaded and the failure that shows is the body's.
after_body(Body, Cleanup) ->
    try
        Body()
    after
        Cleanup()
    end.

%% The rows as one binary, and the rows back from it: a binary held in a
%% persistent term does not take the literal area a term of the same rows does.
pack(Rows) -> term_to_binary(Rows).

unpack(Packed) -> binary_to_term(Packed).
