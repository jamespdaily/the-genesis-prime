-- The class resource's numbers that change it over time with no press: the
-- Warrior's Kinetic Energy drains after its last gain, and the Esper's Psi Points
-- go to 0 a while after it leaves combat (genesis_prime/game/class_resource). The
-- client holds neither (tooltip 500714: Kinetic Energy "decays over time", with no
-- rate; tooltip 500718: Psi Points "degenerate over time while out of combat"), so
-- each is the server's choice or a retail record, and says so.

insert into class_resource (class_id, name, value, unit, source, reason) values
  (1, 'drain_amount', 150, 'points', 'server_choice',
   'Jim''s choice at the step''s design, 2026-11-05: Kinetic Energy drains 150 a second, in and out of combat; the client''s text gives no rate (500714)'),
  (1, 'drain_period_ms', 1000, 'ms', 'server_choice',
   'Jim''s choice at the step''s design, 2026-11-05: 150 each second'),
  (1, 'drain_after_ms', 1500, 'ms', 'server_choice',
   'Jim''s choice at the step''s design, 2026-11-05: the drain starts 1.5 s after the last gain'),
  (1, 'drain_tick_ms', 1000, 'ms', 'server_choice',
   'one tick a second, as the Stalker''s and Spellslinger''s refill; the client holds no drain of its own'),
  (3, 'empty_after_combat_ms', 10000, 'ms', 'retail_record',
   'marcleoseguin.com, 2014-08-13: Psi Points go to 0 ten seconds after the Esper leaves combat');
