//// A creature's fight: the feature of the creature's rule
//// (genesis_prime/world_map/creature) that decides whom it fights, where it runs,
//// when it strikes and when it gives up and walks home. Its health stays
//// creature_life's (genesis_prime/world_map/creature_life); the player's side of a
//// fight is the player's connection's (genesis_prime/game/player_life). It runs in
//// the creature's process, so every 0x908, 0x90a, 0x89a, 0x638, 0x7ff, 0x7f4 and
//// 0x7fe of the unit comes from its one owner.
////
//// From aggro to home, and what each side sends:
////
//// ```
//// P's connection           map                          creature C (this rule)                   C's viewers
//// 0x637 ─Moved(place, seq)─▶ P is ready, hostile, and
////                            crossed C's ring (aggro_range of the spawn)
////                          ─Approached(P, unit, place, seq)─▶ Resting, P a viewer:
////                                                         threat {P: aggro_threat}; near + P
////                                                         ─0x908(C, P, threat) 0x89a(C, 1)──────▶
//// ◀──────────────────────────────── Threatened(C, life) ──
//// 0x89a(P, 1) to P and P's viewers; P's place now, then each accepted 0x637:
//// ─TargetMoved(place, seq)────────────────────────────────▶ the newest seq per connection wins
////                                                         StartTimer(attack tick, interval)
////                                                         the target out of reach of the path's end:
////                                                         ─0x638[kind 0, kind 4 to the target less
////                                                            chase_stop_fraction x reach, at the run
////                                                            speed, clipped at the leash circle]──▶
//// the attack tick, the target in reach of place_at(path, now):
////                                                         ─0x7ff───────────────────────────────▶
//// ◀──────────── Attacks(Strike(key, C, CreatureStriker(unit, spell4_id), offence)) ─ StartTimer(strike deadline, 1 s)
//// the hit rule on P's health and shield, rolls from P's seed
//// 0x938(20), 0x92f to P; 0x938, 0x937 to P's viewers
//// ─TellStrikeAnswered(Answered(key, Landed))──────────────▶ ─0x7f4(effect, P's descriptions) 0x7fe─▶
////                                                         the deadline first: the go leaves P out
//// the attack tick finds C at the leash circle with the target out of reach, or no threat is left:
////                                                         ─0x90a(C, X, 0) for each X, 0x89a(C, 0),
////                                                            0x937 full, 0x638 home────────────▶
//// ◀──────────────────────────────── Released(C) ─ to each threatened connection
//// 0x89a(P, 0) when no fighter is left; the stream stops   Returning: strikes Refused(Returning),
////                                                         Approached only adds to near
//// the home timer ─────────────────────────────────────▶   Resting; each near player it still sees
////                                                         is aggroed as by Approached
//// ```
////
//// A player's death, and what the creature does with it (the player's side is
//// genesis_prime/game/player_life; the map's is genesis_prime/world_map/map `LifeChanged`):
////
//// ```
//// C strikes P; the hit leaves P at 0
//// P's connection                map                          creature C                      C's viewers
//// Answer(Landed, killed) ───────────────────────────────────▶ P out of near; the entry is
////                                                            released (below)
//// TellLifeChanged(False) ─LifeChanged(P, False)─▶ P Dead; `inside` emptied
////                          ─PlayerDied(P)─▶ C, and each Live spawn P sees
////                                                         P not near, not on the list: nothing
//// C2 fighting P too, takes PlayerDied(P):
////                                                         P out of near; P's entry erased:
////                                                         ─0x90a(C2, P, 0)─────────────────────▶
////                                                         another entry: 0x908 names it, Released
////                                                         to P; the next attack tick strikes it
////                                                         P the only entry: the leash, as
////                                                         for a release; at home no one is aggroed
//// C Resting or Returning, P near, takes PlayerDied(P):
////                                                         P out of near: the home timer and the
////                                                         corpse timer aggro no one for P
//// P wakes in C's ring: LifeChanged(P, True) ─Approached(P, ..)─▶ C Resting: aggro, as a walk-in
//// ```
////
//// A charge, the attack of a creature whose spell has a cast time (`creature_life.Charged`): the
//// attack of the kind or one of its specials (`creature_life.Special`), whose gos (`Go`) are the
//// spell's phases, each with the strike its damage rows name or none:
////
//// ```
//// the attack tick, the target in reach of the attack `chosen` (the first ready special that
//// reaches it, else the attack), no round open:
////                                                         a creature that can move turns to face the target:
////                                                         ─0x638 (a kind 14 turn in place)─────────────────▶
////                                                         round = Charging(CastEnds generation, go 0, no entries);
////                                                            the attack tick's generation moves on and no
////                                                            next attack tick starts: the round's close starts it
////                                                         ─0x7ff(cast id, spell, target, C's place)────────▶ the client draws the
////                                                         StartTimer(CastEnds, first go's due time)          telegraph from the spell
//// CastEnds of the round's generation, a go C reaches (alive and Fighting):
////                                                         the go joins the round's entries in go order, and the
////                                                         next go's CastEnds is armed (a new generation); after
////                                                         the last go the round is Striking
////                                                         a go with no strike, or that strikes nobody: an empty
////                                                            entry, complete at once
////                                                         a strike go: the fighters on the threat list inside the
////                                                         shapes of the go's own strike (from C's place along its
////                                                         aim) by their newest sightings
//// ◀─── Attacks(Strike(key AtGo(go), C, CreatureStriker(unit, spell4_id), the go's blows)) to each fighter ─ StartTimer(the go's strike deadline, 1 s)
//// each fighter's answer, or the go's deadline ───▶ the entry is complete when no answer is awaited
////                                                         each complete entry at the front of the entries is written:
////                                                         ─0x7f4 (the go's index, each fighter that landed)─▶
////                                                         after the last go's entry: ─0x7fe─▶ and the next attack
////                                                            tick (the hold, else interval) is started
//// a viewer that arrives while the charge is open:
////                                                         ─0x7ff(the open charge's cast id, spell, target, place),
////                                                            then the 0x7f4 of each go already written, no unit─▶
//// a crowd-control state or a throw takes hold of C while a go is still to come (`Controlled`, `Thrown`):
////                                                         CancelTimer(CastEnds) and each open deadline; each entry
////                                                            reached is written at once, in go order, as it stands;
////                                                            the next attack tick (interval) started
////                                                         ─0x7f4 of each entry─▶
////                                                         ─0x7f9(cast id, result 11) 0x7fe─────────────────▶
////                                                         ChargeInterrupted(cast id) ─▶ creature_guard `Interrupted`
//// ```
////
//// - **Aggro** comes only from a viewer, by `Approached` while Resting: the map
////   sends it for a hostile creature (faction level 0 to 2) only. A Neutral creature
////   (3 to 7) enters a fight only by a player's strike (`0x1403ad540`). Any threat
////   above 0 shows the creature hostile (`0x14045a950`). The map leaves a stealthed
////   player out of every ring (genesis_prime/world_map/map `StealthChanged`, Jim's
////   decision, a server choice): it sends `Withdrew` when the player enters stealth and
////   `Approached` when it leaves stealth inside the ring. So the home timer and the
////   respawn, which aggro the players in `near`, do not aggro a stealthed one, and a
////   creature already fighting it keeps it on its threat list, since `Withdrew`
////   touches only `near`.
//// - **A dead player is not aggroed** (server choice: the client holds no creature rule,
////   and a dead unit is struck by nothing, `Spell4ValidTargets.targetBitmask`). The map
////   leaves a dead player out of every ring and sends `PlayerDied` to each creature the
////   player sees (genesis_prime/world_map/map `LifeChanged`); the creature drops the
////   player from `near` and from its threat list. A player that wakes inside the ring is
////   sent `Approached` as a walk-in or a stealth exit is, so it is aggroed.
//// - **Threat** added by a strike is the damage taken times the effect's
////   `Spell4Effects.threatMultiplier`. The top entry is the target: a change of target
////   sends 0x908, and every other entry 0x90a (`opcode.0x908`, `opcode.0x90a`).
//// - **Threat only for viewers.** A strike or a `TargetMoved` from a connection that
////   is not a viewer adds no threat, and `Unwatched` drops the viewer's entry, so the
////   threat list is always within the viewers and the map's sweep, which retires only a
////   creature with no viewer, never retires a fighting one.
//// - **Ordering.** Each accepted 0x637 gets its connection's next move sequence
////   number (genesis_prime/game/connection). The creature keeps the newest per
////   connection and drops a lower one; an equal one is the same move. So `Approached`,
////   from the map, and `TargetMoved`, from the connection, two senders, may arrive in
////   either order. 0x637's client clock is not used: two moves of one frame share it
////   (`opcode.0x637.client_clock`).
//// - **The chase** is a straight path of kind 4 at the creature's run speed
////   (`movement_command.kind_4`, `0x1405b45e0`), planned again only when the target is
////   beyond reach of the current path's end, and clipped at the leash circle
////   (genesis_prime/world_map/creature_path).
//// - **A path that ends in standing is replaced.** A new path that is no distance
////   to run (the leash in the instant a chase began, a target that doubled back
////   onto the creature, a death) is sent as 0x638 of kind 2 at the creature's place with its
////   blend bit clear, which places the unit at once (`0x1407138f0`, `0x140714120`), but
////   only while the path last sent is still being run; a creature that has stood
////   since its path ended sends nothing. A death mid-path places the viewers where
////   the creature fell the same way.
//// - **Reach** is the attack spell's `targetMaxRange` plus the creature's hit radius,
////   centre to centre (a server choice), and for a charge on its target the target's hit
////   radius too, as the client ranges a cast on a unit (`0x1403b2240`;
////   genesis_prime/world_map/creature_life `Attack`).
//// - **One round at a time.** The attack interval is never below the strike
////   deadline (genesis_prime/world_map/creature_kind), so a tick of an attack with no cast
////   time never finds a round open. A charge is the open round while a go is still to come
////   (`Charging`) and while an entry is open after the last go (`Striking`): it starts no attack
////   tick, the close of its round starts the next, and a tick that finds a charge open does
////   nothing, so there is never a second round. The strikes of two gos may be open at once, each
////   with its own deadline timer, and their 0x7f4 are written in go order: the client keeps the
////   phase it was last told (`opcode.0x7f4.phase`), and the player's own cast closes its rounds
////   in the order they began (`game/strike.gleam` `close_ready`).
//// - **The charge's area** is the attack spell's damage telegraph, in the order of its area
////   row: nearest or furthest first, or Random by the round's cast id as the seed
////   (genesis_prime/game/spell_area `area_of_spell`, genesis_prime/game/area `select_ordered`),
////   centred where the picture is (`Charged.anchor`). A row with TelegraphDamage flag 0x4000 or
////   0x1000 is drawn only from the positions the 0x7ff carries (genesis_prime/game/telegraph_entries),
////   made at the cast's start and kept in the round (`Round.start`), where it stays whatever
////   moves: its hit is centred on the pose the cast started at, the creature's
////   (`FixedAtCaster`) or the cast target's (`FixedAtTarget`), and a viewer that arrives
////   mid-cast is sent the same entries. A row with neither is drawn by the
////   client on its unit each frame from that unit's own yaw
////   (`0x14054b1b0.follows_caster`): on the caster, its hit is centred on the creature at the
////   strike (`FollowsCaster`); on the cast's target, on that player's newest sighting with its
////   facing (`FollowsTarget`). A row on the cast's target, following or fixed, is drawn for as
////   long as the target's unit is in the viewers' world, so a target that died or left the
////   fight still has its row struck, and nobody is struck when the target is no longer a
////   viewer (`centre_of`, `0x14054b1b0.unit_gone`). The cast's target is the one the
////   creature had when the cast began (`Start.target`, the 0x7ff's primary target), not the
////   0x908 target of a later moment. A creature that cannot move turns its aim toward its 0x908 target
////   through the cast only when the spell has `Spell4.propertyFlags` 0x2, and holds the aim it
////   had at the cast's start otherwise (`0x14046cdc0.turret_cast_aim`).
//// - **The auto-attacks alternate**: a creature whose kind lists several (`Fighter.attack`, then
////   `Fighter.alternates`) strikes the first, then each next, then the first again, one for each
////   attack tick that strikes (`State.autos_struck`); a special cast between them, and a tick that
////   finds the attack refused, leave the turn where it was, and a new fight opens with the first.
////   Each waits the kind's attack interval. The turn's attack is the one a tick closes in on and
////   strikes with; the leash keeps the first's reach (`chosen`, `ticked`).
//// - **A special** is chosen at the attack tick: the first of `Fighter.specials` that is not refused by
////   the states the creature holds, whose cooldown is over and whose reach covers the target, else the
////   next auto-attack; none while the creature holds a state (`chosen`). The cooldown starts at the cast's start
////   (`ready_at`, a server choice) and is cleared by a new fight (`start_fight`), so a fight opens with
////   its specials ready. A special's gos are armed from the cast's start, each for `max(0, due - now)`
////   (`due_in`), so a timer handled late does not push the gos after it.
//// - **A creature that can move keeps facing its target** (`State.turn`, `wanted`, `faced`): the client
////   never turns a creature by itself (`creature.facing`), so the creature sends kind 18 naming its
////   target's unit (`movement_command.kind_18`), which the client keeps through the chase, the circling of
////   the target and the strikes with no further message, and which only a later rotation command replaces.
////   The turn goes before the path it goes with (a kind 4 path never turns it) and is sent again only when
////   the face changes: a new target, the leash (kind 19 toward home, `movement_command.kind_19`), the
////   arrival home (`Home`, the spawn's facing, which a viewer's frame writes as a blended kind 19 along it), a charge, a state, a flight, a death.
////   - A charge turns the creature once before the 0x7ff (`turned_to_face`, kind 14) and holds that turn
////     through the cast and the strikes: the 0x7ff's entries are made from the pose the creature has when
////     the cast starts, so a cone drawn from an entry (flag 0x4000, as Earthen Roar's) points along that
////     facing and stays there, and a cone the client draws on the caster each frame
////     (`0x14054b1b0.follows_caster`) points along the facing the creature holds; the strike go's area
////     points along it (`aim_of`). The close of the round turns it to its target again,
////     and so does the hold after a special, in which it starts no path.
////   - A Stun, Knockdown, Knockback or an opened guard (`Fighter.turn_held`) stands the creature as it
////     faces, by a kind 14 at that facing (a server's choice, a guess: no client fact covers it); a Root
////     and the other states that only stop its run leave it turning. The creature's rule tells the fight
////     when this changes without the creature's run changing (`Reconsidered`).
////   - A death or a despawn freezes the facing it had by a kind 14 that moves nothing, so the corpse
////     follows no one; the flight a throw gives is left to its own news.
////   - A throw whose row turns the creature sets that turn (the path's kind 14); the first step after the
////     flight turns it to its target again.
////   - A creature that cannot move is sent no rotation (a turret aims itself, `0x14046cdc0.turret_cast_aim`;
////     an object's creature belongs to its object).
////   - The server's own yaw for the creature (`place_at`, which the gates and the strike read) is the
////     facing its viewers' clients show: the fixed facing, or the bearing to the unit it keeps or to home,
////     taken as done at once, where the client blends a kind 18 or 19 over half a second (`0x140715c00`);
////     a target on the creature's own ground point leaves the facing it had (the client's too-close case).
//// - **The hold** (`Hold`): the next attack tick starts `Charged.hold_ms` after the round closes (the
////   NpcExecutionDelay rows, whose effect the client's code does not hold, `Spell4Effects.effectType.35`: a
////   guess), else after the attack interval. The tick is the creature's only driver in the hold: it starts
////   no path and casts or strikes nothing until the tick.
//// - **The charge's aim.** An aiming turret turns its aim toward its 0x908 target, not the
////   0x7ff's, all through a cast whose spell has the follow flag, and its telegraph turns with
////   it (`0x14046cdc0.turret_cast_aim`). So at `CastEnds` the area points along the bearing
////   from the turret to the fight's target, the unit its 0x908 names, by that player's
////   newest sighting, not along where the player stood at the go: a fighter that left that
////   line is not struck, and one that walked round the turret with its target is. With no
////   sighting of the target the strike goes along the turret's body yaw, the facing of its
////   place. The server never turns the body: the 0x7ff's yaw turns nothing
////   (`creature.facing`).
//// - **A creature that cannot move** (a turret, or a creature placed as part of a map
////   object: `creature_unit_type.can_move`) sends no 0x638 to chase or walk home. An attack tick that
////   finds its target beyond the leash range from home releases it as the leash does, but goes
////   straight to Resting where it stands: no walk and no home timer. A player that entered
////   its ring before is aggroed again only when it enters it again (`Approached`).
//// - **Reach of a charge** is the smaller of the area row's max range and the farthest point of
////   its hit shapes, not the spell's `targetMaxRange` (genesis_prime/world_map/spawn
////   `attack_of`): the charge starts when the target is inside the range the area covers. A ready
////   special is gone for beyond its reach: the creature closes to it.
//// - **The leash** is taken on an attack tick that finds the creature at the circle,
////   `leash_range` from its spawn, with its target out of reach, or when no threat is
////   left (274 section 3). Walking home it takes no strike and turns to no one; at home,
////   at full health, it aggroes the players still in its ring.
//// - **Death** sends 0x89a (C, 0) and `Released` to everyone on the threat list
////   (`death.combat_flag`); the respawn aggroes the players in its ring. Whether the
////   creature stands or lies dead is creature_life's alone: the fight leaves at the
////   kill, and the creature's place, kept apart from the fight's status, stays where
////   it fell.
//// - **A leash restores the health**: the fight asks the creature's rule
////   (`RestoreHealth`), which sets creature_life's health to full and sends the 0x937.
//// - **Every timer carries a generation**: a tick of a fight that ended, a deadline
////   of a round that closed or a home timer of an earlier walk does nothing when it
////   fires, though it waited in the mailbox when it was cancelled.
//// - **A player at 0** answers `Landed` with the killed bit, or `Refused(Dead)` to a strike
////   that finds it dead; the creature releases it and also drops it from `near`, so its home
////   timer, which can fire 0 ms after a kill at its spawn, does not aggro the body before the
////   map's `PlayerDied` arrives. `PlayerDied` does the same for a creature whose strike did not
////   kill it, and for one that holds the player only in `near` or on its list.
//// - **What a held state stops** (genesis_prime/world_map/creature_control), by the state:
////   - A state whose CCStates flags hold the value 2 (Stun, Sleep, Root, Hold, Knockdown, Disable,
////     Knockback, Pushback, Pull, PositionSwitch, DisableCinematic) starts no chase or walk
////     home, and a path the creature runs stops where it stands, as at a death
////     (`Fighter.still`). When the last such state ends it acts again from where it stands
////     (`Controlled`, `ControlEnded`).
////   - A state the attack spell's caster conditions mask (Spell4CCConditions) starts no strike
////     of an instant attack, and a Stun, Knockdown or Knockback starts none whatever the mask
////     (`Fighter.attack_refused`).
////   - A charge starts only while no state is held (`Fighter.holds_a_state`), although the
////     client's conditions for the charge spells mask nothing.
////   - The attack tick goes on and does nothing else; threat, targets and the viewers' news are
////     kept as usual, and a creature that stands still (`Fighter.still`) does not leash from its
////     tick: out of reach at its leash circle it stays in the fight, with its threat and its health,
////     and leashes at the first tick after the state ends. It leashes in place only when its
////     last threat entry goes while it is held (`Released`), when the walk home waits for `ControlEnded`.
//// - **A state breaks a charge.** Any crowd-control state, or a throw, that takes hold while the
////   round is `Charging` (a go is still to come) ends the cast; the hits that went stand. The authority is Jim's decision of 2026-11-11 ("any crowd control
////   that lands during the charge is the interrupt"); the client holds no rule for it. Spell4 85474's
////   tooltip, text 748852 ("unless it is interrupted while charging"), and Spell4 85469's hint, text
////   748860, are evidence for the Sim-Turrets only. Interrupt Armor already decides whether a state
////   lands (genesis_prime/world_map/creature_control), so the fight breaks the charge only when a
////   state took hold. The fight cancels the `CastEnds` timer and each open deadline, writes
////   every entry reached in go order with what was struck so far (a viewer's connection forgets a
////   cast at its 0x7f9, and the client drops a 0x7f4 of a cast it no longer holds), then 0x7f9 with
////   result 11 (SpellInterrupted) and the 0x7fe, closes the round, starts the next attack tick and asks the
////   creature's rule to tell the guard (`ChargeInterrupted`, with the charge's cast id), which opens the creature
////   (genesis_prime/world_map/creature_guard). A creature holding a state starts no charge, so a state
////   that lands in a charge is the first; once the last go is reached (`Striking`) the strikes are
////   out and nothing breaks. The break is the fight's
////   for any creature with a charge, guarded or not: a bare turret's charge breaks the same way
////   and the guard, finding itself `Bare`, opens nothing.
//// - **An opened creature is held** (`Fighter.still`, `attack_refused` and `holds_a_state`): it
////   starts no charge, strike, chase or walk until its opening ends, when `ControlEnded` lets it
////   act again.
////
//// What happens at each deadline and process death:
////
//// | Point | What happens | Test |
//// |---|---|---|
//// | P's answer comes after the strike deadline | the go leaves P out; the hit stands and P's 0x92f shows it | `an_answer_after_the_deadline_is_left_out_of_the_go_test` |
//// | P's connection ends, camps or P goes out of sight | the map's `Unwatched` drops P from threat; with no threat left the creature leashes | `a_player_whose_connection_ends_mid_chase_makes_the_dagun_leash_test`, `unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test` |
//// | a strike or `TargetMoved` from a connection that is not a viewer (a race with `Unwatched`) | the damage applies, no threat is added | `a_strike_from_a_non_viewer_adds_no_threat_test` |
//// | P and C strike each other at one instant | both are tells; each side answers in its own step, before the other's deadline | `a_medic_and_a_beast_striking_each_other_at_one_instant_both_get_their_answers_before_either_deadline_test` |
//// | C crashes mid-fight | the map sends every player `Gone`; P drops C, and sends 0x89a (P, 0) when no fighter is left (genesis_prime/game/player_life) | `a_dagun_that_crashes_mid_fight_is_gone_and_the_bots_combat_flag_clears_test` |
//// | C is told `Retire` while Returning | it stops; the map's sweep sends it only with no viewer, so no one is on its threat list | `over_random_sights_rings_strikes_and_ticks_the_threat_list_stays_within_the_viewers_test` |
//// | a timer of a round that closed, or of a fight that ended, fires | it is of an old generation and does nothing | `a_deadline_timer_already_fired_for_a_closed_round_does_nothing_test` |
//// | C dies while it runs | it rests where it fell, and a viewer that arrives before its respawn is shown it there | `a_viewer_arriving_between_a_running_creatures_death_and_its_respawn_sees_it_where_it_fell_test` |
//// | P dies and C's killing answer and the map's `PlayerDied` both reach C | two senders, either order: the first drops P from `near` and the threat list, the second finds nothing | `a_creature_told_player_died_for_its_target_erases_its_entry_names_the_next_and_never_strikes_the_body_test`, `player_died_for_a_player_neither_near_nor_on_the_list_changes_nothing_test` |
//// | P died and C's home timer or corpse timer fires before `PlayerDied` reaches C | C aggroes the body; P drops `Threatened`, C's first strike is refused `Dead`, and C releases P and drops it from `near`: at most one swing, in the window of one map hop | `a_creature_that_kills_its_only_target_in_its_ring_does_not_aggro_the_body_at_its_home_timer_test`, `a_creature_whose_strike_is_refused_dead_does_not_aggro_the_body_at_its_home_timer_nor_when_its_corpse_timer_stands_it_test` |
//// | a strike P sent before it died reaches C after `PlayerDied` | `StruckBy` adds P to the threat list; C's first strike is refused `Dead` and releases it |  |
//// | `PlayerDied` for a player on neither `near` nor the threat list (its `Unwatched` came first, or the killing answer dropped it) | nothing | `player_died_for_a_player_neither_near_nor_on_the_list_changes_nothing_test` |
//// | C is Returning, or dead, when `PlayerDied` reaches it | Returning: P out of `near`, nothing sent; dead: the send is dropped, and the map's `inside` holds no dead player for C's next start | `a_near_player_told_player_died_is_not_aggroed_at_the_home_timer_nor_by_the_corpse_timer_and_one_approached_again_is_test` |
//// | P dies, wakes inside C's ring, and C's killing answer reaches C after the wake's `Approached` | the answer drops P from `near` after the wake put it there: P stands in the ring and is not aggroed until it enters again; the answer is taken only before the strike deadline (`strike_tell.deadline_ms`, 1000 ms), so it is a Wake Here chosen within that second of the death |  |
//// | the home timer fires | C stands at its spawn, Resting, at full health, and aggroes the near players it sees | `at_home_the_creature_aggroes_the_near_players_test` |
//// | Charge start: the attack tick finds the target in reach, no round open, the attack is `Charged` | round Charging, 0x7ff of the spell, `StartTimer(CastEnds, cast time)`, no strike and no next attack tick; the tick's generation moves on | `a_charge_starts_with_its_cast_time_and_telegraph_test` |
//// | Charge start: the special has server-placed telegraph rows (flag 0x4000 or 0x1000) | the 0x7ff carries their entries at the creature's pose after it turned to its target | `the_specials_cast_start_carries_the_entries_of_its_server_placed_rows_test` |
//// | a viewer arrives while a charge with server-placed rows is open | it is sent the entries made at the cast's start, not ones made where the creature stands now | `a_viewer_arriving_mid_charge_gets_the_entries_of_the_cast_start_test` |
//// | CastEnds timer: a turret's charge has a row the client draws fixed, and the target moved since the start | the rectangle is the one the 0x7ff showed, not turned to the target | `a_turret_strikes_a_fixed_caster_row_from_the_pose_stored_at_the_start_test` |
//// | CastEnds timer: a turret's charge whose spell lacks propertyFlags 0x2, and the target walked round it | the rectangle stays at the aim it had at the cast's start | `a_turret_whose_spell_lacks_the_aim_bit_holds_its_aim_from_the_start_test` |
//// | CastEnds timer: a fixed row with a rotation | the hit is where the client draws the turned shape | `the_rotated_cone_of_52448_strikes_where_the_client_draws_it_test` |
//// | Charge start: a second attack tick finds the charge open | nothing: the tick it came from is of an old generation | `a_second_attack_tick_during_a_charge_starts_nothing_test`, `a_second_attack_tick_during_a_special_starts_nothing_test` |
//// | a special's go, a strike go too, is handled late | the next go's timer is armed for what is left of its due time, never below 0; a strike's deadline is 1,000 ms from the handling | `a_late_go_timer_arms_the_next_go_for_what_is_left_of_its_due_time_test` |
//// | a go's timer fires of an earlier generation, or after the round closed | it does nothing | `a_stale_go_timer_does_nothing_test` |
//// | a state takes hold between a special's gos | the cast breaks as a charge does, the cooldown stays spent | `a_state_between_gos_breaks_the_special_and_the_cooldown_stays_spent_test` |
//// | a special has several strike gos | each strike go strikes at its own phase, with the blows that name it; the 0x7f4 of each go is written when its entry is complete and every entry before it is written; the cast finishes after the last go's entry, and the hold counts from that close | `each_damage_go_strikes_at_its_phase_and_the_cast_finishes_after_the_last_go_test` |
//// | the strikes of two gos are open at once | each has its own deadline timer; the entries are written in go order, a late or missing answer holding the entries behind it until its answer or its deadline | `the_rounds_of_overlapping_hits_are_written_in_go_order_test` |
//// | a hit selects nobody, or its row is on a target that is gone | an empty entry in go order; the cast goes on | `a_hit_that_selects_nobody_is_an_empty_entry_and_the_cast_goes_on_test` |
//// | the hits of one cast have different shapes and blows | each strikes the fighters inside its own go's shapes, with the blows that name its go and the attack's crit and strikethrough | `each_hit_strikes_the_fighters_and_the_blows_that_name_its_go_test` |
//// | a hit kills a fighter | the next hit does not strike it; a kill that empties the threat list leashes inside the answer | `a_fighter_the_first_hit_killed_is_not_struck_by_the_second_test` |
//// | a state or a throw takes hold between hits | the pending go and each open deadline are cancelled, the open entries are written at once as they stand, then 0x7f9; the later timers and answers do nothing; a second state finds none | `a_state_between_hits_ends_the_rest_of_the_cast_and_closes_the_open_rounds_at_once_test` |
//// | a state takes hold between the hits of a guarded creature's cast | the viewer is sent the stun, the open entries' 0x7f4, the 0x7f9, then the guard's opening, once | `a_stun_between_hits_of_a_guarded_creatures_cast_opens_it_once_after_the_cast_is_closed_test` |
//// | death or the leash between hits | every timer of the cast is cancelled once; death sends the 0x7fe alone, the leash writes the open entries first; a late timer or answer does nothing | `death_and_the_leash_between_hits_cancel_every_timer_and_close_the_cast_once_test` |
//// | a viewer arrives between hits | it is sent the open cast and the 0x7f4 of the gos already written, with no target; the rest reaches it when it is written; none after a break | `a_viewer_arriving_between_hits_is_told_only_the_gos_already_written_test` |
//// | a go's timer or an answer comes again, or the last answer and a deadline cross | the other rounds are left alone and an entry is written once | `a_timer_or_an_answer_that_comes_again_leaves_the_other_rounds_alone_test` |
//// | death or the leash between a special's gos | the pending go's timer is cancelled and the cast finishes | `death_between_gos_ends_the_special_test`, `leash_between_gos_ends_the_special_test` |
//// | the target or another fighter moves, is named or leaves, a state that held it ends, or a kill retargets, in a hold, a cast or the strikes of a charged round | the creature starts no path | `a_creature_in_its_hold_neither_chases_nor_strikes_test`, `a_specials_cone_faces_its_target_test`, `no_path_starts_while_a_charged_round_strikes_or_holds_test` |
//// | a ready special whose reach the target is beyond | the creature closes to the special's reach, then casts it | `a_ready_special_closes_to_its_own_reach_test` |
//// | the tick strikes: the creature has several auto-attacks | it strikes the first, then each next in turn, then the first again, each waiting the attack interval | `a_creature_strikes_its_auto_attacks_in_turn_test`, `each_auto_attack_waits_the_attack_interval_test` |
//// | the tick finds the attack refused by a state, or a special is cast between the auto-attacks | nothing is struck and the turn stays | `a_refused_auto_attack_does_not_advance_the_turn_test`, `a_special_between_autos_leaves_the_turn_unchanged_test` |
//// | a new fight begins | the turn is the first auto-attack | `a_new_fight_opens_with_the_lead_auto_attack_test` |
//// | the next auto-attack reaches farther than the first | the creature closes in to the next's reach | `the_next_alternates_reach_is_closed_in_on_test` |
//// | a round names an alternate's spell after the creature's values change | the attack is found among the alternates | `a_round_naming_an_alternates_spell_finds_its_attack_test` |
//// | a viewer arrives between a special's gos, or while its strikes are out | it is sent the open cast and the gos that went | `a_viewer_arriving_between_gos_gets_the_open_cast_and_the_gos_so_far_test` |
//// | Charge start: the guard holds the number `next_cast` offers | the round takes the next free id and `next_cast` moves past that id, so two charges in a row take different ids and a late answer to the first closes nothing of the second | `two_charges_under_a_held_guard_take_different_cast_ids_test` |
//// | CastEnds timer: it fires for the open charge | each fighter on the threat list inside the rectangle along the bearing to the target now gets a strike, and the strike deadline starts; none inside, the go (0x7f4) names no unit and 0x7fe follows | `at_its_end_the_charge_strikes_each_fighter_inside_its_rectangle_test`, `a_charge_faces_its_target_test`, `a_charge_with_nobody_inside_goes_with_no_target_test` |
//// | CastEnds timer: it fires for a charge that ended (a death or a leash) or of an old generation | it does nothing | `a_stale_cast_end_does_nothing_test` |
//// | a state takes hold during the charge | `CancelTimer(CastEnds)`, 0x7f9 (cast id, 11) and 0x7fe, the round closed, the next attack tick started, `ChargeInterrupted` | `a_state_that_takes_hold_during_the_charge_breaks_it_so_the_cast_end_strikes_no_one_test`, `a_stun_on_the_target_during_the_charge_breaks_it_and_the_next_attack_tick_starts_test`, `a_stun_during_the_charge_interrupts_it_and_opens_the_turret_test` |
//// | CastEnds timer: it fires after an interrupt | the round was closed and the generation moved on, so it does nothing | `a_cast_end_after_an_interrupt_is_stale_test` |
//// | a state takes hold after the go (the round is `Striking`) | nothing breaks: the strikes are out | `an_interrupt_after_the_go_opens_nothing_test` |
//// | a second state takes hold in the same round | the first state closed the round, so the second finds no charge: nothing more | `a_second_state_in_the_same_round_opens_nothing_more_test` |
//// | CastEnds timer: a fighter was released during the charge | it is off the threat list, so it is not struck | `a_fighter_released_mid_charge_is_not_struck_test` |
//// | Strike to a fighter: its answer, the last one or the deadline | each answer joins the go as a round's does; the last answer or the deadline closes the round (0x7f4, 0x7fe), and the next attack tick starts | `the_struck_go_and_finish_follow_the_answers_test` |
//// | Death or leash during the charge: C is killed, or its last threat entry is released | `CancelTimer(CastEnds)` and 0x7fe for the charge, no 0x7f4, then the death or the release as without a charge; the later CastEnds does nothing | `death_during_a_charge_ends_it_test`, `leash_during_a_charge_ends_it_test` |
//// | a viewer arrives while the charge is open | its news holds the charge's 0x7ff, with its cast id, so its client takes the later 0x7f4 | `a_viewer_arriving_mid_charge_gets_the_open_cast_test` |
//// | a viewer arrives while the charge is open and the threat list's top entry changed since it began | its 0x908 names the top entry, its 0x7ff the cast's own target and the entries of the start | `a_viewer_arriving_mid_charge_is_told_the_casts_own_target_test` |
//// | Charge start: the special has a row placed on its target | the 0x7ff names the target as primary target and carries its initial position and telegraph position with the role bit 2 | `a_charge_on_a_target_row_opens_with_the_target_in_its_0x7ff_test` |
//// | CastEnds timer: a target row the client draws fixed (`FixedAtTarget`), and the target moved since the start | the circle is the one the 0x7ff showed, around where the target stood | `a_fixed_target_row_strikes_around_where_the_target_stood_at_the_start_test` |
//// | CastEnds timer: a target row the client draws on its target (`FollowsTarget`) | the area is around where the cast's target stands now, turned by its facing | `a_client_placed_target_row_strikes_around_the_cast_targets_place_at_the_strike_test`, `a_cone_on_the_target_turns_with_the_targets_facing_test` |
//// | CastEnds timer: a target row, and the 0x908 target changed since the start | the area is around the cast's target, not the 0x908 target | `a_target_row_uses_the_cast_target_not_the_0x908_target_of_the_moment_test` |
//// | CastEnds timer: the cast's target died or left the ring, and is still a viewer | the row follows the body or the unit, or stays at its stored place, and strikes the fighters in it | `a_target_row_strikes_while_its_cast_target_is_in_the_world_test` |
//// | CastEnds timer: the cast's target is no longer a viewer (`Unwatched`) | a row on it, following or fixed, strikes nobody and the cast finishes as an empty strike does | `a_target_row_strikes_while_its_cast_target_is_in_the_world_test` |
//// | a creature that cannot move: its target is out of reach, or beyond the leash range from home | out of reach: no 0x638, it keeps its place; beyond the leash range: the release as the leash does, with no walk, to Resting | `a_turret_never_chases_or_walks_home_test`, `a_turret_leashes_in_place_when_its_target_is_beyond_its_leash_range_test`, `a_creature_placed_as_part_of_a_map_object_does_not_chase_a_target_that_leaves_its_reach_test`, `a_creature_placed_as_part_of_a_map_object_leaves_combat_without_a_walk_home_test`, `a_creature_placed_as_part_of_a_map_object_leaves_combat_in_place_when_its_target_is_beyond_its_leash_range_test` |
//// | `Thrown` reaches a creature that is dead, Returning, cannot move (a Turret, or a creature placed as part of a map object) or does not run (run speed 0) | the fight drops it: no path, no timer, no news | `a_turret_is_not_thrown_test`, `a_creature_placed_as_part_of_a_map_object_is_not_moved_by_a_forced_move_test`, `a_throw_at_a_dead_or_returning_creature_is_dropped_test` |
//// | `Thrown` reaches a creature that runs, Fighting or Resting | the path is `Timed` from where it is, `FlightEnds` starts, the viewers are sent one 0x638; an open charge breaks as `held` does, unless the throw moves the creature nowhere | `a_thrown_creature_sends_its_viewers_the_flight_once_test`, `a_throw_breaks_an_open_charge_test`, `a_throw_that_moves_the_creature_nowhere_leaves_an_open_charge_test` |
//// | `Thrown` reaches a creature already in flight | the new path starts from where the first had reached, the old `FlightEnds` is cancelled and a new one starts | `a_second_throw_mid_flight_starts_from_where_the_first_had_reached_test` |
//// | an attack tick fires in flight | no round starts: the creature does not attack or chase until it lands | `a_thrown_creature_does_not_chase_or_attack_until_it_lands_test` |
//// | `FlightEnds` fires of the flight's generation | the creature stands at the last point with no news and chases again from there, unless a state holds it | `a_bare_throw_resumes_the_chase_from_the_landing_test`, `a_flight_ending_while_a_state_holds_does_not_resume_test` |
//// | `FlightEnds` fires of an older generation | nothing | `a_stale_flight_end_does_nothing_test` |
//// | a state takes hold in flight | the run stops only for a path that is `Running`; a `Timed` flight is kept and finishes | `a_state_landing_mid_flight_lets_the_flight_finish_test` |
//// | the last state ends in flight | the creature acts again at `FlightEnds`, not before | `a_state_ending_mid_flight_does_not_resume_until_the_landing_test` |
//// | the leash fires in flight | the creature is `Returning` and sends no walk: the flight finishes and `FlightEnds` starts the walk home from the landing | `a_leash_in_flight_walks_home_from_the_landing_test` |
//// | the creature dies in flight | `CancelTimer(FlightEnds)`, the path is kept and no kind 2 is sent: the corpse lies at the landing | `a_creature_killed_mid_flight_lies_at_the_landing_test` |
//// | a creature is killed or despawned while it keeps facing its target, walks home, charges or flies | a kind 14 at the facing it had, which no later turn changes; in flight the corpse flies on at that yaw | `a_killed_or_despawned_creature_is_turned_where_it_faces_and_stops_following_test`, `a_creature_that_dies_walking_home_or_in_a_charge_or_in_flight_freezes_the_facing_it_had_test` |
//// | a Stun ends while a Root holds the creature, or the guard opens as a Root breaks a charge | `Reconsidered`: it turns to its target again or stands as it faces, and starts no path | `a_stun_ending_while_a_root_holds_turns_the_creature_again_and_starts_no_path_test`, `a_root_that_breaks_a_charge_leaves_the_creature_standing_as_the_opened_guard_holds_it_test` |
//// | the walk home stops where it stands, or starts again after a state | the arrival timer of the stopped walk is cancelled, and the walk that follows has a new arrival timer | `a_walk_home_after_a_leash_in_a_state_starts_one_fresh_arrival_timer_test` |
//// | the walk home ends with a player near | the spawn's facing, then the new fight's turn | `a_creature_that_walks_home_and_finds_a_player_near_turns_to_the_spawn_before_it_turns_to_the_player_test` |
//// | a chase path is built, or its speed changes while the creature fights | `CancelTimer(ChaseArrival)` then `StartTimer(ChaseArrival)` for the path's end, so the creature's shell never starts a timer whose id runs | `a_chase_path_cancels_and_restarts_the_arrival_timer_for_the_paths_end_test` |
//// | `ChaseArrival` fires while the creature fights along a running path | the viewers are sent `CreaturePlaced` at the path's end, which ends the walk animation the path's frame started (kind 11 and kind 24); the state does not change | `the_arrival_timer_sends_the_creature_placed_where_the_chase_ends_test` |
//// | `ChaseArrival` fires after a stand, a flight, a walk home or a death replaced the path | nothing | `the_arrival_timer_of_a_path_that_is_no_longer_run_sends_nothing_test` |
//// | `HomeArrival` fires of the walk's generation | `CreaturePlaced` at the spawn when the walk is a running path, then the spawn's facing and the aggro | `the_walk_home_arrival_sends_the_creature_placed_at_home_before_the_turn_test` |
//// | a chase starts | the turn goes out before the path | `a_chase_sends_the_turn_before_the_path_test` |
//// | a viewer arrives in flight | it is sent the rest of the path from where the creature is now | `an_arriving_viewer_mid_flight_is_sent_the_rest_of_the_path_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/area.{type Inside, type Row}
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/forced_move
import genesis_prime/game/hit.{type Offence}
import genesis_prime/game/start_place.{type Facing, type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Fight as Told, type Key, Attacks, CreatureStriker,
  Released, Threatened,
}
import genesis_prime/game/telegraph_entries
import genesis_prime/gap
import genesis_prime/step.{type Address, type ConnectionId}
import genesis_prime/table/id.{type Spell4Id}
import genesis_prime/world_map/creature_life.{
  type Attack, type Special, Charged, Instant,
}
import genesis_prime/world_map/creature_path.{
  type Path, Circle, Running, Standing, Timed,
}
import genesis_prime/world_map/creature_turn.{type Face, Fixed}
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/map
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// What the creature fights with: its unit and address, the place of its spawn,
/// which is home and the leash circle's centre, its attack and alternates, the time between its
/// attack ticks and the run's game numbers, which are fixed for its life; what its held
/// crowd-control states stop it doing now, which the creature's rule gives each step
/// (genesis_prime/world_map/creature_control); and the ids of the guard's live casts
/// (`creature_guard.live_casts`), which its casts take no id of (`cast_state.mint`). An opened
/// creature (genesis_prime/world_map/creature_guard `opened`) is stopped in all three.
/// - `still`: it holds a state that stops its run (genesis_prime/game/crowd_control
///   `stopping_mask`), so `chase` starts no path, `leash` starts no walk and a state that
///   takes hold stands it where it is.
/// - `attack_refused`: it holds a state its attack spell's caster conditions mask, or a
///   Stun, Knockdown or Knockback, so `ticked` starts no strike of an instant attack.
/// - `holds_a_state`: it holds any state, so `ticked` starts no charge (though the client's conditions for the charge spells mask nothing) and a state that takes hold during a charge breaks it.
/// - `can_move`: the creature may move (`creature_unit_type.can_move`); one that may not never
///   chases or walks home.
/// - `alternates`: the auto-attacks it strikes with after `attack` in turn, in the order its kind
///   lists them (`creature_life.Combat.alternates`); empty for a creature with one auto-attack.
/// - `specials`: the spells it casts besides its auto-attacks, in the order its kind lists them
///   (`creature_life.Combat.specials`). A creature that holds any state casts none of them
///   (`holds_a_state`), which covers every state a special's caster conditions name.
/// - `turn_held`: it holds a Stun, Knockdown or Knockback, or is opened: it stands facing as
///   it did and does not turn to its target until that ends (a server's choice, a guess: the
///   client holds no rule for turning under a state; a Root and the other run-stopping states
///   leave it turning, since they only stop its run).
/// An attack that is `Charged` is a charge.
pub type Fighter {
  Fighter(
    unit_id: Int,
    address: Address,
    can_move: Bool,
    home: Place,
    attack: Attack,
    alternates: List(Attack),
    interval_ms: Int,
    numbers: GameNumbers,
    still: Bool,
    attack_refused: Bool,
    holds_a_state: Bool,
    guard_casts: List(Int),
    hit_radius: Float,
    specials: List(Special),
    turn_held: Bool,
  )
}

