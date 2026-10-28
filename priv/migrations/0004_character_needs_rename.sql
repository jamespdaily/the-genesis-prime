-- Whether the character's player must pick a new name before playing it. The
-- client offers a rename, instead of playing, for a character whose list entry
-- carries the needs-a-rename bit (bRequiresRename; opcode.0x117,
-- lua.CharacterSelection.OnSelectCharacter), and a rename that the server
-- accepts clears it (opcode.0x14b). No character has it set until something
-- marks it: the developer tool today, a game master's action later.
alter table character
  add column needs_rename boolean not null default false;
