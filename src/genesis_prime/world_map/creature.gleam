//// One creature: the process that owns a creature's unit in one run of one map,
//// from the time a player first sees its spawn to the time it has gone unseen
//// for the idle stop. It tells its map the picture of its own unit for each player
//// who comes to see it and the news of it for those who do, and owns its health: it takes
//// the strikes a caster's connection tells it, decides what each does
//// (genesis_prime/world_map/creature_life) and tells its map the 0x937 and 0x88c of its
//// unit, the answer to the caster, and, at its corpse timer, the 0x355 of its removal and
//// that it expired. It sends nothing to a connection: the map relays what it tells to the
//// players it relates, so a player has one sender for each creature, and that sender's order.
//// Which players see it, when it starts and when it stops are the map's
//// (genesis_prime/world_map/map), and so is its next life: the creature that expired stops,
//// and the map starts another process under the same unit id and a new life number.
////
//// This is the rule of a service shell (genesis_prime/service/shell), started
//// by the creature supervisor (genesis_prime/world_map/creature_supervisor)
//// when its map's `StartCreature` effect is carried out, and found by its
//// `Creature` address in the registry (genesis_prime/world_map/creature_registry).
//// Its state, the players who see it, lives only in the process: a crash loses
//// it, and the map, which watches the creature, tells every player the unit is
//// `Gone`, starts the spawn again as another unit after the respawn time if a
//// player sees it then, with those players as its first viewers. In the diagrams
//// `Broadcast(news)` is one send to the map for every viewer, `Snapshot` a viewer's first
//// picture, and `Relay(c, payload)` a send to the player of connection c with its stay.
////
//// From the start to the end of a creature, and what the players in sight are
//// sent:
////
//// ```
//// map                     creature                                    map
////                         Started ─▶ Watch(map run)                   (the shell monitors the run)
////                                    for each first viewer c, g (CreatureStart.viewers):
////                                      Send(map, Snapshot(c, g, its first picture))
////                                    CreatureStart.ring, when the map's respawn carries one:
////                                      the fight takes RingAtStart: every ring player is
////                                      sighted and near, and one aggro starts the fight over
////                                      those who are viewers
//// Retire ───────────────▶ Stop                                        (no one sees it: the map sent every
////                                                                      viewer Unseen, 60 s ago or more)
//// the run's end (WatchEnded(run)) ─▶ Stop                             (the map is gone: so are its players)
////
//// A creature tells only its map, which relays to the players (genesis_prime/world_map/map):
////
//// ```
//// map                     creature                                    map
//// Seen(by: c, stay, g) ─▶ viewers + (c, stay, g); builds c's first picture from its state now
////                         (its 0x262, its guard's cast, each held unit state, the fight's arrival news;
////                          an empty burst when it is despawned)
////                         Send(map, Snapshot(unit, life, c, g, burst)) ─▶ relayed to c when (c, g) awaits it
//// Unseen(by: c, g) ─────▶ when (c, g) is the viewer held: viewers - c, its threat entry and its fight
////                         copy of c; no 0x355 (the map tells c); the fight's release of c:
////                         Send(map, Relay(unit, life, c, stay, Released)); an Unseen of another
////                         generation, or of a connection that is no viewer, changes nothing
//// a news of its unit ───▶ Send(map, Broadcast(unit, life, news)), once for all viewers
//// an answer, a credit, a fight tell ─▶ Send(map, Relay(unit, life, to, stay, payload))
//// ```
////
//// caster's connection c0
//// Strike(key, c0, striker, offence, controls, gates) ─▶ each gate checked against `prerequisite.of_creature`
////                                    (the blows and states of a row that did not pass are dropped, the ids that passed are answered in `gates_passed`),
////                                    then the hit rule on its health (genesis_prime/world_map/creature_life)
////                                    alive: Relay(c0, Struck(Landed | Deflected))   Broadcast(Health(h', dead))
////                                    landed: the fight takes StruckBy (genesis_prime/world_map/creature_fight)
////                                    killed: Broadcast(Died); StartServiceTimer(corpse, respawn_ms); the fight takes Killed
////                                            Relay(c0, KillCredit(unit, creature row, faction, level)), once, for the blow that killed it
////                                    dead:  Relay(c0, Struck(Refused(Dead)))
////                                    walking home: Relay(c0, Struck(Refused(Returning)))
//// Approached(c, unit, place, seq), Withdrew(c), PlayerDied(c) from the map,
//// TargetMoved(c, place, seq), StrikeAnswered(answered) from a connection,
//// the attack tick, the cast end of a charge, the strike deadline, the home timer ─▶ the fight (genesis_prime/world_map/creature_fight)
//// the corpse timer ─────▶ Broadcast(Removed) (a creature that was despawned: none, its removal went
////                         at the despawn), Send(map, Expired(unit, life)), Stop; the map starts the
////                         next life under the same unit id, at full health with properties from the
////                         bases and no source held
////                         told Retire while dead: Stop alone (no Expired: the map restarts a retiring spawn itself)
////
//// caster's connection c0, a property modifier of its spell
//// ModifierStarts(c0, source, m)
////                         dead: dropped
////                         else ─▶ apply(source, m) to its properties (genesis_prime/game/unit_properties)
////                                    Broadcast(PropertiesChanged(changed entries)) ─▶ writes 0x93a if shown
////                                    the rules take the new values: run speed, defence, offence,
////                                    maximum health, Interrupt Armor's maximum
//// ModifierEnds(source) ─────────▶ remove(source)          Broadcast(PropertiesChanged(changed entries))
//// CasterGone(c0) ───────────────▶ remove every source of c0, each as ModifierEnds does
////
//// caster's connection c0, a ForcedMove effect of its spell
//// Thrown(move, draws, reference)
////                         dead: dropped
////                         else ─▶ the fight takes Thrown (genesis_prime/world_map/creature_fight)
////                                    walking home or run speed 0: dropped
////                                    else Broadcast(News(0x638)), and the fight's `FlightEnds`
////                                    timer starts (`timer_id`), which stands the creature at the landing
////
//// caster's connection c0, a DespawnUnit effect of its spell
//// Despawn(delay_ms, went_at_ms)
////                         dead, gone: dropped
////                         else ─▶ at went_at_ms + delay_ms the creature leaves the field (`Despawn`'s doc):
////                                    the fight and the guard end as at a kill, the controls are dropped,
////                                    Broadcast(Removed); StartServiceTimer(corpse, respawn_ms)
////
//// caster's connection c0, what its cast holds on the creature
//// CastViewSet(c0, view)
////                         views[cast id] = (c0, view), in place of that cast's earlier view
////                                    no news: the viewers have the 0x7f4 from the caster's audience
//// CastViewEnds(c0, cast_id)
////                         held by c0 ─▶ dropped
////                         else nothing
//// caster's connection c0, its cast no longer holds a node on the creature (a push off by the stack rule)
//// ControlsEnd(c0, cast_id)
////                         each state c0's cast landed ─▶ dropped, its timer cancelled,
////                                    Broadcast(News(0x880)); the fight acts again when it
////                                    was the last that kept the creature still
////                         no state of c0's cast held ─▶ nothing
//// CasterGone(c0) ─────────────▶ every view and source of c0 dropped (no control)
//// a viewer's arrival (`Started`, `Seen`) ─▶ the 0x262 lists each view
////                                    (`unit_casts.entries_of`), with the tail's cast id 0
//// ```
////
//// - **The unit** is `creature_unit.create(spawn, unit_id, time)`, stamped with
////   the map's server time at the moment it is sent, from the clock origin the
////   map gave (`map.server_time`).
//// - **Retire** is the map's word that no player has seen the creature for the
////   idle stop, so it ends cleanly: the map's watch on it ends, and the spawn is
////   dormant with its unit id kept. A creature takes `Retire` once and has no
////   viewer to tell: its viewers went with their `Unseen`. A creature that lies
////   dead when told to retire stops at its respawn, since its map keeps the spawn
////   retiring until it ends and a corpse is never shown to a viewer that comes
////   after.
//// - **A strike's crowd-control states** land after its damage, on a creature that
////   lives and whose Interrupt Armor is already 0 (a strike on armor above 0 wears it down
////   instead), and the answer's `Landed` names the ones that did; while the creature holds one it does not act
////   (genesis_prime/world_map/creature_control).
//// - **A strike's gates** are the target apply prerequisites of its rows that read this
////   creature's own state (genesis_prime/game/strike_tell `Gate`). They are checked when the
////   strike arrives, before the hit rule, against the creature's level, factions, combat state,
////   vitals, difficulty and Creature2 row and the caster as the second unit
////   (genesis_prime/game/prerequisite `of_creature`). A corpse reads none: it answers
////   `Refused(Dead)`. The effect ids that passed are in the answer's `gates_passed`, which
////   `Landed`, `Immune` and `Deflected` carry (a deflect still checks its gates), and the
////   blows and states of a gated row not listed there are in neither its descriptions nor its
////   states. A refusal passes no gate.
//// - **A strike** is told by the connection of the caster through its map
////   (genesis_prime/world_map/map `TellCreature`, which the map passes on as `ToldCreature`),
////   and answered by a send to that connection. A strike for a creature that has ended is
////   dropped by the map or the registry and left out at the caster's deadline
////   (genesis_prime/game/strike).
//// - **The corpse timer** is the creature's own, whatever its viewers: it starts at the
////   kill for the kind's respawn time and fires with no viewer too
////   (genesis_prime/world_map/creature_kind). The creature then removes its unit, tells its
////   map it expired and stops: the map numbers the next life and starts it, so a life never
////   outlives its address (genesis_prime/world_map/creature_registry).
//// - **The fight** is creature_fight's, whose module holds its sequence from aggro
////   to home and what happens at each of its deadlines; the creature carries out its
////   effects: news to its viewers, tells to the players in the fight
////   (`FightTold`), and its four timers: the attack tick, the cast end of a charge, the strike
////   deadline and the walk home. An attack with a cast time (`Attack.cast_ms` above 0, the
////   Sim-Turrets') is a charge: the fight opens it on an attack tick and carries it out as
////   the 0x7ff, the `CastEnds` timer, the strikes to the fighters inside its rectangle and the
////   go; the creature takes no message for it beyond its own timer. An attack with run speed
////   0 never moves the unit.
//// - **The guard** is creature_guard's, which holds what a guard and an opening are. The creature
////   gives it its inputs: `Interrupted` (with the charge's cast id) when the fight
////   broke a charge (`ChargeInterrupted`), its timer's firing and `Killed` at a kill; it carries out
////   its effects, news to every viewer and the opening's timer (`OpeningEnds`, id 12 and 7 more for
////   each generation). A guarded creature's strike takes no health. An opened creature counts as
////   still, refused and holding (`still`, `attack_refused`, `holds_a_state`): the fight starts no
////   charge, strike or path, and acts again when both the states that stop its run and the
////   opening are gone. A viewer that arrives is shown the guard's or the opening's cast after the 0x262.
//// - **A viewer that is not a connection any more** is dropped by the map's relay (the
////   registry finds no process); the map's `Unseen` follows from its end.
//// - **A `Seen` twice from one connection** is answered with a snapshot twice; the map relays
////   the first and drops the second, which no longer awaits it. The second `Seen` names the
////   stay and generation the creature holds that player by from then on
////   (genesis_prime/world_map/stay).
//// - **A stay travels from the message that caused the work.** A strike's answer
////   goes for the stay the strike was told for; the fight holds each player in
////   the stay of the message that put it in the fight (the map's `Approached`, the
////   player's strike) and tells it for that stay; a player's strike or move of a
////   stay other than the one its `Seen` named starts and moves nothing
////   (genesis_prime/world_map/creature_fight).
//// - **A property modifier** of a player's spell is told by the caster's connection
////   through its map, as a strike is; the caster's cast owns
////   its time and the creature owns the values and every rule that reads them. A tell
////   addressed to a life that ended finds no creature, so the creature fences nothing: it
////   drops a start that reaches it dead. An end names only the source, which the caster
////   keeps one node of for each unit. A modifier on another player, and stacking across
////   casters, are not handled here.
//// - **A throw** is told by the caster's connection through its map, as a strike and a
////   modifier are (`Thrown`). The connection draws the two
////   fractions the move needs from its seed (genesis_prime/game/forced_move), so the
////   creature keeps no random state, and names the unit the move is measured from. The
////   creature owns the path and the flight's timer. The timers
////   are numbered in 7 slots by generation: the fight's 0 to 3 above a multiple of 7, a
////   control's 4, the guard's 5 and the flight's end 6 (`timer_id`).
//// - **Only the run's watch stops the creature.** It watches no caster's connection: the
////   map tells it `CasterGone` when a caster leaves or its connection ends, and any other
////   watch end is a crash.
//// - **The map run's end** ends the creature: it watches the run by the pid the
////   run gave when it started the creature, not through Maps, which is waiting
////   on the run's start while the run starts its creatures.
////
//// What happens at each failure point of a creature:
////
//// | Point | What happens |
//// |---|---|
//// | the creature crashes | its map's watch ends; the map sends every player `Gone(unit)` and starts the spawn again, after the respawn time and only if a player sees it then, as a new unit |
//// | the creature crashes while it charges | the same: its `CastEnds` timer goes with the process, no 0x7fe is sent, and the map's `Gone` removes the unit from each viewer |
//// | the creature dies while it charges | the fight cancels the `CastEnds` timer and finishes the cast (0x7fe); the corpse timer starts as for any kill (`death_during_a_charge_ends_it_test`) |
//// | a `CastEnds` fires after its charge ended | the fight finds no charge of that generation and does nothing (`a_stale_cast_end_does_nothing_test`) |
//// | an `OpeningEnds` fires after the creature died | the guard finds no opening of that generation and does nothing (`an_opening_end_after_death_does_nothing_test`) |
//// | the creature dies while opened | the guard cancels the opening's timer and sends no 0x880: the death clears the states (`a_turret_killed_while_opened_gives_its_kill_credit_test`) |
//// | the creature crashes while opened | the same as any crash: the timer goes with the process, and the spawn starts again guarded as a new unit |
//// | a strike with damage reaches a guarded creature | it takes no health and the answer is `Landed` with no descriptions (`a_damaging_strike_on_a_guarded_turret_takes_no_health_test`) |
//// | the creature is told `Retire` | it stops, and the map's watch ends; the map takes that as a clean stop |
//// | the creature is told `Retire` while dead | it stops at its corpse timer, and the map's watch ends then |
//// | the creature is struck while dead | the strike is answered `Refused(Dead)`; no health changes and no news is sent |
//// | a strike carries a gate its creature fails | the blows and states of that row are not dealt or taken, the answer's `gates_passed` leaves its id out (`strike_row_failing_its_gate_lands_nothing_test`) |
//// | a strike carries a gate its creature passes | the row lands as an ungated one does and its id is in `gates_passed` (`strike_row_passing_its_gate_lands_as_before_test`) |
//// | a gate reads the creature's health, factions, level, Creature2 row or difficulty | it reads them when the strike arrives, not when the cast was made (`gate_reads_the_creature_when_the_strike_arrives_test`, `strike_gates_read_the_creature_row_and_the_spawn_it_names_test`, `gate_reads_the_difficulty_of_the_creature_row_test`) |
//// | a gate reads the combat or the Interrupt Armor the creature wears | the first strike's own fight state starts the combat the later gate reads, and worn armor is the current one (`strike_with_every_gate_failed_does_not_pull_the_creature_test`, `gate_reads_the_interrupt_armor_the_creature_wears_test`) |
//// | a gate reads what the creature does not hold (`prerequisite.NotRead`) | it does not pass (`gate_of_a_type_the_creature_does_not_read_passes_nothing_test`) |
//// | the strike is deflected | the gates are still checked, and the answer's `Deflected` names the ones that passed (`deflected_strike_still_answers_the_gates_it_passed_test`) |
//// | two strikes reach it one after the other, each with gates | each is checked against the creature the one before left (`two_strikes_in_turn_each_get_their_own_answer_and_gates_test`) |
//// | a gated strike reaches a dead creature | it is answered `Refused(Dead)` with no gate read (`dead_creature_refuses_a_gated_strike_test`) |
//// | two strikes reach it one after the other | each is answered in turn on the health the one before left; the second finds a corpse if the first killed |
//// | the caster's connection has ended when the creature answers | the send is dropped by the registry; the hit and its news stand |
//// | the killing blow's caster has left the world, or its stay has changed, when the credit arrives | the connection drops the credit (`stay_sent`): no experience is given, the death and its news stand |
//// | a second strike reaches the creature after the killing one | it finds a corpse and is answered `Refused(Dead)`; it sends no credit, so a kill is credited once |
//// | a viewer arrives while the creature is dead | its 0x262 carries health 0, which the client creates dead |
//// | the creature crashes while retiring | the same watch end: the map takes it as a clean stop, since no client shows the unit |
//// | the map run ends | the creature's watch on the run ends and it stops |
//// | the creature supervisor restarts | every creature ends and so does every map (genesis_prime/server): the world subtree is `rest_for_one` |
//// | a viewer's connection ends | the map's relay to it is dropped; the map sends `Unseen`, and the creature forgets it |
//// | a `Seen` or `Unseen` reaches a creature that has ended | dropped: the registry finds no process |
//// | an `Unseen` names a generation other than the one the creature holds the viewer under | changes nothing: it is not this viewer's sight that ended |
//// | the creature crashes while it holds a modifier | the map starts the spawn again as a new unit with no modifier; the caster's later `ModifierEnds` is dropped by the registry |
//// | the same source starts twice | it is held once |
//// | a `ModifierStarts` is addressed to a life that ended | dropped: the registry finds no creature at that life's address |
//// | a `ModifierStarts` reaches the creature while it is dead | dropped |
//// | a `ModifierStarts` or `ModifierEnds` reaches a creature that has ended | dropped: the registry finds no process |
//// | the caster's connection ends before a modifier's end | the map tells the creature `CasterGone`, and it removes every source and view of that caster |
//// | a `ModifierEnds` comes twice, or for a source not held | it changes nothing |
//// | the caster dies | its casts finish, and each modifier they hold on a creature ends |
//// | the creature dies while it holds a modifier | the modifier stays held and no rule reads it; its end still removes it |
//// | the creature's corpse timer fires | it removes its unit, tells the map it expired and stops; the next life is a new creature with its properties from the bases and no source held, and a later `ModifierEnds` of the life that ended finds no creature |
//// | a viewer arrives while a modifier lasts | its 0x262 carries the current value (`unit_properties.overlay`) |
//// | a modifier lowers the interrupt armor maximum below the armor the creature wears | the worn armor is clamped to the new maximum and the viewers are sent 0x938 of it |
//// | a modifier raises or lowers the interrupt armor maximum of a creature at full armor | the armor stays full at the new maximum and the viewers are sent 0x938 of it |
//// | a modifier raises the interrupt armor maximum of a creature that wears armor down | the armor it wears stays, and no 0x938 is sent |
//// | a `Thrown` is addressed to a life that ended | dropped: the registry finds no creature at that life's address |
//// | a `Thrown` reaches a creature that is dead, or walks home | dropped (`a_throw_at_a_dead_or_returning_creature_is_dropped_test`) |
//// | a `Thrown` reaches a creature that has ended | dropped: the registry finds no process |
//// | a strike lands a Knockback, Pushback or Pull state | the creature is thrown in the same step by the state's own `Throw`, after the state's news (`a_landed_knockback_throws_the_creature_in_the_same_step_test`) |
//// | a guarded creature meets a strike with such a state | it keeps the state and is not thrown (`an_immune_knockback_does_not_throw_test`) |
//// | the caster's connection ends before its throw's tell | the tell is never sent; a throw already told runs to its landing, since it needs no caster |
//// | the creature crashes in flight | its `FlightEnds` timer goes with the process; the map's `Gone` removes the unit from each viewer and the spawn starts again at home |
//// | the creature is killed after a throw | its corpse timer expires it like any other, and its next life starts at home (`a_creature_killed_after_a_throw_expires_like_any_other_and_its_next_life_starts_at_home_test`) |
//// | a `FlightEnds` timer fires | the fight takes it (`the_flight_end_timer_has_its_own_id_test` for its id); one of an older generation does nothing |
//// | a chase or a walk home at a run speed of 0 or below | the creature stands where it is, with no path and no arrival timer (`chase_with_zero_run_speed_stands_still_test`, `walk_home_with_zero_run_speed_stands_still_test`, `negative_run_speed_stands_still_test`); it goes on from there when the speed is above 0 again (`run_speed_restored_moves_again_test`, `run_speed_restored_walks_home_again_test`), and not while a state holds it until the state ends (`speed_restored_while_held_stays_until_control_ends_test`) |
//// | a creature at a run speed of 0 or below is out of reach of a target | it leashes when the target is beyond the leash range from home, as a turret does (`creature_that_cannot_run_leashes_by_the_turret_rule_test`); at home it rests at once (`rooted_creature_leashing_at_home_rests_test`); away from home it holds, since it has no walk (`rooted_creature_at_the_circle_does_not_leash_test`) |

