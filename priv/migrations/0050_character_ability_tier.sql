-- The tiers a character has bought for its abilities, one row for each ability held
-- above tier 1 in an action set: an ability at tier 1 has no row, and a character that
-- never spent a point has none. A tier belongs to the ability in the set, not to a slot,
-- so it stays when the ability leaves the bar.
--
-- The checks name what the client has: four action sets, the 18-bit Spell4Base id and the
-- 4-bit tier of the ability book's message. Which tiers a base has, and which the level and
-- the points allow, is not decided here.
create table character_ability_tier (
  character_id bigint not null,
  action_set smallint not null,
  spell4_base_id integer not null,
  tier smallint not null,
  constraint character_ability_tier_pkey primary key (character_id, action_set, spell4_base_id),
  constraint character_ability_tier_character_exists
    foreign key (character_id) references character (character_id) on delete cascade,
  constraint character_ability_tier_set_is_one_of_four
    check (action_set between 0 and 3),
  constraint character_ability_tier_ability_fits_the_message
    check (spell4_base_id between 1 and 262143),
  constraint character_ability_tier_is_above_the_first_and_fits_the_message
    check (tier between 2 and 15)
);
