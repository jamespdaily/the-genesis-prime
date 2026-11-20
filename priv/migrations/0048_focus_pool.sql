-- The Focus pool of the three classes that hold Focus (the Esper, Medic and Spellslinger),
-- one `class_resource` row each, loaded once at start (genesis_prime/content/class_resource)
-- and never queried during play. The load refuses a Focus class with no row and a row of
-- any other class (genesis_prime/game/class_resource `select`).
--
-- The pool is the points a healer holds at every level before worn items add to it: the
-- client's tables hold no pool by class or level, so it is the server's choice, 1000 at
-- every level.
insert into class_resource_name (name, unit) values
  ('focus_pool', 'points');

insert into class_resource (class_id, name, value, unit, source, reason)
select class_id, 'focus_pool', 1000, 'points', 'server_choice',
       'Jim''s decision 2026-11-20: a flat 1000-point pool at every level plus what worn items add, starting full, a guess to correct against a retail recording; the client''s tables hold no pool by class or level, and a pool growing with level is ruled out by its costs: every healer class unlocks a spell costing 137 to 152 Focus at level 6 (Esper 32823: 149, Medic 41382: 152, Spellslinger 39092: 137) and no cost scales with level'
from (values (3), (4), (7)) as healers (class_id);