import genesis_prime/game/area
import genesis_prime/game/experience.{Credit}
import genesis_prime/game/forced_move
import genesis_prime/game/held_changes
import genesis_prime/game/hit
import genesis_prime/game/prerequisite
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Tell as StrikeTell, Answered, CreatureStriker,
  PlayerStriker, Refused,
}
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/game/unit_properties.{
  type Modifier, type Properties, type Source,
}
import genesis_prime/game/unit_state
import genesis_prime/gap
import genesis_prime/step.{
  type ConnectionId, type CreatureStart, type Effect, type RingMember,
  type ServiceEffect, type ServiceInput, type ServiceRule, type ServiceStep,
  Asked, Connection, CreatureNotStarted, Effects, OwnEffect, OwnEvent, Send,
  ServiceTimerFired, Started, Stop, Stopping, TimerId, Told, Watch, WatchEnded,
  WatchId,
}
import genesis_prime/table/id.{type Spell4Id, Faction2Id}
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_fight.{
  type Fighter, AttackTick, CastEnds, ChaseArrival, Fighter, FlightEnds,
  HomeArrival, StrikeDeadline,
}
import genesis_prime/world_map/creature_guard
import genesis_prime/world_map/creature_kind.{type Kind}
import genesis_prime/world_map/creature_life.{
  type Body, type Life, Body, Died, Ends, Expires, Health, StopAtRespawn,
  StopNow,
}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/creature_unit_state
import genesis_prime/world_map/creature_unit_type
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/creature"

/// The watch on the map run that started the creature: the only watch whose end stops
/// it.
const run_watch = WatchId(1)

/// The corpse timer. The fight's timers are numbered from it by kind and
/// generation (`timer_id`), so none is 1.
const corpse_timer = TimerId(1)

/// The timer of the creature's Interrupt Armor refill: 2, which no fight timer is (they
/// start at 7), no control's (they start at 11) and no guard's (they start at 12).
const refill_timer = TimerId(2)

/// The timer of a pending despawn: 3, which no fight timer is. A fight timer is 7 times its
/// generation plus a slot of 0 to 3 or 6, and generations start at 1 (`creature_fight`), so
/// 3 is the id a generation 0 would give the cast end, which is never issued; no control's
/// (they start at 11) and no guard's (they start at 12) is 3 either.
const despawn_timer = TimerId(3)

/// The one timer of the held unit states, armed for the earliest end: 4, which is free. A
/// control's id is 4 above 7 times its number from 1, so from 11, and a guard's is 5 above 7
/// times its generation from 1, so from 12; a fight timer is 7 times a generation plus 0 to 3
/// or 6, never 4; the corpse, refill and despawn timers are 1, 2 and 3. A state cannot have
/// an id of its own, since the fight, the controls and the guard take all seven residues of 7.
const unit_state_timer = TimerId(4)

/// The one timer of a chase's arrival, which ends the walk animation of the creature that has run
/// its path (`creature_fight.ChaseArrival`): 5, which is free. A creature has one chase path at a
/// time, so the timer has no generation. The fight timers are 7 times a generation plus 0 to 3 or
/// 6, the controls' 4 above a multiple of 7 from 11, and the guard's 5 above one from 12 (the id 5
/// would be a guard timer of generation 0, which is never issued); the corpse, refill, despawn
/// and unit state timers are 1 to 4. Public for a test.
pub const chase_arrival_timer = TimerId(5)

/// What a creature is started with: which creature of which run it is and the
/// map's clock (`CreatureStart`), the spawn it stands at, found by the id the start
/// names, the kind the server chose for its Creature2 row, and the run's game
/// numbers.
pub type Settings {
  Settings(
    creature: CreatureStart,
    spawn: Spawn,
    kind: Kind,
    numbers: GameNumbers,
  )
}