/// Where a standing creature is in a fight. Whether it is alive is creature_life's
/// (genesis_prime/world_map/creature_life): a creature that dies leaves its fight
/// and rests where it fell until its respawn.
pub type Status {
  /// Fighting no one: a viewer's `Approached` or a strike starts a fight.
  Resting
  /// On a fight: its threat list, never empty, the target it last named, the
  /// strike round it waits on, the generation of its attack tick and the hold it stands in
  /// (it ends with the tick it names, and with the fight).
  Fighting(
    threat: Dict(ConnectionId, Threat),
    target: ConnectionId,
    round: Option(Round),
    tick: Int,
    hold: Option(Hold),
  )
  /// Walking home after a leash, taking no strike, until its home timer of this
  /// generation fires.
  Returning(home: Int)
}

/// One entry of the threat list: the player's unit, the stay of the message that
/// put it on the list, which every tell to it names, and its threat.
pub type Threat {
  Threat(unit_id: Int, stay: Stay, amount: Float)
}

/// The round the creature waits on: the number of its cast (`cast_state.cast_id`, the 0x7ff,
/// 0x7f4 and 0x7fe of the round name it), the Spell4 it casts (the attack of the round is
/// found by this id in the fighter each time, `attack_named`, so a property change between
/// gos works the strike out again), what the cast fixed when it started, how far it has
/// got, and the gos it has reached whose 0x7f4 is not written yet.
pub type Round {
  Round(
    cast_id: Int,
    spell4_id: Spell4Id,
    start: Start,
    stage: Stage,
    go_rounds: List(GoRound),
  )
}

