-- The currencies a character holds, one row each, and the credits a new character starts
-- with. The client sends them in message 0x25e (15 slots of 64 bits, the types 1 to 15 in
-- order, credits first: opcode.0x25e) and changes one with message 0x919; a purchase takes
-- credits in the same transaction that adds the items (genesis_prime/store).
--
-- A currency with no row reads as 0, the client's start value (opcode.0x25e.safe_body), so
-- the load fills the slots a character has no row for with 0; a row may hold 0 too, as a
-- purchase that spends every credit leaves one. The type is one of the 14 the client keeps (SetCurrency 0x1403b5730);
-- 0x919 drops the kinds 14 to 21. The amount is 64 bits like both messages' totals and is
-- never negative. The credit cap (GameFormula 1115) depends on an account flag
-- (0x1403b59f0) and a purchase only lowers the total, so the table holds no upper bound:
-- the step that adds credits applies the cap.

create table character_currency (
  character_id bigint not null,
  currency_type_id smallint not null,
  amount bigint not null,
  constraint character_currency_pkey primary key (character_id, currency_type_id),
  constraint character_currency_character_exists
    foreign key (character_id) references character (character_id) on delete cascade,
  constraint character_currency_type_is_kept
    check (currency_type_id between 1 and 14),
  constraint character_currency_amount_is_not_negative check (amount >= 0)
);

-- The credits a new character starts with, a server choice: the client holds no starting
-- amount, so a character would start with 0 and could buy nothing until something pays
-- credits. The game_number row below is the one place the amount is written, and each
-- character that exists is given it. A whole number of credits, not negative.

insert into game_number_name (name, unit) values
  ('starting_credits', 'units');

alter table game_number
  add constraint game_number_starting_credits_is_a_whole_number_of_credits
    check (name <> 'starting_credits' or (value >= 0 and value = trunc(value)));

insert into game_number (name, value, unit, source, reason) values
  ('starting_credits', 1000, 'units', 'server_choice',
   'the client holds no starting amount of credits (opcode.0x25e, the start value is 0): so that a purchase can be played before any step pays credits, a character starts with 1,000, a server choice');

insert into character_currency (character_id, currency_type_id, amount)
select character_id, 1, value::bigint
from character, game_number
where game_number.name = 'starting_credits';