/// What the map and the connections tell a creature.
pub type Message {
  /// The map: the player of connection `by`, in its stay `stay`, sees the creature
  /// from the sight `generation` names. The creature records the viewer and answers
  /// with a `Snapshot` of that generation; a second `Seen` of the same viewer is
  /// answered again.
  Seen(by: ConnectionId, stay: Stay, generation: Generation)
  /// The map: the sight `generation` of the player of connection `by` ended. The
  /// creature drops the viewer and its threat entry and sends nothing of the unit's
  /// removal (the map tells the viewer); a second `Unseen`, or one of a viewer that is
  /// not held, changes nothing.
  Unseen(by: ConnectionId, generation: Generation)
  /// No player has seen the creature for the idle stop: end.
  Retire
  /// A caster's connection strikes the creature (genesis_prime/game/strike_tell).
  Strike(tell: StrikeTell)
  /// The map: the ready player `member` entered the creature's ring.
  Approached(member: RingMember)
  /// The map: the player of connection `by` left the creature's ring.
  Withdrew(by: ConnectionId)
  /// The map: the player of connection `by` died, so it leaves the creature's ring's
  /// players and its threat list.
  PlayerDied(by: ConnectionId)
  /// The connection of a player on the creature's threat list: its player, in its
  /// stay `stay`, stands at `place`, its move `seq`.
  TargetMoved(
    by: ConnectionId,
    place: Place,
    seq: Int,
    stay: Stay,
    hit_radius: Float,
  )
  /// The connection of a player the creature struck answers the strike.
  StrikeAnswered(answered: Answered)
  /// The connection `by` of a caster: a property modifier of its spell starts on the
  /// creature. It is dropped when the creature lies dead.
  ModifierStarts(by: ConnectionId, source: Source, modifier: Modifier)
  /// A caster's connection: the property modifier of `source` ends on the creature.
  ModifierEnds(source: Source)
  /// A caster's connection: a ForcedMove effect of its spell throws the creature
  /// (genesis_prime/game/forced_move). It is dropped when the creature lies dead; else the
  /// fight takes it (`creature_fight.Thrown`), which drops it for a creature that walks home
  /// or does not run.
  Thrown(throw: forced_move.Throw)
  /// A caster's connection: a DespawnUnit effect of its spell removes the creature
  /// `delay_ms` after `went_at_ms`, the monotonic time of the go. The creature owns the
  /// delay, so the caster's leaving or dying changes nothing.
  ///
  /// ```
  /// Despawn(delay_ms, went_at_ms)
  ///     dead, despawned: dropped
  ///     due = went_at_ms + delay_ms; despawn_due_ms holds the due time of the pending one
  ///     due <= now:                         CancelServiceTimer(despawn_timer) if one is
  ///                                         pending, then leave the field now
  ///     none pending:                       StartServiceTimer(despawn_timer, due - now)
  ///     due >= the pending due time:        no timer effect; the pending timer stands
  ///     due < the pending due time, > now:  CancelServiceTimer(despawn_timer), then
  ///                                         StartServiceTimer(despawn_timer, due - now)
  ///     the despawn timer fires ─▶ leave the field
  ///     leave the field:
  ///         fight and guard take Despawned (stand still, finish a charge, Released to
  ///         the fighters), the controls take `died` (no 0x880)
  ///         life = Despawned; CancelServiceTimer(despawn_timer) only when it is running
  ///         Broadcast(Removed) ─▶ writes 0x355 if shown
  ///         StartServiceTimer(corpse_timer, the kind's respawn_ms)
  ///     the corpse timer fires ─▶ Send(map, Expired(unit, life)), Stop, with no second Removed
  /// ```
  ///
  /// No health or death news, no kill credit and no corpse are sent: the removal is a
  /// death's stand-still, release and respawn without them. The delay runs from the go, as a
  /// cast's own delay does.
  ///
  /// | If | Then |
  /// |---|---|
  /// | the tell is in flight when the creature ends | the registry drops it |
  /// | it reaches a creature that is dead or already despawned | dropped (a server guess: the client's tables hold no rule for a removal that meets a corpse, so it takes no second life of its own) |
  /// | it reaches a creature that walks home or fights | the creature is removed and the fight releases its players: the removal is no strike |
  /// | the delay is 0 | the creature leaves the field in the tell's own step, after the go's frames; another viewer's 0x7f4 and 0x355 have two senders, which no order holds |
  /// | the delay is above 0 | one timer to the go plus the delay, and nothing is sent before |
  /// | a second `Despawn` arrives while one is pending, with the same or a later due time | the earlier due time wins, a server guess (no client rule orders two removals); no timer effect: the shell ends the process when a timer id already running is started, so the pending timer stands |
  /// | a second `Despawn` arrives while one is pending, with an earlier due time still ahead | the pending timer is cancelled, then the despawn timer is started for the earlier due time |
  /// | a second `Despawn` arrives while one is pending, with a due time already past | the pending timer is cancelled and the creature leaves the field now |
  /// | the creature dies while one is pending | the despawn timer is cancelled at the kill; a stale fire already queued is dropped by the shell |
  /// | the creature retires unseen while one is pending | the process stops and the pending despawn is lost, a server guess (the spawn's next creature stands fresh) |
  /// | it is told `Retire` while despawned | it stops at its corpse timer (`StopAtRespawn`), so the spawn does not come back early |
  /// | a viewer arrives while despawned | it is recorded and sent nothing; its map sends it the next life's picture when it starts |
  /// | a viewer leaves while despawned | `Unseen` drops it and sends nothing; the map's notice reaches a connection that shows no such unit |
  /// | a strike reaches the despawned creature | `Refused(Despawned)`; a throw, a modifier or a gate is dropped, since `is_dead` holds |
  /// | the corpse timer fires for a despawned creature | `Expired` and `Stop`, with no second `Removed`: the viewers were sent it at the removal |
  /// | the corpse timer fires for a run-only creature | `Stop` only: the viewers were sent `Removed` at the removal |
  /// | the creature crashes pending or despawned | the map sends `Gone` and starts the spawn again after the respawn time as a new unit |
  Despawn(delay_ms: Int, went_at_ms: Int)
  /// A caster's connection: the UnitStateSet rows of its go hold their states on the creature,
  /// each from `went_at_ms`, the monotonic time of the go, plus its delay for its duration (the
  /// delay delays the hold, a server guess: the client reads no row of the type). The
  /// creature owns the end of each state, so the caster's leaving or dying changes nothing.
  ///
  /// ```
  /// UnitStates(rows, went_at_ms)
  ///     dead, despawned: dropped
  ///     each row: starts_at = went_at_ms + delay, ends_at = starts_at + duration
  ///         no duration, or ends_at <= now: not held, nothing sent
  ///         else a Held with the creature's next number
  ///     Send(each viewer, in connection order, UnitStateHeld(state, number)) per held row
  ///         with starts_at <= now, in row order ─▶ the viewer's picture
  ///     the earliest start or end changed: CancelServiceTimer(unit_state_timer) if one runs,
  ///         then StartServiceTimer(unit_state_timer, earliest - now)
  ///     the timer fires ─▶ each Held with starts_at <= now not yet told is told as above
  ///         each Held with ends_at <= now is dropped
  ///         Send(each viewer, UnitStateEnded(number)) per dropped hold that was told
  ///         holds left: StartServiceTimer(unit_state_timer, next - now)
  ///     a strike with blows or states meets a creature that holds a blocking state (from its
  ///     start to its end)
  ///         ─▶ Immune, no state lands, no armor is lost, and the creature is threatened as a
  ///         guarded one is, a server guess (`unit_state.blocks_hostile`)
  ///     the creature dies or is removed ─▶ every hold dropped, the timer
  ///         cancelled, no `UnitStateEnded` (the viewers' pictures clear on its own news)
  /// ```
  ///
  /// | If | Then |
  /// |---|---|
  /// | the tell is in flight when the creature ends | the registry drops it |
  /// | it reaches a creature that is dead or despawned | dropped |
  /// | a row's end is already past at the tell, or its duration is 0 | the row is not held and nothing is sent for it |
  /// | a row's start is after the tell | nothing is told, blocked or shown until its start; the timer is armed for it (`a_delayed_row_blocks_only_from_its_start_test`) |
  /// | two casters hold one state on the creature, or one caster's two rows hold one | two holds with two numbers, each ending by its own end; the creature blocks while any is held |
  /// | the timer fires with a hold not yet due | `ended` drops only the due ones and arms the timer again for the next |
  /// | a stale timer fire arrives after the holds were cleared | the shell drops it; `ended` finds nothing |
  /// | a viewer arrives while states are held | after its 0x262, one `UnitStateHeld` per hold, in the order they began |
  /// | a viewer leaves | its connection drops the unit and its picture entry with it |
  /// | the creature retires unseen while states are held | the process stops and the holds are lost, a server guess (the spawn's next creature stands fresh) |
  /// | the creature crashes while it holds states | the map sends `Gone` and starts the spawn again as a new unit that holds none |
  /// | a strike with neither blows nor states (a go row of gates only) meets a blocking creature | as any creature: the unit-state check does not apply |
  /// | a periodic tick meets a blocking creature | `Immune` at each tick, as for a guarded creature |
  /// | a throw reaches a blocking creature | dropped, a server guess |
  /// | a struck-change modifier reaches a blocking creature | dropped, a server guess, as a throw is (`a_modifier_at_a_creature_holding_a_blocking_state_is_dropped_test`) |
  /// | a despawn reaches a blocking creature | it still removes the creature: a removal is not hostile |
  /// | the caster leaves or dies after the tell | no effect: the creature owns the end |
  UnitStates(rows: List(unit_state.Row), went_at_ms: Int)
  /// The caster's connection `by` tells the creature that its cast holds `view` on it
  /// (a node of the cast's go on the creature). The view is the whole target: a later set
  /// for the same cast id replaces the earlier one. The creature keeps it to list it in the
  /// 0x262 of each viewer that arrives.
  ///
  /// ```
  /// CastViewSet(by, view)
  ///     views[view.cast_id] = (by, view), kept on a dead creature (a corpse keeps its nodes);
  /// ```
  ///
  /// | If | Then |
  /// |---|---|
  /// | the tell is in flight when the creature ends, or is told for another life | the registry drops it |
  /// | it reaches a dead creature | kept, and the corpse's 0x262 lists it |
  /// | two casters' views | both kept, each under its own cast id (a cast id names its caster) |
  /// | the caster leaves the map or its connection ends | `CasterGone` drops every view of it |
  /// | the creature crashes | the views are lost and the map starts the spawn again as a new unit |
  CastViewSet(by: ConnectionId, view: unit_casts.CastView)
  /// The caster's connection `by` tells the creature that its cast `cast_id` holds
  /// nothing on it any more. The creature drops the view of that cast when `by` holds
  /// it; an end for a cast it does
  /// not hold, or one held by another connection, changes nothing.
  CastViewEnds(by: ConnectionId, cast_id: Int)
  /// The caster's connection `by`: its cast `cast_id` no longer holds a node on the
  /// creature that holds the states the cast landed, so each of those states ends.
  ControlsEnd(by: ConnectionId, cast_id: Int)
  /// The map's word that the player of connection `by` is gone from it, by its leave or
  /// by its connection's end: every source and view of that connection ends (each source
  /// with its property news), whatever state the creature is in (live, dead, retiring or
  /// releasing). A control stands until its own timer ends it. Told by the map once for
  /// each running creature: the creature watches no caster's connection.
  CasterGone(by: ConnectionId)
}

/// What a creature sends its map without waiting. The map relays it to the players
/// (genesis_prime/world_map/map); a creature sends no connection anything.
pub type Outgoing {
  /// To the creature's map: the picture of the creature for the viewer of connection
  /// `by` that took `Seen` of `generation`, built from the creature's state when it took
  /// it, `burst` in the order the viewer writes it. Empty for a creature that is not
  /// shown (`map.Snapshot`).
  Snapshot(
    unit_id: Int,
    life: Int,
    by: ConnectionId,
    generation: Generation,
    burst: List(PeerNews),
  )
  /// To the creature's map: news of the creature's unit for every viewer, once, which
  /// the map relays to each viewer it holds as relaying (`map.Broadcast`).
  Broadcast(unit_id: Int, life: Int, news: PeerNews)
  /// To the creature's map: a tell to one player, for its stay: the answer to its
  /// strike, the credit for a kill or a fight tell (`map.Relay`). News of the
  /// creature's unit is no relay: it goes as a snapshot or a broadcast.
  Relay(
    unit_id: Int,
    life: Int,
    to: ConnectionId,
    stay: Stay,
    payload: relay.Payload,
  )
  /// To the creature's map: the creature of `unit_id` and `life` lay dead or despawned
  /// until its corpse timer and stops now; the map starts the creature's next life
  /// under the same unit id when it ends (`map.Expired`).
  Expired(unit_id: Int, life: Int)
}

/// A player in sight of a creature: the stay the map named it for and the generation
/// of the sight it began under, which the map's `Unseen` must name to end it.
pub type Viewer {
  Viewer(stay: Stay, generation: Generation)
}