/// One go of a round that was reached and not yet written (0x7f4), in go order: what it still
/// awaits (`Awaiting`) and what the answers struck so far. An entry is complete when it awaits
/// nothing (no strike, a strike that struck nobody, every answer in, or its deadline passed);
/// it is written when it is complete and every entry before it is written.
pub type GoRound {
  GoRound(phase: Int, awaiting: Awaiting, struck: List(cast_state.Struck))
}

/// The strikes of a go not answered yet. `Pending` holds the generation of the go's
/// `StrikeDeadline` timer with the key of each strike not answered, each with the connection it
/// went to. It is built only by `pending` and `without_answer`, which give `Complete` for no
/// key, so a go never awaits an answer with no deadline to end the wait, and a deadline is
/// never held for a go that awaits nothing.
pub type Awaiting {
  Complete
  Pending(deadline: Int, keys: Dict(Key, ConnectionId))
}

/// The go awaits the strikes of `keys` until its `StrikeDeadline` of `deadline`; no key is
/// `Complete`.
fn pending(
  deadline deadline: Int,
  keys keys: Dict(Key, ConnectionId),
) -> Awaiting {
  use <- bool.guard(when: dict.is_empty(keys), return: Complete)
  Pending(deadline:, keys:)
}

/// `awaiting` after the answer of `key`: `Complete` when it was the last one awaited.
fn without_answer(awaiting awaiting: Awaiting, key key: Key) -> Awaiting {
  case awaiting {
    Complete -> Complete
    Pending(deadline:, keys:) ->
      pending(deadline:, keys: dict.delete(keys, key))
  }
}

/// What a cast fixed when it started: the creature's pose, which is its facing after it turned
/// to its target (a creature that cannot move: the aim toward its 0x908 target), the unit the
/// cast is on (none for an attack with no cast time), and the entries its 0x7ff carried. A row
/// the client draws where the 0x7ff put it keeps its hit at the pose it names, and a viewer
/// that arrives later is sent the same cast target and entries.
pub type Start {
  Start(
    aim: area.Pose,
    target: Option(CastTarget),
    opening: telegraph_entries.Opening,
  )
}

/// The unit a charge is cast on, which the 0x7ff names as its primary target and the client
/// draws a client-placed target row on (`opcode.0x7ff`, `0x140546e60.placement_branches`): its
/// connection, and its unit and place when the cast began, the one value the entries are made
/// from and a fixed row is struck around. It is the target the creature had then; the 0x908
/// target of a later moment does not change it.
pub type CastTarget {
  CastTarget(connection: ConnectionId, placed: telegraph_entries.Placed)
}

/// Where a round stands. An attack with no cast time starts at `Striking` with one entry
/// awaiting its answer; a charge is `Charging` while a go is still to come, then `Striking`:
/// every go has been reached and the entries still open are all that is left.
pub type Stage {
  /// The cast is under way: the generation of the `CastEnds` timer of the go it waits for, the
  /// index of that go in the attack's `Charged.gos` (the phase its 0x7f4 carries), and the
  /// monotonic time the cast started. A go is due `started_ms + at_ms`, and its timer is
  /// armed for `max(0, due - now_ms)`, so a late timer does not push the later gos. A state
  /// that takes hold while it lasts breaks it (`held`).
  Charging(ends: Int, go: Int, started_ms: Int)
  /// Every go is reached. The round closes (0x7fe) when its last entry is written.
  Striking
}

/// The newest place the creature knows a connection's player at, with the move
/// sequence number and the stay it came with, and the hit radius of the player's race
/// (genesis_prime/game/hit_radius), which a charge's rectangle counts the player by.
pub type Sighting {
  Sighting(unit_id: Int, place: Place, seq: Int, stay: Stay, hit_radius: Float)
}

/// A creature's fight: its status, where it stands or runs (kept apart from the
/// status, and still where it fell while it lies dead), the players inside its
/// ring (from `Approached` and `Withdrew`), the newest place of each player it
/// heard of, the number of its next cast, the next timer generation, a throw it is in,
/// and when each special may be cast again (`ready_at`: a Spell4 id to the monotonic time;
/// absent means ready; emptied by `start_fight`, so every fight opens with its specials ready),
/// and how many auto-attacks it has struck with this fight (`autos_struck`: the next auto-attack
/// is `attack` and `alternates` at that count's remainder; zero from `start_fight`, so every
/// fight opens with the lead), `turn`, what its viewers' clients hold its rotation to
/// (genesis_prime/world_map/creature_turn): the facing of its spawn until the fight turns it,
/// and `facing`, the facing its viewers' clients showed it at the end of the last input: the
/// one it keeps when the unit it faces stands on its own ground point (`facing_of`).
pub opaque type State {
  State(
    status: Status,
    path: Path,
    near: Set(ConnectionId),
    sightings: Dict(ConnectionId, Sighting),
    next_cast: Int,
    next_generation: Int,
    flight: Option(Flight),
    ready_at: Dict(Int, Int),
    autos_struck: Int,
    turn: Face,
    facing: Facing,
  )
}

/// A creature standing still after a special (`Charged.hold_ms`, from the strike's
/// NpcExecutionDelay rows, a server choice): the generation of the `AttackTick` that ends it
/// and the monotonic time that tick is due. While it lasts the creature starts no path
/// (`chase`, whether a target moved, a new target was named, `ControlEnded` or `SpeedChanged`
/// asked) and casts and strikes nothing, since the tick is its only driver. The creature
/// already stands: its path was turned in place when the cast began (`turned_to_face`) and
/// `chase` starts none while a charge is open or its strikes are out (`casting_or_holding`). The tick that ends it clears it; so do the
/// leash, a death and a new fight, by leaving `Fighting`.
pub type Hold {
  Hold(ends: Int, until_ms: Int)
}

/// A throw the creature is in (genesis_prime/game/forced_move): the generation of its
/// `FlightEnds` timer and the monotonic time the path's last point is reached.
pub type Flight {
  Flight(ends: Int, until_ms: Int)
}

