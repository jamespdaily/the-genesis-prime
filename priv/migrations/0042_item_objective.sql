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

insert into item_objective (objective_id, kind, item2_id, creature2_id, source, reason) values
  (16311, 'equip', 12631, null, 'server_choice',
   'Quest2 9058 "Algoroc Mining Expedition", objective text "Equip the $(item=12631)"; done while the player wears Item2 12631'),
  (16379, 'equip', 17978, null, 'server_choice',
   'Quest2 9077 "Hunting for Eldan Relics", objective text "Equip the $(item=17978)"; done while the player wears Item2 17978'),
  (18069, 'buy', 54409, 47172, 'server_choice',
   'Quest2 9448 "Vouchers: What Are They Good For?", objective text "Buy a $(item=54409) from $(creature=47172) in Thayd"; counts Item2 54409 bought from Creature2 47172'),
  (18070, 'buy', 54409, 47413, 'server_choice',
   'Quest2 9449 "Vouchers: What Are They Good For?", objective text "Buy a $(item=54409) from $(creature=47413) in Illium"; counts Item2 54409 bought from Creature2 47413');