/// A creature's players in sight, each by its connection with the stay and generation the map
/// named it for, its health, its fight, the crowd-control states it holds, whether
/// it was told to retire while it lay dead, its properties with the modifiers of
/// players' spells on them, the caster's connection of each modifier's source in the order
/// the modifiers started, and the monotonic time its pending despawn is due (none when
/// none is pending). `views` holds what players' casts hold on it, by cast id with the
/// caster's connection that told it; `CasterGone` drops them with the modifiers' sources.
pub opaque type State {
  State(
    settings: Settings,
    body: Body,
    life: Life,
    fight: creature_fight.State,
    control: creature_control.State,
    guard: creature_guard.State,
    retiring: Bool,
    viewers: Dict(ConnectionId, Viewer),
    properties: Properties,
    held: held_changes.Held,
    views: Dict(Int, #(ConnectionId, unit_casts.CastView)),
    despawn_due_ms: Option(Int),
    unit_state: creature_unit_state.State,
  )
}

/// The creature's rule, as its service shell runs it.
pub fn rule(
  creature creature: CreatureStart,
  spawn spawn: Spawn,
  kind kind: Kind,
  numbers numbers: GameNumbers,
) -> ServiceRule(Settings, State, Message, Outgoing) {
  step.Rule(
    name: rule_name,
    settings: Settings(creature:, spawn:, kind:, numbers:),
    new:,
    step:,
  )
}

/// A creature's first state: the players the map started it for are its viewers,
/// and it stands at full health at its spawn, resting.
pub fn new(settings: Settings) -> State {
  let body = base_body(settings:)
  State(
    settings:,
    body:,
    life: creature_life.new(body:),
    fight: creature_fight.new(home: settings.spawn.place),
    control: creature_control.new(),
    guard: creature_guard.new(
      guard: settings.kind.guard,
      unit_id: settings.creature.unit_id,
    ),
    retiring: False,
    viewers: dict.from_list(
      list.map(settings.creature.viewers, fn(viewer) {
        #(viewer.0, Viewer(stay: viewer.1, generation: viewer.2))
      }),
    ),
    properties: base_properties(settings:),
    held: held_changes.new(),
    views: dict.new(),
    despawn_due_ms: None,
    unit_state: creature_unit_state.new(),
  )
}

/// What the creature brings to a fight with no modifier held: the spawn's health and
/// combat values.
fn base_body(settings settings: Settings) -> Body {
  Body(
    max_health: settings.spawn.health,
    combat: settings.spawn.combat,
    respawn_ms: settings.kind.respawn_ms,
  )
}

/// The creature's properties with no modifier held: the spawn's bases, and for a spawn
/// whose health is recorded, Base Health (property 7) at that health, which is the
/// maximum the client holds for it (`creature_unit`).
fn base_properties(settings settings: Settings) -> Properties {
  let spawn = settings.spawn
  let bases = case spawn.health_source {
    unit_fields.Recorded ->
      list.key_set(
        spawn.bases,
        unit_properties.base_health,
        int.to_float(spawn.health),
      )
    unit_fields.ClientDefault -> spawn.bases
  }
  unit_properties.of_creature(bases:, level: spawn.level)
}

/// The creature's fight: whether it rests, fights or walks home, for a test.
pub fn fight(state state: State) -> creature_fight.State {
  state.fight
}

/// Whether the creature holds a crowd-control state, for a test.
pub fn controlled(state state: State) -> Bool {
  creature_control.holds(state: state.control)
}

/// The connections whose players see the creature.
pub fn viewers(state state: State) -> Set(ConnectionId) {
  set.from_list(dict.keys(state.viewers))
}

/// One input in, the new state and what the shell must do out, as the sequence
/// above gives. An input a service's shell never gives a creature is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Outgoing)) {
  let creature = state.settings.creature
  let now_ms = input.now.monotonic_ms
  let run_only = spawn_source.is_run_only(creature.spawn)
  case input.event {
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Started) -> {
      let snapshots =
        list.map(creature.viewers, fn(viewer) {
          to_the_map(
            state:,
            message: Snapshot(
              unit_id: creature.unit_id,
              life: creature.life,
              by: viewer.0,
              generation: viewer.2,
              burst: [
                appeared(state:, now_ms:),
                ..list.append(
                  guard_shown(state:, now_ms:),
                  unit_states_shown(state:, now_ms:),
                )
              ],
            ),
          )
        })
      let #(state, fought) = case creature.ring {
        [] -> #(state, [])
        members ->
          fought(state:, input: creature_fight.RingAtStart(members:), now_ms:)
      }
      #(
        state,
        Effects(
          list.flatten([
            [
              Watch(
                watch: run_watch,
                target: step.Map(
                  map: creature.map,
                  incarnation: creature.incarnation,
                ),
              ),
            ],
            snapshots,
            fought,
          ]),
        ),
      )
    }
    OwnEvent(Told(message: Seen(by:, stay:, generation:))) -> #(
      State(
        ..state,
        viewers: dict.insert(state.viewers, by, Viewer(stay:, generation:)),
      ),
      Effects([
        to_the_map(
          state:,
          message: Snapshot(
            unit_id: creature.unit_id,
            life: creature.life,
            by:,
            generation:,
            burst: case creature_life.is_shown(life: state.life) {
              False -> []
              True -> [
                appeared(state:, now_ms:),
                ..list.flatten([
                  guard_shown(state:, now_ms:),
                  unit_states_shown(state:, now_ms:),
                  list.map(
                    creature_fight.arrival_news(
                      state: state.fight,
                      fighter: fighter_of(state:),
                      now_ms:,
                    ),
                    fn(news) { peer_news(creature:, news:) },
                  ),
                ])
              ]
            },
          ),
        ),
      ]),
    )
    OwnEvent(Told(message: Unseen(by:, generation:))) ->
      case dict.get(state.viewers, by) {
        Ok(Viewer(generation: held, ..)) if held == generation -> {
          let state = State(..state, viewers: dict.delete(state.viewers, by))
          let #(state, fought) =
            fought(state:, input: creature_fight.Unseen(by:), now_ms:)
          #(state, Effects(fought))
        }
        Ok(Viewer(..)) | Error(Nil) -> #(state, Effects([]))
      }
    OwnEvent(Told(message: Retire)) ->
      case creature_life.on_retire(life: state.life) {
        StopNow -> #(state, Effects([Stop]))
        StopAtRespawn -> #(State(..state, retiring: True), Effects([]))
      }
    OwnEvent(Told(message: Strike(tell:))) -> struck(state:, tell:, now_ms:)
    OwnEvent(Told(message: Approached(member:))) ->
      fought_alone(state:, input: creature_fight.Approached(member:), now_ms:)
    OwnEvent(Told(message: Withdrew(by:))) ->
      fought_alone(state:, input: creature_fight.Withdrew(by:), now_ms:)
    OwnEvent(Told(message: PlayerDied(by:))) ->
      fought_alone(state:, input: creature_fight.PlayerDied(by:), now_ms:)
    OwnEvent(Told(message: TargetMoved(by:, place:, seq:, stay:, hit_radius:))) ->
      fought_alone(
        state:,
        input: creature_fight.TargetMoved(by:, place:, seq:, stay:, hit_radius:),
        now_ms:,
      )
    OwnEvent(Told(message: StrikeAnswered(answered:))) ->
      fought_alone(
        state:,
        input: creature_fight.StrikeAnswered(answered:),
        now_ms:,
      )
    OwnEvent(ServiceTimerFired(timer:)) if timer == corpse_timer && run_only -> #(
      state,
      Effects(list.append(removed_if_shown(state:), [Stop])),
    )
    OwnEvent(ServiceTimerFired(timer:)) if timer == corpse_timer ->
      case
        creature_life.corpse_timer_fired(
          life: state.life,
          retiring: state.retiring,
        )
      {
        Ends -> #(state, Effects([Stop]))
        Expires -> #(
          state,
          Effects(
            list.flatten([
              removed_if_shown(state:),
              [
                to_the_map(
                  state:,
                  message: Expired(
                    unit_id: creature.unit_id,
                    life: creature.life,
                  ),
                ),
                Stop,
              ],
            ]),
          ),
        )
      }
    OwnEvent(ServiceTimerFired(timer:)) if timer == despawn_timer ->
      despawn_timer_fired(state:, now_ms:)
    OwnEvent(ServiceTimerFired(timer:)) if timer == unit_state_timer ->
      unit_state_timer_fired(state:, now_ms:)
    OwnEvent(ServiceTimerFired(timer:)) if timer == refill_timer -> {
      let #(control, effects) =
        creature_control.refilled(
          state: state.control,
          armor: state.body.combat.interrupt_armor,
        )
      let state = State(..state, control:)
      #(state, Effects(carried(state:, effects:)))
    }
    OwnEvent(ServiceTimerFired(timer:)) ->
      case control_of(timer:), guard_timer(timer:), fight_timer(timer:) {
        Ok(number), _, _ -> control_ended(state:, number:, now_ms:)
        Error(Nil), Ok(timer), _ -> guard_timer_fired(state:, timer:, now_ms:)
        Error(Nil), Error(Nil), Ok(timer) ->
          fought_alone(
            state:,
            input: creature_fight.TimerFired(timer:),
            now_ms:,
          )
        Error(Nil), Error(Nil), Error(Nil) ->
          panic as "a creature starts no timer but its corpse's, its armor refill's, its fight's, its guard's and its controls'"
      }
    OwnEvent(Told(message: ModifierStarts(by:, source:, modifier:))) ->
      modifier_started(state:, by:, source:, modifier:, now_ms:)
    OwnEvent(Told(message: ModifierEnds(source:))) ->
      modifier_ended(state:, source:, now_ms:)
    OwnEvent(Told(message: Thrown(throw:))) -> thrown(state:, throw:, now_ms:)
    OwnEvent(Told(message: Despawn(delay_ms:, went_at_ms:))) ->
      despawn_told(state:, delay_ms:, went_at_ms:, now_ms:)
    OwnEvent(Told(message: UnitStates(rows:, went_at_ms:))) ->
      unit_states_told(state:, rows:, went_at_ms:, now_ms:)
    OwnEvent(Told(message: CastViewSet(by:, view:))) ->
      view_set(state:, by:, view:)
    OwnEvent(Told(message: CastViewEnds(by:, cast_id:))) ->
      view_ended(state:, by:, cast_id:)
    OwnEvent(Told(message: ControlsEnd(by:, cast_id:))) ->
      controls_ended_by(state:, by:, cast_id:, now_ms:)
    OwnEvent(Told(message: CasterGone(by:))) -> {
      let #(state, effects) = dropped_from(state:, by:, now_ms:)
      #(state, Effects(effects))
    }
    WatchEnded(watch:) if watch == run_watch -> #(state, Effects([Stop]))
    WatchEnded(..) ->
      panic as "a creature watches only its map's run: a watch that ended is not the run's"
    OwnEvent(Asked(..)) | OwnEvent(CreatureNotStarted(..)) ->
      panic as "a creature is told, and starts no creature"
  }
}

/// A ForcedMove effect throws the creature: the fight takes it as `Thrown`, unless the
/// creature lies dead or holds a state that blocks hostile effects, a server guess: a throw
/// is not applied to a creature that takes no strike.
fn thrown(
  state state: State,
  throw throw: forced_move.Throw,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  use <- bool.guard(
    when: creature_life.is_dead(life: state.life)
      || creature_unit_state.blocks_hostile(state: state.unit_state, now_ms:),
    return: #(state, Effects([])),
  )
  fought_alone(state:, input: creature_fight.Thrown(throw:), now_ms:)
}

/// A DespawnUnit effect reaches the creature (`Despawn`): dropped when the creature lies dead
/// or gone, else removed now or at the go's time
/// plus the delay, whichever due time is earlier. Server guesses: a despawn that meets a
/// corpse is dropped, and of two pending despawns the earlier due time wins; the client's
/// tables rule neither. The despawn timer is started only when none
/// runs and cancelled before it is started again, since the shell ends the process when a
/// timer id already running is started.
fn despawn_told(
  state state: State,
  delay_ms delay_ms: Int,
  went_at_ms went_at_ms: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let due_ms = went_at_ms + delay_ms
  case
    creature_life.despawned(life: state.life, body: state.body),
    state.despawn_due_ms,
    due_ms <= now_ms
  {
    None, _, _ -> #(state, Effects([]))
    Some(#(life, corpse_for_ms)), pending, True ->
      left_the_field(
        state:,
        life:,
        corpse_for_ms:,
        timer_running: option.is_some(pending),
        now_ms:,
      )
    Some(_), None, False -> #(
      State(..state, despawn_due_ms: Some(due_ms)),
      Effects([
        OwnEffect(step.StartServiceTimer(
          timer: despawn_timer,
          after_ms: due_ms - now_ms,
        )),
      ]),
    )
    Some(_), Some(pending_ms), False if due_ms >= pending_ms -> #(
      state,
      Effects([]),
    )
    Some(_), Some(_), False -> #(
      State(..state, despawn_due_ms: Some(due_ms)),
      Effects([
        OwnEffect(step.CancelServiceTimer(timer: despawn_timer)),
        OwnEffect(step.StartServiceTimer(
          timer: despawn_timer,
          after_ms: due_ms - now_ms,
        )),
      ]),
    )
  }
}

