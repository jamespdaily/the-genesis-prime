%% Finds where Erlang source calls or refers to named functions, read with
%% Erlang's own scanner, so comments, strings and whitespace are what the
%% compiler sees. Each target is {target, Module, Function}; it counts when
%% Function is qualified by Module, or unqualified when Module is erlang (an
%% auto-imported BIF), and is called (followed by `(`) or referred to as a fun
%% (followed by `/`). Gives the line of each, or the line where the text stops
%% scanning.
-module(erlang_calls_ffi).
-export([lines/2, atom_lines/2, timed_receive_lines/1]).

%% Reads Text with the scanner and gives Fun the tokens; text that does not
%% scan gives the line where it stops.
scanned(Text, Fun) ->
    case erl_scan:string(unicode:characters_to_list(Text)) of
        {ok, Tokens, _End} -> Fun(Tokens);
        {error, {Anno, _Module, _Reason}, _} -> [erl_anno:line(Anno)]
    end.

%% The line of each atom the text writes that is Name or starts with Name and
%% an underscore (`pgo` and `pgo_pool_sup` for Name `pgo`), read with the same
%% scanner, so a comment or a string is not one; text that does not scan gives
%% the line where it stops.
atom_lines(Text, Name) ->
    Whole = binary_to_atom(Name),
    Prefix = binary_to_list(Name) ++ "_",
    scanned(Text, fun(Tokens) ->
        [erl_anno:line(Anno) || {atom, Anno, Atom} <- Tokens,
                                Atom =:= Whole orelse
                                    lists:prefix(Prefix, atom_to_list(Atom))]
    end).

%% The line of the `after` of each `receive` whose timeout is not the integer 0
%% or `infinity`, read with the same scanner. A stack of the open blocks tells a receive's
%% `after` from a try's: each block opener is pushed, `end` pops, and a form's
%% end empties the stack, since a `fun` in a type has no `end`. Text that does
%% not scan gives the line where it stops.
timed_receive_lines(Text) ->
    scanned(Text, fun(Tokens) -> timed(Tokens, [], []) end).

timed([], _Open, Found) ->
    lists:reverse(Found);
timed([{dot, _} | Rest], _Open, Found) ->
    timed(Rest, [], Found);
timed([{'receive', _} | Rest], Open, Found) ->
    timed(Rest, ['receive' | Open], Found);
timed([{'after', Anno} | Rest], ['receive' | _] = Open, Found) ->
    case Rest of
        [{integer, _, 0}, {'->', _} | _] -> timed(Rest, Open, Found);
        [{atom, _, infinity}, {'->', _} | _] -> timed(Rest, Open, Found);
        _ -> timed(Rest, Open, [erl_anno:line(Anno) | Found])
    end;
timed([{'fun', _} | Rest], Open, Found) ->
    case Rest of
        [{'(', _} | _] -> timed(Rest, [block | Open], Found);
        [{var, _, _}, {'(', _} | _] -> timed(Rest, [block | Open], Found);
        _ -> timed(Rest, Open, Found)
    end;
timed([{Opener, _} | Rest], Open, Found)
  when Opener =:= 'try'; Opener =:= 'case'; Opener =:= 'if'; Opener =:= 'begin';
       Opener =:= 'maybe' ->
    timed(Rest, [block | Open], Found);
timed([{'end', _} | Rest], [_ | Open], Found) ->
    timed(Rest, Open, Found);
timed([_ | Rest], Open, Found) ->
    timed(Rest, Open, Found).

lines(Text, Targets) ->
    Wanted = [{binary_to_atom(M), binary_to_atom(F)} || {target, M, F} <- Targets],
    scanned(Text, fun(Tokens) -> walk(Tokens, none, none, Wanted, []) end).

%% Before is the token just before the current one, BeforeThat the one before.
walk([], _, _, _, Found) ->
    lists:reverse(Found);
walk([{atom, Anno, Name} = Token | Rest], Before, BeforeThat, Wanted, Found) ->
    Counts = lists:member({module_of(Before, BeforeThat), Name}, Wanted)
        andalso called_or_referred(Rest),
    Next = case Counts of
               true -> [erl_anno:line(Anno) | Found];
               false -> Found
           end,
    walk(Rest, Token, Before, Wanted, Next);
walk([Token | Rest], Before, _BeforeThat, Wanted, Found) ->
    walk(Rest, Token, Before, Wanted, Found).

%% The module a name is qualified by; an unqualified name is erlang's.
module_of({':', _}, {atom, _, Module}) -> Module;
module_of({':', _}, _) -> none;
module_of(_, _) -> erlang.

called_or_referred([{'(', _} | _]) -> true;
called_or_referred([{'/', _} | _]) -> true;
called_or_referred(_) -> false.
