-module(owned_test_ffi).
-export([
    is_skip/1,
    run_unless_skipped/1,
    monotonic_milliseconds/0,
    body_name/1,
    mark_body/2,
    counting_build/2
]).

%% unitest marks a skipped test by throwing {gleam_unitest, skip}
%% (unitest_ffi:skip/0); a process that does not catch it exits with
%% {nocatch, {gleam_unitest, skip}}.
is_skip({{nocatch, {gleam_unitest, skip}}, _Stack}) -> true;
is_skip({nocatch, {gleam_unitest, skip}}) -> true;
is_skip(_) -> false.

run_unless_skipped(Body) ->
    try {ok, Body()}
    catch throw:{gleam_unitest, skip} -> {error, nil}
    end.

monotonic_milliseconds() ->
    erlang:monotonic_time(millisecond).

%% A closure made in a function is named '-function/arity-fun-N-' by the
%% compiler: the test function the body was written in.
body_name(Body) ->
    {module, Module} = erlang:fun_info(Body, module),
    {name, Name} = erlang:fun_info(Body, name),
    Function =
        case atom_to_list(Name) of
            [$- | Rest] -> lists:takewhile(fun(Char) -> Char =/= $/ end, Rest);
            Plain -> Plain
        end,
    unicode:characters_to_binary([atom_to_list(Module), ":", Function]).

mark_body(Opened, Closed) ->
    put(owned_test_builds, {Opened, Closed}),
    nil.

%% Runs Build, and tells the test that owns this process, when this process is
%% its body, that a one-time build for Key is open until Build ends, so the
%% test's deadline does not count it. A process that is not a test body just
%% runs Build.
counting_build(Key, Build) ->
    case get(owned_test_builds) of
        undefined ->
            Build();
        {Opened, Closed} ->
            Opened(Key),
            try
                Build()
            after
                Closed()
            end
    end.