/// A go's UnitStateSet rows reach the creature (`UnitStates`): dropped when the creature lies
/// dead or gone, else each row not yet past is held,
/// told to the viewers from its start, and the timer is armed for the earliest start or end.
fn unit_states_told(
  state state: State,
  rows rows: List(unit_state.Row),
  went_at_ms went_at_ms: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  use <- bool.guard(when: creature_life.is_dead(life: state.life), return: #(
    state,
    Effects([]),
  ))
  let #(unit_state, effects) =
    creature_unit_state.set(
      state: state.unit_state,
      rows:,
      went_at_ms:,
      now_ms:,
    )
  let state = State(..state, unit_state:)
  #(state, Effects(unit_state_carried(state:, effects:)))
}

/// The unit-state timer fired: the holds whose start has come are told and the ones whose end
/// has come end, as `UnitStates` says.
fn unit_state_timer_fired(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(unit_state, effects) =
    creature_unit_state.due(state: state.unit_state, now_ms:)
  let state = State(..state, unit_state:)
  #(state, Effects(unit_state_carried(state:, effects:)))
}

/// The creature's holds are dropped when its life ends, by a death or a removal
/// (`creature_unit_state.cleared`); the effects cancel a running timer and tell no viewer.
fn unit_states_cleared(
  state state: State,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let #(unit_state, effects) =
    creature_unit_state.cleared(state: state.unit_state)
  let state = State(..state, unit_state:)
  #(state, unit_state_carried(state:, effects:))
}

/// The effects the held unit states ask for, carried out: news to every viewer and the one
/// timer.
fn unit_state_carried(
  state state: State,
  effects effects: List(creature_unit_state.Effect),
) -> List(Effect(ServiceEffect(Outgoing))) {
  list.flat_map(effects, fn(effect) {
    case effect {
      creature_unit_state.ToViewers(news:) -> to_viewers(state:, news:)
      creature_unit_state.StartTimer(after_ms:) -> [
        OwnEffect(step.StartServiceTimer(timer: unit_state_timer, after_ms:)),
      ]
      creature_unit_state.CancelTimer -> [
        OwnEffect(step.CancelServiceTimer(timer: unit_state_timer)),
      ]
    }
  })
}

/// What a viewer's first picture holds after the creature's 0x262: each unit state the
/// creature still holds.
fn unit_states_shown(state state: State, now_ms now_ms: Int) -> List(PeerNews) {
  list.map(
    creature_unit_state.shown(state: state.unit_state, now_ms:),
    fn(news) { peer_news(creature: state.settings.creature, news:) },
  )
}

/// The despawn timer fired: the creature leaves the field, as `Despawn` says. A fire the
/// creature holds no despawn for removes nothing.
fn despawn_timer_fired(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case
    state.despawn_due_ms,
    creature_life.despawned(life: state.life, body: state.body)
  {
    Some(_), Some(#(life, corpse_for_ms)) ->
      left_the_field(
        state:,
        life:,
        corpse_for_ms:,
        timer_running: False,
        now_ms:,
      )
    None, _ | _, None -> #(state, Effects([]))
  }
}

/// The creature leaves the field with `life`, no health or death news, no credit and no
/// corpse: its fight and guard end as at a kill (the fight releases its players, an open
/// opening's cast is finished), its controls and its held unit states are dropped with no
/// 0x880 and no `UnitStateEnded`, and each viewer, in the order of the connections, is sent
/// `Removed` after that. The corpse timer then runs for the kind's respawn time. A running
/// despawn timer is cancelled.
fn left_the_field(
  state state: State,
  life life: creature_life.Life,
  corpse_for_ms corpse_for_ms: Int,
  timer_running timer_running: Bool,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, unit_states) =
    unit_states_cleared(state: State(..state, life:, despawn_due_ms: None))
  let #(state, fought) =
    fought(state:, input: creature_fight.Despawned, now_ms:)
  let #(state, guarded) =
    guard_stepped(state:, input: creature_guard.Despawned, now_ms:)
  let #(control, dropped) = creature_control.died(state: state.control)
  let controlled = carried(state:, effects: dropped)
  let state = State(..state, control:)
  #(
    state,
    Effects(
      list.flatten([
        fought,
        guarded,
        controlled,
        unit_states,
        case timer_running {
          True -> [OwnEffect(step.CancelServiceTimer(timer: despawn_timer))]
          False -> []
        },
        to_viewers(state:, news: Removed),
        [
          OwnEffect(step.StartServiceTimer(
            timer: corpse_timer,
            after_ms: corpse_for_ms,
          )),
        ],
      ]),
    ),
  )
}

/// A property modifier of the caster of connection `by` starts on the creature: it is
/// applied to the creature's properties, the entries that changed go to every viewer as
/// `PropertiesChanged`, the rules that read a changed property take its new value. The same source
/// twice is held once. A start that reaches a dead creature changes nothing; nor does one
/// that reaches a creature holding a state that blocks hostile effects, a server guess as for a
/// throw (`thrown`).
fn modifier_started(
  state state: State,
  by by: ConnectionId,
  source source: Source,
  modifier modifier: Modifier,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  use <- bool.guard(
    when: creature_life.is_dead(life: state.life)
      || result.is_ok(held_changes.holder_of(held: state.held, source:))
      || creature_unit_state.blocks_hostile(state: state.unit_state, now_ms:),
    return: #(state, Effects([])),
  )
  let #(properties, changed) =
    unit_properties.apply(properties: state.properties, source:, modifier:)
  let #(held, _) =
    held_changes.started_by_connection(held: state.held, by:, source:)
  let state = State(..state, held:)
  let news = changed_news(state:, changed:)
  let #(state, revalued) = revalued(state:, properties:, now_ms:)
  #(state, Effects(list.append(news, revalued)))
}

/// The caster of connection `by` tells the creature that its cast holds `view` on it:
/// kept in place of that cast's earlier view. A dead creature keeps it, as a corpse keeps
/// its nodes. No news goes to the viewers.
fn view_set(
  state state: State,
  by by: ConnectionId,
  view view: unit_casts.CastView,
) -> #(State, ServiceStep(Outgoing)) {
  #(
    State(..state, views: dict.insert(state.views, view.cast_id, #(by, view))),
    Effects([]),
  )
}

/// The caster of connection `by` tells the creature that its cast `cast_id` holds
/// nothing on it: the view is dropped when `by` holds it. Any other end changes nothing.
fn view_ended(
  state state: State,
  by by: ConnectionId,
  cast_id cast_id: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.views, cast_id) {
    Ok(#(holder, _)) if holder == by -> #(
      State(..state, views: dict.delete(state.views, cast_id)),
      Effects([]),
    )
    Ok(_) | Error(Nil) -> #(state, Effects([]))
  }
}

/// The 0x355 for every viewer of a creature that lies dead, once for all of them; none for
/// one that was despawned, whose removal went at the despawn.
fn removed_if_shown(
  state state: State,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case creature_life.is_shown(life: state.life) {
    True -> to_viewers(state:, news: Removed)
    False -> []
  }
}

/// The creature's properties are now `properties`: its body's combat values and
/// maximum health follow them (`spawn.values_of`). A health above the new maximum
/// falls to it, with a 0x937 for the viewers; a lower maximum that is raised again
/// adds none. An Interrupt Armor maximum that changed goes to the controls, which keep
/// the armor in use and the viewers' stat 21 one value. A run speed that changed goes
/// to the fight, which runs on the path it holds at the new speed, stops it where the
/// creature stands when the speed is not above 0, and starts a chase or a walk home again
/// from where the creature stands when the speed is above 0 again. The property news is
/// the caller's.
fn revalued(
  state state: State,
  properties properties: Properties,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let values = spawn.values_of(spawn: state.settings.spawn, properties:)
  let run_speed_before = state.body.combat.attack.run_speed
  let health_before = creature_life.health(life: state.life)
  let body =
    Body(..state.body, max_health: values.max_health, combat: values.combat)
  let life =
    creature_life.clamped(life: state.life, max_health: body.max_health)
  let #(control, armor) =
    creature_control.maximum_changed(
      state: state.control,
      before: state.body.combat.interrupt_armor,
      after: body.combat.interrupt_armor,
    )
  let state = State(..state, properties:, body:, life:, control:)
  let armor = carried(state:, effects: armor)
  let health = case
    creature_life.health(life:) != health_before,
    creature_life.is_dead(life:)
  {
    True, False ->
      to_viewers(
        state:,
        news: unit_news.Health(health: creature_life.health(life:), dead: False),
      )
    _, _ -> []
  }
  let #(state, fought) = case body.combat.attack.run_speed != run_speed_before {
    True -> fought(state:, input: creature_fight.SpeedChanged, now_ms:)
    False -> #(state, [])
  }
  #(state, list.flatten([health, armor, fought]))
}

/// The property modifier of `source` ends on the creature: it is removed, the entries
/// that changed go to every viewer, and the rules take the values back. A source the
/// creature does not hold changes nothing.
fn modifier_ended(
  state state: State,
  source source: Source,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case held_changes.released(held: state.held, source:) {
    Error(Nil) -> #(state, Effects([]))
    Ok(#(held, _)) -> {
      let #(state, effects) =
        modifier_removed(state: State(..state, held:), source:, now_ms:)
      #(state, Effects(effects))
    }
  }
}

/// The modifier of `source`, already out of the ledger, taken off the creature's
/// properties: the news of what changed and the creature's values again.
fn modifier_removed(
  state state: State,
  source source: Source,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let #(properties, changed) =
    unit_properties.remove(properties: state.properties, source:)
  let news = changed_news(state:, changed:)
  let #(state, revalued) = revalued(state:, properties:, now_ms:)
  #(state, list.append(news, revalued))
}

/// What the connection `by` holds on the creature has gone: every view it told is
/// dropped, and every source of it is removed in the order they started, each as
/// `modifier_ended` removes it. The views are dropped by their holder, not by cast id: a
/// later holder of a cast id keeps its view. The one place that knows each kind of holding
/// a connection has on the creature: told by `CasterGone`, the map's one word that the
/// caster is gone.
fn dropped_from(
  state state: State,
  by by: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let state =
    State(
      ..state,
      views: dict.filter(state.views, fn(_, held) { held.0 != by }),
    )
  let #(held, sources) = held_changes.released_by(held: state.held, by:)
  let #(state, removed) =
    list.fold(sources, #(State(..state, held:), []), fn(so_far, source) {
      let #(state, done) = so_far
      let #(state, more) = modifier_removed(state:, source:, now_ms:)
      #(state, list.append(done, more))
    })
  #(state, removed)
}

/// The 0x93a of the entries a modifier's start or end changed, for every viewer;
/// none when it changed nothing.
fn changed_news(
  state state: State,
  changed changed: List(unit_properties.Changed),
) -> List(Effect(ServiceEffect(Outgoing))) {
  case changed {
    [] -> []
    _ ->
      to_viewers(
        state:,
        news: unit_news.PropertiesChanged(properties: unit_properties.entries(
          changed:,
        )),
      )
  }
}

