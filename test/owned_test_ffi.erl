-module(owned_test_ffi).
-export([is_skip/1]).

%% unitest marks a skipped test by throwing {gleam_unitest, skip}
%% (unitest_ffi:skip/0); a process that does not catch it exits with
%% {nocatch, {gleam_unitest, skip}}.
is_skip({{nocatch, {gleam_unitest, skip}}, _Stack}) -> true;
is_skip({nocatch, {gleam_unitest, skip}}) -> true;
is_skip(_) -> false.