/// What the creature's rule turns its messages and timers into for the fight.
pub type Input {
  /// The map: the player of `by`, in its stay `stay`, entered the creature's ring,
  /// at `place` of move `seq`, with the hit radius of its race.
  Approached(
    by: ConnectionId,
    unit_id: Int,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
  )
  /// The map: the player of `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The map: the player of `by` died. It leaves `near` and the threat list.
  PlayerDied(by: ConnectionId)
  /// The player of `by`, on the threat list, in its stay `stay`, moved to `place`
  /// of move `seq`; its race's hit radius is `hit_radius`.
  TargetMoved(
    by: ConnectionId,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
  )
  /// A player's strike landed on the creature for `threat`
  /// (`threat_of`), from `place` of move `seq`; its race's hit radius is `hit_radius`.
  StruckBy(
    by: ConnectionId,
    unit_id: Int,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
    threat: Float,
  )
  /// The map: the player of `by` no longer sees the creature.
  Unwatched(by: ConnectionId)
  /// The player's answer to the creature's strike.
  StrikeAnswered(answered: Answered)
  /// One of the fight's timers fired.
  TimerFired(timer: Timer)
  /// creature_life: a strike killed the creature.
  Killed
  /// creature_life: a DespawnUnit effect removed the creature from the field. The fight ends
  /// as it does at a death (`Killed`): a path stops, a charge ends, each threatened player is
  /// `Released`.
  Despawned
  /// creature_life: the corpse timer stood the creature again at its spawn.
  StoodAgain
  /// creature_control: a state took hold of the creature while it lives. An open charge
  /// breaks; a path it runs stops where it stands (0x638 of kind 2 for its viewers, as at a
  /// death) when its states stop its run (`Fighter.still`).
  Controlled
  /// creature_control: the last state that stopped the creature's run ended. It acts again
  /// from where it stands: a fight chases its target and goes on; a creature that was to walk home
  /// when a state held it starts the walk.
  ControlEnded
  /// creature: a property modifier changed the creature's run speed
  /// (`fighter.attack.run_speed`). A path it runs at another speed is run on from where
  /// the creature stands at the new speed, to the same end. A speed not above 0 stops the
  /// run where the creature stands; a creature that stands starts again when its speed is
  /// above 0 and no state holds it (a fight chases; a walk home away from home goes on,
  /// with its home timer; `ControlEnded` starts them when a state holds the creature).
  SpeedChanged
  /// creature: a ForcedMove effect of a player's cast reaches the creature
  /// (genesis_prime/game/forced_move `Throw`): the move the row asks for, the two
  /// fractions the caster's connection drew, and the unit it is measured from. A creature
  /// that is walking home, or does not run, takes no throw. Else it takes the path the move
  /// builds from where it is, the viewers are sent it, and `FlightEnds` ends the flight.
  /// A throw breaks an open charge as a held state does.
  Thrown(throw: forced_move.Throw)
  /// creature: whether the creature may turn (`Fighter.turn_held`) changed with no other change
  /// to the fight, as a state ended while another still holds the creature, or the guard opened
  /// or closed. It turns, or stands, as the fight now wants and does nothing else.
  Reconsidered
}

/// The fight's timers, each of the generation it was started with: a timer of a
/// generation the fight no longer waits on (a round that closed, a tick of a fight
/// that ended) does nothing when it fires.
pub type Timer {
  /// Every `interval_ms` while Fighting: strike when the target is in reach, else
  /// chase or leash.
  AttackTick(generation: Int)
  /// The strike round's deadline (genesis_prime/game/strike_tell `deadline_ms`).
  StrikeDeadline(generation: Int)
  /// The walk home is run.
  HomeArrival(generation: Int)
  /// A go of the charge is due (`Charged.gos`, counted from the 0x7ff): a go that strikes
  /// sends the strikes, any other sends its 0x7f4 and arms the next go.
  CastEnds(generation: Int)
  /// The thrown creature's path is run: it stands at the path's last point, and acts
  /// again unless a state holds it.
  FlightEnds(generation: Int)
  /// The chase path is run: the viewers are told the creature stands at its end, which stops the
  /// walk animation the path's frame started. A creature has one chase path at a time, so the
  /// timer has no generation; it does nothing unless the creature is Fighting with a running path.
  ChaseArrival
}

/// What the fight asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer.
  ToViewers(news: News)
  /// A tell to the connection of a player in the fight, for the stay the fight
  /// holds it in.
  ToPlayer(to: ConnectionId, stay: Stay, told: Told)
  /// The creature stands at full health again: creature_life's health is restored
  /// and each viewer is sent its 0x937.
  RestoreHealth
  /// A crowd-control state broke the open charge: its `CancelTimer(CastEnds)`, the 0x7f9 of
  /// result 11 and the 0x7fe are in the effects before it, and the creature's rule tells the
  /// guard (`creature_guard.Interrupted`), which opens the creature.
  ChargeInterrupted(cast_id: Int)
  StartTimer(timer: Timer, after_ms: Int)
  CancelTimer(timer: Timer)
}

/// A creature resting at its spawn, with no one near.
pub fn new(home home: Place) -> State {
  State(
    status: Resting,
    path: Standing(at: home),
    near: set.new(),
    sightings: dict.new(),
    next_cast: 1,
    next_generation: 1,
    flight: None,
    ready_at: dict.new(),
    autos_struck: 0,
    turn: Fixed(facing: start_place.facing(home)),
    facing: start_place.facing(home),
  )
}

/// One input of the fight in, the new state and the effects out. `viewers` are the
/// creature's viewers now, each in the stay its `Watched` named, `alive` whether
/// creature_life holds it standing, and `now_ms` the monotonic time of the input.
/// A player's strike or move of another stay than its viewer's is of an earlier
/// stay, delayed past the player's leave and new join: it starts and moves nothing.
pub fn step(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Dict(ConnectionId, Stay),
  alive alive: Bool,
  input input: Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    stepped(
      state: shown_facing(state:, now_ms:),
      fighter:,
      viewers:,
      alive:,
      input:,
      now_ms:,
    )
  let #(state, turned) = faced(state:, fighter:, now_ms:)
  #(shown_facing(state:, now_ms:), list.append(effects, turned))
}

/// The state holding the facing its viewers' clients show the creature at `now_ms`, which an
/// input that puts the unit it faces on its own ground point leaves it with. It is taken before
/// the input (the facing the clients show when the input arrives) and after (the facing the
/// input's news gave).
fn shown_facing(state state: State, now_ms now_ms: Int) -> State {
  State(
    ..state,
    facing: facing_of(
      state:,
      here: creature_path.place_at(path: state.path, now_ms:),
    ),
  )
}

fn stepped(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Dict(ConnectionId, Stay),
  alive alive: Bool,
  input input: Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case input {
    Approached(by:, unit_id:, place:, seq:, stay:, hit_radius:) -> {
      let state =
        State(
          ..sighted(state:, by:, unit_id:, place:, seq:, stay:, hit_radius:),
          near: set.insert(state.near, by),
        )
      case state.status, alive && in_stay(viewers:, by:, stay:) {
        Resting, True ->
          aggro(state:, fighter:, viewers:, players: [by], now_ms:)
        Resting, False | Fighting(..), _ | Returning(..), _ -> #(state, [])
      }
    }
    Withdrew(by:) -> #(State(..state, near: set.delete(state.near, by)), [])
    PlayerDied(by:) -> fell(state:, fighter:, by:, now_ms:)
    TargetMoved(by:, place:, seq:, stay:, hit_radius:) -> {
      use <- bool.guard(
        when: !in_stay(viewers:, by:, stay:),
        return: #(state, []),
      )
      let state =
        sighted(
          state:,
          by:,
          unit_id: unit_of(state:, by:),
          place:,
          seq:,
          stay:,
          hit_radius:,
        )
      case state.status, alive {
        Fighting(target:, ..), True if target == by ->
          chase(state:, fighter:, now_ms:)
        Fighting(..), _ | Resting, _ | Returning(..), _ -> #(state, [])
      }
    }
    StruckBy(by:, unit_id:, place:, seq:, stay:, hit_radius:, threat:) -> {
      use <- bool.guard(
        when: !in_stay(viewers:, by:, stay:),
        return: #(state, []),
      )
      let state =
        sighted(state:, by:, unit_id:, place:, seq:, stay:, hit_radius:)
      case alive {
        False -> #(state, [])
        True -> threatened_by(state:, fighter:, by:, stay:, threat:, now_ms:)
      }
    }
    Unwatched(by:) -> fell(state:, fighter:, by:, now_ms:)
    StrikeAnswered(answered:) ->
      answered_strike(state:, fighter:, answered:, now_ms:)
    TimerFired(timer: AttackTick(generation:)) ->
      case state.status, alive {
        Fighting(tick:, ..), True if tick == generation ->
          ticked(state:, fighter:, now_ms:)
        Fighting(..), _ | Resting, _ | Returning(..), _ -> #(state, [])
      }
    TimerFired(timer: StrikeDeadline(generation:)) ->
      case state.status {
        Fighting(round: Some(round), ..) ->
          case deadline_entry(round:, generation:) {
            Ok(entry) -> {
              let round =
                with_entry(round:, entry: GoRound(..entry, awaiting: Complete))
              let #(state, written, ticking) =
                settled(state:, fighter:, round:, now_ms:)
              #(state, list.append(written, ticking))
            }
            Error(Nil) -> #(state, [])
          }
        Fighting(..) | Resting | Returning(..) -> #(state, [])
      }
    TimerFired(timer: CastEnds(generation:)) ->
      case state.status {
        Fighting(
          round: Some(Round(stage: Charging(ends:, ..), ..) as round),
          ..,
        )
          if ends == generation
        -> go_reached(state:, fighter:, round:, viewers:, now_ms:)
        Fighting(..) | Resting | Returning(..) -> #(state, [])
      }
    TimerFired(timer: HomeArrival(generation:)) ->
      case state.status {
        Returning(home:) if home == generation -> {
          let arrived = case state.path {
            Running(..) -> [
              ToViewers(client_connection.CreaturePlaced(
                place: fighter.home,
                at_ms: now_ms,
              )),
            ]
            Standing(..) | Timed(..) -> []
          }
          let state =
            State(..state, status: Resting, path: Standing(at: fighter.home))
          let #(state, turned) = faced(state:, fighter:, now_ms:)
          let #(state, fought) =
            aggro(
              state:,
              fighter:,
              viewers:,
              players: near_viewers(state:, viewers:),
              now_ms:,
            )
          #(state, list.flatten([arrived, turned, fought]))
        }
        Returning(..) | Resting | Fighting(..) -> #(state, [])
      }
    TimerFired(timer: ChaseArrival) ->
      case state.status, state.path {
        Fighting(..), Running(..) -> {
          let end = creature_path.end(path: state.path)
          #(State(..state, path: Standing(at: end)), [
            ToViewers(client_connection.CreaturePlaced(
              place: end,
              at_ms: now_ms,
            )),
          ])
        }
        Fighting(..), Standing(..)
        | Fighting(..), Timed(..)
        | Resting, _
        | Returning(..), _
        -> #(state, [])
      }
    Killed | Despawned -> killed(state:, fighter:, now_ms:)
    Reconsidered -> #(state, [])
    Controlled -> held(state:, fighter:, now_ms:)
    ControlEnded -> resumed(state:, fighter:, now_ms:)
    SpeedChanged -> speed_changed(state:, fighter:, now_ms:)
    Thrown(throw:) -> thrown(state:, fighter:, alive:, throw:, now_ms:)
    TimerFired(timer: FlightEnds(generation:)) ->
      flight_ended(state:, fighter:, generation:, now_ms:)
    StoodAgain -> {
      let state =
        State(
          ..state,
          status: Resting,
          path: Standing(at: fighter.home),
          turn: Fixed(facing: start_place.facing(fighter.home)),
        )
      aggro(
        state:,
        fighter:,
        viewers:,
        players: near_viewers(state:, viewers:),
        now_ms:,
      )
    }
  }
}

/// A throw reaches the creature: dropped when it is dead, walking home or does not run
/// (`creature_path.runs` of `Fighter.attack.run_speed`); else its path is built from where it is
/// (`forced_move.path`, clipped at the leash circle), kept as `Timed` with a `Flight`
/// and its `FlightEnds` timer, an open charge is broken as `held` does, and the viewers
/// are sent the path.
fn thrown(
  state state: State,
  fighter fighter: Fighter,
  alive alive: Bool,
  throw throw: forced_move.Throw,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let walking_home = case state.status {
    Returning(..) -> True
    Resting | Fighting(..) -> False
  }
  use <- bool.guard(
    when: !alive
      || walking_home
      || cannot_move(fighter:)
      || !creature_path.runs(speed: fighter.attack.run_speed),
    return: #(state, []),
  )
  let here = creature_path.place_at(path: state.path, now_ms:)
  let was_run = creature_path.arrives_ms(path: state.path, now_ms:) > now_ms
  let path =
    forced_move.path(
      move: throw.move,
      draws: throw.draws,
      from: here,
      velocity: creature_path.velocity(path: state.path, now_ms:),
      radius: fighter.hit_radius,
      reference: throw.reference,
      circle: Circle(centre: fighter.home, radius: fighter.numbers.leash_range),
      now_ms:,
    )
  let displaced = case path {
    Timed(..) -> True
    Standing(at:) -> at != here || was_run
    Running(..) -> panic as "a throw's path is Standing or Timed"
  }
  let #(state, broken) = case displaced {
    True -> charge_broken(state:, fighter:, now_ms:)
    False -> #(state, [])
  }
  let #(state, left) = flight_cleared(state:)
  let turn = case path {
    Timed(turned_to: Some(facing), ..) -> Fixed(facing:)
    Timed(..) | Standing(..) | Running(..) -> state.turn
  }
  let state = State(..state, path:, turn:)
  let #(state, moved) = case path {
    Timed(..) -> {
      let until_ms = creature_path.arrives_ms(path:, now_ms:)
      let news = [ToViewers(client_connection.CreatureMoved(path:))]
      case until_ms > now_ms {
        False -> #(state, news)
        True -> {
          let #(state, ends) = generation(state)
          #(
            State(..state, flight: Some(Flight(ends:, until_ms:))),
            list.append(news, [
              StartTimer(timer: FlightEnds(ends), after_ms: until_ms - now_ms),
            ]),
          )
        }
      }
    }
    Standing(at:) ->
      case displaced {
        True -> #(state, [
          ToViewers(client_connection.CreaturePlaced(place: at, at_ms: now_ms)),
        ])
        False -> #(state, [])
      }
    Running(..) -> panic as "a throw's path is Standing or Timed"
  }
  #(state, list.flatten([broken, left, moved]))
}

/// The flight the creature is in ends without its `FlightEnds`: the flight is cleared and
/// its timer cancelled. A creature in no flight is as it was.
fn flight_cleared(state state: State) -> #(State, List(Effect)) {
  case state.flight {
    Some(Flight(ends:, ..)) -> #(State(..state, flight: None), [
      CancelTimer(timer: FlightEnds(ends)),
    ])
    None -> #(state, [])
  }
}

/// `FlightEnds` fires: of the generation of the flight the fight holds, the creature
/// stands at the path's last point with no news for its viewers (a client holds a kind 3
/// path's last point), and chases again unless a state holds it; of any other generation
/// it does nothing.
fn flight_ended(
  state state: State,
  fighter fighter: Fighter,
  generation generation: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.flight {
    Some(Flight(ends:, ..)) if ends == generation -> {
      let state =
        State(
          ..state,
          flight: None,
          path: Standing(at: creature_path.end(path: state.path)),
        )
      case fighter.still {
        True -> #(state, [])
        False -> resumed(state:, fighter:, now_ms:)
      }
    }
    Some(..) | None -> #(state, [])
  }
}

/// Whether the creature takes a strike: a creature walking home refuses it.
pub fn refusal(state state: State) -> Result(Nil, strike_tell.Refusal) {
  case state.status {
    Returning(..) -> Error(strike_tell.Returning)
    Resting | Fighting(..) -> Ok(Nil)
  }
}

/// The id of the cast the fight holds live: the open round's, which the guard's casts take no id
/// of (`cast_state.mint`); none with no round open.
pub fn live_casts(state state: State) -> List(Int) {
  case state.status {
    Fighting(round: Some(Round(cast_id:, ..)), ..) -> [cast_id]
    Fighting(..) | Resting | Returning(..) -> []
  }
}

/// Whether the creature is in combat, as its combat flag (0x89a) tells its viewers: True
/// while Fighting, False at rest and on the way home.
pub fn in_combat(state state: State) -> Bool {
  case state.status {
    Fighting(..) -> True
    Resting | Returning(..) -> False
  }
}

/// The connections on the threat list: none unless Fighting.
pub fn threatened(state state: State) -> Set(ConnectionId) {
  case state.status {
    Fighting(threat:, ..) -> set.from_list(dict.keys(threat))
    Resting | Returning(..) -> set.new()
  }
}