/// A strike on the creature: refused while it walks home; else the hit rule on its
/// health, the answer first, then the health news, the corpse timer, and the fight's
/// part: a landed player's strike adds its threat, a kill ends the fight. A strike whose
/// every row failed its gate left nothing that reaches the creature: it answers a landing
/// of nothing, rolls no hit, sends no health and starts no fight. That is the server's
/// choice: neither the client nor a retail record says whether a cast whose effects all
/// fail their target gate pulls the creature. A creature that holds a state that blocks
/// hostile effects takes none of a strike's blows or states: it answers `Immune`, lands no
/// state, wears no armor, and is threatened as a guarded one is.
fn struck(
  state state: State,
  tell tell: StrikeTell,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case creature_fight.refusal(state: state.fight) {
    Error(why) -> #(
      state,
      Effects(answer_to(
        state:,
        tell:,
        answered: Answered(key: tell.key, outcome: Refused(why:)),
      )),
    )
    Ok(Nil) -> {
      // The gates are read before the hit rule, and not for a corpse, which the hit rule
      // answers `Refused(Dead)`.
      let #(tell, gates_passed) = case
        tell.gates,
        creature_life.is_dead(life: state.life)
      {
        [], _ | _, True -> #(tell, [])
        [_, ..], False -> gates_checked(state:, tell:, now_ms:)
      }
      let nothing_reached =
        tell.gates != []
        && gates_passed == []
        && tell.offence.blows == []
        && tell.controls == []
        && !creature_life.is_dead(life: state.life)
      // A creature that holds a state that blocks hostile effects takes none of the strike's
      // blows or states: the gates that passed are still carried. A strike of neither
      // (a go row of gates only) is as for any creature.
      let blocked =
        creature_unit_state.blocks_hostile(state: state.unit_state, now_ms:)
        && !creature_life.is_dead(life: state.life)
        && { tell.offence.blows != [] || tell.controls != [] }
      let reaction = case
        nothing_reached,
        blocked,
        creature_guard.guarded(state: state.guard)
      {
        True, _, _ ->
          creature_life.Reaction(
            life: state.life,
            answer: Answered(
              key: tell.key,
              outcome: strike_tell.Landed(
                descriptions: [],
                controls: [],
                armor_removed: 0,
                gates_passed: [],
              ),
            ),
            news: [],
            corpse_for_ms: None,
          )
        False, True, _ ->
          creature_life.Reaction(
            life: state.life,
            answer: Answered(
              key: tell.key,
              outcome: strike_tell.Immune(
                controls: [],
                armor_removed: 0,
                gates_passed: [],
              ),
            ),
            news: [],
            corpse_for_ms: None,
          )
        False, False, True ->
          creature_life.Reaction(
            life: state.life,
            answer: Answered(key: tell.key, outcome: case tell.offence.blows {
              [] ->
                strike_tell.Landed(
                  descriptions: [],
                  controls: [],
                  armor_removed: 0,
                  gates_passed: [],
                )
              [_, ..] ->
                strike_tell.Immune(
                  controls: [],
                  armor_removed: 0,
                  gates_passed: [],
                )
            }),
            news: [],
            corpse_for_ms: None,
          )
        False, False, False ->
          creature_life.struck(life: state.life, body: state.body, strike: tell)
      }
      // A blocked strike lands no state and wears no armor, so no control is touched.
      let #(state, answered, controlled) = case blocked {
        True -> #(state, reaction.answer, [])
        False -> controls_after(state:, tell:, reaction:, now_ms:)
      }
      let answered =
        Answered(
          key: answered.key,
          outcome: with_gates_passed(outcome: answered.outcome, gates_passed:),
        )
      // The answer goes first: the caster's connection then knows the strike
      // before it is told the health it left, one sender in one order.
      let answer = answer_to(state:, tell:, answered:)
      let news =
        list.flat_map(reaction.news, fn(news) {
          to_viewers(state:, news: viewer_news(news))
        })
      let corpse = case reaction.corpse_for_ms {
        Some(after_ms) -> [
          OwnEffect(step.StartServiceTimer(timer: corpse_timer, after_ms:)),
        ]
        None -> []
      }
      let despawn_cancelled = case
        reaction.corpse_for_ms,
        state.despawn_due_ms
      {
        Some(..), Some(..) -> [
          OwnEffect(step.CancelServiceTimer(timer: despawn_timer)),
        ]
        Some(..), None | None, _ -> []
      }
      let credit = credit_for(state:, tell:, reaction:)
      let state =
        State(
          ..state,
          life: reaction.life,
          despawn_due_ms: case reaction.corpse_for_ms {
            Some(..) -> None
            None -> state.despawn_due_ms
          },
        )
      // A strike that landed, or that the guard took no damage from, threatens the
      // creature by the descriptions it left (none for a guarded one). A strike a held
      // state blocked threatens it the same way: a server guess, since the client reads no
      // row of the type and no retail record says whether a blocked strike angers a creature.
      let landed = case nothing_reached, reaction.answer.outcome {
        True, _ -> None
        False, strike_tell.Landed(descriptions:, ..) -> Some(descriptions)
        False, strike_tell.Immune(..) -> Some([])
        False, strike_tell.Deflected(..) | False, strike_tell.Refused(..) ->
          None
      }
      let input = case landed, tell.striker, tell.from, reaction.corpse_for_ms {
        _, _, _, Some(..) -> Some(creature_fight.Killed)
        Some(descriptions),
          PlayerStriker(unit_id:, place:, seq:, stay:, hit_radius:, ..),
          Connection(by),
          None
        ->
          Some(creature_fight.StruckBy(
            by:,
            unit_id:,
            place:,
            seq:,
            stay:,
            hit_radius:,
            threat: creature_fight.threat_of(
              offence: tell.offence,
              descriptions:,
            ),
          ))
        _, _, _, None -> None
      }
      let #(state, fought) = case input {
        Some(input) -> fought(state:, input:, now_ms:)
        None -> #(state, [])
      }
      let #(state, guarded) = case reaction.corpse_for_ms {
        Some(..) -> guard_stepped(state:, input: creature_guard.Killed, now_ms:)
        None -> #(state, [])
      }
      let #(state, unit_states) = case reaction.corpse_for_ms {
        Some(..) -> unit_states_cleared(state:)
        None -> #(state, [])
      }
      #(
        state,
        Effects(
          list.flatten([
            answer,
            credit,
            news,
            despawn_cancelled,
            corpse,
            fought,
            guarded,
            controlled,
            unit_states,
          ]),
        ),
      )
    }
  }
}

/// The kill credit for the blow that killed the creature: a player's strike that left
/// a corpse sends its connection the creature's row and level, once. A creature
/// dies once per stay, so no other strike reaches a corpse.
fn credit_for(
  state state: State,
  tell tell: StrikeTell,
  reaction reaction: creature_life.Reaction,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case reaction.corpse_for_ms, strike_tell.player_sender(tell:) {
    Some(..), Ok(#(connection, stay)) -> [
      relayed(
        state:,
        to: connection,
        stay:,
        payload: relay.KillCredit(credit: Credit(
          unit_id: state.settings.creature.unit_id,
          creature_id: state.settings.spawn.creature_id,
          faction_id: Faction2Id(state.settings.spawn.faction_id),
          level: state.settings.spawn.level,
        )),
      ),
    ]
    Some(..), Error(Nil) | None, _ -> []
  }
}

/// The creature's controls after a strike and its damage: a strike with states asks
/// the controls to take them (`creature_control.land`), which land on a creature
/// the strike left alive and name the ones that did in the answer, and the fight
/// stops the creature's path when a state that stops its run lands; a strike that kills a
/// creature that holds states or worn armor drops them with no 0x880
/// (`creature_control.died`). A strike with no state that kills no such creature touches
/// no control, and its answer stands.
fn controls_after(
  state state: State,
  tell tell: StrikeTell,
  reaction reaction: creature_life.Reaction,
  now_ms now_ms: Int,
) -> #(State, Answered, List(Effect(ServiceEffect(Outgoing)))) {
  case
    tell.controls,
    reaction.corpse_for_ms,
    creature_control.holds_anything(state: state.control)
  {
    [], None, _ | [], Some(..), False -> #(state, reaction.answer, [])
    _, Some(..), _ -> {
      let #(control, dropped) = creature_control.died(state: state.control)
      #(
        State(..state, control:),
        reaction.answer,
        carried(state:, effects: dropped),
      )
    }
    [_, ..], None, _ ->
      case reaction.answer.outcome {
        strike_tell.Landed(..) | strike_tell.Immune(..) -> {
          let landing =
            creature_control.land(
              state: state.control,
              tell:,
              armor: state.body.combat.interrupt_armor,
              refill_ms: state.settings.numbers.interrupt_armor_refill_ms,
              now_ms:,
            )
          let state = State(..state, control: landing.state)
          let #(state, stopped, broke) = case landing.landed {
            [_, ..] ->
              fought_breaking(state:, input: creature_fight.Controlled, now_ms:)
            [] -> #(state, [], None)
          }
          let landed = first_marked(landed: landing.landed, broke:)
          let #(state, thrown_effects) =
            thrown_by_states(
              state:,
              outcome: reaction.answer.outcome,
              landed:,
              now_ms:,
            )
          #(
            state,
            Answered(
              key: reaction.answer.key,
              outcome: with_controls(
                outcome: reaction.answer.outcome,
                controls: landed,
                armor_removed: landing.armor_removed,
              ),
            ),
            list.flatten([
              carried(state:, effects: landing.effects),
              stopped,
              thrown_effects,
            ]),
          )
        }
        strike_tell.Deflected(..) | strike_tell.Refused(..) -> #(
          state,
          reaction.answer,
          [],
        )
      }
  }
}

/// The states a strike landed, the first marked with the cast the strike's landing broke
/// when it broke one (`strike_tell.ControlLanded.interrupted`): the caster's combat log
/// shows the interrupt once, for the first state that landed.
fn first_marked(
  landed landed: List(strike_tell.ControlLanded),
  broke broke: Option(Spell4Id),
) -> List(strike_tell.ControlLanded) {
  case landed, broke {
    [first, ..rest], Some(spell4_id) -> [
      strike_tell.ControlLanded(
        ..first,
        interrupted: Some(strike_tell.Interrupted(spell4_id:)),
      ),
      ..rest
    ]
    [], Some(..) | [_, ..], None | [], None -> landed
  }
}

/// A strike that landed throws the creature once for each Knockback, Pushback or Pull
/// state it took, as the state's helper spell moves it (`Throw`), after the state stopped
/// its run, so the flight starts where the creature stood. A guarded creature
/// (`Immune`) keeps its states and is not thrown. The creature is alive on the life this
/// strike struck, so no throw is dropped as a stale one is (`thrown`). Each landed row
/// throws once, a server guess for the spells that hold more than one state row, and a
/// delayed row throws at the landing, not after its delay.
fn thrown_by_states(
  state state: State,
  outcome outcome: strike_tell.Outcome,
  landed landed: List(strike_tell.ControlLanded),
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let throws = case outcome {
    strike_tell.Landed(..) ->
      list.filter_map(landed, fn(control) {
        option.to_result(control.tell.throw, Nil)
      })
    strike_tell.Immune(..)
    | strike_tell.Deflected(..)
    | strike_tell.Refused(..) -> []
  }
  list.fold(throws, #(state, []), fn(so_far, throw) {
    let #(state, effects) = so_far
    let #(state, more) =
      fought(state:, input: creature_fight.Thrown(throw:), now_ms:)
    #(state, list.append(effects, more))
  })
}

/// The outcome of a strike that landed or met the immunity, with the states the creature
/// took of it and the armor it lost to it.
fn with_controls(
  outcome outcome: strike_tell.Outcome,
  controls controls: List(strike_tell.ControlLanded),
  armor_removed armor_removed: Int,
) -> strike_tell.Outcome {
  case outcome {
    strike_tell.Landed(descriptions:, gates_passed:, ..) ->
      strike_tell.Landed(
        descriptions:,
        controls:,
        armor_removed:,
        gates_passed:,
      )
    strike_tell.Immune(gates_passed:, ..) ->
      strike_tell.Immune(controls:, armor_removed:, gates_passed:)
    strike_tell.Deflected(..) | strike_tell.Refused(..) -> outcome
  }
}

/// The outcome of a strike that landed, met the immunity or was deflected, naming the effect
/// ids of the gates the creature passed. A refusal passes none.
fn with_gates_passed(
  outcome outcome: strike_tell.Outcome,
  gates_passed gates_passed: List(Int),
) -> strike_tell.Outcome {
  case outcome {
    strike_tell.Landed(descriptions:, controls:, armor_removed:, ..) ->
      strike_tell.Landed(
        descriptions:,
        controls:,
        armor_removed:,
        gates_passed:,
      )
    strike_tell.Immune(controls:, armor_removed:, ..) ->
      strike_tell.Immune(controls:, armor_removed:, gates_passed:)
    strike_tell.Deflected(..) -> strike_tell.Deflected(gates_passed:)
    strike_tell.Refused(..) -> outcome
  }
}

/// The strike's gates checked against the creature's own subject
/// (`prerequisite.of_creature`: its level, factions, combat state, vitals, difficulty and
/// Creature2 row, and the caster as the second unit), in the strike's order: the strike
/// without the blows (`hit.Blow.spell4_effects_id`) and states (`ControlTell.effect_id`) of
/// the rows that did not pass, which the hit rule then sees, and the effect ids that passed.
/// A gate that reads something the subject does not hold (`prerequisite.NotRead`) does not
/// pass.
fn gates_checked(
  state state: State,
  tell tell: StrikeTell,
  now_ms now_ms: Int,
) -> #(StrikeTell, List(Int)) {
  let subject =
    prerequisite.of_creature(facts: creature_facts(state:, tell:, now_ms:))
  let #(passing, failing) =
    list.partition(tell.gates, fn(gate) {
      case prerequisite.check(prerequisite: gate.prerequisite, subject:) {
        prerequisite.Passes -> True
        prerequisite.Fails | prerequisite.NotRead(..) -> False
      }
    })
  let passed = list.map(passing, fn(gate) { gate.effect_id })
  let failed = list.map(failing, fn(gate) { gate.effect_id })
  let offence =
    hit.Offence(
      ..tell.offence,
      blows: list.filter(tell.offence.blows, fn(blow) {
        !list.contains(failed, blow.spell4_effects_id)
      }),
    )
  let controls =
    list.filter(tell.controls, fn(control) {
      !list.contains(failed, control.effect_id)
    })
  #(strike_tell.Strike(..tell, offence:, controls:), passed)
}

