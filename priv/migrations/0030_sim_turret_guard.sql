-- The Sim-Turrets of the training simulation take no damage until a stun or a knockdown
-- breaks their charge, then open to damage for 15 s: `creature_kind` gains the two
-- Spell4s of that, the guard that makes a creature take no damage and the opening that
-- lifts it. Both are set or neither is; a creature with neither takes damage always.
--
-- The client links neither spell to a creature (Creature2 73494 and 74862 hold no spell
-- in any column, `Spell4.85472.trigger`), so both turrets' pair is a server choice:
-- Spell4 85474 "Turret Immune" guards (one effect, type 79, immune to Damage) and Spell4
-- 85472 "Moment of Opportunity" opens (a vulnerability state, a disable state and a Proxy
-- that puts 85474 back after 15000 ms). No Exile or Dominion version of either exists
-- among Spell4's rows, and each turret's charge (Spell4 85469, 86978) names 85472 in its
-- cast prerequisite, so the Dominion's turret takes the same pair.

alter table creature_kind
  add column guard_spell4_id integer,
  add column opening_spell4_id integer,
  add constraint creature_kind_guard_spell4_id_is_positive
    check (guard_spell4_id > 0),
  add constraint creature_kind_opening_spell4_id_is_positive
    check (opening_spell4_id > 0),
  add constraint creature_kind_guard_and_opening_together
    check ((guard_spell4_id is null) = (opening_spell4_id is null));

update creature_kind
set guard_spell4_id = 85474,
    opening_spell4_id = 85472,
    reason = reason || '; guard and opening: no client link (Spell4.85472.trigger), Spell4 85474 (type 79 immune to Damage) and 85472 (state 9, state 12, Proxy back after 15000 ms) are the pair its charge names (prerequisite 41722)'
where creature_id in (73494, 74862);