/// Where the creature stands at monotonic time `now_ms`, facing as its viewers' clients
/// show it (`facing_of`), for the 0x262 of a viewer that arrives while it runs and for the
/// yaw its gates and strikes read.
pub fn place_at(state state: State, now_ms now_ms: Int) -> Place {
  turned_place(state:, place: creature_path.place_at(path: state.path, now_ms:))
}

/// The place with the facing the creature's turn gives it there.
fn turned_place(state state: State, place place: Place) -> Place {
  start_place.turned(place:, facing: facing_of(state:, here: place))
}

/// The facing of the creature standing at `here`, by what its viewers' clients hold its
/// rotation to: a fixed facing, or the bearing to the unit it keeps facing by the newest
/// sighting of that unit, or to the point (`creature_turn.toward`). A target on its own ground
/// point, or a unit it has no sighting of, leaves the facing it showed last (`State.facing`),
/// as the client leaves its rotation.
fn facing_of(state state: State, here here: Place) -> Facing {
  let kept = state.facing
  case state.turn {
    Fixed(facing:) | creature_turn.Home(facing:) -> facing
    creature_turn.Point(place:) ->
      creature_turn.toward(from: here, target: place, kept:)
    creature_turn.Unit(unit_id:) ->
      case
        list.find(map.sorted_by_connection(state.sightings), fn(entry) {
          { entry.1 }.unit_id == unit_id
        })
      {
        Ok(#(_, sighting)) ->
          creature_turn.toward(from: here, target: sighting.place, kept:)
        Error(Nil) -> kept
      }
  }
}

/// What the creature's rotation should be held to now (`faced` sends the change). A creature
/// that cannot move, or is thrown, keeps what it has. Resting, it faces its spawn's way (the
/// one change a fight leaves for it: from facing home). Fighting, it faces the unit of its
/// target, unless it is held (`Fighter.turn_held`: it stands as it faces) or a charge fixes it
/// (the open charge, and the strikes of a charged round, along the facing the charge turned it
/// to); Returning, it faces home, or stands as it faces when held. The hold after a special
/// turns it again, since it is no round. A creature that is home already takes its spawn's facing
/// as it leashes: a point under it would leave it as it was.
fn wanted(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> Face {
  use <- bool.guard(
    when: cannot_move(fighter:) || option.is_some(state.flight),
    return: state.turn,
  )
  let frozen = fn() {
    Fixed(facing: facing_of(
      state:,
      here: creature_path.place_at(path: state.path, now_ms:),
    ))
  }
  case state.status {
    Resting ->
      case state.turn {
        Fixed(..) | creature_turn.Home(..) -> state.turn
        creature_turn.Unit(..) | creature_turn.Point(..) ->
          creature_turn.Home(facing: start_place.facing(fighter.home))
      }
    Returning(..) -> {
      let here = creature_path.place_at(path: state.path, now_ms:)
      case
        fighter.turn_held,
        area.point_of(place: here) == area.point_of(place: fighter.home)
      {
        True, _ -> frozen()
        False, True ->
          creature_turn.Home(facing: start_place.facing(fighter.home))
        False, False -> creature_turn.Point(place: fighter.home)
      }
    }
    Fighting(threat:, target:, ..) ->
      case fighter.turn_held, round_fixes_the_turn(state:, fighter:) {
        True, _ -> frozen()
        False, True -> state.turn
        False, False -> {
          let assert Ok(entry) = dict.get(threat, target)
            as "the target is on the threat list"
          creature_turn.Unit(unit_id: entry.unit_id)
        }
      }
  }
}

/// Whether a charge holds the creature's facing: while it is open, and while the strikes of a
/// charged round are out (the cone is fixed from the wind-up's start to the round's close).
fn round_fixes_the_turn(state state: State, fighter fighter: Fighter) -> Bool {
  case state.status {
    Fighting(round: Some(Round(stage: Charging(..), ..)), ..) -> True
    Fighting(round: Some(Round(stage: Striking, spell4_id:, ..)), ..) ->
      case attack_named(fighter:, spell4_id:).cast {
        Charged(..) -> True
        Instant -> False
      }
    Fighting(..) | Resting | Returning(..) -> False
  }
}

/// The creature turns as `wanted` says: nothing when it is held to that already, else the
/// turn is kept and the viewers are sent it. Every step ends with it, and each place that
/// sends a path or a cast first (a fight's start, a new target, the leash, a resumed creature,
/// the arrival home) calls it before them, so the turn goes out before the path it goes with.
fn faced(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let face = wanted(state:, fighter:, now_ms:)
  case face == state.turn {
    True -> #(state, [])
    False -> #(State(..state, turn: face), [
      ToViewers(client_connection.CreatureFaces(face:, at_ms: now_ms)),
    ])
  }
}

/// What a viewer that arrives at monotonic time `now_ms` is sent after the
/// creature's 0x262, so its client shows what the others' do: in a fight, the
/// combat flag (0x89a), the target (0x908) and each other entry (0x90a); a charge that is
/// open, its 0x7ff again on the cast's own target (`Start.target`, not the 0x908 target of
/// now) with the entries of the start and its cast id, which the later go names, and the 0x7f4 of each go
/// already written, with no target (the viewer's cast bar runs from its arrival, not from the
/// cast's start; a go still open is written to every viewer when it closes); and on a path not
/// yet run, the rest of it from where the creature is now (0x638).
pub fn arrival_news(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> List(News) {
  let fight = case state.status {
    Fighting(threat:, target:, ..) -> {
      let others =
        map.sorted_by_connection(threat)
        |> list.filter(fn(entry) { entry.0 != target })
        |> list.map(fn(entry) { threat_news(entry.1) })
      let assert Ok(top) = dict.get(threat, target)
        as "the target is on the threat list"
      [
        client_connection.CombatState(in_combat: True),
        targeting_news(top),
        ..others
      ]
    }
    Resting | Returning(..) -> []
  }
  let turn = case state.turn {
    Fixed(..) | creature_turn.Home(..) -> []
    creature_turn.Unit(..) as face | creature_turn.Point(..) as face -> [
      client_connection.CreatureFaces(face:, at_ms: now_ms),
    ]
  }
  let charge = case state.status {
    Fighting(
      round: Some(Round(cast_id:, spell4_id:, start:, stage:, go_rounds:)),
      ..,
    ) ->
      case attack_named(fighter:, spell4_id:).cast {
        Charged(gos:, ..) -> {
          let assert Some(cast_target) = start.target
            as "a charge is cast on a target"
          let place = place_at(state:, now_ms:)
          let reached = case stage {
            Charging(go:, ..) -> go
            Striking -> list.length(gos)
          }
          let gone = reached - list.length(go_rounds)
          [
            client_connection.CastStarted(start: cast_frame.creature_started(
              cast_id:,
              spell4_id: spell4_id.value,
              caster_unit_id: fighter.unit_id,
              target_unit_id: cast_target.placed.unit_id,
              place:,
              opening: start.opening,
            )),
            ..list.index_map(list.take(gos, gone), fn(_, phase) {
              client_connection.CastWent(
                go: cast_frame.creature_went(
                  cast_id:,
                  phase:,
                  place:,
                  struck: [],
                ),
              )
            })
          ]
        }
        Instant -> []
      }
    Fighting(..) | Resting | Returning(..) -> []
  }
  let path = case state.path {
    Running(..) ->
      case creature_path.rest_of(path: state.path, now_ms:) {
        Standing(..) -> []
        Running(..) as rest | Timed(..) as rest -> [
          client_connection.CreatureMoved(path: rest),
        ]
      }
    Standing(..) -> []
    Timed(..) ->
      case creature_path.arrives_ms(path: state.path, now_ms:) > now_ms {
        True -> [
          client_connection.CreatureMoved(path: creature_path.rest_of(
            path: state.path,
            now_ms:,
          )),
        ]
        False -> []
      }
  }
  list.flatten([fight, turn, charge, path])
}

/// The threat a landed strike adds: each blow's damage taken (to health) times its
/// effect's threatMultiplier (`Spell4Effects.threatMultiplier`), matched by effect.
pub fn threat_of(
  offence offence: Offence,
  descriptions descriptions: List(hit.Description),
) -> Float {
  list.fold(descriptions, 0.0, fn(sum, description) {
    let multiplier =
      list.find(offence.blows, fn(blow) {
        blow.spell4_effects_id == description.spell4_effects_id
      })
      |> result.map(fn(blow) { blow.threat_multiplier })
      |> result.unwrap(1.0)
    sum
    +. int.to_float(description.damage.health_damage_with_overkill)
    *. multiplier
  })
}

/// Whether the player of `by` is a viewer in the stay `stay`.
fn in_stay(
  viewers viewers: Dict(ConnectionId, Stay),
  by by: ConnectionId,
  stay stay: Stay,
) -> Bool {
  dict.get(viewers, by) == Ok(stay)
}

/// The state with the player's newest place: in the same stay, a move of a lower
/// sequence number than the one held is older and dropped, and an equal one is the
/// same move; a sighting of another stay gives way to the newer stay's.
fn sighted(
  state state: State,
  by by: ConnectionId,
  unit_id unit_id: Int,
  place place: Place,
  seq seq: Int,
  stay stay: Stay,
  hit_radius hit_radius: Float,
) -> State {
  case dict.get(state.sightings, by) {
    Ok(held) if held.stay == stay && held.seq > seq -> state
    Ok(..) | Error(Nil) ->
      State(
        ..state,
        sightings: dict.insert(
          state.sightings,
          by,
          Sighting(unit_id:, place:, seq:, stay:, hit_radius:),
        ),
      )
  }
}

/// The unit the creature last knew the connection's player as, 0 for none.
fn unit_of(state state: State, by by: ConnectionId) -> Int {
  case dict.get(state.sightings, by) {
    Ok(sighting) -> sighting.unit_id
    Error(Nil) -> 0
  }
}

/// The near players the creature sees now, in the order of their connections.
fn near_viewers(
  state state: State,
  viewers viewers: Dict(ConnectionId, Stay),
) -> List(ConnectionId) {
  map.sorted_connections(set.intersection(
    state.near,
    set.from_list(dict.keys(viewers)),
  ))
}

/// A resting creature aggroes these players, each with the aggro threat, in the
/// stay its sighting came with (`start_fight`). No player it has a place for in
/// the stay it is a viewer in, no fight.
fn aggro(
  state state: State,
  fighter fighter: Fighter,
  viewers viewers: Dict(ConnectionId, Stay),
  players players: List(ConnectionId),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let entries =
    list.filter_map(players, fn(player) {
      case dict.get(state.sightings, player) {
        Ok(sighting) ->
          case in_stay(viewers:, by: player, stay: sighting.stay) {
            True ->
              Ok(#(
                player,
                Threat(
                  unit_id: sighting.unit_id,
                  stay: sighting.stay,
                  amount: fighter.numbers.aggro_threat,
                ),
              ))
            False -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    })
  start_fight(state:, fighter:, entries:, now_ms:)
}

/// A resting creature starts a fight with these entries: the first is the target
/// (0x908), each other is named in 0x90a, the creature is in combat (0x89a), each
/// player is told `Threatened`, the creature chases its target when it is out of
/// reach, and the attack tick starts.
fn start_fight(
  state state: State,
  fighter fighter: Fighter,
  entries entries: List(#(ConnectionId, Threat)),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case entries {
    [] -> #(state, [])
    [first, ..others] -> {
      let #(state, tick) = generation(state)
      let state =
        State(
          ..state,
          ready_at: dict.new(),
          autos_struck: 0,
          status: Fighting(
            threat: dict.from_list(entries),
            target: first.0,
            round: None,
            tick:,
            hold: None,
          ),
        )
      let named = [
        targeting(first.1),
        ..list.map(others, fn(other) { ToViewers(threat_news(other.1)) })
      ]
      let told =
        list.map(entries, fn(entry) {
          ToPlayer(
            to: entry.0,
            stay: { entry.1 }.stay,
            told: threatened_told(fighter:),
          )
        })
      let #(state, turned) = faced(state:, fighter:, now_ms:)
      let #(state, chased) = chase(state:, fighter:, now_ms:)
      #(
        state,
        list.flatten([
          named,
          [ToViewers(client_connection.CombatState(in_combat: True))],
          told,
          turned,
          chased,
          [StartTimer(timer: AttackTick(tick), after_ms: fighter.interval_ms)],
        ]),
      )
    }
  }
}

fn threatened_told(fighter fighter: Fighter) -> Told {
  case fighter.address {
    step.Creature(life:, ..) -> Threatened(unit_id: fighter.unit_id, life:)
    step.Sessions
    | step.HandOff
    | step.Store
    | step.Maps
    | step.Map(..)
    | step.Connection(..)
    | step.CharacterNamed(..)
    | step.ZoneChannel(..) ->
      panic as "a creature's address is a Creature address"
  }
}

/// A viewer's strike, in its stay `stay`, adds its threat: a resting creature
/// starts a fight with it; a fighting one adds to its entry, naming a new top entry
/// as its target (0x908), and any other entry's new threat in 0x90a.
fn threatened_by(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  stay stay: Stay,
  threat threat: Float,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Returning(..) -> #(state, [])
    Resting ->
      start_fight(
        state:,
        fighter:,
        entries: [
          #(by, Threat(unit_id: unit_of(state:, by:), stay:, amount: threat)),
        ],
        now_ms:,
      )
    Fighting(threat: entries, target:, ..) as fighting -> {
      let unit_id = unit_of(state:, by:)
      let is_new = !dict.has_key(entries, by)
      let entries =
        dict.upsert(entries, by, fn(found) {
          case found {
            Some(entry) -> Threat(..entry, amount: entry.amount +. threat)
            None -> Threat(unit_id:, stay:, amount: threat)
          }
        })
      let #(top, top_entry) = top_of(entries)
      let state =
        State(
          ..state,
          status: Fighting(..fighting, threat: entries, target: top),
        )
      let told = case is_new {
        True -> [ToPlayer(to: by, stay:, told: threatened_told(fighter:))]
        False -> []
      }
      let named = case top != target || top == by {
        True -> [targeting(top_entry)]
        False -> {
          let assert Ok(entry) = dict.get(entries, by)
            as "the striker is on the list"
          [ToViewers(threat_news(entry))]
        }
      }
      #(state, list.append(named, told))
    }
  }
}

/// 0x908 naming the entry as the target, with its threat, to the viewers.
fn targeting(entry: Threat) -> Effect {
  ToViewers(targeting_news(entry))
}

/// The news of 0x908 naming the entry as the target, with its threat.
fn targeting_news(entry: Threat) -> News {
  client_connection.Targeting(
    target_unit_id: entry.unit_id,
    threat: whole(entry.amount),
  )
}

/// The news of 0x90a giving another entry's threat.
fn threat_news(entry: Threat) -> News {
  client_connection.Threat(
    other_unit_id: entry.unit_id,
    threat: whole(entry.amount),
  )
}

/// The top entry of a threat list: the most threat, the lowest connection on a tie.
fn top_of(entries: Dict(ConnectionId, Threat)) -> #(ConnectionId, Threat) {
  let assert [top, ..] =
    dict.to_list(entries)
    |> list.sort(fn(first, second) {
      float.compare({ second.1 }.amount, { first.1 }.amount)
      |> order.break_tie(map.compare_connections(
        first: first.0,
        second: second.0,
      ))
    })
    as "a fight's threat list is never empty"
  top
}

/// A player that is no longer a foe of the creature leaves the near players and the
/// threat list, and is told `Released`: a viewer that no longer sees the creature
/// (`Unwatched`), or a player that died (`PlayerDied`). The last one leashes the
/// creature, and a new top entry is named its target.
fn fell(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  released(
    state: State(..state, near: set.delete(state.near, by)),
    fighter:,
    by:,
    now_ms:,
  )
}

