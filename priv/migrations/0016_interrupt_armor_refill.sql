-- How long a creature's Interrupt Armor takes to come back to its maximum after the
-- last point of it was destroyed, in milliseconds. The client decides nothing with
-- Interrupt Armor (UnitProperty2.InterruptArmor_Threshold): it shows the maximum
-- (property 44) and the current value (stat 21 of 0x938), so when and how fast armor
-- returns is the server's choice, and no retail record gives it. A strike that
-- destroys more of it before this time restarts the wait (genesis_prime/world_map/
-- creature_control).
--
-- The name and its unit go into `game_number_name` first, which the row's unit is
-- checked against (migration 0014). A refill time is a whole number of milliseconds
-- above 0: the creature starts a timer of that many.

insert into game_number_name (name, unit) values
  ('interrupt_armor_refill_ms', 'ms');

insert into game_number (name, value, unit, source, reason) values
  ('interrupt_armor_refill_ms', 10000, 'ms', 'server_choice',
   'no client value says when or how fast Interrupt Armor returns (UnitProperty2.InterruptArmor_Threshold, opcode.0x938.interrupt_armor); 10 seconds without a strike is a server choice');

alter table game_number
  add constraint game_number_interrupt_armor_refill_ms_is_a_whole_positive_ms
    check (name <> 'interrupt_armor_refill_ms' or (value > 0 and value = trunc(value)));
