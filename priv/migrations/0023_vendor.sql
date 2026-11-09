-- Content tables `vendor` and `vendor_item`: the creatures that sell and what each sells,
-- loaded once at start into a persistent term (genesis_prime/content) and never queried
-- during play. They follow the pattern of `zone_welcome` (0020): `source`, `source_row`
-- and `reason`, and the same checks.
--
-- A `vendor` row says "Creature2 `creature_id` is a vendor", with the multipliers the
-- 0x90b message sends. The client's tables hold no vendor stock, so a `vendor_item` row
-- is a retail record: item `item_id` is the `position`th line of the creature's Jabbithole
-- npc page, Sells tab, version "launch". `position` is the unique id the client names an
-- item by when it buys.

create table vendor (
  creature_id integer not null,
  buy_multiplier real not null default 1.0,
  sell_multiplier real not null default 1.0,
  source text not null,
  source_row integer,
  reason text,
  constraint vendor_pkey primary key (creature_id),
  constraint vendor_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint vendor_creature_id_is_positive check (creature_id > 0),
  constraint vendor_multipliers_are_positive
    check (buy_multiplier > 0 and sell_multiplier > 0),
  constraint vendor_source_row_is_unique unique (source, source_row),
  constraint vendor_source_row_is_positive check (source_row > 0),
  constraint vendor_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint vendor_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint vendor_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

create table vendor_item (
  creature_id integer not null,
  position integer not null,
  item_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint vendor_item_pkey primary key (creature_id, position),
  constraint vendor_item_vendor_exists
    foreign key (creature_id) references vendor (creature_id),
  constraint vendor_item_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint vendor_item_ids_and_position_are_positive
    check (creature_id > 0 and position > 0 and item_id > 0),
  constraint vendor_item_item_is_listed_once unique (creature_id, item_id),
  constraint vendor_item_source_row_is_unique unique (source, source_row),
  constraint vendor_item_source_row_is_positive check (source_row > 0),
  constraint vendor_item_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint vendor_item_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint vendor_item_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into vendor (creature_id, buy_multiplier, sell_multiplier, source, reason) values
  (11705, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)'),
  (24491, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)'),
  (27039, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)'),
  (27230, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)'),
  (28739, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)'),
  (33905, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)'),
  (50889, 1.0, 1.0, 'server_choice',
   'Multipliers 1.0, the price the client shows with no vendor (Item GetBuyPrice 0x14041bf80)');

insert into vendor_item (creature_id, position, item_id, source, reason)
select 11705, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/supply-officer-windward-1 (captured 20170916003655), Sells tab, version launch'
from unnest(array[14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);

insert into vendor_item (creature_id, position, item_id, source, reason)
select 24491, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/supply-officer-mazzu-12 (captured 20170915174039), Sells tab, version launch'
from unnest(array[14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);

insert into vendor_item (creature_id, position, item_id, source, reason)
select 27039, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/merchant-razzu-22 (captured 20170901225349), Sells tab, version launch'
from unnest(array[12078, 14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);

insert into vendor_item (creature_id, position, item_id, source, reason)
select 27230, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/supply-officer-darru-22 (captured 20170915140814), Sells tab, version launch'
from unnest(array[14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);

insert into vendor_item (creature_id, position, item_id, source, reason)
select 28739, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/supplier-ingavak-27 (captured 20170901220418), Sells tab, version launch'
from unnest(array[12078, 14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);

insert into vendor_item (creature_id, position, item_id, source, reason)
select 33905, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/supplier-lupav-27 (captured 20170901224743), Sells tab, version launch'
from unnest(array[12078, 14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);

insert into vendor_item (creature_id, position, item_id, source, reason)
select 50889, position, item_id, 'retail_record',
  'Jabbithole npc page /npcs/supplier-tento-22 (captured 20170915134310), Sells tab, version launch'
from unnest(array[14838, 20791, 13176, 13185, 13194, 13188, 12044, 13191, 13179, 13151, 13154, 13166, 27874, 27873, 27876, 13157, 13163, 27875, 13169, 13148, 13160]) with ordinality as stock (item_id, position);