/// The player of `by` leaves the threat list and is told `Released`: with no one
/// left the creature leashes, which tells it with the rest of the leash, else its
/// entry is erased (0x90a 0) and a new top entry is named its target (0x908). A
/// player no longer on the list (its `Unwatched` came during the round) was
/// released then.
fn released(
  state state: State,
  fighter fighter: Fighter,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let entry = case state.status {
    Fighting(threat: entries, ..) ->
      dict.get(entries, by) |> result.map(fn(entry) { #(entries, entry) })
    Resting | Returning(..) -> Error(Nil)
  }
  case entry {
    Error(Nil) -> #(state, [])
    Ok(#(entries, entry)) -> {
      let erased = ToViewers(threat_news(Threat(..entry, amount: 0.0)))
      let entries = dict.delete(entries, by)
      case dict.is_empty(entries) {
        True -> leash(state:, fighter:, now_ms:)
        False -> {
          let told =
            ToPlayer(
              to: by,
              stay: entry.stay,
              told: Released(unit_id: fighter.unit_id),
            )
          let #(state, named, chased) =
            retargeted(state:, fighter:, entries:, now_ms:)
          #(state, list.flatten([[erased], named, [told], chased]))
        }
      }
    }
  }
}

/// A fight left with these entries: its top entry is the target, named in 0x908
/// when it changed, and the creature chases it; the naming and the chase are given
/// apart, so the release goes between them.
fn retargeted(
  state state: State,
  fighter fighter: Fighter,
  entries entries: Dict(ConnectionId, Threat),
  now_ms now_ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  let assert Fighting(target:, ..) as fighting = state.status
    as "a fight is retargeted only while Fighting"
  let #(top, top_entry) = top_of(entries)
  let state =
    State(..state, status: Fighting(..fighting, threat: entries, target: top))
  let named = case top == target {
    True -> []
    False -> [targeting(top_entry)]
  }
  let #(state, turned) = faced(state:, fighter:, now_ms:)
  let #(state, chased) = chase(state:, fighter:, now_ms:)
  #(state, list.append(named, turned), chased)
}

/// The attack tick: with the target in reach and no round open the creature
/// strikes, or opens its charge when its attack has a cast time; out of reach at the
/// leash circle it leashes; else it chases. The next tick starts unless it leashed or
/// opened a charge, whose round's close starts it. A creature whose states refuse its
/// attack starts none (`attacks`), and one whose states stop its run starts no path
/// (`chase`) and does not leash while they hold: out of reach at its circle it only
/// starts the next tick, and the first tick after they end leashes or chases. A creature
/// that cannot move, or whose run speed is not above 0 (`creature_path.runs`), is at its
/// leash when its target is beyond the leash range from home, since it never walks to
/// the circle (a server's choice for the second: the client holds no creature rule). One
/// that cannot run and stands away from home holds like one held by a state (also a
/// server's choice): leashing would leave it Returning with no walk, until its speed is
/// above 0 again (`SpeedChanged`).
fn ticked(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Fighting(target:, round:, ..) as fighting = state.status
    as "a tick is taken only while Fighting"
  use <- bool.lazy_guard(when: option.is_some(state.flight), return: fn() {
    next_tick(state:, fighter:, effects: [])
  })
  let state = State(..state, status: Fighting(..fighting, hold: None))
  let here = creature_path.place_at(path: state.path, now_ms:)
  case dict.get(state.sightings, target) {
    Error(Nil) -> next_tick(state:, fighter:, effects: [])
    Ok(sighting) -> {
      let distance = creature_path.distance(from: here, to: sighting.place)
      let attack = chosen(state:, fighter:, now_ms:)
      let in_reach = distance <=. reach_of(attack:, target: sighting)
      let in_attack_reach =
        distance <=. reach_of(attack: fighter.attack, target: sighting)
      let cannot_run = !creature_path.runs(speed: fighter.attack.run_speed)
      let at_circle = case cannot_move(fighter:) || cannot_run {
        True ->
          creature_path.distance(from: fighter.home, to: sighting.place)
          >. fighter.numbers.leash_range
        False ->
          creature_path.distance(from: here, to: fighter.home)
          >=. fighter.numbers.leash_range -. circle_tolerance
      }
      // A creature that cannot run and stands away from home would leash into a walk
      // it cannot start, so it holds as a held one does.
      let held = fighter.still || { cannot_run && here != fighter.home }
      case in_reach, round, at_circle {
        True, None, _ ->
          attacks(state:, fighter:, attack:, target:, sighting:, here:, now_ms:)
        True, Some(..), _ -> next_tick(state:, fighter:, effects: [])
        False, _, True if held && !in_attack_reach ->
          next_tick(state:, fighter:, effects: [])
        False, _, True if !in_attack_reach -> leash(state:, fighter:, now_ms:)
        False, _, _ -> {
          let #(state, chased) = chase(state:, fighter:, now_ms:)
          next_tick(state:, fighter:, effects: chased)
        }
      }
    }
  }
}

/// The attack on a target in reach with no round open: the charge when the attack has
/// a cast time, else the strike, and the next tick for a strike. A charge starts only
/// while the creature holds no state, and a strike while none refuses the attack
/// (`Fighter`); otherwise the tick only starts the next.
fn attacks(
  state state: State,
  fighter fighter: Fighter,
  attack attack: Attack,
  target target: ConnectionId,
  sighting sighting: Sighting,
  here here: Place,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case attack.cast {
    Charged(..) if fighter.holds_a_state ->
      next_tick(state:, fighter:, effects: [])
    Instant if fighter.attack_refused -> next_tick(state:, fighter:, effects: [])
    Charged(..) -> charges(state:, fighter:, attack:, sighting:, here:, now_ms:)
    Instant -> {
      let #(state, struck) =
        strikes(state:, fighter:, attack:, target:, sighting:, here:)
      next_tick(
        state: State(..state, autos_struck: state.autos_struck + 1),
        fighter:,
        effects: struck,
      )
    }
  }
}

/// Whether the creature never moves (`Fighter.can_move`).
fn cannot_move(fighter fighter: Fighter) -> Bool {
  !fighter.can_move
}

/// How near the leash circle a creature counts as at it: a path clipped at the
/// circle ends on it, give or take a float's rounding.
const circle_tolerance = 0.01

fn next_tick(
  state state: State,
  fighter fighter: Fighter,
  effects effects: List(Effect),
) -> #(State, List(Effect)) {
  tick_after(
    state:,
    effects:,
    after_ms: fighter.interval_ms,
    hold_until_ms: None,
  )
}

/// The one place an attack tick is started: a new generation, so the tick before it is
/// stale, started after `after_ms`. With `hold_until_ms` the creature stands in a hold
/// until that tick (`Hold`).
fn tick_after(
  state state: State,
  effects effects: List(Effect),
  after_ms after_ms: Int,
  hold_until_ms hold_until_ms: Option(Int),
) -> #(State, List(Effect)) {
  let assert Fighting(..) as fighting = state.status
    as "a tick is started only while Fighting"
  let #(state, tick) = generation(state)
  let hold =
    option.map(hold_until_ms, fn(until_ms) { Hold(ends: tick, until_ms:) })
  #(
    State(..state, status: Fighting(..fighting, tick:, hold:)),
    list.append(effects, [
      StartTimer(timer: AttackTick(tick), after_ms:),
    ]),
  )
}

/// The creature casts its attack on its target: 0x7ff to its viewers, the strike to
/// the target's connection, and the round's deadline.
fn strikes(
  state state: State,
  fighter fighter: Fighter,
  attack attack: Attack,
  target target: ConnectionId,
  sighting sighting: Sighting,
  here here: Place,
) -> #(State, List(Effect)) {
  let cast_id =
    cast_state.mint(
      unit_id: fighter.unit_id,
      number: state.next_cast,
      live: fighter.guard_casts,
    )
  let key =
    strike_tell.Key(
      cast_id:,
      occasion: strike_tell.AtGo(phase: 0),
      unit_id: sighting.unit_id,
    )
  let #(state, deadline) = generation(state)
  let assert Fighting(..) as fighting = state.status
    as "a creature strikes only while Fighting"
  let spell4_id = attack.spell4_id
  // An attack with no cast time has no telegraph: the importer writes no telegraphed instant.
  let start =
    Start(
      aim: area.pose_of(place: here),
      target: None,
      opening: telegraph_entries.none,
    )
  let entry =
    GoRound(
      phase: 0,
      awaiting: pending(deadline:, keys: dict.from_list([#(key, target)])),
      struck: [],
    )
  #(
    State(
      ..state,
      next_cast: cast_state.number_of(cast_id:) + 1,
      status: Fighting(
        ..fighting,
        round: Some(
          Round(cast_id:, spell4_id:, start:, stage: Striking, go_rounds: [
            entry,
          ]),
        ),
      ),
    ),
    [
      ToViewers(
        client_connection.CastStarted(start: cast_frame.creature_started(
          cast_id:,
          spell4_id: spell4_id.value,
          caster_unit_id: fighter.unit_id,
          target_unit_id: sighting.unit_id,
          place: here,
          opening: start.opening,
        )),
      ),
      ToPlayer(
        to: target,
        stay: sighting.stay,
        told: Attacks(
          tell: strike_tell.Strike(
            key:,
            from: fighter.address,
            striker: CreatureStriker(unit_id: fighter.unit_id, spell4_id:),
            offence: attack.offence,
            controls: [],
            gates: [],
          ),
        ),
      ),
      StartTimer(
        timer: StrikeDeadline(deadline),
        after_ms: strike_tell.deadline_ms,
      ),
    ],
  )
}

/// A fighter's answer to a strike of the open round: its go names what landed, and a
/// fighter the strike killed, or found dead, is released and leaves the near players, so
/// the creature's home timer or corpse timer does not aggro the body. An entry is written
/// when its last answer is in and every entry before it is written; the round closes with
/// its last entry, and a charging creature then starts its next attack tick.
fn answered_strike(
  state state: State,
  fighter fighter: Fighter,
  answered answered: Answered,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Fighting(round: Some(round), ..) ->
      case answered_entry(round:, key: answered.key) {
        Ok(#(entry, target)) ->
          answer_taken(
            state:,
            fighter:,
            round:,
            entry:,
            target:,
            answered:,
            now_ms:,
          )
        Error(Nil) -> #(state, [])
      }
    Fighting(..) | Resting | Returning(..) -> #(state, [])
  }
}

/// The entry of `round` that awaits the answer of `key`, with the connection it went to.
fn answered_entry(
  round round: Round,
  key key: Key,
) -> Result(#(GoRound, ConnectionId), Nil) {
  list.find_map(round.go_rounds, fn(entry) {
    case entry.awaiting {
      Pending(keys:, ..) ->
        dict.get(keys, key) |> result.map(fn(target) { #(entry, target) })
      Complete -> Error(Nil)
    }
  })
}

/// The entry of `round` whose `StrikeDeadline` is of `generation` and still awaits an answer.
fn deadline_entry(
  round round: Round,
  generation generation: Int,
) -> Result(GoRound, Nil) {
  list.find(round.go_rounds, fn(entry) {
    case entry.awaiting {
      Pending(deadline:, ..) -> deadline == generation
      Complete -> False
    }
  })
}

/// The round with `entry` in place of its go's.
fn with_entry(round round: Round, entry entry: GoRound) -> Round {
  Round(
    ..round,
    go_rounds: list.map(round.go_rounds, fn(listed) {
      case listed.phase == entry.phase {
        True -> entry
        False -> listed
      }
    }),
  )
}

/// The answer of the fighter of `target`, to the strike of `entry`: it joins the go, the
/// entry's deadline is cancelled when no answer is awaited, and a fighter the answer ends is
/// released.
fn answer_taken(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  entry entry: GoRound,
  target target: ConnectionId,
  answered answered: Answered,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(struck, ends_target, target_dead) = answer_of(answered:)
  let was_awaiting = entry.awaiting
  let entry =
    GoRound(
      ..entry,
      awaiting: without_answer(awaiting: entry.awaiting, key: answered.key),
      struck: list.append(entry.struck, struck),
    )
  let round = with_entry(round:, entry:)
  let cancelled = case entry.awaiting, was_awaiting {
    Complete, Pending(deadline:, ..) -> [
      CancelTimer(timer: StrikeDeadline(deadline)),
    ]
    Complete, Complete | Pending(..), _ -> []
  }
  let #(state, written, ticking) = settled(state:, fighter:, round:, now_ms:)
  // The next tick and its hold are set before the target's entry ends, so the retarget that
  // follows a kill finds the hold and starts no path (`chase`). A leash after it leaves
  // `Fighting`, which drops the hold with the fight, and its tick is not started.
  let #(state, ended) = case ends_target, target_dead {
    False, _ -> #(state, [])
    True, True -> fell(state:, fighter:, by: target, now_ms:)
    True, False -> released(state:, fighter:, by: target, now_ms:)
  }
  let ticking = case state.status {
    Fighting(..) -> ticking
    Resting | Returning(..) -> []
  }
  #(state, list.flatten([cancelled, written, ended, ticking]))
}

/// The state with `round` as its open round.
fn with_round(state state: State, round round: Round) -> State {
  let assert Fighting(..) as fighting = state.status
    as "a round is held only while Fighting"
  State(..state, status: Fighting(..fighting, round: Some(round)))
}

/// What the target's answer was: what struck for the round's go, whether the entry
/// ends (a kill or a refusal), and whether the target is dead (a kill or a `Dead`
/// refusal).
fn answer_of(
  answered answered: Answered,
) -> #(List(cast_state.Struck), Bool, Bool) {
  let unit_id = answered.key.unit_id
  case answered.outcome {
    strike_tell.Landed(descriptions:, ..) -> {
      let killed =
        list.any(descriptions, fn(description) {
          description.damage.killed == 1
        })
      #(
        [
          cast_state.Hit(
            unit_id:,
            unit: cast_state.HitPlayer,
            descriptions:,
            controls: [],
            armor_removed: 0,
            ticking: [],
          ),
        ],
        killed,
        killed,
      )
    }
    strike_tell.Immune(..) ->
      panic as "a player is never guarded: only a creature answers Immune"
    strike_tell.Deflected(..) -> #(
      [cast_state.Deflected(unit_id:)],
      False,
      False,
    )
    strike_tell.Refused(why: strike_tell.Dead) -> #([], True, True)
    strike_tell.Refused(why: strike_tell.Despawned) -> #([], True, True)
    strike_tell.Refused(why: strike_tell.Returning) -> #([], True, False)
  }
}

/// Writes what is ready of the round `round`, which the state then holds: each complete entry
/// at the front of its list, in go order, is written (0x7f4 naming the units struck, the 0x7fb
/// any deflect); an entry waits for every entry before it. When every go is reached and the
/// last entry is written, the cast finishes (0x7fe) and the round is closed. The effects of
/// the writing, then the next attack tick's (the hold, else the interval: `ticking_again`),
/// which only a closed round has.
fn settled(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  now_ms now_ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  let here = creature_path.place_at(path: state.path, now_ms:)
  let #(ready, waiting) =
    list.split_while(round.go_rounds, fn(entry) { entry.awaiting == Complete })
  let written = list.flat_map(ready, written_entry(round:, entry: _, here:))
  case round.stage, waiting {
    Striking, [] -> {
      let assert Fighting(..) as fighting = state.status
        as "a round closes only while Fighting"
      let state = State(..state, status: Fighting(..fighting, round: None))
      let #(state, ticking) = ticking_again(state:, fighter:, round:, now_ms:)
      #(
        state,
        list.append(written, [
          ToViewers(client_connection.CastFinished(cast_id: round.cast_id)),
        ]),
        ticking,
      )
    }
    Striking, [_, ..] | Charging(..), _ -> #(
      with_round(state:, round: Round(..round, go_rounds: waiting)),
      written,
      [],
    )
  }
}

/// The go of `entry` written to the viewers: its 0x7f4 naming the units struck, and the
/// 0x7fb when one was deflected.
fn written_entry(
  round round: Round,
  entry entry: GoRound,
  here here: Place,
) -> List(Effect) {
  let cast_id = round.cast_id
  let missed = case cast_frame.creature_missed(cast_id:, struck: entry.struck) {
    Some(missed) -> [ToViewers(client_connection.CastMissed(missed:))]
    None -> []
  }
  [
    ToViewers(
      client_connection.CastWent(go: cast_frame.creature_went(
        cast_id:,
        phase: entry.phase,
        place: here,
        struck: entry.struck,
      )),
    ),
    ..missed
  ]
}

/// The creature opens a charge on its target: it turns to face it (`turned_to_face`), round
/// `Charging` at go 0 with a `CastEnds` generation, the 0x7ff of the attack's spell to the
/// viewers, and `StartTimer(CastEnds)` for the first go. A special's cooldown starts here, at
/// the cast's start. The attack tick's generation moves on to one no timer carries, so the tick
/// that opened the charge, or a later copy of it, does nothing, and no attack tick starts: the
/// round's close starts it.
fn charges(
  state state: State,
  fighter fighter: Fighter,
  attack attack: Attack,
  sighting sighting: Sighting,
  here here: Place,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Charged(gos: [first, ..], draws:, ..) = attack.cast
    as "a charge has a go"
  let #(state, turned) =
    turned_to_face(state:, fighter:, target: sighting, here:, now_ms:)
  let here = creature_path.place_at(path: state.path, now_ms:)
  let cast_id =
    cast_state.mint(
      unit_id: fighter.unit_id,
      number: state.next_cast,
      live: fighter.guard_casts,
    )
  let #(state, ends) = generation(state)
  let #(state, tick) = generation(state)
  let assert Fighting(target:, ..) as fighting = state.status
    as "a creature charges only while Fighting"
  let spell4_id = attack.spell4_id
  let aim = aim_of(state:, fighter:, target:, here:)
  let cast_target =
    CastTarget(
      connection: target,
      placed: telegraph_entries.Placed(
        unit_id: sighting.unit_id,
        place: sighting.place,
      ),
    )
  let opening =
    telegraph_entries.opening_of(
      draws:,
      caster: telegraph_entries.Placed(
        unit_id: fighter.unit_id,
        place: start_place.turned(
          place: here,
          facing: start_place.Facing(..start_place.facing(here), yaw: aim.yaw),
        ),
      ),
      target: Some(cast_target.placed),
    )
  let round =
    Round(
      cast_id:,
      spell4_id:,
      start: Start(aim:, target: Some(cast_target), opening:),
      stage: Charging(ends:, go: 0, started_ms: now_ms),
      go_rounds: [],
    )
  let ready_at = case special_named(fighter:, spell4_id:) {
    Ok(special) ->
      dict.insert(state.ready_at, spell4_id.value, now_ms + special.cooldown_ms)
    Error(Nil) -> state.ready_at
  }
  #(
    State(
      ..state,
      next_cast: cast_state.number_of(cast_id:) + 1,
      ready_at:,
      status: Fighting(..fighting, round: Some(round), tick:),
    ),
    list.flatten([
      turned,
      [
        ToViewers(
          client_connection.CastStarted(start: cast_frame.creature_started(
            cast_id:,
            spell4_id: spell4_id.value,
            caster_unit_id: fighter.unit_id,
            target_unit_id: sighting.unit_id,
            place: here,
            opening:,
          )),
        ),
        StartTimer(
          timer: CastEnds(ends),
          after_ms: due_in(started_ms: now_ms, at_ms: first.at_ms, now_ms:),
        ),
      ],
    ]),
  )
}

