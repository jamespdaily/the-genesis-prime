-- Content table `server_proxy`: the spells the server casts on the caster with a go of
-- an ability, where nothing in the client's tables does, one row each, loaded once at
-- start into a persistent term (genesis_prime/content) and never queried during play.
-- It follows the pattern of `class_resource` (0011): `source`, `source_row` and
-- `reason`, and the same checks.
--
-- A row says "at go `phase` of the ability of Spell4Base `spell4_base_id`, cast `spell4_id`
-- on the caster": the load turns it into a Proxy of the ability's tree
-- (genesis_prime/game/server_proxy). The client holds no such link for the Engineer's
-- Volatility: the hidden spell 42148 gives +15 behind prerequisite 903 and nothing in
-- its tables or code casts it (`Spell4.42148`), so the link is the server's choice.

create table server_proxy (
  spell4_base_id integer not null,
  phase integer not null,
  spell4_id integer not null,
  source text not null,
  source_row integer,
  reason text,
  constraint server_proxy_pkey primary key (spell4_base_id, phase, spell4_id),
  constraint server_proxy_source_is_a_content_source
    foreign key (source) references content_source (name),
  constraint server_proxy_ids_are_positive
    check (spell4_base_id > 0 and spell4_id > 0),
  constraint server_proxy_phase_is_below_32 check (phase between 0 and 31),
  constraint server_proxy_source_row_is_unique unique (source, source_row),
  constraint server_proxy_source_row_is_positive check (source_row > 0),
  constraint server_proxy_world_database_row_has_a_source_row
    check ((source = 'world_database') = (source_row is not null)),
  constraint server_proxy_other_source_states_its_reason
    check (source = 'world_database' or reason is not null),
  constraint server_proxy_reason_says_something
    check (reason is null or length(trim(reason)) > 0)
);

insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values
  (26468, 1, 42148, 'server_choice',
   'Jim''s decision 2026-11-06: Pulse Blast''s tooltips (376222, 491167, 491176) say it generates $(eff=95337) Volatility once, and nothing in the client casts the hidden 42148 that holds 95337 (Spell4.42148), so the server casts it once per Pulse Blast at its striking go (phase 1, 1250 ms), behind prerequisite 903 (in combat); to correct against a retail recording');

-- The Engineer's Volatility empties 5 s after combat, as the Esper's Psi Points do
-- (0012). The client casts no Volatility Resource Control spell either (34630), whose
-- rows let all of it go in one step 5 to 6 s after combat (`Spell4.34630`); tooltips
-- 472510 and 500719 say it dissipates out of combat.
insert into class_resource (class_id, name, value, unit, source, reason) values
  (2, 'empty_after_combat_ms', 5000, 'ms', 'server_choice',
   'Jim''s decision 2026-11-06: the rows of Volatility Resource Control 34630 empty all Volatility in one step 5 to 6 s after combat (34688 lasts 5000 ms, then 34693 removes 100; Spell4.34630), and nothing in the client applies 34630, so the server empties it 5000 ms after the combat flag clears; to correct against a retail recording');
