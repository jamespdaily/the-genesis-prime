-- The AMPs a character has bought, one row for each AMP held in an action set. An AMP
-- belongs to the set, and a character that never picked one has no row.
--
-- The checks name what the client has: four action sets and the 16-bit id of the AMP list
-- of the 0x01A3 message. Which AMPs the class holds, and what the level's power allows, is
-- not decided here.
create table character_action_amp (
  character_id bigint not null,
  action_set smallint not null,
  eldan_augmentation_id integer not null,
  constraint character_action_amp_pkey primary key (character_id, action_set, eldan_augmentation_id),
  constraint character_action_amp_character_exists
    foreign key (character_id) references character (character_id) on delete cascade,
  constraint character_action_amp_set_is_one_of_four
    check (action_set between 0 and 3),
  constraint character_action_amp_id_fits_the_message
    check (eldan_augmentation_id between 1 and 65535)
);