/// Milliseconds from `now_ms` until a go counted `at_ms` from the cast's start at `started_ms`
/// is due, never below 0: a timer handled late does not push the gos after it.
fn due_in(
  started_ms started_ms: Int,
  at_ms at_ms: Int,
  now_ms now_ms: Int,
) -> Int {
  int.max(0, started_ms + at_ms - now_ms)
}

/// A go of the open charge is due (`CastEnds` of the round's generation, C alive and Fighting).
/// The go joins the round's entries in go order (`GoRound`). A go that strikes selects the
/// fighters on the threat list inside the shapes of its own strike (`game/spell_area`,
/// `game/area` select) and tells each to take the blows that name the go (`strikes_sent`); a go
/// with no strike, or whose strike finds no one inside, or no centre (`centre_of`: a row on a
/// target that is no longer a viewer), is an empty entry, complete at once. The `CastEnds` of
/// the next go is armed, of a new generation, for what is left of its due time; after the last
/// go the round is `Striking`. Whatever is ready is then written (`settled`), so a go is
/// written only after every go before it, and the cast finishes after its last entry. No state is
/// held then: one that took hold between the gos broke the cast (`held`), and its `CastEnds` is
/// stale.
fn go_reached(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  viewers viewers: Dict(ConnectionId, Stay),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let attack = attack_named(fighter:, spell4_id: round.spell4_id)
  let assert Charged(gos:, ..) = attack.cast
    as "a charge is a round of a charged attack"
  let assert Charging(go:, started_ms:, ..) = round.stage
    as "a go is reached only by a charging round"
  let assert Ok(this) = list.first(list.drop(gos, go))
    as "the round's go is one of the attack's gos"
  let #(state, entry, struck) = case this.strike {
    Some(strike) ->
      go_strikes(
        state:,
        fighter:,
        round:,
        attack:,
        strike:,
        go:,
        viewers:,
        now_ms:,
      )
    None -> #(state, GoRound(phase: go, awaiting: Complete, struck: []), [])
  }
  let #(state, stage, armed) = case list.first(list.drop(gos, go + 1)) {
    Ok(next) -> {
      let #(state, ends) = generation(state)
      #(state, Charging(ends:, go: go + 1, started_ms:), [
        StartTimer(
          timer: CastEnds(ends),
          after_ms: due_in(started_ms:, at_ms: next.at_ms, now_ms:),
        ),
      ])
    }
    Error(Nil) -> #(state, Striking, [])
  }
  let round =
    Round(..round, stage:, go_rounds: list.append(round.go_rounds, [entry]))
  let #(state, written, ticking) = settled(state:, fighter:, round:, now_ms:)
  #(state, list.flatten([struck, armed, written, ticking]))
}

/// The go that strikes: the fighters inside the shapes of its strike are told to take the
/// attack. The entry of the go and the strikes sent; an entry with nobody awaited when no one
/// is inside.
fn go_strikes(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  attack attack: Attack,
  strike strike: creature_life.GoStrike,
  go go: Int,
  viewers viewers: Dict(ConnectionId, Stay),
  now_ms now_ms: Int,
) -> #(State, GoRound, List(Effect)) {
  let assert Fighting(threat:, target:, ..) = state.status
    as "a go is reached only while Fighting"
  let assert Charged(area: row, anchor:, aims_at_target:, ..) = attack.cast
    as "a charge is a round of a charged attack"
  let here = creature_path.place_at(path: state.path, now_ms:)
  let centre =
    centre_of(
      state:,
      fighter:,
      round:,
      anchor:,
      aims_at_target:,
      target:,
      viewers:,
      here:,
    )
  let struck = case centre {
    Some(centre) ->
      inside_rectangle(
        state:,
        row:,
        inside: strike.inside,
        centre:,
        fighters: map.sorted_by_connection(threat),
        seed: round.cast_id,
      )
    None -> []
  }
  case struck {
    [] -> #(state, GoRound(phase: go, awaiting: Complete, struck: []), [])
    [_, ..] ->
      strikes_sent(state:, fighter:, round:, attack:, strike:, go:, struck:)
  }
}

/// Each fighter inside the area gets the attack's strike for the go, keyed `AtGo(go)`, with
/// the blows that name the go (`creature_life.offence_of_go`), and the go's deadline starts.
/// The go's entry awaits each of them.
fn strikes_sent(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  attack attack: Attack,
  strike strike: creature_life.GoStrike,
  go go: Int,
  struck struck: List(#(ConnectionId, Threat, Sighting)),
) -> #(State, GoRound, List(Effect)) {
  let #(state, deadline) = generation(state)
  let keyed =
    list.map(struck, fn(found) {
      let #(connection, threat, sighting) = found
      #(
        connection,
        threat,
        strike_tell.Key(
          cast_id: round.cast_id,
          occasion: strike_tell.AtGo(phase: go),
          unit_id: sighting.unit_id,
        ),
      )
    })
  let entry =
    GoRound(
      phase: go,
      awaiting: pending(
        deadline:,
        keys: dict.from_list(list.map(keyed, fn(found) { #(found.2, found.0) })),
      ),
      struck: [],
    )
  let offence = creature_life.offence_of_go(attack:, strike:)
  let strikes =
    list.map(keyed, fn(found) {
      ToPlayer(
        to: found.0,
        stay: { found.1 }.stay,
        told: Attacks(
          tell: strike_tell.Strike(
            key: found.2,
            from: fighter.address,
            striker: CreatureStriker(
              unit_id: fighter.unit_id,
              spell4_id: attack.spell4_id,
            ),
            offence:,
            controls: [],
            gates: [],
          ),
        ),
      )
    })
  #(
    state,
    entry,
    list.append(strikes, [
      StartTimer(
        timer: StrikeDeadline(deadline),
        after_ms: strike_tell.deadline_ms,
      ),
    ]),
  )
}

/// Where the creature points now: the creature that cannot move is a turret, which turns
/// its aim toward its 0x908 target by itself, so it points from its place along the
/// bearing to that player, by the player's newest sighting (`area.bearing` with yaw 0 is the
/// yaw that faces the target, `movement_command.kind_14.facing`), or along its own facing when
/// it has no sighting of it. A creature that can move is turned only by the server
/// (`creature.facing`), and `turned_to_face` turned it when the cast began, so it points
/// along its own facing, as the client draws a telegraph on the caster by the caster's yaw.
fn aim_of(
  state state: State,
  fighter fighter: Fighter,
  target target: ConnectionId,
  here here: Place,
) -> area.Pose {
  let body = area.pose_of(place: turned_place(state:, place: here))
  case cannot_move(fighter:), dict.get(state.sightings, target) {
    True, Ok(sighting) ->
      area.Pose(
        ..body,
        yaw: area.bearing(
          from: body.at,
          target: area.point_of(place: sighting.place),
          yaw: 0.0,
        ),
      )
    True, Error(Nil) | False, _ -> body
  }
}

/// Where the strike go's area is centred, which is where the client draws it, or none when
/// the picture is gone and nobody is struck. A row the client drew at the 0x7ff's entries
/// (`FixedAtCaster`, `FixedAtTarget`) is centred on the pose the entry holds, the creature's
/// or the cast target's at the cast's start, so a creature that was thrown, a turret whose
/// target walked round it or a target that stepped out still strikes the picture. A row the
/// client draws on the caster each frame (`FollowsCaster`) is centred where the creature
/// points now (`aim_of`), except that a creature that cannot move holds the aim it had at the
/// start unless the spell's aim follows its 0x908 target (`0x14046cdc0.turret_cast_aim`). A
/// row the client draws on the cast's target each frame (`FollowsTarget`) is centred on the
/// target's newest sighting, with its facing.
///
/// A row on the cast's target, following or fixed, is bound to the target's unit: the client
/// drops a telegraph when it cannot find that unit in its world (`0x14054b1b0.unit_gone`,
/// which holds for a server-placed row too), not when the unit leaves the fight. So the row is struck while the target is a viewer, a target
/// that died or left the threat list still being in the world, and nobody is struck once
/// the target is no longer a viewer (`Unwatched`: it left, logged out, camped or was
/// despawned).
fn centre_of(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  anchor anchor: area.Anchor,
  aims_at_target aims_at_target: Bool,
  target target: ConnectionId,
  viewers viewers: Dict(ConnectionId, Stay),
  here here: Place,
) -> Option(area.Pose) {
  case anchor, cannot_move(fighter:) && !aims_at_target {
    area.FixedAtCaster, _ | area.FollowsCaster, True -> Some(round.start.aim)
    area.FollowsCaster, False -> Some(aim_of(state:, fighter:, target:, here:))
    area.FixedAtTarget, _ ->
      option.map(cast_target_in_world(round:, viewers:), fn(cast_target) {
        area.pose_of(place: cast_target.placed.place)
      })
    area.FollowsTarget, _ ->
      option.map(cast_target_in_world(round:, viewers:), fn(cast_target) {
        let assert Ok(sighting) =
          dict.get(state.sightings, cast_target.connection)
          as "a cast target was sighted, and a sighting is never dropped"
        area.pose_of(place: sighting.place)
      })
  }
}

/// The unit the round's charge is cast on while it is in the viewers' world, which is while
/// its connection is a viewer of the creature.
fn cast_target_in_world(
  round round: Round,
  viewers viewers: Dict(ConnectionId, Stay),
) -> Option(CastTarget) {
  let assert Some(cast_target) = round.start.target
    as "a charge is cast on a target"
  case dict.has_key(viewers, cast_target.connection) {
    True -> Some(cast_target)
    False -> None
  }
}

/// The fighters of the threat list, by their newest sightings, that the attack's area
/// selects around the pose `centre`, the unit the area is placed on and its facing, in the
/// area row's order and at most its target count; a Random order is by `seed`, the round's
/// cast id, so the same round strikes the same fighter.
fn inside_rectangle(
  state state: State,
  row row: Row,
  inside inside: Inside,
  centre centre: area.Pose,
  fighters fighters: List(#(ConnectionId, Threat)),
  seed seed: Int,
) -> List(#(ConnectionId, Threat, Sighting)) {
  let seen =
    list.filter_map(fighters, fn(entry) {
      dict.get(state.sightings, entry.0)
      |> result.map(fn(sighting) { #(entry.0, entry.1, sighting) })
    })
  area.select_ordered(
    candidates: list.map(seen, fn(found) {
      area.Candidate(
        unit_id: { found.2 }.unit_id,
        at: area.point_of(place: { found.2 }.place),
        hit_radius: { found.2 }.hit_radius,
      )
    }),
    centre:,
    row:,
    inside:,
    seed:,
  )
  |> list.filter_map(fn(unit_id) {
    list.find(seen, fn(found) { { found.2 }.unit_id == unit_id })
  })
}

/// The one starter of the attack tick after a round of a charged attack: when the round of
/// `round` closes and the creature still fights, the next tick starts after the attack's hold
/// when it has one (`Charged.hold_ms`, standing in the `Hold` until the tick), else after the
/// attack interval (`next_tick`). The attack tick of an attack with no cast time starts at its
/// strike (`attacks`), and a creature that left the fight has none, so no round has two ticks.
/// It reads the round's own attack (`attack_named`), not `fighter.attack`: an instant attack
/// and a charged special can alternate.
fn ticking_again(
  state state: State,
  fighter fighter: Fighter,
  round round: Round,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status, attack_named(fighter:, spell4_id: round.spell4_id).cast {
    Fighting(..), Charged(hold_ms:, ..) if hold_ms > 0 ->
      tick_after(
        state:,
        effects: [],
        after_ms: hold_ms,
        hold_until_ms: Some(now_ms + hold_ms),
      )
    Fighting(..), Charged(..) -> next_tick(state:, fighter:, effects: [])
    Fighting(..), Instant | Resting, _ | Returning(..), _ -> #(state, [])
  }
}

/// The attack of the spell `spell4_id`: one of the fighter's auto-attacks, or the special that
/// casts it. A round names its spell by this id, so each go works its strike out from the
/// fighter as it is then.
fn attack_named(
  fighter fighter: Fighter,
  spell4_id spell4_id: Spell4Id,
) -> Attack {
  case
    list.find([fighter.attack, ..fighter.alternates], fn(candidate) {
      candidate.spell4_id == spell4_id
    })
  {
    Ok(found) -> found
    Error(Nil) ->
      case special_named(fighter:, spell4_id:) {
        Ok(special) -> special.attack
        Error(Nil) ->
          panic as "a round names one of the fighter's auto-attacks or specials"
      }
  }
}

/// The special of the fighter that casts the spell `spell4_id`.
fn special_named(
  fighter fighter: Fighter,
  spell4_id spell4_id: Spell4Id,
) -> Result(Special, Nil) {
  list.find(fighter.specials, fn(special) {
    special.attack.spell4_id == spell4_id
  })
}

/// The attack the creature goes for at `now_ms`: the first of `fighter.specials` whose `ready_at`
/// has passed (absent is ready); else the next auto-attack (`next_auto`). It is the next
/// auto-attack whenever the creature `holds_a_state` (a charge starts only while none is held).
/// The target's distance does not choose: a ready special whose reach the target is beyond is
/// gone for, so `ticked` and `chase` close to the special's reach even where the attack already
/// reaches, and to an alternate's reach when it is the next; the leash keeps the lead's reach.
fn chosen(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> Attack {
  use <- bool.guard(
    when: fighter.holds_a_state,
    return: next_auto(state:, fighter:),
  )
  let ready =
    list.find(fighter.specials, fn(special) {
      case dict.get(state.ready_at, special.attack.spell4_id.value) {
        Ok(ready_at) -> now_ms >= ready_at
        Error(Nil) -> True
      }
    })
  case ready {
    Ok(special) -> special.attack
    Error(Nil) -> next_auto(state:, fighter:)
  }
}

/// The auto-attack whose turn it is: `fighter.attack` and `fighter.alternates` in order, at
/// the remainder of the auto-attacks struck this fight over their number. A special cast or
/// an attack a state refused does not move it.
fn next_auto(state state: State, fighter fighter: Fighter) -> Attack {
  let autos = [fighter.attack, ..fighter.alternates]
  let assert Ok(attack) =
    autos
    |> list.drop(state.autos_struck % list.length(autos))
    |> list.first
    as "the remainder is below the number of auto-attacks"
  attack
}

/// The creature that can move turns to face its target before the 0x7ff of a charge, and
/// stands still through the cast and the hold (`casting_or_holding`): one `CreatureMoved` of a
/// one-point timed path at its place now, turned along the bearing to the target
/// (`movement_command.kind_14`), which also stops a path it was running. The client never
/// turns a creature by itself (`creature.facing`), so the facing it holds when the 0x7ff
/// arrives is the yaw of the entries the 0x7ff carries (a cone with flag 0x4000 is drawn from
/// them and stays there, `0x14054b1b0.fixed_placement`) and the facing a cone drawn on the
/// caster each frame follows (`0x14054b1b0.follows_caster`); the strike go's area points along it
/// (`aim_of`). A creature that cannot move aims itself (a turret, `0x14046cdc0.turret_cast_aim`):
/// it sends none.
fn turned_to_face(
  state state: State,
  fighter fighter: Fighter,
  target target: Sighting,
  here here: Place,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(when: cannot_move(fighter:), return: #(state, []))
  let facing =
    creature_turn.toward(from: here, target: target.place, kept: state.facing)
  let path = Timed(first: #(now_ms, here), rest: [], turned_to: Some(facing))
  #(State(..state, path:, turn: Fixed(facing:)), [
    ToViewers(client_connection.CreatureMoved(path:)),
  ])
}

/// The round ends at the leash: every timer it waits on is cancelled, every entry reached is
/// written in go order with what was struck so far, then the cast finishes (0x7fe).
fn round_ended(
  state state: State,
  round round: Round,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let assert Fighting(..) as fighting = state.status
    as "a round ends only while Fighting"
  let here = creature_path.place_at(path: state.path, now_ms:)
  #(
    State(..state, status: Fighting(..fighting, round: None)),
    list.flatten([
      cancels_of(round:),
      written_all(round:, here:),
      [ToViewers(client_connection.CastFinished(cast_id: round.cast_id))],
    ]),
  )
}

/// Every entry the round reached and has not written, written in go order with what was
/// struck so far.
fn written_all(round round: Round, here here: Place) -> List(Effect) {
  list.flat_map(round.go_rounds, written_entry(round:, entry: _, here:))
}

/// The timers the round waits on, to cancel when it ends first: the pending `CastEnds`, then the
/// `StrikeDeadline` of each entry that still awaits an answer (a complete entry's is
/// cancelled or has fired).
fn cancels_of(round round: Round) -> List(Effect) {
  let pending = case round.stage {
    Charging(ends:, ..) -> [CancelTimer(timer: CastEnds(ends))]
    Striking -> []
  }
  let deadlines =
    list.filter_map(round.go_rounds, fn(entry) {
      case entry.awaiting {
        Pending(deadline:, ..) ->
          Ok(CancelTimer(timer: StrikeDeadline(deadline)))
        Complete -> Error(Nil)
      }
    })
  list.append(pending, deadlines)
}

/// The creature runs toward its target when the target is beyond reach of where its
/// path ends: a new path from where it is, stopping short of the target and clipped
/// at the leash circle, sent as 0x638. A creature whose states stop its run starts no path,
/// and one that cannot move never does.
fn chase(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: fighter.still
      || cannot_move(fighter:)
      || option.is_some(state.flight)
      || casting_or_holding(state:, fighter:),
    return: #(state, []),
  )
  let target = case state.status {
    Fighting(target:, ..) -> dict.get(state.sightings, target)
    Resting | Returning(..) -> Error(Nil)
  }
  case target {
    Error(Nil) -> #(state, [])
    Ok(target) -> {
      let #(state, turned) = faced(state:, fighter:, now_ms:)
      let #(state, chased) = chase_to(state:, fighter:, target:, now_ms:)
      #(state, list.append(turned, chased))
    }
  }
}

/// Whether the creature casts a charged attack or stands in the hold after it: while a charge is
/// open, while the strikes of a charged round are out (`Striking` of an attack with a cast time)
/// and in the hold, it starts no path. An instant attack's round does not stop it.
fn casting_or_holding(state state: State, fighter fighter: Fighter) -> Bool {
  case state.status {
    Fighting(round: Some(Round(stage: Charging(..), ..)), ..) -> True
    Fighting(round: Some(Round(stage: Striking, spell4_id:, ..)), ..) ->
      case attack_named(fighter:, spell4_id:).cast {
        Charged(..) -> True
        Instant -> False
      }
    Fighting(tick:, hold: Some(Hold(ends:, ..)), ..) -> ends == tick
    Fighting(..) | Resting | Returning(..) -> False
  }
}

/// How far the attack reaches, from the creature's centre to the target's: its `reach`, and
/// the target's hit radius too when the attack adds it (`Attack.adds_target_radius`).
fn reach_of(attack attack: Attack, target target: Sighting) -> Float {
  case attack.adds_target_radius {
    True -> attack.reach +. target.hit_radius
    False -> attack.reach
  }
}

/// The chase toward the target's place, unless it is in reach of where the path
/// ends: the reach of the attack the creature goes for (`chosen`), so a ready special is
/// closed in on to its own reach.
fn chase_to(
  state state: State,
  fighter fighter: Fighter,
  target target: Sighting,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let reach = reach_of(attack: chosen(state:, fighter:, now_ms:), target:)
  let target_place = target.place
  use <- bool.guard(
    when: creature_path.distance(
      from: creature_path.end(path: state.path),
      to: target_place,
    )
      <=. reach,
    return: #(state, []),
  )
  let path =
    creature_path.toward(
      from: creature_path.place_at(path: state.path, now_ms:),
      target: target_place,
      stop_short: fighter.numbers.chase_stop_fraction *. reach,
      circle: Circle(centre: fighter.home, radius: fighter.numbers.leash_range),
      speed: fighter.attack.run_speed,
      now_ms:,
    )
  #(
    State(..state, path:),
    list.append(
      path_news(was: state.path, now: path, now_ms:),
      chase_arrival(path:, now_ms:),
    ),
  )
}

/// The timer that tells the viewers the creature stands when a chase path is run, started
/// after the path's own time and after a cancel of the one a path it replaces started (the
/// creature's shell ends a process that starts a timer whose id runs). A path that is not run
/// starts none.
fn chase_arrival(path path: Path, now_ms now_ms: Int) -> List(Effect) {
  case path {
    Running(..) -> [
      CancelTimer(timer: ChaseArrival),
      StartTimer(
        timer: ChaseArrival,
        after_ms: creature_path.arrives_ms(path:, now_ms:) - now_ms,
      ),
    ]
    Standing(..) | Timed(..) -> []
  }
}

/// What the viewers are told of the creature's new path: a running path as 0x638 of
/// kind 4, and a standing one as 0x638 of kind 2 when the path they were last sent is a
/// run, which a client ends only by an explicit stop, or a flight still in the air. A
/// run's arrival timer sends its stop and sets the path standing, so a stand after that
/// says nothing, and a stand before it, though the run has ended, sends the stop.
fn path_news(was was: Path, now now: Path, now_ms now_ms: Int) -> List(Effect) {
  case now, was {
    Running(..), _ | Timed(..), _ -> [
      ToViewers(client_connection.CreatureMoved(path: now)),
    ]
    Standing(at:), Running(..) -> [
      ToViewers(client_connection.CreaturePlaced(place: at, at_ms: now_ms)),
    ]
    Standing(at:), Timed(..) ->
      case creature_path.arrives_ms(path: was, now_ms:) > now_ms {
        True -> [
          ToViewers(client_connection.CreaturePlaced(place: at, at_ms: now_ms)),
        ]
        False -> []
      }
    Standing(..), Standing(..) -> []
  }
}

/// The leash: every threat entry erased (0x90a 0), out of combat (0x89a 0), full
/// health (0x937), the path home (0x638), each threatened player told `Released`,
/// an open round closed, and the home timer started. The creature takes no strike
/// until it is home. A creature whose states stop its run leashes in everything but the walk
/// and its timer, which `ControlEnded` (or `SpeedChanged`, when the creature stands
/// away from home and its speed is above 0 again) starts, and so does a creature in
/// flight, whose walk starts at the landing (`FlightEnds`). A creature that cannot move
/// has no walk: it rests where it stands. A creature that stands at home with a speed
/// not above 0 walks no distance: its home timer is due at once.
fn leash(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(entries, round) = case state.status {
    Fighting(threat:, round:, ..) -> #(map.sorted_by_connection(threat), round)
    Resting | Returning(..) -> #([], None)
  }
  let #(state, closed) = case round {
    Some(round) -> round_ended(state:, round:, now_ms:)
    None -> #(state, [])
  }
  let #(state, walked) = case cannot_move(fighter:) {
    True -> #(State(..state, status: Resting), [])
    False -> {
      let #(state, home) = generation(state)
      let state = State(..state, status: Returning(home:))
      case fighter.still || option.is_some(state.flight) {
        True -> #(state, [])
        False -> walk_home(state:, fighter:, home:, now_ms:)
      }
    }
  }
  let #(state, turned) = faced(state:, fighter:, now_ms:)
  #(
    state,
    list.flatten([
      closed,
      list.map(entries, fn(entry) {
        ToViewers(client_connection.Threat(
          other_unit_id: { entry.1 }.unit_id,
          threat: 0,
        ))
      }),
      [
        ToViewers(client_connection.CombatState(in_combat: False)),
        RestoreHealth,
      ],
      turned,
      walked,
      list.map(entries, fn(entry) {
        ToPlayer(
          to: entry.0,
          stay: { entry.1 }.stay,
          told: Released(unit_id: fighter.unit_id),
        )
      }),
    ]),
  )
}

