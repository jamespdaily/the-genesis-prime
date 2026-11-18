-- Content table `item_objective`: the QuestObjective rows of type 5 (a scripted objective,
-- done only by the server's 0x361) whose text asks the player to wear an item or to buy one
-- from a vendor, loaded once at start into a persistent term (genesis_prime/content) and
-- never queried during play. It follows the pattern of `arrival_objective` (0038):
-- `source`, `source_row` and `reason`, and the same checks.
--
-- The client holds nothing for such an objective beyond its text, whose `$(item=N)` and
-- `$(creature=N)` tokens name the Item2 and Creature2 rows; so each row is the server's
-- choice, read from that text, with the text in its reason. `kind` is 'equip' (done while
-- the item is worn) or 'buy' (counts the item bought from the vendor `creature2_id`, which
-- only a buy names). The load checks each row against the client's tables
-- (genesis_prime/game/item_objective).
--
-- The table holds no row: the four objectives that ask for an item (Quest2 9058 and 9077
-- to wear Item2 12631 and 17978, Quest2 9448 and 9449 to buy Item2 54409 from Creature2
-- 47172 and 47413) have a rule that cannot fire on this server, so each stays a stand-in
-- on accept and its quest stays finishable. The two items carry Prerequisite 40040 and
-- 40044, whose type 19 (a tradeskill tier) the server does not read, so wearing either is
-- refused with 144; the two vendors have no `vendor` rows, and the voucher has no price.
-- A row is added when its rule can fire.

create table item_objective (
  objective_id integer not null,
  kind text not null,
  item2_id integer not null,
  creature2_id integer,
  source text not null,
  source_row integer,
  reason text,
  constraint item_objective_pkey primary key (objective_id),
  constraint item_objective_id_is_positive check (objective_id > 0),
  constraint item_objective_kind_is_known check (kind in ('equip', 'buy')),
  constraint item_objective_item_is_positive check (item2_id > 0),
  constraint item_objective_only_a_buy_names_a_vendor
    check ((kind = 'buy') = (creature2_id is not null)),
  constraint item_objective_vendor_is_positive
    check (creature2_id is null or creature2_id > 0),
  constraint item_objective_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint item_objective_source_row_is_unique unique (source, source_row),
  constraint item_objective_source_row_is_positive check (source_row > 0),
  constraint item_objective_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint item_objective_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint item_objective_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);
