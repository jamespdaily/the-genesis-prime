-- A character with no saved place is world 0, zone 0 and position 0, and has
-- nothing else. World 0 is no World row, which the client's world entry (0xAD)
-- needs (opcode.0xad), so a zone or a position beside it means nothing and the
-- server reads the row as having no place. The check refuses such a row. Rows
-- that already hold a zone or a position beside world 0 are cleared first, so
-- the check can be added; they were read as having no place already.
update character
  set world_zone_id = 0, position_x = 0, position_y = 0, position_z = 0
  where world_id = 0
    and (world_zone_id <> 0 or position_x <> 0 or position_y <> 0 or position_z <> 0);

alter table character
  add constraint character_no_world_has_no_zone_or_position
    check (
      world_id <> 0
      or (world_zone_id = 0 and position_x = 0 and position_y = 0 and position_z = 0)
    );