/// The path home from where the creature stands, sent as 0x638 (or placed, when the path
/// it ran ends in standing), with the home timer of generation `home` for its arrival.
/// The leash starts it, or `ControlEnded` does when a state held the creature at the
/// leash. A creature that does not run (`creature_path.runs`) and stands away from home
/// has no walk and no timer: it goes on walking home when its speed is above 0 again
/// (`SpeedChanged`).
fn walk_home(
  state state: State,
  fighter fighter: Fighter,
  home home: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let here = creature_path.place_at(path: state.path, now_ms:)
  let path =
    creature_path.straight(
      from: here,
      to: fighter.home,
      speed: fighter.attack.run_speed,
      now_ms:,
    )
  #(
    State(..state, path:),
    list.append(
      path_news(was: state.path, now: path, now_ms:),
      home_timer(path:, fighter:, home:, now_ms:),
    ),
  )
}

/// The timer of generation `home` for the walk's arrival, none for a creature that
/// stands away from home.
fn home_timer(
  path path: Path,
  fighter fighter: Fighter,
  home home: Int,
  now_ms now_ms: Int,
) -> List(Effect) {
  case path {
    Standing(at:) if at != fighter.home -> []
    Standing(..) | Running(..) | Timed(..) -> [
      StartTimer(
        timer: HomeArrival(home),
        after_ms: creature_path.arrives_ms(path:, now_ms:) - now_ms,
      ),
    ]
  }
}

/// The creature stands where it is: the path it runs stops, and its viewers are placed
/// there when they still run it (0x638 of kind 2). A death does it, and so does a state
/// that takes hold.
fn stand_still(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let in_flight = case state.path {
    Timed(..) -> creature_path.arrives_ms(path: state.path, now_ms:) > now_ms
    Running(..) | Standing(..) -> False
  }
  use <- bool.guard(when: in_flight, return: #(state, []))
  let here = creature_path.place_at(path: state.path, now_ms:)
  let placed = path_news(was: state.path, now: Standing(at: here), now_ms:)
  #(State(..state, path: Standing(at: here)), placed)
}

/// A crowd-control state takes hold: the creature stands where it is when its states stop
/// its run (`Fighter.still`), and runs on under the others. An open charge is
/// broken whatever the state: `CancelTimer(CastEnds)`, 0x7f9 of result 11 and 0x7fe of its cast, the round closed
/// and the next attack tick started, then `ChargeInterrupted` with the charge's cast id for the guard. A charge already
/// gone (the go is out, round `Striking`) is not broken, and a second state of the same round finds
/// none.
fn held(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(state, placed) = case fighter.still {
    True -> stand_still(state:, now_ms:)
    False -> #(state, [])
  }
  // A walk home that stops where it stands has no arrival: its timer is cancelled, and the
  // walk the end of the state starts is of a new generation (`resumed`).
  let stopped = case state.status, fighter.still {
    Returning(home:), True -> [CancelTimer(timer: HomeArrival(home))]
    Returning(..), False | Resting, _ | Fighting(..), _ -> []
  }
  let #(state, broken) = charge_broken(state:, fighter:, now_ms:)
  #(state, list.flatten([placed, stopped, broken]))
}

/// An open charge is broken, by a state or a throw: every timer it waits on is cancelled, the
/// entries it reached are written at once in go order with what was struck so far (the viewers'
/// connections forget a cast at its 0x7f9, so a go listed after it would be lost), then 0x7f9 of
/// result 11 and 0x7fe of its cast, the round closed, the next attack tick started and
/// `ChargeInterrupted`. A creature with no charge open, or whose last go is reached, is as it was.
fn charge_broken(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.status {
    Fighting(round: Some(Round(cast_id:, stage: Charging(..), ..) as round), ..) as fighting -> {
      let here = creature_path.place_at(path: state.path, now_ms:)
      let #(state, ticked) =
        next_tick(
          state: State(..state, status: Fighting(..fighting, round: None)),
          fighter:,
          effects: [],
        )
      #(
        state,
        list.flatten([
          cancels_of(round:),
          written_all(round:, here:),
          [ToViewers(client_connection.CastInterrupted(cast_id:))],
          ticked,
          [ChargeInterrupted(cast_id:)],
        ]),
      )
    }
    Fighting(..) | Resting | Returning(..) -> #(state, [])
  }
}

/// The creature died: its path frozen where it fell and its viewers placed there
/// when they still run it, out of combat (0x89a 0), each threatened player told
/// `Released`, and an open round's cast finished.
fn killed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let frozen = case cannot_move(fighter:), state.turn {
    True, _ | False, Fixed(..) | False, creature_turn.Home(..) -> state.turn
    False, creature_turn.Unit(..) | False, creature_turn.Point(..) ->
      Fixed(facing: facing_of(
        state:,
        here: creature_path.place_at(path: state.path, now_ms:),
      ))
  }
  let #(state, placed) = stand_still(state:, now_ms:)
  let #(state, landed) = flight_cleared(state:)
  let turned = case frozen == state.turn {
    True -> []
    False -> [
      ToViewers(client_connection.CreatureFaces(face: frozen, at_ms: now_ms)),
    ]
  }
  let state = State(..state, turn: frozen)
  let placed = list.flatten([landed, placed, turned])
  case state.status {
    Fighting(threat:, round:, ..) -> {
      let finished = case round {
        Some(round) ->
          list.append(cancels_of(round:), [
            ToViewers(client_connection.CastFinished(cast_id: round.cast_id)),
          ])
        None -> []
      }
      #(
        State(..state, status: Resting),
        list.flatten([
          placed,
          finished,
          [ToViewers(client_connection.CombatState(in_combat: False))],
          list.map(map.sorted_by_connection(threat), fn(entry) {
            ToPlayer(
              to: entry.0,
              stay: { entry.1 }.stay,
              told: Released(unit_id: fighter.unit_id),
            )
          }),
        ]),
      )
    }
    Resting | Returning(..) -> #(State(..state, status: Resting), placed)
  }
}

/// What stopped the creature's run is over (the last state that held it ended, or its
/// run speed is above 0 again): a Fighting creature chases its target again from where it
/// stands (its attack tick went on), and a Returning one starts the walk its leash could
/// not, with its home timer. A creature in flight waits for its landing.
fn resumed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(when: option.is_some(state.flight), return: #(state, []))
  case state.status {
    Fighting(..) -> {
      let #(state, turned) = faced(state:, fighter:, now_ms:)
      let #(state, chased) = chase(state:, fighter:, now_ms:)
      #(state, list.append(turned, chased))
    }
    Returning(home: old) -> {
      let #(state, home) = generation(state)
      let state = State(..state, status: Returning(home:))
      let #(state, turned) = faced(state:, fighter:, now_ms:)
      let #(state, walked) = walk_home(state:, fighter:, home:, now_ms:)
      #(state, [
        CancelTimer(timer: HomeArrival(old)),
        ..list.append(turned, walked)
      ])
    }
    Resting -> #(state, [])
  }
}

/// The creature's run speed changed: a path still being run at another speed is
/// run on from where the creature stands, to the same end, at the new speed, and sent
/// as 0x638. A walk home gets a new home timer for the new arrival, and its old one is
/// cancelled. A speed that is not above 0 (`creature_path.runs`) stops the run where the
/// creature stands, and a walk home then has no timer. A creature that stands starts
/// again from where it stands when its speed is above 0: a fight chases and a walk home
/// goes on, unless a state holds it (`ControlEnded` starts it then). A creature whose
/// path is run has nothing to replan.
fn speed_changed(
  state state: State,
  fighter fighter: Fighter,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let still_run = creature_path.arrives_ms(path: state.path, now_ms:) > now_ms
  case state.path {
    Running(speed:, ..) as was
      if still_run && speed != fighter.attack.run_speed
    -> {
      let path =
        creature_path.with_speed(
          path: was,
          speed: fighter.attack.run_speed,
          now_ms:,
        )
      let state = State(..state, path:)
      let moved = path_news(was:, now: path, now_ms:)
      case state.status {
        Returning(home: old) -> {
          let #(state, home) = generation(state)
          #(
            State(..state, status: Returning(home:)),
            list.flatten([
              [CancelTimer(timer: HomeArrival(old))],
              moved,
              home_timer(path:, fighter:, home:, now_ms:),
            ]),
          )
        }
        Fighting(..) -> #(
          state,
          list.append(moved, chase_arrival(path:, now_ms:)),
        )
        Resting -> #(state, moved)
      }
    }
    Standing(at:) -> {
      use <- bool.guard(
        when: fighter.still
          || !creature_path.runs(speed: fighter.attack.run_speed),
        return: #(state, []),
      )
      case state.status {
        Returning(..) if at == fighter.home -> #(state, [])
        Fighting(..) | Returning(..) | Resting ->
          resumed(state:, fighter:, now_ms:)
      }
    }
    Running(..) | Timed(..) -> #(state, [])
  }
}

fn generation(state: State) -> #(State, Int) {
  #(
    State(..state, next_generation: state.next_generation + 1),
    state.next_generation,
  )
}

/// A threat as the client's 32-bit field holds it: rounded half away from zero.
fn whole(threat: Float) -> Int {
  float.round(threat)
}

/// What a creature's fight does that the client's rules ask differently.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Creature fights",
      missing: "a viewer that arrives in the middle of a cast with several hits is sent the gos already written with no target, so it does not see the hits taken before it arrived",
    ),
    gap.Entry(
      area: "Creature fights",
      missing: "a strike's answer that arrives after a state broke the cast, or after the leash, is left out of that go's 0x7f4; the hit stands on the player",
    ),
    gap.Entry(
      area: "Creature fights",
      missing: "a viewer that arrives mid-cast on a target row whose client does not know the cast's target (it is not in the viewer's picture): the client draws no entry for it, while the creature's hit still lands; the turn a client-placed cone follows is the target's newest sighting, not the client's current yaw",
    ),
    gap.Entry(
      area: "Creature fights",
      missing: "a player who dies and chooses Wake Here within a second of the death, inside the ring of the creature that killed it, when the creature's killing answer arrives after the wake's approach: the creature does not aggro the player until it leaves the ring and enters it again",
    ),
  ]
}
