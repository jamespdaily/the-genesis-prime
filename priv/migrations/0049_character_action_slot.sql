-- The abilities a character has placed on the bars of its action sets, one row for
-- each slot of each set the character has saved: a set saved at all has all twelve
-- rows, an empty slot with a NULL ability, so a set saved empty and a set never
-- saved differ (a set with no rows shows the class's bar).
--
-- The checks name what the client has: four action sets and twelve slots in a
-- set (the client refuses a set above 3, and its builder sends twelve ids), and
-- the ability is the 18-bit Spell4Base id the message carries (opcode.0x1a0).
create table character_action_slot (
  character_id bigint not null,
  action_set smallint not null,
  slot smallint not null,
  spell4_base_id integer,
  constraint character_action_slot_pkey primary key (character_id, action_set, slot),
  constraint character_action_slot_character_exists
    foreign key (character_id) references character (character_id) on delete cascade,
  constraint character_action_slot_set_is_one_of_four
    check (action_set between 0 and 3),
  constraint character_action_slot_slot_is_one_of_twelve
    check (slot between 0 and 11),
  constraint character_action_slot_ability_fits_the_message
    check (spell4_base_id between 1 and 262143),
  -- An ability is in one place of its set. It is deferrable so that one statement
  -- can swap two abilities: a plain unique key is checked row by row and refuses
  -- the swap, and this one is checked at the statement's end.
  constraint character_action_slot_one_place_per_ability
    unique (character_id, action_set, spell4_base_id) deferrable initially immediate
);