/// What the creature holds that its gates read, for `prerequisite.of_creature`: its level and
/// class, factions, combat state, vitals, difficulty and Creature2 row, and the two poses.
/// What the strike's caster's casts hold on it is not held (`under` is empty), and the zones it stands in are its place's own zone, without the zones above it.
fn creature_facts(
  state state: State,
  tell tell: StrikeTell,
  now_ms now_ms: Int,
) -> prerequisite.CreatureFacts {
  let spawn = state.settings.spawn
  let armor = state.body.combat.interrupt_armor
  let armor_current =
    creature_control.armor_now(state: state.control, armor:)
    |> option.unwrap(0)
    |> int.to_float
  let armor_maximum = case armor {
    creature_life.Armor(points:) -> int.to_float(points)
    creature_life.InfiniteArmor -> -1.0
    creature_life.NoArmor -> 0.0
  }
  let #(caster_unit, caster) = case tell.striker {
    PlayerStriker(unit_id:, place:, ..) -> #(
      unit_id,
      Some(area.pose_of(place:)),
    )
    CreatureStriker(..) -> #(0, None)
  }
  prerequisite.CreatureFacts(
    player: prerequisite.Player(
      race_id: 0,
      class_id: prerequisite.creature_class_id,
      level: spawn.level,
      path: 0,
      gender: 0,
      world_id: start_place.world_id(spawn.place),
      zones: [start_place.world_zone_id(spawn.place)],
    ),
    factions: prerequisite.Factions(
      current: spawn.faction_id,
      base: spawn.base_faction_id,
    ),
    in_combat: creature_fight.in_combat(state: state.fight),
    health: prerequisite.Vital(
      current: int.to_float(creature_life.health(life: state.life)),
      maximum: int.to_float(state.body.max_health),
    ),
    shield_maximum: unit_properties.value(
      properties: state.properties,
      property: unit_properties.shield_capacity_max,
    ),
    armor: prerequisite.Vital(current: armor_current, maximum: armor_maximum),
    difficulty: spawn.context.difficulty_id,
    creature_id: spawn.creature_id.value,
    under: [],
    caster_unit:,
    creature: area.pose_of(place: creature_fight.place_at(
      state: state.fight,
      now_ms:,
    )),
    caster:,
  )
}

/// The effects the creature's controls ask for, carried out: news to every viewer and
/// the control and refill timers.
fn carried(
  state state: State,
  effects effects: List(creature_control.Effect),
) -> List(Effect(ServiceEffect(Outgoing))) {
  list.flat_map(effects, fn(effect) {
    case effect {
      creature_control.ToViewers(news:) -> to_viewers(state:, news:)
      creature_control.StartTimer(control:, after_ms:) -> [
        OwnEffect(step.StartServiceTimer(
          timer: control_timer(control:),
          after_ms:,
        )),
      ]
      creature_control.CancelTimer(control:) -> [
        OwnEffect(step.CancelServiceTimer(timer: control_timer(control:))),
      ]
      creature_control.StartRefill(after_ms:) -> [
        OwnEffect(step.StartServiceTimer(timer: refill_timer, after_ms:)),
      ]
      creature_control.CancelRefill -> [
        OwnEffect(step.CancelServiceTimer(timer: refill_timer)),
      ]
    }
  })
}

/// A control's timer fired: its state ends with a 0x880, and the fight acts again
/// when it was the last one that stopped the creature's run.
fn control_ended(
  state state: State,
  number number: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  controls_ended(state:, now_ms:, ending: creature_control.ended(
    state: _,
    number:,
  ))
}

/// The connection `by` took its cast `cast_id` off the creature: each state that cast
/// landed ends with its own 0x880 and its timer is cancelled, as a timer's end ends it.
fn controls_ended_by(
  state state: State,
  by by: ConnectionId,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  controls_ended(state:, now_ms:, ending: creature_control.ended_by(
    state: _,
    caster: step.Connection(connection: by),
    cast_id:,
  ))
}

/// The controls end as `ending` ends them, and the fight acts again when that was the last
/// state that kept the creature still.
fn controls_ended(
  state state: State,
  now_ms now_ms: Int,
  ending ending: fn(creature_control.State) ->
    #(creature_control.State, List(creature_control.Effect)),
) -> #(State, ServiceStep(Outgoing)) {
  let was_still = still(state:)
  let was_held = turn_held(state:)
  let #(control, effects) = ending(state.control)
  let state = State(..state, control:)
  let #(state, resumed) = case was_still && !still(state:) {
    True -> fought(state:, input: creature_fight.ControlEnded, now_ms:)
    False -> turn_reconsidered(state:, was_held:, now_ms:)
  }
  #(state, Effects(list.append(carried(state:, effects:), resumed)))
}

/// The answer to a strike, relayed to the caster's connection through the map for the stay
/// the strike was told for: the caster's connection takes it only in that stay. A
/// strike with no player striker has no stay to answer for, and no answer: no
/// creature strikes a creature.
fn answer_to(
  state state: State,
  tell tell: StrikeTell,
  answered answered: Answered,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case strike_tell.player_sender(tell:) {
    Ok(#(connection, stay)) -> [
      relayed(state:, to: connection, stay:, payload: relay.Struck(answered:)),
    ]
    Error(Nil) -> []
  }
}

/// What a viewer's first picture holds after the creature's 0x262 of the guard: the guard's
/// cast, or the opening's; none for a creature with no guard.
fn guard_shown(state state: State, now_ms now_ms: Int) -> List(PeerNews) {
  list.map(
    creature_guard.shown(
      state: state.guard,
      unit_id: state.settings.creature.unit_id,
      place: creature_fight.place_at(state: state.fight, now_ms:),
      now_ms:,
    ),
    fn(news) { peer_news(creature: state.settings.creature, news:) },
  )
}

/// The creature's fight takes the input, and its effects are the creature's.
fn fought_alone(
  state state: State,
  input input: creature_fight.Input,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, effects) = fought(state:, input:, now_ms:)
  #(state, Effects(effects))
}

/// The fight's step and its effects carried out: news to every viewer, a tell to a
/// player for the stay the fight holds it in, the health restored with its 0x937,
/// and the fight's timers.
fn fought(
  state state: State,
  input input: creature_fight.Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let #(state, carried_out, _) = fought_breaking(state:, input:, now_ms:)
  #(state, carried_out)
}

/// The same, and the Spell4 of the charge the input broke, when it broke one.
fn fought_breaking(
  state state: State,
  input input: creature_fight.Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing))), Option(Spell4Id)) {
  let #(fight, effects) =
    creature_fight.step(
      state: state.fight,
      fighter: fighter_of(state:),
      viewers: dict.map_values(state.viewers, fn(_, viewer) { viewer.stay }),
      alive: !creature_life.is_dead(life: state.life),
      input:,
      now_ms:,
    )
  let state = State(..state, fight:)
  let was_held = turn_held(state:)
  let #(state, carried_out) =
    list.fold(effects, #(state, []), fn(so_far, effect) {
      let #(state, done) = so_far
      let #(state, more) = case effect {
        creature_fight.ToViewers(news:) -> #(state, to_viewers(state:, news:))
        creature_fight.ToPlayer(to:, stay:, told:) -> #(state, [
          relayed(state:, to:, stay:, payload: relay.Fight(told:)),
        ])
        creature_fight.RestoreHealth -> {
          let life = creature_life.new(body: state.body)
          #(
            State(..state, life:),
            to_viewers(
              state:,
              news: unit_news.Health(
                health: creature_life.health(life:),
                dead: False,
              ),
            ),
          )
        }
        creature_fight.ChargeInterrupted(cast_id:, ..) ->
          guard_stepped(
            state:,
            input: creature_guard.Interrupted(charge_cast: cast_id),
            now_ms:,
          )
        creature_fight.StartTimer(timer:, after_ms:) -> #(state, [
          OwnEffect(step.StartServiceTimer(timer: timer_id(timer:), after_ms:)),
        ])
        creature_fight.CancelTimer(timer:) -> #(state, [
          OwnEffect(step.CancelServiceTimer(timer: timer_id(timer:))),
        ])
      }
      #(state, list.append(done, more))
    })
  // An effect can open the guard (`ChargeInterrupted`) after the step chose its turn by the
  // creature as it was.
  let #(state, reconsidered) = turn_reconsidered(state:, was_held:, now_ms:)
  let broke =
    list.find_map(effects, fn(effect) {
      case effect {
        creature_fight.ChargeInterrupted(spell4_id:, ..) -> Ok(spell4_id)
        creature_fight.ToViewers(..)
        | creature_fight.ToPlayer(..)
        | creature_fight.RestoreHealth
        | creature_fight.StartTimer(..)
        | creature_fight.CancelTimer(..) -> Error(Nil)
      }
    })
    |> option.from_result
  #(state, list.append(carried_out, reconsidered), broke)
}

/// What the creature fights with: its unit and address, its spawn as home, its
/// attack, its kind's interval, and the run's numbers.
fn fighter_of(state state: State) -> Fighter {
  let creature = state.settings.creature
  Fighter(
    unit_id: creature.unit_id,
    address: step.Creature(
      map: creature.map,
      incarnation: creature.incarnation,
      unit_id: creature.unit_id,
      life: creature.life,
    ),
    can_move: creature_unit_type.can_move(
      unit_type: state.settings.spawn.unit_type,
      world_object_id: state.settings.spawn.world_object_id,
    ),
    home: state.settings.spawn.place,
    attack: state.body.combat.attack,
    alternates: state.body.combat.alternates,
    interval_ms: state.settings.kind.attack_interval_ms,
    numbers: state.settings.numbers,
    still: still(state:),
    attack_refused: attack_refused(state:),
    holds_a_state: holds_a_state(state:),
    guard_casts: creature_guard.live_casts(state: state.guard),
    hit_radius: state.body.combat.hit_radius,
    specials: state.body.combat.specials,
    turn_held: turn_held(state:),
    fights: state.body.combat.fights,
  )
}

/// Whether the creature holds a Stun, Knockdown or Knockback, or is opened: it stands as it
/// faces and does not turn to its target (`creature_fight.Fighter.turn_held`, a server's choice).
fn turn_held(state state: State) -> Bool {
  creature_control.hard_held(state: state.control)
  || creature_guard.opened(state: state.guard)
}

/// The fight turns, or stands, as it now wants when whether the creature may turn changed with
/// no other change to the fight: a state that ended while another still holds the creature, or
/// the guard that opened or closed. A change that also lets the creature run again is the
/// fight's `ControlEnded`, which turns it too.
fn turn_reconsidered(
  state state: State,
  was_held was_held: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  use <- bool.guard(when: turn_held(state:) == was_held, return: #(state, []))
  fought(state:, input: creature_fight.Reconsidered, now_ms:)
}

/// Whether the creature holds a state that stops its run, or is opened
/// (genesis_prime/world_map/creature_guard): it starts no chase or walk, and the fight
/// acts again when it stops being still.
fn still(state state: State) -> Bool {
  creature_control.stops_moving(
    state: state.control,
    stopped_by: state.body.combat.attack.run_stopped_by,
  )
  || creature_guard.opened(state: state.guard)
}

/// Whether the creature holds a state that refuses its attack's strike, or is opened: the
/// attack spell's caster conditions, and a Stun, Knockdown or Knockback whatever they say.
fn attack_refused(state state: State) -> Bool {
  creature_control.refuses(
    state: state.control,
    mask: state.body.combat.attack.caster_cc_mask,
  )
  || creature_control.hard_held(state: state.control)
  || creature_guard.opened(state: state.guard)
}

/// Whether the creature holds any state, or is opened: it starts no charge.
fn holds_a_state(state state: State) -> Bool {
  creature_control.holds(state: state.control)
  || creature_guard.opened(state: state.guard)
}

/// The guard takes the input: its effects carried out, news to every viewer and its timer.
fn guard_stepped(
  state state: State,
  input input: creature_guard.Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let #(guard, effects) =
    creature_guard.step(
      state: state.guard,
      unit_id: state.settings.creature.unit_id,
      live: creature_fight.live_casts(state: state.fight),
      place: creature_fight.place_at(state: state.fight, now_ms:),
      input:,
      now_ms:,
    )
  let state = State(..state, guard:)
  #(
    state,
    list.flat_map(effects, fn(effect) {
      case effect {
        creature_guard.ToViewers(news:) -> to_viewers(state:, news:)
        creature_guard.StartTimer(timer:, after_ms:) -> [
          OwnEffect(step.StartServiceTimer(
            timer: guard_timer_id(timer:),
            after_ms:,
          )),
        ]
        creature_guard.CancelTimer(timer:) -> [
          OwnEffect(step.CancelServiceTimer(timer: guard_timer_id(timer:))),
        ]
      }
    }),
  )
}

/// The opening's timer fired: the guard comes back, and the fight acts again when that was the
/// last thing that kept the creature still.
fn guard_timer_fired(
  state state: State,
  timer timer: creature_guard.Timer,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let was_still = still(state:)
  let was_held = turn_held(state:)
  let #(state, effects) =
    guard_stepped(state:, input: creature_guard.TimerFired(timer:), now_ms:)
  let #(state, resumed) = case was_still && !still(state:) {
    True -> fought(state:, input: creature_fight.ControlEnded, now_ms:)
    False -> turn_reconsidered(state:, was_held:, now_ms:)
  }
  #(state, Effects(list.append(effects, resumed)))
}

/// The timer id of a fight timer: a multiple of 7 and 1, 2, 3 and 6 above it for the attack
/// tick, the walk home, the strike deadline, the cast end and the flight's end, by
/// generation (from 1), so none is the corpse timer's 1 or the refill timer's 2 and a timer of
/// an old generation is never the new one's. The ids 4 above a multiple of 7 are the controls'
/// (11, 18, 25 ...: `control_timer`) and 5 above it the guard's (12, 19, 26 ...:
/// `guard_timer_id`), so no two timers of a creature share an id. The chase's arrival, which has
/// no generation, is `chase_arrival_timer`.
fn timer_id(timer timer: creature_fight.Timer) -> step.TimerId {
  case timer {
    AttackTick(generation:) -> TimerId(7 * generation)
    HomeArrival(generation:) -> TimerId(7 * generation + 1)
    StrikeDeadline(generation:) -> TimerId(7 * generation + 2)
    CastEnds(generation:) -> TimerId(7 * generation + 3)
    FlightEnds(generation:) -> TimerId(7 * generation + 6)
    ChaseArrival -> chase_arrival_timer
  }
}

/// The timer id of the control numbered `control`: 4 above 7 times it, from 11 (11, 18, 25
/// ...), so none is the corpse timer's 1, the refill timer's 2, a fight timer's or a guard's.
fn control_timer(control control: Int) -> step.TimerId {
  TimerId(7 * control + 4)
}

/// The timer id of a guard timer: 5 above 7 times its generation, from 12 (12, 19, 26 ...).
fn guard_timer_id(timer timer: creature_guard.Timer) -> step.TimerId {
  let creature_guard.OpeningEnds(generation:) = timer
  TimerId(7 * generation + 5)
}

/// The number of the control a timer id is for, or `Error(Nil)` for one that is not a
/// control's: the corpse timer's 1, the refill timer's 2, a fight timer, a guard timer or any
/// other. For a test.
pub fn control_of(timer timer: step.TimerId) -> Result(Int, Nil) {
  let TimerId(number) = timer
  case number >= 11 && number % 7 == 4 {
    True -> Ok({ number - 4 } / 7)
    False -> Error(Nil)
  }
}

/// Whether a timer id is a creature's strike deadline (`StrikeDeadline`): 2 above a
/// multiple of 7, from generation 1. The number alone tells it: another service's timer can
/// carry the same number (the map's restart timer of a spawn is the spawn's number), so
/// the caller tells the creature's by the process that armed it. For a tool that watches
/// the deadlines.
pub fn is_strike_deadline(timer timer: step.TimerId) -> Bool {
  case fight_timer(timer:) {
    Ok(StrikeDeadline(..)) -> True
    Ok(AttackTick(..))
    | Ok(HomeArrival(..))
    | Ok(CastEnds(..))
    | Ok(FlightEnds(..))
    | Ok(ChaseArrival)
    | Error(Nil) -> False
  }
}

/// The guard timer of a timer id, or `Error(Nil)` for one the guard never starts.
fn guard_timer(timer timer: step.TimerId) -> Result(creature_guard.Timer, Nil) {
  let TimerId(number) = timer
  case number >= 12 && number % 7 == 5 {
    True -> Ok(creature_guard.OpeningEnds(generation: { number - 5 } / 7))
    False -> Error(Nil)
  }
}

/// The fight timer of a timer id, or `Error(Nil)` for one the fight never starts: the
/// corpse timer's, the refill timer's, a control's, a guard's, or any other.
fn fight_timer(timer timer: step.TimerId) -> Result(creature_fight.Timer, Nil) {
  let TimerId(number) = timer
  use <- bool.guard(
    when: timer == chase_arrival_timer,
    return: Ok(ChaseArrival),
  )
  case number >= 7, number % 7 {
    True, 0 -> Ok(AttackTick(generation: number / 7))
    True, 1 -> Ok(HomeArrival(generation: { number - 1 } / 7))
    True, 2 -> Ok(StrikeDeadline(generation: { number - 2 } / 7))
    True, 3 -> Ok(CastEnds(generation: { number - 3 } / 7))
    True, 6 -> Ok(FlightEnds(generation: { number - 6 } / 7))
    _, _ -> Error(Nil)
  }
}

/// What a viewer's connection writes of a news of the creature's health.
fn viewer_news(news: creature_life.News) -> unit_news.News {
  case news {
    Health(health:, dead:) -> unit_news.Health(health:, dead:)
    Died -> unit_news.Died
  }
}

/// The creature's 0x262, stamped with the map's time, at its current health and where it
/// stands now: at its spawn, on its path, or where it fell.
fn appeared(state state: State, now_ms now_ms: Int) -> PeerNews {
  let creature = state.settings.creature
  let place = creature_fight.place_at(state: state.fight, now_ms:)
  peer_news(
    creature:,
    news: CreatureAppeared(
      spawn_id: state.settings.spawn.id,
      unit: creature_unit.with_casts(
        unit: creature_unit.overlaid(
          unit: creature_unit.create(
            spawn: Spawn(..state.settings.spawn, place:),
            unit_id: creature.unit_id,
            health: creature_life.health(life: state.life),
            interrupt_armor: creature_control.armor_now(
              state: state.control,
              armor: state.body.combat.interrupt_armor,
            ),
            server_time_estimate_start: map.server_time(
              origin_ms: creature.clock_origin_ms,
              monotonic_ms: now_ms,
            ),
          ),
          properties: state.properties,
        ),
        casts: unit_casts.entries_of(
          views: list.map(dict.values(state.views), pair.second),
          now_ms:,
        ),
      ),
      life: creature.life,
      place:,
      unit_type: state.settings.spawn.unit_type,
      hit_radius: state.body.combat.hit_radius,
      attackable: state.body.combat.attackable,
      hostile_to: state.body.combat.hostile_to,
      fights: state.body.combat.fights,
    ),
  )
}

/// News about the creature's own unit for every viewer, once: one broadcast to its map,
/// which relays it to each viewer it holds as relaying. None when the creature has no
/// viewer.
fn to_viewers(
  state state: State,
  news news: unit_news.News,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case dict.is_empty(state.viewers) {
    True -> []
    False -> {
      let creature = state.settings.creature
      [
        to_the_map(
          state:,
          message: Broadcast(
            unit_id: creature.unit_id,
            life: creature.life,
            news: peer_news(creature:, news:),
          ),
        ),
      ]
    }
  }
}

/// News about the creature's own unit.
fn peer_news(
  creature creature: CreatureStart,
  news news: unit_news.News,
) -> PeerNews {
  PeerNews(unit_id: creature.unit_id, news:)
}

/// A tell to one player through the creature's map, for the player's stay.
fn relayed(
  state state: State,
  to to: ConnectionId,
  stay stay: Stay,
  payload payload: relay.Payload,
) -> Effect(ServiceEffect(Outgoing)) {
  let creature = state.settings.creature
  to_the_map(
    state:,
    message: Relay(
      unit_id: creature.unit_id,
      life: creature.life,
      to:,
      stay:,
      payload:,
    ),
  )
}

/// A send to the creature's map: the only address the creature sends to.
fn to_the_map(
  state state: State,
  message message: Outgoing,
) -> Effect(ServiceEffect(Outgoing)) {
  let creature = state.settings.creature
  OwnEffect(Send(
    to: step.Map(map: creature.map, incarnation: creature.incarnation),
    message:,
  ))
}

/// What the map's `Outgoing` means to a creature: `Seen` and `Unseen`,
/// each by the connection whose player sees or stops seeing it, `Approached` and
/// `Withdrew`, by the connection whose ready player entered or left its ring,
/// `PlayerDied`, by the connection whose player died, `Retire`, and the tells of a
/// player (`ToldCreature`), each as the message of its kind with the sender and the stay
/// the map names. Any other is no message to a creature, and `Error(Nil)`.
pub fn told_by_map(outgoing outgoing: map.Outgoing) -> Result(Message, Nil) {
  case outgoing {
    map.Seen(by:, stay:, generation:) -> Ok(Seen(by:, stay:, generation:))
    map.Unseen(by:, generation:) -> Ok(Unseen(by:, generation:))
    map.Approached(member:) -> Ok(Approached(member:))
    map.Withdrew(by:) -> Ok(Withdrew(by:))
    map.PlayerDied(by:) -> Ok(PlayerDied(by:))
    map.Retire -> Ok(Retire)
    map.CasterGone(by:) -> Ok(CasterGone(by:))
    map.ToldCreature(by:, stay:, payload:) ->
      Ok(told_by_a_player(by:, stay:, payload:))
    map.Joined(..)
    | map.NotJoined(..)
    | map.Summoned(..)
    | map.NotSummoned(..)
    | map.Left
    | map.Relayed(..)
    | map.Noticed(..) -> Error(Nil)
  }
}

/// What a player's tell, as the map passed it on, means to a creature: the message of
/// that kind, with the sender and the stay the map named.
fn told_by_a_player(
  by by: ConnectionId,
  stay stay: Stay,
  payload payload: relay.Inbound,
) -> Message {
  case payload {
    relay.Strike(tell:) -> Strike(tell:)
    relay.TargetMoved(place:, seq:, hit_radius:) ->
      TargetMoved(by:, place:, seq:, stay:, hit_radius:)
    relay.StrikeAnswered(answered:) -> StrikeAnswered(answered:)
    relay.ModifierStarts(source:, modifier:) ->
      ModifierStarts(by:, source:, modifier:)
    relay.ModifierEnds(source:) -> ModifierEnds(source:)
    relay.Thrown(throw:) -> Thrown(throw:)
    relay.Despawn(delay_ms:, went_at_ms:) -> Despawn(delay_ms:, went_at_ms:)
    relay.UnitStates(rows:, went_at_ms:) -> UnitStates(rows:, went_at_ms:)
    relay.CastViewSet(view:) -> CastViewSet(by:, view:)
    relay.CastViewEnds(cast_id:) -> CastViewEnds(by:, cast_id:)
    relay.ControlsEnd(cast_id:) -> ControlsEnd(by:, cast_id:)
  }
}

/// What a creature's `Outgoing` means to its map: `Snapshot`, `Broadcast`, `Relay` and
/// `Expired`, each as the map's message of the same name.
pub fn told_to_map(outgoing outgoing: Outgoing) -> map.Message {
  case outgoing {
    Snapshot(unit_id:, life:, by:, generation:, burst:) ->
      map.Snapshot(unit_id:, life:, by:, generation:, burst:)
    Broadcast(unit_id:, life:, news:) -> map.Broadcast(unit_id:, life:, news:)
    Relay(unit_id:, life:, to:, stay:, payload:) ->
      map.Relay(unit_id:, life:, to:, stay:, payload:)
    Expired(unit_id:, life:) -> map.Expired(unit_id:, life:)
  }
}

/// What a creature holds and does for a strike that the client's rows ask more of.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Creature crowd control",
      missing: "the timing of a crowd-control state's throw: each landed row throws once, a server guess for a spell that holds more than one state row, and a delayed row throws at the landing, not after its delay",
    ),
    gap.Entry(
      area: "Creature prerequisites",
      missing: "the casts the strike's caster holds on a creature and the zones above the creature's place, which a prerequisite on the creature reads as none",
    ),
  ]
}
