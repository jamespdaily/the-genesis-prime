//// One map: a world of the client's World table and one instance of it, with
//// the players and the creatures in it. It builds the unit of each player that
//// joins, with the next unit id, the body of the character's look and the Novice set it wears, keeps it,
//// and forgets the player and its unit when the player's connection ends. It has
//// a creature started at a spawn of its world when a player first sees the spawn
//// and stopped after no player has seen it for the idle stop, and watches it. It
//// owns who sees whom: a player and another player, or a player
//// and a creature, see each other when they are within
//// `genesis_prime/shared/sight.range`; two creatures never do. It decides
//// sight and tells it; it sends the client no unit and carries no move. Each
//// player's connection sends everything about its own unit to the connections of
//// the players who see it (genesis_prime/game/connection), and each creature's
//// process everything about its own unit (genesis_prime/world_map/creature), so
//// the work of a move is spread over the movers' processes, and the map's is one
//// sight check per other player and creature.
////
//// This is the rule of a map's service shell (genesis_prime/service/shell),
//// started without a name by the map supervisor when Maps is first asked for
//// it (genesis_prime/world_map/registry). Its players and their units live only
//// in the process: a restart loses them, and each player's connection, which
//// watches its map, ends (genesis_prime/game/connection).
////
//// Join, from the map's side, and what the players in sight are told:
////
//// ```
//// connection c1                      map                                      shell
////   Join(c1, character, place, stay, alive, hidden) ─▶ Asked ─▶ loadout of its class and faction
////                                          a c1 that is in the map already is removed as a Leave
////                                            removes it (its creatures told `Unseen` and
////                                            `CasterGone` of its old address), then joins as below
////                                          unit id u = next unit id; next + 1
////                                          address a1 = the next address of this run (`issue_address`)
////                                          unit = the character at place as unit u,
////                                                 with the body visuals of its look and its loadout
////                                          player = (c1, stay, a1, unit, watch w1, sees, hidden);
////                                          a1 is indexed to c1 (`by_address`)
////                                          Watch(w1, Connection(c1))           ─▶ monitors c1
////   ◀─ Joined(0x262's record of unit, loadout, a1, run, the map's clock origin)
////                                ◀─ OwnEffect(Reply(caller, Joined(..)))
////   ◀─ NotJoined(reason)         when the class and faction have no Novice set:
////                                    no unit id is given, no player kept, no watch opened
////                                          for each player c2 in sight, in the same step:
////   ◀─ Noticed(c1's stay, SeenBy(c2, c2's stay, c2's unit id, g(c2 sees c1)))                ─▶ send to c1
////                                          Noticed(c2's stay, SeenBy(c1, c1's stay, c1's unit id, g(c1 sees c2))) ─▶ send to c2
//// ```
////
//// Leave, from the map's side, for a player whose connection goes on after its
//// camp (genesis_prime/game/camp):
////
//// ```
//// connection c1                      map                                      shell
////   Leave(c1)                  ─▶ Asked ─▶ player of c1 removed with its unit
////                                          its watch w1 forgotten
////                                          Unwatch(w1)                         ─▶ drops the watch on c1
////                                          to each player c2 who saw c1:
////                                          UnseenBy(c1, g(c1 sees c2)), for c2's stay ─▶ sends to c2
////   ◀─ Left                    ◀─ OwnEffect(Reply(caller, Left))
//// ```
////
//// A visibility change, a tell with no answer: the connection's end-of-step check
//// (genesis_prime/game/connection/visibility_check) found that the visibility
//// prerequisites failing for its player are now a different set, and the map shows
//// or hides the units that set names, in the player's sight, with the same unit ids:
////
//// ```
//// connection c1                      map                                      shell
////   VisibilityChanged(c1, hidden) ─▶ Told ─▶ player of c1 holds hidden already: nothing
////                                          for each object and spawn in c1's sight whose
////                                          visibility prerequisite left the set (shown):
////                                            ObjectsSeen(its spawn, its 0x262) ─▶ send to c1
////                                            Seen(c1, g) to its creature     ─▶ (a creature is started
////                                                                               if none lives)
////                                          for each whose prerequisite entered the set (hidden):
////                                            ObjectsUnseen(its unit id)      ─▶ send to c1
////                                            Unseen(c1, g) to its creature, the unit's 0x355 to c1,
////                                            and Withdrew if c1 stood in its ring
////                                          units out of c1's sight: nothing sent
//// ```
////
//// A static object or a spawn with no visibility prerequisite (0), or one the server
//// does not read (`Verdict.NotRead`), is never hidden: only a prerequisite that
//// `Fails` for the player is in `hidden`.
////
//// A move, a tell with no answer, which decides sight only:
////
//// ```
//// connection B                       map                                      connection A
////   Moved(B, place)            ─▶ Told ─▶ B's unit at place; each pair decided on that place:
////                                         in sight before and after: nothing
////                                         into sight, in one step:
////                                           SeenBy(A, g) ─▶ B        SeenBy(B, g') ─▶ A
////                                         out of sight, in one step:
////                                           UnseenBy(A, g) ─▶ B      UnseenBy(B, g') ─▶ A
//// A connection's end (its watch's DOWN)   ─▶ to each player c2 who saw it: UnseenBy(it, g)
////                                           to every player in the map: Gone(its unit)
//// (every notice to a player's connection goes as Noticed(its stay, notice))
//// ```
////
//// The relation of one player with another, kept once, in the viewer's `Player.sees` under
//// the owner's connection (`Relation`), with the generation of the sight the viewer has of the
//// owner, as the creature's is; the owner finds its viewers among its own `sees`, whose
//// sights are symmetric. A pair that comes into sight begins it awaiting the owner's
//// snapshot; the owner's news is relayed only through a relation that relays, in the order
//// the map takes it; the pair that leaves sight ends it by `PlayerUnseen`, whether or not
//// the viewer took the snapshot. The owner's moves are not news: the owner tells its viewers
//// itself, stamped with the generation (`genesis_prime/game/move_stamp`), and the map only
//// decides sight from the place a move ends at.
////
//// ```
//// owner's connection C                map                                        viewer's connection V
////   SeenBy(V, stay, unit, g) ◀──── pair comes into sight: g new; (V, g) AwaitingSnapshot
////   PlayerSnapshot(C, V, g, burst) ─▶ (V, g) awaited, V in its stay: Relayed(stay, News(item)) ─▶ V
////                                     for each item, in order; (V, g) Relaying
////   PlayerBroadcast(C, news) ───────▶ Relayed(stay, News(news)) to each Relaying viewer, in
////                                     connection order; none to an awaiting or departed one
////   TellLanding(C, T, landing) ─────▶ the kind's checks (`relay.landing_kind_of`); Relayed(stay,
////                                     Landed(landing)) ─▶ T
////   Say(C, line) ───────────────────▶ Relayed(stay, Said(line)) to each Relaying viewer, in
////                                     connection order
////   the pair leaves sight ──────────▶ UnseenBy(V, g) ─▶ C   and   PlayerUnseen(unit, g) ─▶ V;
////                                     the relation is dropped, and a snapshot of g is dropped
//// ```
////
//// - A local chat line is relayed as a broadcast is: to the viewers whose relation relays,
////   for each viewer's stay, so a line that reaches a viewer after it camped and entered
////   again is dropped by the stay fence of its connection.
////
//// The map's start, from the map's side, and the creatures a player's sight starts
//// and stops. A spawn that no player sees has no process and no state, only its unit
//// id when it has had one: it is dormant.
////
//// ```
//// supervisor                map                                         shell
////   starts the map ─▶ Started ─▶ the sweep timer TimerId(0), every sweep_ms
////                                 (no creature starts)
//// Join / Moved: the spawns the player sees now (spawn_cell.near, then exact sight)
////   a dormant spawn, seen now:   unit id u = the spawn's own, else next unit id
////                                 life w = next watch
////                                 StartCreature(w, spawn, u, life w, viewers [c]) ─▶ the creature supervisor starts it;
////                                                                       the shell watches Creature(map, run, u, w) as w;
////                                                                       the creature answers c with its snapshot as it starts
////   a live spawn, seen now:      Seen(by: c, c's stay, a new generation) ─▶ Creature(.., u, w); idle ends;
////                                 the creature answers with its snapshot
////   a live spawn, no longer:     Unseen(by: c, g) ─▶ Creature(.., u, w), and c is sent the notice that the
////                                 unit is unseen, which writes c's 0x355
////                                 the last viewer gone: idle since now
////   a retiring or respawning spawn, seen now:
////                                nothing is sent, nothing starts: c is found among the seers at its end
//// the sweep fires ─▶ for each live spawn idle for idle_stop_ms or more:
////                                 Send(Creature(.., u, w), Retire)     the spawn is retiring
////                                 StartServiceTimer(TimerId(0), sweep_ms)
//// WatchEnded(w) of a retiring creature (or one that crashed while retiring)
////                              ─▶ dormant, with u kept; no Gone: the 0x355s went when its viewers did
////                                 players who see the spawn now: StartCreature(u, life w', viewers them)
//// Expired(u, w) of a live creature (its corpse timer; it sent every viewer its 0x355 already)
////                              ─▶ the spawn is Respawning(u, w): its relations end, no one is sent anything
//// WatchEnded(w) of a Respawning creature (it stopped after Expired)
////                              ─▶ players who see the spawn now: StartCreature(u, life w', viewers them, ring)
////                                 fresh relations, AwaitingSnapshot under generations never given before;
////                                 ring: each ready, living, unstealthed player in the spawn's ring (`ring_of`),
////                                 so the new creature aggroes them in one step and gets no Approached;
////                                 none see it now: dormant, with u kept
//// WatchEnded(w) of a live creature (a crash)
////                              ─▶ Gone(u) to every player in the map (the creature that ended sent nothing)
////                                 StartServiceTimer(the spawn's number, its kind's respawn time); u is given up
//// the spawn's timer fires      ─▶ players see the spawn now: a new unit id, a creature as for a dormant spawn
////                                 none: dormant
//// CreatureNotStarted(w)        ─▶ error line; the spawn stays empty for the run (after a respawn's
////                                 removal too: the viewers saw it removed and see no new unit)
//// ```
////
//// A creature that lay dead until its corpse timer and the next life the map starts, in the
//// order the map takes them (the creature's sends and its end are one sender's, in order):
////
//// ```
//// creature (dead, corpse timer fires)          map                                    next life
////   Broadcast(Removed)  ─▶ relayed to each Relaying viewer (none for a despawned creature)
////   Expired(unit, life) ─▶ Live ─▶ Respawning(unit, life): relations end (no Unseen, no Gone)
////   Stop                    WatchEnded(life) ─▶ Respawning: players_seeing ─▶ start_creature:
////                             fresh relations (g', new life, AwaitingSnapshot), ring = ring_of(inside now)
////                             StartCreature(viewers (c, stay, g'), ring) ─────────▶ Started: Watch(run),
////                                                                                   Snapshot(c, g', burst) for each
////                                                                                   viewer, then one aggro over the
////                                                                                   ring players who are viewers
////                           Snapshot relayed in order; later Broadcast relayed ◀────
//// ```
////
//// A creature told `Retire` while dead stops at its corpse timer with no `Expired`: its
//// spawn is `Retiring`, and its end restarts the spawn as for any retire. A creature that
//// stops with its run, or a run-only creature at its corpse timer, sends no `Expired`.
////
//// A use releases a unit, a tell with no answer: the connection's count of the use
//// counted a unit new to an objective that counts each unit once, and the map ends the
//// creature of the unit and the creatures at its x and z through the stop path of
//// an idle one, then keeps the spawns waiting for the release time:
////
//// ```
//// connection c1                 map                                         creature
////   a use counted a unit new to an objective (genesis_prime/game/objective `ReleaseUnit`)
////   Released(u)               ─▶ Told ─▶ u is a live creature's unit, spawn s:
////                                         s and each spawn in `spawn.captives` of s, live:
////                                           s becomes Releasing(u, life, release time)
////                                           Send(Creature(.., u, life), Retire) ─────▶ Stop
////                                         s or a captive Respawning (its creature expired and stops by
////                                         itself): Releasing(u, life, release time) with no relations,
////                                         and no Retire
////                                         s a static object, not yet released: it joins `released_objects`;
////                                         each player's objects are decided again (ObjectsUnseen of s's unit
////                                         to those who saw it); StartServiceTimer(s's number, the release time)
////                                         u is no live creature's and no unreleased object's unit (a second
////                                         release, or a unit the map does not hold): nothing
////                                         a static object in `spawn.captives` of s: the same as s
//// WatchEnded(life) of a Releasing creature
////                              ─▶ Gone(u) to every player in the map; u is given up
////                                 s becomes WaitingForRestart; StartServiceTimer(s's number, the release time)
//// a released object's timer   ─▶ the spawn leaves `released_objects`; each player's objects are decided
////                                 again (ObjectsSeen of the unit, under its first id, to those in sight)
//// the spawn's timer fires      ─▶ restart_due: players see the spawn now: a new unit id, a creature
////                                 as for a dormant spawn; none: dormant
//// the new creature dies        ─▶ its kind's respawn time, as every creature's: the release time is
////                                 spent with the one restart
//// a map that restarts          ─▶ rebuilt from storage: every spawn starts at once, the release is lost
//// ```
////
//// The release time runs from the moment the unit leaves sight: at the release for a static
//// object, at the end of the creature's process for a live creature, and, for a creature
//// already dead, after its corpse timer. A creature already retiring ignores a release.
////
//// The rings: which ready players stand within a hostile creature's aggro range, so
//// the creature can fight them (genesis_prime/world_map/creature_fight). Decided on
//// each `Moved` beside the spawns in sight:
////
//// ```
//// connection c                  map                                          creature
////   Ready(c) (its first 0xF2) ─▶ c ready; for each Live spawn whose ring holds c,
////                                hostile to c's faction:
////                                  Approached(c, unit, place, seq) ─────────▶ may aggro
////   Moved(c, place, seq)      ─▶ c's seq kept; c ready: the rings it stands in now
////                                (spawn_cell.near, aggro_range, then exact 3D
////                                distance to the spawn's place), hostile spawns only
////                                  entered, Live: Approached(c, unit, place, seq) ─▶
////                                  left, Live:    Withdrew(c) ──────────────────▶
////                                  inside before and after, or outside: nothing
//// a creature starts             each ready, unstealthed, living player in its ring:
////                               Approached, after the start effects; a respawn's start carries
////                               them as `CreatureStart.ring` instead, and no Approached follows
////
//// connection c                  map                                          creature
////   StealthChanged(c, s)      ─▶ Told ─▶ c not in the map: error line, nothing changes
////                                         s as held: nothing
////                                         else c's stealth = s; c still loading: nothing more
////                                         c ready, s True: the rings it stands in are now none:
////                                           Withdrew(c), each Live spawn it was in, in spawn
////                                           order ─────────────────────────▶ near without c;
////                                                                            threat list kept
////                                         c ready, s False: the rings it stands in now:
////                                           Approached(c, unit, place, seq, stay), each Live
////                                           spawn, in spawn order ─────────▶ may aggro, as a walk-in
//// ```
////
//// Where a stealthed player's rings are decided, in order (the connection tells
//// `Moved`, `Ready` and `StealthChanged` from one process, so the map takes them in
//// the order the connection decided them):
////
//// ```
//// StealthChanged(c, True), then Moved into a ring   ─▶ no Approached: c stands in no ring
//// Moved into a ring, then StealthChanged(c, True)   ─▶ Approached, then Withdrew: the creature
////                                                      aggroed c first and keeps c on its threat list
//// StealthChanged(c, True), then Ready(c)            ─▶ nothing at Ready; leaving stealth then
////                                                      sends Approached to each ring c stands in
//// a creature starts, restarts or respawns, or a summon starts, with c stealthed in its ring
////                                                   ─▶ no Approached, and c is not in the start's ring:
////                                                      `inside` holds no ring for c
//// ```
////
//// connection c                  map                                          creature
////   LifeChanged(c, a)         ─▶ Told ─▶ c not in the map: error line, nothing changes
////                                         a as held: nothing
////                                         a False: c's life = Dead, `inside` emptied, no Withdrew:
////                                           PlayerDied(c), each Live spawn in c's `seen`, in
////                                           spawn order, whether or not c stood in its ring
////                                           ─────────────────────────────▶ c out of near and
////                                                                          the threat list
////                                         a True: c's life = Alive; c still loading: nothing more
////                                           (Ready decides); c ready: the rings it stands in now:
////                                           Approached(c, unit, place, seq, stay), each Live
////                                           spawn, in spawn order ─────────▶ may aggro, as a walk-in
////
//// Where a dead player's rings are decided, in order (the connection tells `Join`, `Moved`,
//// `Ready`, `StealthChanged` and `LifeChanged` from one process, and tells `LifeChanged(c, False)`
//// before the `StealthChanged(c, False)` that ends a stealthed player's casts at its death):
////
//// ```
//// LifeChanged(c, False), then Moved into a ring     ─▶ no Approached: c stands in no ring
//// Moved into a ring, then LifeChanged(c, False)     ─▶ Approached, then PlayerDied: the creature
////                                                      aggroed c, then drops c from near and its list
//// LifeChanged(c, False), then StealthChanged(c, s)  ─▶ nothing: c is in no ring either way
//// Join(.., alive: False), Ready(c)                  ─▶ nothing at Ready; LifeChanged(c, True) then
////                                                      sends Approached to each ring c stands in
//// a creature starts, restarts or respawns, or a summon starts, with c dead in its ring
////                                                   ─▶ no Approached, and c is not in the start's ring:
////                                                      `inside` holds no ring for c
//// ```
////
//// - **A player is not ready until its client's first 0xF2 of the stay**
////   (`opcode.0xf2`), so no creature fights a loading player.
//// - **A ring** is a circle of `aggro_range` about the spawn's place, not the
////   creature's: a creature that runs keeps its spawn's ring and its spawn's sight.
////   The aggro range lies inside sight (genesis_prime/world_map/game_number), so a
////   player in a ring sees the creature, and its creature is Live or about to start.
//// - **Hostile** is a faction level of 0 to 2 toward the player's faction, worked out
////   at load (genesis_prime/world_map/creature_life `Hostile`); a Neutral or Friendly
////   creature has no ring.
//// - **Only Live creatures are told.** A retiring, respawning, waiting or failed spawn's ring is
////   kept in `inside` and told when its creature starts: a respawn's in `CreatureStart.ring`,
////   read at the step that takes the creature's end (`ring_of`), so the creature aggroes every
////   player of it in one step.
//// - **A stealthed player stands in no ring** (server choice, `StealthChanged`; the
////   client holds no rule, `UnitProperty2.stealth_detection`). A creature is told
////   `Withdrew` when the player enters stealth and `Approached` when it leaves
////   stealth inside the ring, and a creature that is fighting the player keeps it on
////   its threat list, since `Withdrew` touches only the creature's `near`
////   (genesis_prime/world_map/creature_fight). A player's stealth is the connection's
////   to decide; the map holds a copy, told one way and in the connection's order.
//// - **A dead player stands in no ring and is told of to every creature it sees** (server
////   choice, `LifeChanged`; the client holds no creature rule, and a dead unit is struck
////   by nothing, `Spell4ValidTargets.targetBitmask`). The map sends `PlayerDied` to each
////   Live spawn in the player's `seen`, not only the rings it stood in, since a creature
////   that chased the player out of its ring, or whose `Threatened` was dropped by the dead
////   player, may still hold it (genesis_prime/world_map/creature_fight: a threat list is
////   within the viewers, and a viewer sees the spawn). A player that wakes inside a ring is
////   told to its creatures as `Approached`, as a walk-in or a stealth exit is. A player
////   that joins dead (`Join` with `alive` False: its saved health is 0,
////   genesis_prime/game/player_life `entering`) is in no ring until it wakes. The
////   Holocrypt sends `Leave`, then a `Join` with `alive` True, and no `LifeChanged`.
//// - **A `LifeChanged` from a connection not in the map** changes nothing and is logged as
////   an error, as for a `Moved`; one of a value the map already holds sends nothing.
//// - **When a life tell is late, out of order or lost to a death:**
////   - A `LifeChanged` is decided on the state the connection had when it sent it, and
////     cannot cross a `Join`, `Moved`, `Ready` or `StealthChanged` of the same connection.
////   - A creature's home timer that fires before the `PlayerDied` reaches it aggroes the
////     body: the death tell is one hop behind. The strike is refused `Dead`, which releases
////     the player and drops it from `near` (genesis_prime/world_map/creature_fight).
////   - A death the map takes before it starts a creature's next life leaves the player out of
////     the start's ring, so the body is not aggroed; one it takes after the start reaches the
////     new life as `PlayerDied` and drops the player. A wake before the start puts the player in
////     the ring, which aggroes it on waking, and after the start it is an `Approached`
////     (`a_death_a_stealth_or_a_wake_decides_the_new_lifes_ring_by_whether_the_map_took_it_before_the_start_test`).
////   - A `PlayerDied` or `Approached` for a creature that died before it is dropped; the
////     spawn keeps `inside`, which holds no dead player, and `ring_of` reads it at the
////     creature's next start.
////   - A `PlayerDied` that reaches a creature after the player's `Unseen` finds the player
////     in neither `near` nor the threat list: nothing.
////   - A player whose connection ends while dead is removed as any player is: its creatures
////     are sent `Unseen`, and no `PlayerDied` follows.
////   - A map that dies ends every connection in it; no life copy outlives it.
//// - **A `StealthChanged` from a connection not in the map** changes nothing and is
////   logged as an error, as for a `Moved`; one of a value the map already holds sends
////   nothing. A player that left and joined again starts `NotStealthed`: its camp
////   clears its stealth with no `StealthChanged` (genesis_prime/game/cast/tick `left`), and
////   its `Leave` removes the player with its copy.
//// - **When a stealth tell is late, out of order or lost to a death:**
////   - A `StealthChanged` is decided on the state the connection had when it sent it,
////     and cannot cross a `Moved` or a `Ready` of the same connection.
////   - A creature's home timer that fires before the `Withdrew` reaches it aggroes the
////     player: the stealth tell is one hop behind, as any move is. A stealth the map takes
////     before it starts the creature's next life leaves the player out of the start's ring;
////     one it takes after reaches the new life as `Withdrew`, which keeps the player on the
////     threat list as for any stealth after an aggro.
////   - A `Withdrew` or `Approached` for a creature that died before it is dropped; the
////     spawn keeps `inside`, which `ring_of` reads at the creature's next start.
////   - An `Approached` that reaches a creature after the player's `Unseen` is no
////     aggro: the player is not a viewer in that stay.
////   - A player whose connection ends while stealthed in a ring is removed as any
////     player is: its creatures are sent `Unseen`, and no `Withdrew` follows.
////   - A map that dies ends every connection in it; no stealth copy outlives it.
////
//// What a connection does with them is its own (genesis_prime/game/connection):
//// told `SeenBy(v, stay, unit_id, generation)`, it builds its snapshot of that sight (its 0x262
//// at its current place) and tells it to the map (`PlayerSnapshot`), which relays it to v; its
//// 0x638s go to v itself as it moves, each stamped with that generation; told
//// `UnseenBy(v, generation)`, it stops stamping moves for v. The 0x355 of its unit at v is the
//// map's `PlayerUnseen`, sent for a pair that leaves sight, a second join, a camp and an end.
//// A viewer's connection writes only what its client can take, from the units it has shown and
//// the ones the map reported `Gone`.
////
//// - **The unit** is a game-level value (genesis_prime/shared/player_unit)
////   the map keeps for as long as the player is in it, standing where the
////   player's last `Moved` put it; the answer's 0x262 record is built from it
////   with the map's realm, and the answer carries the unit's typed loadout and
////   maximum health, which the player's connection keeps for its casts. The
////   `place` of a Join is the bounded place the client is told.
//// - **The incarnation** is in every `Joined`, so the joiner watches the run
////   of the map that holds its player, not a later one started after this
////   one ended.
//// - **The unit address** (genesis_prime/world_map/unit_address) is what a creature and
////   a player's tell to a creature name a player's unit by. The map issues one for each
////   join from a counter that never goes back, keeps it in `Player.address` and indexes
////   it to the joiner's connection (`by_address`); `Joined` carries it, and a creature
////   names it back in `Snapshot` and `Relay`, which the map delivers to the connection
////   that joined it (`Delivery`, `player_at`). Nothing is sent to an address.
//// - **The stay** (genesis_prime/world_map/stay) of each player is the one its Join
////   named: the connection fences by its count (`ForStay`,
////   genesis_prime/game/connection), so a message for an earlier stay is dropped there;
////   every notice (`Noticed`) and `SeenBy` names it. A message to a creature has none.
//// - **A message for an address that is not a unit of this run** is dropped (the failure
////   table below): `player_at` finds a connection only while its unit is in the map.
//// - **Held until the player interface names addresses.** The connection's stay count,
////   `Join.stay`, `Player.stay`, `Entered.stay`, `player_at`, `Delivery`, `by_address`,
////   `UnitAddress.joiner` (a creature's tie-break by connection, kept when it goes),
////   `players` keyed by connection and the type parameter of genesis_prime/game/held_changes
////   still route a message to a player by connection.
//// - **Unit ids** start at 1 and are never given to two units at once, whoever
////   leaves or ends: the client refuses a 0x262 whose unit id it already holds
////   (opcode.0x262), and a 0x262 with unit id 0 makes the client's controlled unit
////   (0x1403d9760). A player's id is given once. A spawn has one id for the run, given
////   when its first creature starts and reused after a clean stop, since the client
////   holds no unit of that id then (its 0x355 went with the last viewer) and takes a
////   0x262 for an id it removed (`death.creature_respawn`, `opcode.0x262`); a creature
////   that crashed gave its id up with its `Gone`, and the spawn's next creature takes
////   a new one. A static object's spawn has one id for the run, given when a player
////   first sees it. The ids stay below 2^20, since a cast id is built from its
////   caster's unit id in the rest of the 32 bits (`0x140561c30`): a map that has given
////   them all crashes, and its players' connections end.
//// - **A second Join from a connection in the map** removes the first unit as a Leave
////   does, then joins a new unit under a new address, and logs nothing.
//// - **A Leave** removes the connection's player with its unit and its watch, tells each
////   player that saw it `UnseenBy` and `PlayerUnseen`, and is answered `Left`, so the
////   connection, which lives on in character select, is not watched by a map it has
////   left. A Leave from a connection not in the map changes nothing, logs an error and
////   is answered `Left`: the connection's rule leaves once.
//// - **A player's connection ends.** Its watch comes back as `WatchEnded(w)`; the player
////   whose watch is `w` is removed as a Leave removes it, and every player in the map
////   is sent `Gone(unit)`: the ended connection cannot send its 0x355, so this is the
////   one case the map speaks of a unit. A watch that names no player is logged as an
////   error and changes nothing.
//// - **A caller that ended before its answer** is dropped by the shell; the
////   player stays until its connection's watch ends, which the joining
////   connection's end then gives.
//// - **The server stopping.** `Stopping` stops the rule at once. The map saves
////   nothing: the connection owns its player's place and saves it
////   (genesis_prime/game/connection).
//// - **Sight** is `genesis_prime/shared/sight`: one threshold, 1024 units. A
////   pair is in sight or not after each join, move, leave and end; the map keeps
////   each player's `sees`, and the relation is symmetric. A pair that comes into
////   sight is sent `SeenBy` both ways, a pair that leaves it `UnseenBy` both
////   ways, in one step, so a connection's viewers are exactly the players whose
////   `SeenBy` it was sent and not `UnseenBy`; each viewer is also told its own end of a
////   pair that leaves, `PlayerUnseen`.
//// - **A sight has a generation.** Each time a pair comes into sight the map gives each
////   direction a generation from its one counter (`issued`), keeps it in the seeing
////   player's `sees`, and names it in the `SeenBy` and the `UnseenBy` of that sight; a
////   second join of a connection gives each of its pairs two new ones.
//// - **A move is decided on the place it ends at.** At most one `SeenBy` or
////   `UnseenBy` per pair per `Moved`. The map sends no move: its `Moved` holds
////   the place and nothing else.
//// - **Server time** is the map's one clock, in milliseconds since the map
////   started, taken from the monotonic time of the input being handled
////   (`server_time`) mod 2^32 (the client's fields hold 32 bits, opcode.0x638).
////   `Joined` carries its origin, the monotonic time the map started at, so a
////   connection stamps its unit's 0x262 and 0x638s from the same clock
////   (`server_time`). One owner stamps both in the order it takes its inputs, so
////   for a viewer the times of one unit only go forward. The clock only goes
////   forward until the map is 49.7 days old, when it counts from 0 again: the client takes a sample only
////   when its signed 32-bit difference from the last is at least half the send
////   interval, so the wrap is a step forward in that difference; its fit across
////   the wrap is not read.
//// - **A `Moved` from a connection not in the map** changes nothing and is
////   logged as an error: the connection's rule tells only while joined. A
////   tell in the form of an ask, or an ask in the form of a tell, is a bug and
////   crashes the map.
//// - **Started** sets the map's clock and starts the sweep timer, `TimerId(0)`
////   (spawn numbers start at 1): a map starts with no player and no creature.
//// - **The spawns a player sees** are the spawns of the map's world within sight
////   (`sight.sees`, exact, 3D) of its place, found through the cell index
////   (`spawn_cell.near`) so a move reads only the spawns near it. The map keeps
////   them for each player (`seen`), and the players who see each live spawn
////   (`viewers`), so the two always agree.
//// - **A creature** is a process of its own (genesis_prime/world_map/creature):
////   the map keeps, for each spawn that is not dormant, whether its creature is
////   live, retiring, released, waiting for its restart or failed (`SpawnState`), and sends it
////   `Seen`, `Unseen` and `Retire`, so the creature tells its map the 0x262 and the
////   news of its own unit and decides nothing about its own life. Sight of
////   a creature is decided at its spawn's place, also while it runs (at most the
////   leash range plus its reach off), so a move of a player is the only change of
////   sight with it.
//// - **A creature starts** when its spawn gets its first viewer, with the spawn's
////   unit id, a new life (its watch id) and its first viewers in `CreatureStart`, so
////   it answers each with a snapshot as it starts and a burst of starts is followed by
////   no burst of `Seen`; the map's `Reply` of a Join comes first, then the starts. A
////   player's watch is taken before the starts, so no life is the player's watch.
//// - **A creature stops** when no player has seen it for `idle_stop_ms`: the sweep,
////   every `sweep_ms`, sends `Retire` to each live spawn idle that long, so a stop
////   comes between `idle_stop_ms` and `idle_stop_ms + sweep_ms` after the last
////   viewer left. A player that steps back within that time finds the same
////   creature, with its corpse and its health.
//// - **A spawn seen while its creature retires** waits: the creature has been
////   told to stop, so it cannot be shown to a viewer, and nothing starts until its
////   end. Then a creature starts there under the same unit id and a new life, with
////   the players who see the spawn from where they stand then as its first viewers. The registry drops a member when
////   it learns of the member's end, which can be after the map has, so the new
////   creature's address differs by its life: two members of one group would crash
////   the map's `find` (`group_registry`).
//// - **A creature that does not start** (`CreatureNotStarted`) is an error line
////   with the reason; its spawn stays empty for the rest of the run, with no
////   later creature and no one told. The other spawns are not affected.
//// - **A creature that ends** while live (its watch's `WatchEnded`, whatever the
////   reason) is removed, and every player in the map is sent `Gone` of its unit,
////   as for a player's end: the creature that ended sent nothing. Its spawn waits
////   its creature's kind's respawn time on a timer of the spawn's number, and nothing about
////   the spawn is started or told until it fires. Then, when a player sees the
////   spawn from where it stands, a creature is started there as a new unit under
////   the next unit id, and each player in sight is told to it `Seen`; when none
////   does, the spawn is dormant. A creature that crashes in a loop is so started at
////   most once in a respawn time.
//// - **A creature that ends while retiring** is a clean stop, whatever the reason:
////   no client shows the unit.
//// - **A map that ends** ends its creatures: each watches the run.
//// - **Static objects** (genesis_prime/world_map/static_object) are the map's own
////   units, with no process: their sight is decided with the creatures', from the
////   same `spawn_cell.near`, and kept for each player (`objects`). The objects a
////   join or a move brings into sight go to the player's connection in one
////   `ObjectsSeen`, in spawn order, each as its 0x262 stamped with the map's
////   server time; the ones it leaves, in one `ObjectsUnseen` of their ids. A
////   join's `ObjectsSeen` comes after its answer and before its creatures'
////   starts. A leave or an end sends nothing about them: the player's client
////   leaves the world. A second join sends the objects it sees again; the
////   connection writes none its client shows. A used object's release
////   (`Released`) takes it out of every player's sight until its timer fires: it
////   is `ObjectsUnseen` to those who saw it, left out of every later join and
////   move (`released_objects`), and `ObjectsSeen` again at its timer under the
////   unit id it had. It is never `Gone` and has no spawn state.
////
//// A development summon (genesis_prime/game/dev_command), asked by a connection that
//// has a player here:
////
//// ```
//// connection c                     map                                          shell
////   Summon(c, creature2 id, level) ─▶ Asked ─▶ place = c's player's place and facing
////                                      spawn.summoned(checks, Summoned(id s, creature2 id, level, place))
////                                      refused ─▶ Reply(NotSummoned(CreatureRefused(why))); nothing changes
////                                      s = next run-only id (-1, -2, ...); run_spawns[s] = the spawn
////                                      the players who see place (sight, exact) are its first viewers:
////                                      u = next unit id; life w = next watch
////                                      StartCreature(w, spawn: RunOnly(summoned), u, life w, viewers) ─▶ started
////                                      StartServiceTimer(TimerId(s), 0); c's caller held in `summoning[s]`
////                                      CreatureNotStarted(w, why) (the shell gives it before any timer's firing)
////   ◀─ NotSummoned(CreatureNotStarted(why)) ◀─ Reply; the timer cancelled; run_spawns[s], its state and its unit id dropped
////                                      ServiceTimerFired(TimerId(s)) (no failure came)
////   ◀─ Summoned(u)             ◀─ Reply(Summoned(u))
////   no player here for c       ─▶ Reply(NotSummoned(NoPlayerHere))
//// the creature ends (death's corpse timer, or a crash) ─▶ Gone(u) to every player; run_spawns[s], its
////                                      state and its unit id dropped; no restart timer
//// ```
////
//// - **A run-only spawn id is negative** (`spawn_source`): never a stored id, which is
////   above 0, nor the sweep timer's 0, so the spawn tables, the timers and the unit ids
////   never meet it. It counts down from -1 in `next_run_only_id` and is never given twice.
//// - **Sight and rings read `run_spawns` beside the stored spawns**, so the usual sight
////   rules show the creature and a hostile one attacks on sight, as any spawn does; the
////   cell index holds only stored spawns, so a move scans the few run spawns too.
//// - **A summon does not respawn**: its creature's end drops the spawn (a server choice, it
////   is a test tool). The creature's own corpse timer ends it after the kind's respawn time.
////   The sweep never retires a run-only creature, since a retired spawn goes dormant and a
////   creature would stand there again at full health.
//// - **The answer waits for the start's outcome**: the shell reports only a start that
////   failed, as the next input after the step (genesis_prime/service/shell `take`), so the
////   summon's timer under its run-only id (0 ms, which no stored spawn or sweep uses)
////   is the first input that says it did not fail.
//// - **A map that ends or restarts** loses its run spawns; nothing is saved.
////
//// What a player hears about a creature comes from the map alone. The map keeps, for
//// each pair of a player and a live creature in sight, a relation: the generation the
//// pair's sight was given (`generation`, never given twice by a map) and whether the
//// creature's snapshot of that generation is awaited or relayed (`Relation`). The creature
//// tells only its map (`Snapshot`, `Broadcast`, `Relay`), and the map relays to the player's
//// connection (`Relayed`, and the notice `UnitUnseen`), so a player has one sender for a
//// creature and its order is the map's:
////
//// ```
//// join:   Join ─▶ Reply(Joined(.., a_V, ..)); start_creature: relation(V) = g1, AwaitingSnapshot
////         StartCreature(viewers [(a_V, g1)])
////         creature Started ─▶ Send(map, Snapshot(unit, life, a_V, g1, burst))
////         map: (V, g1, life) is current and AwaitingSnapshot ─▶ Relayed(stay, News(item)) per
////              burst item, in order; the relation is Relaying
//// later:  map ─▶ creature Seen(a_W, g2) ─▶ Snapshot(unit, life, a_W, g2, burst); the copy gains a_W
//// news:   creature ─▶ Broadcast(unit, life, news) ─▶ map: Relayed to each Relaying viewer, in
////         connection order; an AwaitingSnapshot or departed viewer is sent none
//// tell:   creature ─▶ Relay(unit, life, to: a_P, payload) ─▶ map admits it (`admitted`: the
////         spawn is live, retiring, respawning or releasing under that life; then the destination
////         check of the payload's kind, `relay.kind_of`: a_P is a unit of this run) ─▶ Relayed(the
////         stay of a_P's join, payload) to the connection that joined a_P (`player_at`)
//// told:   a player's connection P ─▶ TellCreature(a_P, unit, life, inbound) ─▶ map admits it
////         (`admitted_inbound`: the spawn check as above; then the source check of the inbound's
////         kind, `relay.inbound_kind_of`: a_P is a unit of this run, and a `Strike` names a_P
////         as its striker) ─▶ ToldCreature(a_P, inbound): a creature hears of a player from the map alone
//// leave sight, Leave, a viewer's end:
////         map: the relation is removed in one step ─▶ creature Unseen(V, g), V Noticed(UnitUnseen(unit, g))
////         creature: the copy and the threat entry of V go; its release of V is one Relay(Released)
//// expiry: creature ─▶ Broadcast(Removed), Expired(unit, life), Stop; map: Live becomes Respawning (the
////         relations end, no one is told); WatchEnded(life) starts the next life, as drawn above
//// crash:  WatchEnded(life) ─▶ Gone to every player; Live becomes WaitingForRestart; the relations go with Live
//// re-entry: a Leave and a Join: Seen(a', g') with an address and a g' never given before
//// second Join of a connection in the map: the first unit is removed as a Leave removes
////         it, then a new unit joins under a new address a'
//// ```
////
//// | Point | What happens |
//// |---|---|
//// | the creature is killed with a viewer `AwaitingSnapshot` | `WatchEnded` gives `Gone` to every player and the spawn waits the respawn time; the relations go with `Live`; a `Snapshot` it sent before it died reaches the map first (one sender's signals arrive in order) and is relayed, then `Gone` follows (`a_snapshot_in_the_maps_mailbox_when_its_creature_ends_is_relayed_and_gone_follows_test`) |
//// | the creature is killed after the map sent it `Unseen` and before it took it | the same, and `Gone` reaches V too, whose connection writes nothing for a unit it removed (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`, `a_viewer_writes_a_0x262_only_for_a_unit_its_client_does_not_hold_and_a_0x638_or_0x355_only_for_one_it_holds_test`, `an_unseen_and_the_creatures_news_write_nothing_after_the_unit_is_removed_in_every_legal_order_test`) |
//// | the creature is killed while a relay of its is in flight | the relay was sent before the creature died, so it reaches the map before the end does and is admitted (the spawn is still live, retiring, respawning or releasing under that life); one taken after the end is dropped (`a_relay_from_a_live_retiring_or_releasing_creature_is_admitted_and_one_from_an_ended_creature_or_an_earlier_life_is_dropped_test`) |
//// | a viewer's connection is killed | the watch ends, the map removes the player and sends each creature it had a relation with `Unseen(g)`; the creature drops the entry and its threat; relays to the dead connection are dropped by the registry (`a_failed_write_while_a_viewer_takes_a_relayed_burst_ends_the_connection_and_the_map_unsees_the_creature_test`, `a_leave_and_a_connections_end_tell_every_running_creature_that_the_caster_is_gone_and_no_other_test`, `unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test`, `a_tell_to_a_connection_is_delivered_with_no_watch_and_one_that_is_gone_is_dropped_with_no_warning_test`) |
//// | the map is killed | creatures stop with their run watch and connections end with the run; relations and relays in flight are lost with it (`a_map_run_that_ends_ends_its_creatures_test`, `the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test`) |
//// | `Seen(V, g)` reaches a creature twice | answered twice; the map relays the first snapshot and drops the second (`a_seen_a_snapshot_and_an_unseen_taken_twice_change_nothing_the_second_time_test`) |
//// | `Snapshot` reaches the map twice, or after `Unseen`, or of an earlier generation or life | dropped; the old life's snapshot cannot follow its `Expired`, which the creature sends after it in one queue, and the next life starts only at its end (`a_snapshot_of_an_earlier_generation_relays_nothing_and_leaves_the_relation_awaiting_its_own_test`, `a_snapshot_a_broadcast_and_a_relay_of_the_life_that_expired_are_dropped_in_each_state_the_spawn_goes_through_test`) |
//// | the creature is killed after its `Removed` and before its `Expired` | `WatchEnded` of a `Live` spawn: the crash path, `Gone` to every player, the spawn waits the respawn time and the unit id is given up; the viewers wrote the 0x355 already (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`) |
//// | the creature is killed after its `Expired` and before it stops | the same as the clean end: the spawn is `Respawning`, and the next life starts at once (`a_spawn_whose_creature_expired_is_respawning_and_each_later_event_has_one_result_for_each_state_test`) |
//// | the next life is killed before its snapshot | `WatchEnded` of a `Live` spawn with an `AwaitingSnapshot` relation: the crash path; no viewer was shown a unit, and `Gone` is sent once (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`) |
//// | the next life's start fails | `CreatureNotStarted`: the spawn is `Failed` for the run with one error line, and no player is told anything; the viewers saw `Removed` and no new unit (`a_respawn_that_does_not_start_leaves_the_spawn_failed_for_the_run_and_tells_no_player_anything_test`) |
//// | a child starts and exits before the map's watch | `WatchEnded` as the step's next input: taken as a creature that ended while `Live` (`a_creature_that_exits_before_the_shell_watches_it_comes_back_as_watch_ended_test`, `a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`) |
//// | `Expired` is taken twice, or of an earlier life or unit | the map ignores an `Expired` for a spawn that is not `Live` under that unit and life; the creature sends one and stops (`a_spawn_whose_creature_expired_is_respawning_and_each_later_event_has_one_result_for_each_state_test`) |
//// | `Expired` is taken while the spawn is `Retiring` or `Releasing` | ignored: the creature's end restarts a retiring spawn, and a releasing one waits the release time (`a_spawn_whose_creature_expired_is_respawning_and_each_later_event_has_one_result_for_each_state_test`) |
//// | `Released` reaches a `Respawning` spawn, or twice | `Releasing` with no relations; at the creature's end `Gone` to every player and the release time; the second finds `Releasing` and changes nothing (`a_spawn_whose_creature_expired_is_respawning_and_each_later_event_has_one_result_for_each_state_test`) |
//// | the map is killed while a spawn is `Respawning` | creatures stop with the run and the spawn is rebuilt from storage with it (`a_map_run_that_ends_ends_its_creatures_test`, `a_map_that_ended_is_started_again_with_a_new_incarnation_and_the_old_run_is_not_found_test`); no test kills the map while a spawn is `Respawning`: they end it with creatures live |
//// | `Expired` waits past a deadline, or the next life's start waits behind a burst | it waits its turn in the map's one queue and the respawn is late by the queue's length; the creature that expired is dead and nothing can reach it; the shell's 5000 ms initialisation timeout decides a start that does not finish (`a_run_that_showed_fewer_players_than_pairs_a_map_that_falls_behind_and_a_delay_past_its_guard_each_fail_and_a_run_that_holds_all_three_passes_test`, `a_tell_to_the_life_that_ended_is_dropped_and_the_same_tell_to_the_life_that_replaced_it_is_taken_for_every_kind_of_tell_test`, `a_respawn_that_does_not_start_leaves_the_spawn_failed_for_the_run_and_tells_no_player_anything_test`) |
//// | a tell is addressed to the life that ended | dropped by the registry, which finds no creature at that life's address (`a_tell_to_the_life_that_ended_is_dropped_and_the_same_tell_to_the_life_that_replaced_it_is_taken_for_every_kind_of_tell_test`, `a_creature_that_expired_is_removed_and_created_again_by_a_new_life_under_the_same_unit_id_and_the_old_address_finds_no_creature_test`) |
//// | `Unseen(V, g)` reaches a creature twice | the second finds no entry and changes nothing (`a_seen_a_snapshot_and_an_unseen_taken_twice_change_nothing_the_second_time_test`) |
//// | a `Broadcast` is sent twice | cannot happen: a creature sends each news once in its step and a mailbox delivers a message once; a `Broadcast` has no id, so the map does not guard a repeat |
//// | a `Relay` comes from a creature that ended, or of an earlier life | dropped by `admitted`; a creature that is releasing, retiring or respawning is still admitted until it ends (`a_relay_from_a_live_retiring_or_releasing_creature_is_admitted_and_one_from_an_ended_creature_or_an_earlier_life_is_dropped_test`) |
//// | a relay waits in the map's queue past `strike_tell.deadline_ms` | delivered unchanged; the caster's round decides that it is late; the map keeps no deadline (`the_map_delivers_a_relay_held_past_the_strike_deadline_unchanged_and_the_round_decides_that_it_is_late_test`) |
//// | a player leaves or its connection ends | every running creature (live, retiring, respawning or releasing) is told `CasterGone` of the connection, once and in spawn order, after the removal's other sends; its sources and views of that connection end, the property news once; a control it landed stands until its own timer (`a_leave_and_a_connections_end_tell_every_running_creature_that_the_caster_is_gone_and_no_other_test`, `a_creature_drops_the_sources_and_views_of_a_gone_caster_keeps_its_controls_sends_the_property_news_once_and_watches_only_its_run_test`, `a_connection_that_ends_holding_a_modifier_a_view_and_a_control_on_a_creature_leaves_no_source_no_view_and_no_watch_of_it_test`) |
//// | a connection leaves, then its process ends | the leave dropped the connection's watch, so the end reaches the map as nothing (`a_normal_leave_then_the_connections_death_holds_no_source_or_view_of_it_and_the_second_end_changes_nothing_test`) |
//// | a leave while the connection's ends are in flight | the ends were told to the map first, in the connection's order: they are delivered, then `CasterGone` (`a_camp_tells_the_creatures_the_ends_of_its_holdings_in_the_step_that_starts_its_save_before_any_ask_test`) |
//// | a creature lies dead and retiring and holds a caster's view | dropped at the caster's leave or its connection's end, before the corpse expires (`a_dead_retiring_creature_holding_a_view_of_a_caster_drops_it_when_the_casters_connection_ends_before_its_corpse_expires_test`) |
//// | `CasterGone` is for a creature that ended or was replaced | dropped by the registry (`a_tell_to_the_life_that_ended_is_dropped_and_the_same_tell_to_the_life_that_replaced_it_is_taken_for_every_kind_of_tell_test`) |
//// | a `TellCreature` is for a creature that ended, or of an earlier life | dropped by `admitted_inbound`, with no line; the player's round closes by its deadline (`a_players_tell_is_delivered_to_a_running_creature_unchanged_and_dropped_for_an_ended_one_or_an_earlier_life_test`) |
//// | a `Relay` names an address that ended, one of an earlier run of the map, or one the map never issued | dropped by `admitted` (`DestinationRefused`): `player_at` finds no connection (`a_relay_from_an_address_that_ended_is_not_admitted_by_the_map_test`) |
//// | a `Snapshot` names such an address | dropped, as a snapshot of a pair that ended is (`a_relay_from_an_address_that_ended_is_not_admitted_by_the_map_test`) |
//// | a creature takes `Unseen` of a joiner's earlier address after `Seen` of its later one | the later viewer stays: viewers are keyed by address (`a_creature_names_a_viewer_by_its_address_and_an_unseen_of_an_earlier_address_keeps_the_later_viewer_test`) |
//// | a creature is told `Seen` of a joiner's new address while it charges a telegraph at the first | the row bound to the first address is gone and the new unit, never its target, is struck by nothing: the client drops a telegraph when its unit is gone (`0x14054b1b0.unit_gone`) and the 0xAD of the new join removes every unit (`a_telegraph_whose_target_left_and_joined_again_during_the_charge_strikes_nobody_test`) |
//// | a creature picks among players that tie (the first target, a tie of threat) | the lowest connection of the joiners, as it did when it named connections: a server's choice, the client holds no rule (`a_creature_that_ranks_players_ties_by_their_connection_and_not_by_the_order_they_joined_test`) |
//// | two runs of a map both issue the connection the number 1 | the host's own stay count fences, as the address is in no player-bound message (`a_map_change_between_two_runs_that_both_issue_stay_1_drops_the_first_runs_notice_test`) |
//// | a creature relays to an address of the run | the map delivers it to the connection that joined it, for the stay of that join (`a_creature_relay_reaches_the_host_by_the_connection_and_the_connections_stay_test`) |
//// | a join is answered with an address | the next of the run, never one a join of the run had, a restarted run's apart (`a_map_run_never_issues_one_address_twice_over_any_sequence_of_joins_leaves_and_ends_test`, `a_restarted_run_that_reuses_a_wire_unit_id_names_another_address_test`, `a_join_issues_the_next_address_and_keeps_the_connections_stay_test`) |
//// | a `TargetMoved`, `ModifierStarts` or `CastViewSet` is from an address that is not a unit of this run | dropped (`SourceRefused`), with no line: a start or a view told after its connection's leave holds nothing on the creature (`a_start_told_after_its_casters_leave_holds_nothing_on_the_creature_test`) |
//// | a `Strike` or a `StrikeAnswered` is from a sender that left | delivered: the damage applies and the answer closes its round (`a_strike_or_an_answer_of_an_address_that_ended_still_lands_and_a_move_or_a_holding_is_taken_only_from_a_unit_of_the_run_test`) |
//// | a `Strike` names another address or a creature as its striker | dropped (`StrikerRefused`), with one error line (`a_strike_that_names_another_striker_than_the_connection_that_told_it_is_dropped_with_an_error_line_test`) |
//// | an answer waits in the map's queue past the strike deadline | delivered unchanged to the creature, whose round closed by its deadline and takes it as no change (the creature's side: `an_answer_that_reaches_the_creature_after_its_round_closed_changes_nothing_test`; the map's wait is the load gate's planted run, `behind`) |
//// | a player's strike and its move out of the creature's sight reach the map | in the order the player's connection told them: a strike told first is taken while the player is a viewer (threat, then the release of `Unseen`), one told after it is taken after the `Unseen` (the damage and no threat) (`a_strike_and_the_senders_move_out_of_sight_are_taken_in_the_order_the_sender_told_them_and_each_order_has_its_own_result_test`) |
//// | a connection ends with tells to a creature in the map's mailbox | its tells precede the map's end signal for it and are delivered, then the player is removed and the creature told `Unseen` (`the_map_relays_a_players_killing_answer_its_death_and_its_wake_to_a_creature_in_the_order_the_connection_told_them_test`) |
//// | a tell to a `Respawning` creature that has stopped | admitted by the map (the spawn is still running under that life), dropped by the registry, which finds no creature at that address (`a_players_tell_is_delivered_to_a_running_creature_unchanged_and_dropped_for_an_ended_one_or_an_earlier_life_test`, `a_tell_to_the_life_that_ended_is_dropped_and_the_same_tell_to_the_life_that_replaced_it_is_taken_for_every_kind_of_tell_test`) |
//// | a rule tells a creature directly, and not through the map | the connection's shell writes an error line and sends nothing (`a_rule_that_tells_a_creature_directly_is_logged_and_sends_nothing_test`) |
//// | an ask (`Join`, `Leave`, `Summon`) waits behind relays | the asker's own `ask_deadline_ms` decides; the load gate keeps the queue near zero (`a_store_a_maps_or_a_map_that_gives_no_answer_ends_the_play_with_0x036a_reason_8_and_a_warning_test`, `a_leave_that_gets_no_answer_in_time_tells_the_client_reason_8_and_ends_the_connection_with_no_second_save_test`, `a_map_that_is_not_running_ended_or_gave_no_answer_in_time_answers_not_summoned_and_the_connection_goes_on_test`, `a_run_that_showed_fewer_players_than_pairs_a_map_that_falls_behind_and_a_delay_past_its_guard_each_fail_and_a_run_that_holds_all_three_passes_test`) |
//// | a creature never answers `Seen` | the viewer stays `AwaitingSnapshot` and shown nothing until the creature ends (then `Gone`); no deadline, since a creature answers every `Seen` in its step (`a_creature_answers_a_seen_with_a_snapshot_of_its_burst_live_dead_or_despawned_test`, `a_broadcast_is_relayed_to_each_relaying_viewer_in_connection_order_and_to_no_awaiting_or_departed_viewer_test`, `a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`) |
//// | a viewer's connection fails a write while it takes a relayed burst | the connection ends (nothing after the failed write is written), its watch ends and the map sends each creature `Unseen` (`a_failed_write_while_a_viewer_takes_a_relayed_burst_ends_the_connection_and_the_map_unsees_the_creature_test`) |
//// | a creature is released while a viewer awaits its snapshot | the relations are kept by `Releasing` as they were, each with the stay it was made in: the snapshot and the news still reach the viewer until the creature ends, and none reaches a player that left and joined again in another stay meanwhile (`a_broadcast_is_relayed_to_each_relaying_viewer_in_connection_order_and_to_no_awaiting_or_departed_viewer_test`) |
//// | a `Relay` is taken twice | cannot happen: a creature sends each relay once and a mailbox delivers a message once; a relay of a creature that ended or of an earlier life is dropped by `admitted` |
//// | `WatchEnded` of a creature's watch is taken twice, or after `CreatureNotStarted` | a second `WatchEnded` finds no creature watch, is read as a player's end, finds no player and changes nothing but one error line (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`); after `CreatureNotStarted` the shell opens no watch (`a_creature_that_does_not_start_comes_back_as_not_started_and_no_watch_is_opened_test`) |
//// | the map's end (its process stops) is taken twice | cannot happen: a process stops once; a restarted map is a new process with no relations, and every creature stopped with the run it watched |
//// | `Unseen` waits past a deadline | the creature has none for it: it drops the copy and the threat entry when it takes the message; the viewer's 0x355 comes from the map's notice, not from the creature (`an_unseen_and_the_creatures_news_write_nothing_after_the_unit_is_removed_in_every_legal_order_test`, `a_seen_a_snapshot_and_an_unseen_taken_twice_change_nothing_the_second_time_test`, `the_map_numbers_each_creature_relation_through_join_move_leave_crash_re_entry_and_hide_test`) |
//// | the creature's end waits past a deadline | `Gone` goes to every player when the map takes `WatchEnded`, and the respawn time counts from then; the map keeps no deadline for it (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`) |
//// | the map's end waits past a deadline | the shell's `shutdown_ms` bounds it, after which the supervisor kills the map and its relations are lost with it (`started_starts_the_sweep_timer_and_stopping_stops_the_rule_test`, `the_trees_stop_arrives_as_stopping_with_the_childs_shutdown_time_from_its_arrival_test`) |
//// | a map dies | its players and their relations live only in its process, and every connection in it ends; no relation, hold or tombstone outlives it, since holds end with the stay (as in the creature row `the map is killed`) (`a_map_that_ended_keeps_no_player_so_the_same_connection_joins_the_new_run_as_unit_1_test`, `the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test`) |
//// | an owner's snapshot of an earlier generation, a second one, one after the pair's `PlayerUnseen`, or for a viewer in another stay | dropped; the relation is as it was (`a_players_snapshot_is_relayed_only_for_the_generation_and_stay_the_relation_awaits_and_news_while_awaiting_is_dropped_test`) |
//// | an owner's snapshot does not begin with its own 0x262 of the relation's generation | one error line, nothing relayed, the relation still awaits (`a_players_snapshot_is_relayed_only_for_the_generation_and_stay_the_relation_awaits_and_news_while_awaiting_is_dropped_test`) |
//// | an owner's news reaches the map while a viewer awaits its snapshot, after the pair left sight, or from the owner's earlier stay | not relayed to that viewer, or dropped (`a_players_news_is_relayed_to_each_relaying_viewer_in_connection_order_and_to_no_awaiting_or_departed_viewer_and_news_naming_another_unit_is_dropped_test`) |
//// | an owner's news names another unit than the owner's | dropped with one error line (`a_players_news_is_relayed_to_each_relaying_viewer_in_connection_order_and_to_no_awaiting_or_departed_viewer_and_news_naming_another_unit_is_dropped_test`) |
//// | a pair leaves sight while its snapshot is awaited | `PlayerUnseen` to the viewer, and the late snapshot is dropped (`a_pair_that_leaves_while_its_snapshot_is_awaited_tells_the_viewer_its_unseen_and_the_late_snapshot_is_dropped_test`) |
//// | a connection joins a second time | its first unit is removed as a `Leave` removes it and a new unit joins under a new address, so each pair's sight ends under the generation it held and begins again under a new one, the viewer's end for the stay it had, and each creature is told `Unseen` and `CasterGone` of the old address and `Seen` of the new (`a_second_join_of_one_joiner_removes_its_first_unit_as_a_leave_does_and_joins_a_new_unit_test`) |
//// | a connection ends with news in flight | its tells reach the map in its order, before its watch's end, and are relayed; then `PlayerUnseen` and `Gone` to each viewer, `UnseenBy` to each owner (`the_news_a_connection_sent_before_it_ended_is_relayed_before_its_removal_test`) |
//// | a move takes a viewer out of sight | the map sends the sight notices and no move (`a_move_told_to_the_map_makes_it_decide_sight_and_send_no_move_test`); the move reaches the viewer from the mover, before or after its `PlayerUnseen` |
////
//// The tells of a player's connection to a creature, in one stream because the connection is
//// their one sender to the map (the answer of a killing blow, then the death, then the wake):
////
//// ```
//// player's connection P         map                                           creature (running)
//// TellCreature(a_P, unit, life, StrikeAnswered)
//// LifeChanged(P, False)
//// LifeChanged(P, True)       ─▶ ToldCreature(a_P, StrikeAnswered), PlayerDied(a_P), Approached(a_P)
////                                  in that order, `PlayerDied` and `Approached` as above
//// ```
////
//// Order, in short: every 0x262, 0x638 and 0x355 about a player's unit comes from its
//// connection and about a static object from the map, so for one viewer they are one
//// sender's messages and arrive in the order sent (the BEAM orders signals of one sender to
//// one receiver); the map's `SeenBy` and `UnseenBy` to one owner are one sender's, so the
//// owner's view of its viewers changes in order. The one case two senders speak of a
//// player's unit is `Gone` after its owner's end, which a viewer filters
//// (genesis_prime/game/connection). About a creature's unit every 0x262, 0x638 and 0x355
//// comes from the map: the creature tells its map, which relays in the order it takes the
//// tells, and the map takes a creature's end after everything it sent and starts the next
//// life only then, so the 0x355 of one life and the 0x262 of the next are one sender's, in
//// that order. The map's `Gone` of a creature that crashed is the same sender's.
////
//// What happens at each failure point of seeing:
////
//// | Point | What happens |
//// |---|---|
//// | the map dies | every connection in it ends (genesis_prime/game/connection), so no one is left seeing a unit with no owner (`the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test`) |
//// | a viewer's connection is gone | its watch ends, and the map sends each player who saw it `UnseenBy`, so the owner stops stamping moves for it (`a_connection_ending_tells_each_player_who_saw_it_unwatched_and_gone_once_test`) |
//// | an owner's connection ends (a crash, a close, a takeover) | it sends nothing; the map sends each viewer `PlayerUnseen` and every player in the map `Gone`, and a player writes the 0x355 if its client shows the unit (one that stopped seeing the owner just before may never have been sent it, since an end saves the place first) (`a_connection_ending_tells_gone_to_every_player_in_the_map_even_one_that_no_longer_sees_it_test`) |
//// | an owner's 0x262 lands after the map's `Gone` of it | the viewer drops it: the unit is no ghost (`the_maps_gone_before_the_owners_notice_drops_what_is_held_for_the_unit_with_one_warning_that_names_it_and_counts_the_chunks_test`) |
//// | an owner's 0x638 reaches a viewer before the owner's 0x262 of it, or after its 0x355 | not possible from one sender; one that lands after `Gone` is dropped, since the viewer shows no such unit (`a_viewer_writes_a_0x262_only_for_a_unit_its_client_does_not_hold_and_a_0x638_or_0x355_only_for_one_it_holds_test`) |
//// | a 0x262, 0x638 or 0x355 for a unit of another run of the map, or another map | dropped by the viewer's connection: it was sent for another stay (`messages_of_the_stay_before_are_dropped_in_a_restarted_run_that_gives_the_same_unit_id_test`) |
//// | `Moved` reaches the map after that connection's `Leave` | ignored, with an error line (`a_moved_after_the_connections_leave_is_ignored_with_an_error_test`) |
//// | a connection's `SeenBy` or `UnseenBy` reaches it with no player in the world, or in a later stay | dropped: a player that enters again starts with no viewers and is sent a `SeenBy` for each player in sight by its new join (`after_the_players_own_leave_nothing_more_is_written_for_other_units_test`, `messages_of_the_stay_before_a_camp_are_dropped_after_the_next_entry_test`) |
//// | the same pair crosses sight twice in one `Moved` batch | the map decides on the final place: at most one `SeenBy` or `UnseenBy` per pair per `Moved` (`a_pair_that_crosses_sight_twice_in_one_batch_is_decided_on_the_final_place_test`) |
//// | a creature does not start | an error line with the supervisor's reason; the spawn stays empty for the run; the burst's other spawns start (`a_creature_that_does_not_start_leaves_its_spawn_empty_for_the_run_and_the_others_appear_test`) |
//// | the map crashes in the middle of a burst of starts | every creature started sees the run end and stops; the players' connections end with the run (`a_map_that_ends_while_its_burst_of_starts_runs_ends_every_creature_it_started_test`, `the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test`) |
//// | a Leave or an end is queued behind a burst of starts | taken next: `Unseen` to each of the player's creatures, each stopped after the idle stop (`a_leave_right_after_a_burst_sends_unwatched_to_each_creature_of_the_player_test`) |
//// | a spawn is seen while its creature retires or has expired | waits; a creature starts at its end, with the same unit id and a new life, if a player still sees it, and the viewers are the players who see the spawn then (`a_spawn_seen_while_its_creature_retires_restarts_only_after_the_creatures_end_test`) |
//// | a creature crashes while retiring | taken as retired: the spawn is dormant, or a new creature starts if a player sees it (`a_creature_that_crashes_while_retiring_is_taken_as_retired_test`) |
//// | a creature crashes while live | every player is sent `Gone`; the spawn waits the respawn time, then a new unit is started there if a player sees it, and it is dormant if none does (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`, `a_spawn_whose_creature_crashes_waits_the_respawn_time_of_its_creatures_kind_test`) |
//// | the respawn timer fires with no one in sight | the spawn is dormant (`a_restart_timer_that_fires_with_no_one_in_sight_leaves_the_spawn_dormant_test`) |
//// | a summoned creature does not start | the asker is answered `NotSummoned(CreatureNotStarted(why))`, an error line is written, and the run-only spawn, its state and its unit id are dropped (`a_creature_that_does_not_start_answers_not_summoned_and_drops_the_run_spawn_test`) |
//// | a summoned creature ends before the answer | the run-only spawn is dropped as at any end; the asker is answered `Summoned` when the summon's timer fires, since the start did not fail (`a_creature_that_ends_before_the_answer_is_still_answered_summoned_test`) |
//// | a summon names a level with no CreatureLevel row, or the last row, 101, which holds the properties from 100 up and is no level | answered `NotSummoned(CreatureRefused(why))` at once, naming the level; nothing changes (`a_level_with_no_creature_level_row_is_refused_naming_it_and_starts_nothing_test`, `a_summon_at_level_101_the_row_of_the_properties_from_100_up_is_refused_naming_it_test`) |
//// | a summon is asked for a connection with no player here | answered `NotSummoned(NoPlayerHere)`; nothing changes (`a_connection_with_no_player_here_is_answered_no_player_here_and_nothing_starts_test`) |
//// | two summons are asked at once | each takes the next run-only id and unit id, and each caller is held under its own id, so the answers are told apart (`two_summons_get_two_distinct_negative_run_only_ids_never_a_stored_one_test`) |
//// | a creature crashes as soon as it is told of a player | the same, once for each respawn time: no creature is started or told anything before the timer fires (`a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test`, `a_creature_that_crashes_with_a_despawn_pending_is_gone_and_returns_new_test`) |
//// | the respawn timer fires after the map ended | cannot happen: the timer lives in the process |
//// | a joining character's class and faction have no Novice set | the join is answered `NotJoined`, with an error line, no unit id given and no player kept: the player's connection tells its client the server failed, and the map does not crash on one character's data (`a_character_whose_class_and_faction_have_no_novice_set_is_refused_and_takes_no_unit_id_test`) |
//// | the map has given every unit id | a join, a spawn's first creature or object, a summoned spawn and a crash replacement (after the kind's respawn time) each take one id, so a busy map can use all 2^20 of them; the map crashes, which ends its run and its players' connections, and the next run starts from 1 (`a_map_that_has_given_every_unit_id_crashes_naming_the_limit_test`) |
//// | the map run ends | each creature's watch on the run ends and it stops; the players' connections end with the run (`a_creature_stops_when_its_run_ends_and_when_the_server_stops_test`, `a_map_run_that_ends_ends_its_creatures_test`, `the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test`) |
//// | the creature supervisor or the creature registry restarts | every creature and every map ends (genesis_prime/server) (`the_tree_starts_the_pool_the_store_the_hand_off_sessions_the_world_the_two_subtrees_and_the_closer_last_in_that_order_each_with_its_settings_stated_test`, `a_restart_of_maps_ends_every_map_and_the_map_supervisor_restarts_with_it_test`); the first shows the tree's shape and the second kills Maps: no test kills the creature supervisor or the registry |
//// | the sweep timer fires after a restart of the map | cannot happen: the timer lives in the process, and a restarted map starts its own |
//// | a `Moved` comes before the player's `Ready` | sight is decided; no ring is, and no creature is told (`no_approached_before_ready_and_at_ready_one_for_each_ring_the_player_stands_in_test`) |
//// | a `Ready` comes twice in one stay | the second changes nothing (the connection sends one a stay) (`a_second_ready_in_one_stay_changes_nothing_test`) |
//// | a player in a ring leaves, camps or its connection ends | its creatures are told `Unseen`, which drops it from their threat lists; no `Withdrew` follows (`a_ready_player_in_a_ring_that_leaves_or_whose_connection_ends_alive_or_dead_sends_its_creature_unseen_and_caster_gone_and_no_withdrew_test`, `unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test`) |
//// | a `LifeChanged` reaches the map after that connection's `Leave`, or from a connection never in it | ignored, with an error line (`a_life_changed_of_the_value_held_sends_nothing_and_one_from_a_connection_not_in_the_map_writes_one_error_line_test`) |
//// | a `LifeChanged` of the value the map holds | nothing is sent (`a_life_changed_of_the_value_held_sends_nothing_and_one_from_a_connection_not_in_the_map_writes_one_error_line_test`) |
//// | the player dies in a creature's ring, and its killing answer and the map's `PlayerDied` both reach the creature | one sender, in the order the connection told them: the answer, `PlayerDied`, then a wake's `Approached`; each finds the state the one before left (`the_map_relays_a_players_killing_answer_its_death_and_its_wake_to_a_creature_in_the_order_the_connection_told_them_test`) |
//// | a player that joins dead sends `Ready` | no ring is decided; its `LifeChanged(True)` decides them (`a_player_that_joins_dead_is_sent_to_no_creature_at_ready_and_waking_then_sends_approached_to_each_ring_test`) |
//// | a `LifeChanged(True)` reaches the map before the player's first `Ready` (Wake Here before the first 0xF2) | the player is only marked alive; its `Ready` decides its rings (`a_player_that_wakes_before_its_ready_is_only_marked_and_ready_sends_approached_to_each_ring_test`) |
//// | a dead player's connection ends or camps | its creatures are told `Unseen`; the next entry's `Join` names `alive` False from its saved health 0 (`a_ready_player_in_a_ring_that_leaves_or_whose_connection_ends_alive_or_dead_sends_its_creature_unseen_and_caster_gone_and_no_withdrew_test`, `an_entry_at_a_saved_health_of_0_joins_its_map_dead_and_any_other_entry_and_the_holocrypts_join_alive_test`, `a_player_dead_at_camp_enters_again_dead_at_the_body_and_a_character_never_saved_enters_alive_and_full_test`) |
//// | the Holocrypt's `Leave`, then its `Join` | `alive` True; the old map sent no `LifeChanged(True)`, so no ring creature aggroes the player for one step before the leave (`the_holocrypt_comes_back_as_wake_here_then_leaves_the_map_and_joins_at_the_start_of_the_race_and_faction_in_its_world_test`) |
//// | an `ObjectsSeen` or `ObjectsUnseen` reaches a later stay | dropped by the connection's stay envelope (`an_object_notice_for_another_stay_is_dropped_test`) |
//// | the map crashes and restarts | the player's connection's watch of the map ends: it saves the place, writes 0x036A reason 8 (LostUserServer) and ends, so no rejoin happens and the hidden set dies with the connection (`the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test`); the next play's `Join` carries the set worked out from the store |
//// | the connection ends | the existing path: the map removes the player and sends `UnseenBy`, `PlayerUnseen` and `Gone` (`a_players_connection_ending_removes_the_player_so_its_next_join_is_a_new_unit_test`, `a_connection_ending_tells_each_player_who_saw_it_unwatched_and_gone_once_test`, `the_news_a_connection_sent_before_it_ended_is_relayed_before_its_removal_test`) |
//// | a `VisibilityChanged` reaches a map the player has left, or from a connection never in it | dropped, like `Moved`, with an error line (`a_late_or_unchanged_visibility_changed_gives_no_effect_test`) |
//// | a `VisibilityChanged` with the set the map already holds | no effect (`a_late_or_unchanged_visibility_changed_gives_no_effect_test`) |
//// | an `ObjectsSeen` while a hiding `VisibilityChanged` is still on its way | the client gets the 0x262, then the 0x355 (`visibility_changed_shows_and_hides_the_units_in_sight_test`, `objects_seen_writes_a_0x262_for_each_object_not_shown_and_not_gone_and_nothing_twice_test`, `objects_unseen_writes_a_0x355_for_each_shown_object_and_none_for_one_not_shown_test`) |
//// | a creature is hidden in the middle of a fight | `Unseen` and `Withdrew`, as when a player leaves its sight (`a_hidden_hostile_spawn_takes_no_player_into_its_ring_test`, `unwatched_drops_the_player_from_the_threat_list_and_the_next_entry_is_the_target_test`) |
//// | a move crosses an object's sight twice in one `Moved` batch | cannot happen: a `Moved` names one place, so an object is in sight or out of it after one (`a_move_that_changes_no_objects_sight_sends_no_object_notice_test`) |
//// | a map restarts while a static object is released | `new` holds an empty `released_objects` and no timer: the object shows at once to whoever joins after, which only shortens the wait (`a_map_that_starts_again_shows_a_released_static_object_at_once_test`) |
//// | a second `Released` for a released static object | the spawn is already in `released_objects`: no effect, no second timer; the return stays at the first release plus the release time (`a_second_release_of_a_released_static_object_changes_nothing_and_leaves_the_return_at_the_first_time_test`) |
//// | a released object's timer fires after its viewer left, or with no player in the map | the set and the timer are the map's: the spawn leaves the set and the players in the map are decided; one that left gets nothing (`a_return_after_the_viewer_left_sends_nothing_and_a_rejoin_after_it_sees_the_object_test`) |
//// | a player joins, or moves into sight of, a static object mid-release | `stored_in_sight` leaves it out: other objects show, this one at the return (`a_player_who_joins_or_moves_into_sight_of_a_released_static_object_is_shown_it_only_at_the_return_test`) |
//// | a player moves out of sight of a static object mid-release | its `objects` already lacks the object: nothing at the move, nothing at the return (`a_player_who_moved_out_of_sight_during_the_release_gets_nothing_at_the_return_and_sees_the_object_on_entering_later_test`) |
//// | a released static object also has a visibility prerequisite the player fails | the return decides with the player's `hidden`: it stays hidden (`a_released_static_object_hidden_from_a_viewer_by_its_visibility_prerequisite_stays_hidden_at_the_return_test`) |
//// | a released object has a creature or a static object at its x and z | the creature takes 856's path (`Retire`, `Gone`, a restart after the wait); the static object is released with it, on its own timer (`a_released_creature_takes_the_creature_at_its_x_and_z_with_it_test`, `a_creature_keyed_release_also_unsees_a_static_captive_at_its_x_and_z_test`) |
//// | a creature captive of a released object is not live at the release (dormant, waiting for a restart or failed) | it is not held out: a captive that is waiting or dormant may start during the release time, a failed one stays failed; the player who used the object stands in sight of it, so its captive is normally live (`a_captive_creature_that_is_waiting_failed_or_dormant_when_its_object_is_released_is_left_as_it_is_test`, `a_creature_captive_of_a_released_static_object_is_released_with_it_test`) |

import genesis_prime/game/start_place.{type Place}
import genesis_prime/map/message.{
  type Inbound, type Landing, type Message, type NotJoined, type Notice,
  type Outgoing, type Payload, Approached, Broadcast, CasterGone,
  CreatureNotStarted, CreatureRefused, Expired, Gone, Join, Joined, Leave, Left,
  LifeChanged, Moved, NoLoadout, NoPlayerHere, NotJoined, NotSummoned, Noticed,
  ObjectsSeen, ObjectsUnseen, PlayerBroadcast, PlayerDied, PlayerSnapshot,
  PlayerUnseen, Ready, Relay, Relayed, Released, Retire, Say, Seen, SeenBy,
  Snapshot, StealthChanged, Summon, Summoned, TellCreature, TellLanding,
  ToldCreature, UnitUnseen, Unseen, UnseenBy, VisibilityChanged, Withdrew,
} as map_message
import genesis_prime/shared/appearance
import genesis_prime/shared/chat_tell.{type Said as ChatSaid}
import genesis_prime/shared/creature_combat.{type Hostile}
import genesis_prime/shared/creature_kind.{type Kinds}
import genesis_prime/shared/hit_radius
import genesis_prime/shared/loadout.{type Loadout}
import genesis_prime/shared/player_unit.{type PlayerUnit}
import genesis_prime/shared/sight
import genesis_prime/shared/strike_tell
import genesis_prime/shared/unit_news.{type PeerNews, Appeared, PeerNews}
import genesis_prime/step.{
  type CallerId, type ConnectionId, type Effect, type RingMember,
  type ServiceEffect, type ServiceInput, type ServiceRule, type ServiceStep,
  type TimerId, type WatchId, Asked, CancelServiceTimer, Connection,
  ConnectionId, CreatureStart, Effects, Log, LogError, LogLine, OwnEffect,
  OwnEvent, Reply, RingMember, Send, ServiceTimerFired, StartCreature,
  StartServiceTimer, Started, Stop, Stopping, TimerId, Told, Unwatch, Watch,
  WatchEnded, WatchId,
}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/table/id.{type Creature2Id, type PrerequisiteId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn.{type Spawn, type WorldSpawns}
import genesis_prime/world_map/spawn_cell
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/static_object
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// The rule's name: its module path.
const rule_name = "genesis_prime/world_map/map"

/// The clock's 32 bits: the server time of 0x638 and the estimate start of
/// 0x262 are 32 bits wide (opcode.0x638).
const server_time_modulus = 4_294_967_296

/// The most unit ids a map gives: 2^20 (the cast id of a unit is built from its
/// id, in 2^20 values below the client's 32 bits, `0x140561c30`). Ids 1 up to
/// but not including this one are given.
const unit_id_limit = 1_048_576

/// The sweep timer: it fires every `sweep_ms` and retires the creatures idle for
/// `idle_stop_ms`. A spawn's restart timer is the spawn's number, which starts at
/// 1, so this id is never one.
pub const sweep_timer = TimerId(0)

/// What a map is started with: which map it is, the incarnation Maps gave this
/// run of it, unique in the node's life, the realm its players' units are
/// created in, the client's game tables, which give a unit's body, the spawns
/// that start in its world (the world's persistent term, read by the map's start and
/// never copied: genesis_prime/content/spawn), how long a spawn whose
/// creature crashed waits before a creature is started there again, how long a
/// creature that no player sees keeps running, and how often the map looks for
/// one. The two times are the server's choice, settings so a test can shorten
/// them: 60 s and 10 s. `summons` is what a development summon is checked with
/// (genesis_prime/world_map/spawn `SummonChecks`), the content load's term.
pub type Settings {
  Settings(
    map: MapId,
    incarnation: Int,
    realm_id: Int,
    tables: table_store.Tables,
    spawns: WorldSpawns,
    summons: spawn.SummonChecks,
    kinds: Kinds,
    numbers: GameNumbers,
    idle_stop_ms: Int,
    sweep_ms: Int,
  )
}

/// A map's players, its spawns that have a creature or a failure, the spawns'
/// unit ids and what it gives next: the players by their connection, the
/// connection each open watch was opened for, the state of each spawn that is not
/// dormant, the spawn each creature watch was opened for, the unit id each spawn
/// has had this run, the next unit id and the next watch id, neither of which goes
/// back, and the monotonic time the map started at, which its clock counts from
/// (`Joined` carries it). A dormant spawn is a spawn with no entry in `spawns`.
/// `next_generation` is the generation the next sight of a player and a creature gets
/// (`issued`), which never goes back. `captives` are the spawns that go with a used
/// object's spawn
/// (`spawn.captives`), found once when the map is built. `released_objects` are
/// the static objects a player's use released, each away until its timer fires:
/// no player sees one.
pub opaque type State {
  State(
    settings: Settings,
    players: Dict(ConnectionId, Player),
    watches: Dict(WatchId, ConnectionId),
    by_address: Dict(UnitAddress, ConnectionId),
    spawns: Dict(SpawnId, SpawnState),
    creature_watches: Dict(WatchId, SpawnId),
    unit_of_spawn: Dict(SpawnId, Int),
    captives: Dict(SpawnId, List(SpawnId)),
    released_objects: Set(SpawnId),
    run_spawns: Dict(SpawnId, Spawn),
    summoning: Dict(SpawnId, Summoning),
    next_run_only_id: SpawnId,
    next_unit_id: Int,
    next_address: Int,
    next_watch: Int,
    next_generation: Generation,
    started_ms: Int,
  )
}

/// What a spawn that is not dormant has: a creature running, a creature told to
/// stop, a wait for its restart, or a start that failed. A dormant spawn has
/// none of these and no entry in the map's state.
pub type SpawnState {
  /// A creature runs as `unit_id` under `life` (its watch's number). `relations` are
  /// the players who see it, each with the generation of its sight and whether its
  /// snapshot is awaited or relayed, and `idle_since_ms` is the monotonic time the
  /// last one stopped seeing it, `None` while any does: the sweep retires it when
  /// `idle_stop_ms` has passed.
  Live(
    unit_id: Int,
    life: Int,
    relations: Dict(ConnectionId, Relation),
    idle_since_ms: Option(Int),
  )
  /// The creature was told `Retire` and has not ended. The players who see the
  /// spawn meanwhile are the players whose `seen` holds it, found when it ends.
  Retiring(unit_id: Int, life: Int)
  /// The creature lay dead or despawned until its corpse timer, told the map it expired
  /// (`Expired`) and is stopping: when it ends, the map starts the spawn's next life
  /// under the same unit id for the players who see the spawn then. It holds no
  /// relations, since the creature removed its unit from every viewer before it
  /// expired, and the creature's news and answers meanwhile are dropped, but a relay of
  /// the life that expired is admitted until its end.
  Respawning(unit_id: Int, life: Int)
  /// The creature was told `Retire` because a player's use released its unit
  /// (`Released`) and has not ended. When it ends, every player is sent `Gone` and
  /// the spawn waits `wait_ms`, the release time, in place of its kind's respawn
  /// time: the override lasts this one restart, since the spawn's next creature
  /// is `Live` with no override. The relations it held are kept as they were, so
  /// that its news and its answers reach the players until it ends, and are not
  /// changed by a player's move meanwhile (the creature is told no more of sight).
  Releasing(
    unit_id: Int,
    life: Int,
    wait_ms: Int,
    relations: Dict(ConnectionId, Relation),
  )
  /// The creature crashed: the unit was sent `Gone`, and the spawn's restart
  /// timer runs.
  WaitingForRestart
  /// The creature did not start: the spawn stays empty for the run.
  Failed
}

/// One sight of a creature or of a player by a player: the generation the map gave it when the
/// pair came into sight, the stay the player was in then (a relation relays only
/// while the player is still in that stay, so a player that left and joined again
/// while the creature lies released hears nothing of the earlier stay), and whether the creature's snapshot of that generation is
/// awaited or has been relayed. The map relays a creature's news only to a viewer that
/// is `Relaying`.
pub type Relation {
  Relation(generation: Generation, stay: Stay, state: RelationState)
}

/// Where a relation is in the creature's first picture for the viewer.
pub type RelationState {
  /// The map sent the creature `Seen` and has not taken its `Snapshot` of this
  /// generation: news is dropped, since the snapshot is built after everything the
  /// creature sent earlier.
  AwaitingSnapshot
  /// The snapshot was relayed: the viewer holds the creature's picture, and the
  /// creature's news follows it in the order the map takes it.
  Relaying
}

/// One player in the map: the stay its connection's Join named, its unit, the
/// watch on its connection, the players
/// it sees, each as a `Relation` holding the generation of that sight, which the map gave when
/// the pair came into sight, this player's stay then and the state of the owner's snapshot
/// (the sight is symmetric, so a pair is in one
/// player's `sees` exactly when it is in the other's, each way with its own relation), the spawns of the
/// map's world it sees, whatever their creature's state (a spawn is in `seen`
/// exactly when it is within sight of the player's place), the static objects
/// it sees (`objects`, likewise), whether it is ready,
/// the move sequence number of its place, the hostile spawns whose ring it
/// stands in, empty until it is ready and while it is stealthed or dead, and whether it
/// is stealthed and whether it is alive, as its connection last told, and the
/// visibility prerequisites that fail for it, as its join or its connection last
/// told (`Join`, `VisibilityChanged`): a static object or a spawn whose creature's
/// visibility prerequisite is in `hidden` is in neither `objects` nor `seen`.
type Player {
  Player(
    stay: Stay,
    address: UnitAddress,
    unit: PlayerUnit,
    watch: WatchId,
    sees: Dict(ConnectionId, Relation),
    seen: Set(SpawnId),
    objects: Set(SpawnId),
    readiness: Readiness,
    seq: Int,
    inside: Set(SpawnId),
    stealth: Stealth,
    life: Life,
    hidden: Set(PrerequisiteId),
  )
}

/// Whether a player is stealthed, as its connection last told (`StealthChanged`):
/// a connection that never told is `NotStealthed`, as a new cast state is.
type Stealth {
  NotStealthed
  Stealthed
}

/// Whether a player is alive, as its join or its connection last told (`Join`,
/// `LifeChanged`): a player that enters dead is `Dead`.
type Life {
  Alive
  Dead
}

/// A summon whose creature's start has no outcome yet: the connection that asked
/// and the unit id the creature started under, held under the run-only spawn id
/// until the timer started with the creature fires or its start is found to have
/// failed.
type Summoning {
  Summoning(caller: CallerId, unit_id: Int)
}

/// Whether a player's client has finished loading the world: a creature fights
/// only a ready player.
type Readiness {
  /// Its client has sent no 0xF2 in this stay.
  StillLoading
  /// Its client sent the stay's first 0xF2.
  Loaded
}

/// Why a player is removed: it left, and its connection said so itself, or its
/// connection ended, and said nothing.
type Removal {
  Camped
  Ended
}

/// The state of the spawn, or `Error(Nil)` for a dormant one.
pub fn spawn_state(
  state state: State,
  spawn spawn: SpawnId,
) -> Result(SpawnState, Nil) {
  dict.get(state.spawns, spawn)
}

/// The run-only spawn the map keeps under the id, or `Error(Nil)`, for a test.
pub fn run_spawn(
  state state: State,
  spawn spawn: SpawnId,
) -> Result(Spawn, Nil) {
  dict.get(state.run_spawns, spawn)
}

/// The unit id the map holds for the spawn this run, or `Error(Nil)`, for a test.
pub fn unit_id_of(
  state state: State,
  spawn spawn: SpawnId,
) -> Result(Int, Nil) {
  dict.get(state.unit_of_spawn, spawn)
}

/// The map's rule, as its service shell runs it.
pub fn rule(
  map map: MapId,
  incarnation incarnation: Int,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
  spawns spawns: WorldSpawns,
  summons summons: spawn.SummonChecks,
  kinds kinds: Kinds,
  numbers numbers: GameNumbers,
  idle_stop_ms idle_stop_ms: Int,
  sweep_ms sweep_ms: Int,
) -> ServiceRule(Settings, State, Message, Outgoing) {
  step.Rule(
    name: rule_name,
    settings: Settings(
      map:,
      incarnation:,
      realm_id:,
      tables:,
      spawns:,
      summons:,
      kinds:,
      numbers:,
      idle_stop_ms:,
      sweep_ms:,
    ),
    new:,
    step:,
  )
}

/// A map's first state: no players and every spawn dormant; unit id 1 and watch
/// 1 are next.
pub fn new(settings: Settings) -> State {
  State(
    settings:,
    players: dict.new(),
    watches: dict.new(),
    by_address: dict.new(),
    spawns: dict.new(),
    creature_watches: dict.new(),
    unit_of_spawn: dict.new(),
    captives: spawn.captives(world: settings.spawns, tables: settings.tables),
    released_objects: set.new(),
    run_spawns: dict.new(),
    summoning: dict.new(),
    next_run_only_id: spawn_source.first_run_only_id,
    next_unit_id: 1,
    next_address: 1,
    next_watch: 1,
    next_generation: generation.first(),
    started_ms: 0,
  )
}

/// One input in, the new state and what the shell must do out, as the
/// sequences above give. An input a service's shell never gives is a bug, and
/// crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Outgoing)) {
  case input.event {
    OwnEvent(Started) ->
      started(State(..state, started_ms: input.now.monotonic_ms))
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(step.CreatureNotStarted(watch:, reason:)) ->
      creature_not_started(state:, watch:, reason:)
    OwnEvent(ServiceTimerFired(timer:)) ->
      timer_fired(state:, timer:, now_ms: input.now.monotonic_ms)
    OwnEvent(Asked(
      caller:,
      message: Join(connection:, character:, place:, stay:, alive:, hidden:),
    )) ->
      joined(
        state:,
        caller:,
        connection:,
        character:,
        place:,
        stay:,
        alive:,
        hidden:,
        now_ms: input.now.monotonic_ms,
      )
    OwnEvent(Asked(caller:, message: Leave(connection:))) ->
      left(state:, caller:, connection:, now_ms: input.now.monotonic_ms)
    OwnEvent(Told(message: Moved(connection:, place:, seq:))) ->
      moved(state:, connection:, place:, seq:, now_ms: input.now.monotonic_ms)
    OwnEvent(Told(message: Ready(connection:, seq:))) ->
      ready(state:, connection:, seq:)
    OwnEvent(Told(message: StealthChanged(connection:, stealthed:))) ->
      stealth_changed(state:, connection:, stealthed:)
    OwnEvent(Told(message: LifeChanged(connection:, alive:))) ->
      life_changed(state:, connection:, alive:)
    OwnEvent(Told(message: VisibilityChanged(connection:, hidden:))) ->
      visibility_changed(
        state:,
        connection:,
        hidden:,
        now_ms: input.now.monotonic_ms,
      )
    OwnEvent(Told(message: Released(unit_id:))) ->
      released(state:, unit_id:, now_ms: input.now.monotonic_ms)
    OwnEvent(Asked(caller:, message: Summon(connection:, creature_id:, level:))) ->
      summoned(state:, caller:, connection:, creature_id:, level:)
    OwnEvent(Told(message: Snapshot(unit_id:, life:, by:, generation:, burst:))) ->
      snapshot_taken(state:, unit_id:, life:, by:, generation:, burst:)
    OwnEvent(Told(message: Broadcast(unit_id:, life:, news:))) ->
      broadcast(state:, unit_id:, life:, news:)
    OwnEvent(Told(message: Relay(unit_id:, life:, to:, payload:))) ->
      relayed(state:, unit_id:, life:, to:, payload:)
    OwnEvent(Told(message: Expired(unit_id:, life:))) ->
      expired(state:, unit_id:, life:)
    OwnEvent(Told(message: TellCreature(from:, unit_id:, life:, payload:))) ->
      told_creature(state:, from:, unit_id:, life:, payload:)
    OwnEvent(Told(message: PlayerSnapshot(
      by:,
      stay:,
      viewer:,
      generation:,
      burst:,
    ))) ->
      player_snapshot_taken(state:, by:, stay:, viewer:, generation:, burst:)
    OwnEvent(Told(message: PlayerBroadcast(from:, stay:, news:))) ->
      player_broadcast(state:, from:, stay:, news:)
    OwnEvent(Told(message: TellLanding(from:, stay:, to:, to_stay:, landing:))) ->
      landing_told(state:, from:, stay:, to:, to_stay:, landing:)
    OwnEvent(Told(message: Say(from:, stay:, said:))) ->
      line_said(state:, from:, stay:, said:)
    OwnEvent(Asked(message: Moved(..), ..))
    | OwnEvent(Asked(message: PlayerSnapshot(..), ..))
    | OwnEvent(Asked(message: PlayerBroadcast(..), ..))
    | OwnEvent(Asked(message: TellLanding(..), ..))
    | OwnEvent(Asked(message: Say(..), ..))
    | OwnEvent(Asked(message: Snapshot(..), ..))
    | OwnEvent(Asked(message: Broadcast(..), ..))
    | OwnEvent(Asked(message: Relay(..), ..))
    | OwnEvent(Asked(message: Expired(..), ..))
    | OwnEvent(Asked(message: TellCreature(..), ..))
    | OwnEvent(Asked(message: Ready(..), ..))
    | OwnEvent(Asked(message: StealthChanged(..), ..))
    | OwnEvent(Asked(message: LifeChanged(..), ..))
    | OwnEvent(Asked(message: VisibilityChanged(..), ..))
    | OwnEvent(Asked(message: Released(..), ..))
    | OwnEvent(Told(message: Join(..)))
    | OwnEvent(Told(message: Leave(..)))
    | OwnEvent(Told(message: Summon(..))) ->
      panic as "a map is asked Join, Leave and Summon and told Moved, Ready, StealthChanged, LifeChanged, VisibilityChanged, Released, Snapshot, Broadcast, Relay, Expired, TellCreature, PlayerSnapshot, PlayerBroadcast, TellLanding and Say only"
    WatchEnded(watch:) ->
      case dict.get(state.creature_watches, watch) {
        Ok(spawn) -> creature_ended(state:, spawn:, watch:)
        Error(Nil) -> ended(state:, watch:, now_ms: input.now.monotonic_ms)
      }
  }
}

/// A development summon: the creature is made a run-only spawn at the place and
/// facing the map holds for the connection's player, under the next run-only id
/// (`spawn_source.run_only_id_after`, so never a stored id), checked as a spawn
/// is (`spawn.summoned`), and started for the players who see that place under a
/// new life, as a dormant spawn is started when its first viewer comes; the
/// answer waits for the start's outcome (`summon_settled`, `summon_not_started`):
/// the asker is held in `summoning`, and a timer of 0 ms under the run-only id is
/// started with the creature, which the shell fires after the start's failure, if
/// there was one. A creature that fails the checks, or a connection with no player
/// here, is `NotSummoned` at once and changes nothing: no id is taken and no
/// creature starts. The spawn is kept in `run_spawns` for as long as its creature
/// lives: sight and rings read it beside the stored spawns, and the creature's
/// end, a corpse's timer included, drops it with no restart timer, since a
/// run-only spawn does not respawn (a server choice: it is a test tool). A map
/// that ends or restarts loses its run-only spawns.
fn summoned(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  creature_id creature_id: Creature2Id,
  level level: Option(Int),
) -> #(State, ServiceStep(Outgoing)) {
  let refused = fn(reason) {
    #(state, Effects([OwnEffect(Reply(caller, NotSummoned(reason:)))]))
  }
  case dict.get(state.players, connection) {
    Error(Nil) -> refused(NoPlayerHere)
    Ok(summoner) -> {
      let id = state.next_run_only_id
      let place = player_unit.place(summoner.unit)
      case
        spawn.summoned(
          checks: state.settings.summons,
          summoned: spawn_source.Summoned(id:, creature_id:, level:, place:),
        )
      {
        Error(refusal) -> refused(CreatureRefused(refusal:))
        Ok(run_spawn) -> {
          let state =
            State(
              ..state,
              run_spawns: dict.insert(state.run_spawns, id, run_spawn),
              next_run_only_id: spawn_source.run_only_id_after(id:),
            )
          let state = standing_for_players(state:, spawn: id, run_spawn:)
          let #(state, started) =
            started_for_those_who_see(state:, spawn: id, ring: [])
          let assert Effects(started_effects) = started
            as "a service rule's step makes no ask"
          let assert Ok(unit_id) = dict.get(state.unit_of_spawn, id)
            as "the summoner sees the place, so the creature started"
          let SpawnId(number) = id
          #(
            State(
              ..state,
              summoning: dict.insert(
                state.summoning,
                id,
                Summoning(caller:, unit_id:),
              ),
            ),
            Effects(
              list.append(started_effects, [
                OwnEffect(StartServiceTimer(timer: TimerId(number), after_ms: 0)),
              ]),
            ),
          )
        }
      }
    }
  }
}

/// The state with each player who sees the new run-only spawn's place having it in
/// `seen`, and each ready, unstealthed one that stands in its ring having it in
/// `inside` (`noticeable_by_rings`, as `rings_holding` reads it), as a move into that
/// place would have left them: the cell index does not hold the spawn, so no later move
/// finds it entered.
fn standing_for_players(
  state state: State,
  spawn spawn: SpawnId,
  run_spawn run_spawn: spawn.Spawn,
) -> State {
  let range = state.settings.numbers.aggro_range
  State(
    ..state,
    players: dict.map_values(state.players, fn(_connection, player) {
      let place = player_unit.place(player.unit)
      let seen = case sight.sees(place, run_spawn.place) {
        True -> set.insert(player.seen, spawn)
        False -> player.seen
      }
      let inside = case
        noticeable_by_rings(player:)
        && in_ring(
          spawn: run_spawn,
          place:,
          faction_id: player_unit.faction_id(player.unit),
          range:,
        )
      {
        True -> set.insert(player.inside, spawn)
        False -> player.inside
      }
      Player(..player, seen:, inside:)
    }),
  )
}

/// A summon's timer fired: the shell has carried out the start, and gave the
/// rule its failure before this input, so the start did not fail and the asker is
/// answered `Summoned` with the unit id the creature started under, whatever has
/// become of the creature since.
fn summon_settled(
  state state: State,
  spawn spawn: SpawnId,
) -> #(State, ServiceStep(Outgoing)) {
  let assert Ok(Summoning(caller:, unit_id:)) = dict.get(state.summoning, spawn)
    as "a summon's timer fires only for a summon that waits for it"
  #(
    State(..state, summoning: dict.delete(state.summoning, spawn)),
    Effects([OwnEffect(Reply(caller, Summoned(unit_id:)))]),
  )
}

/// The relation the map holds with the player of connection `viewer` as a viewer of the
/// player of connection `owner`, for a test.
pub fn player_relation(
  state state: State,
  owner owner: ConnectionId,
  viewer viewer: ConnectionId,
) -> Option(Relation) {
  dict.get(state.players, viewer)
  |> result.try(fn(player) { dict.get(player.sees, owner) })
  |> option.from_result
}

/// The send of an owner's news to the connection of a viewer, for the stay its relation was
/// made in: what the map relays of a creature's or a player's snapshot and news.
fn news_relayed(
  to to: ConnectionId,
  stay stay: Stay,
  news news: PeerNews,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: Connection(to),
    message: Relayed(stay:, delivered: map_message.News(news:)),
  ))
}

/// An owner's snapshot of a sight of its unit: relayed to the viewer, each item as
/// `Relayed(stay, News(item))` in the order the owner built it, when the owner is in the
/// stay the tell names, the viewer holds a relation of exactly that generation with it, the
/// relation awaits its snapshot and the viewer is still in the stay of the relation; the
/// relation is then `Relaying`. Any other snapshot is dropped, as a creature's is
/// (`snapshot_taken`): one of an earlier generation (the pair left and came back), one
/// taken twice, one after the pair's `PlayerUnseen`, one for a viewer in another stay, one
/// of an earlier stay of the owner. A burst that does not begin with the owner's
/// `Appeared` of that generation is an error line and is not relayed, since the viewer
/// releases the moves it holds by the generation that 0x262 names.
fn player_snapshot_taken(
  state state: State,
  by by: ConnectionId,
  stay stay: Stay,
  viewer viewer: ConnectionId,
  generation generation: Generation,
  burst burst: List(PeerNews),
) -> #(State, ServiceStep(Outgoing)) {
  let ConnectionId(viewer_number) = viewer
  let awaited = {
    use owner <- result.try(dict.get(state.players, by))
    use <- bool.guard(when: owner.stay != stay, return: Error(Nil))
    use viewing <- result.try(dict.get(state.players, viewer))
    use relation <- result.try(dict.get(viewing.sees, by))
    case relation {
      Relation(generation: held, stay: viewing_stay, state: AwaitingSnapshot)
        if held == generation && viewing.stay == viewing_stay
      -> Ok(#(player_unit.unit_id(unit: owner.unit), viewing, viewing_stay))
      Relation(state: AwaitingSnapshot, ..) | Relation(state: Relaying, ..) ->
        Error(Nil)
    }
  }
  case awaited {
    Error(Nil) -> #(state, Effects([]))
    Ok(#(owner_unit_id, viewing, viewing_stay)) ->
      case burst {
        [PeerNews(unit_id:, news: Appeared(generation: shown, ..)), ..]
          if unit_id == owner_unit_id && shown == generation
        -> #(
          State(
            ..state,
            players: dict.insert(
              state.players,
              viewer,
              Player(
                ..viewing,
                sees: dict.insert(
                  viewing.sees,
                  by,
                  Relation(generation:, stay: viewing_stay, state: Relaying),
                ),
              ),
            ),
          ),
          Effects(
            list.map(burst, news_relayed(
              to: viewer,
              stay: viewing_stay,
              news: _,
            )),
          ),
        )
        _ -> #(
          state,
          Effects([
            log_error(
              state:,
              about: step.About(..step.no_one, connection: Some(by)),
              text: "the snapshot of the sight "
                <> int.to_string(generation.number(generation:))
                <> " that viewer "
                <> int.to_string(viewer_number)
                <> " has of this player does not begin with the player's own 0x262 of that sight, so it is not relayed",
            ),
          ]),
        )
      }
  }
}

/// News of a player's own unit: relayed to each viewer whose relation relays, in
/// connection order, as `Relayed(stay, News(news))` for the viewer's stay, and to no viewer
/// awaiting its snapshot or gone from the relations (`broadcast`). News from a player not in
/// the map or in another stay than the tell names (it left, or joined again, while the news
/// was on its way) is dropped; news that names another unit than the sender's is dropped
/// with an error line.
fn player_broadcast(
  state state: State,
  from from: ConnectionId,
  stay stay: Stay,
  news news: PeerNews,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, from) {
    Ok(owner) if owner.stay == stay ->
      case news.unit_id == player_unit.unit_id(unit: owner.unit) {
        True -> #(
          state,
          Effects(
            list.map(relaying_viewers(state:, from:, owner:), fn(viewer) {
              news_relayed(to: viewer.0, stay: viewer.1, news:)
            }),
          ),
        )
        False -> #(
          state,
          Effects([
            log_error(
              state:,
              about: step.About(..step.no_one, connection: Some(from)),
              text: "the player told news of unit "
                <> int.to_string(news.unit_id)
                <> ", which is not its unit "
                <> int.to_string(player_unit.unit_id(unit: owner.unit))
                <> ", so it is not relayed",
            ),
          ]),
        )
      }
    Ok(_) | Error(Nil) -> #(state, Effects([]))
  }
}

/// The viewers of the player `from` whose relation with it relays and whose stay is the one
/// the relation was made in, each with that stay, in connection order: the viewers a news or
/// a line of the player reaches. A viewer awaiting its snapshot, gone from the relations or
/// in another stay now is not one.
fn relaying_viewers(
  state state: State,
  from from: ConnectionId,
  owner owner: Player,
) -> List(#(ConnectionId, Stay)) {
  list.filter_map(sorted_by_connection(owner.sees), fn(entry) {
    use viewing <- result.try(dict.get(state.players, entry.0))
    use relation <- result.try(dict.get(viewing.sees, from))
    case relation {
      Relation(state: Relaying, stay: relation_stay, ..)
        if viewing.stay == relation_stay
      -> Ok(#(entry.0, relation_stay))
      Relation(state: Relaying, ..) | Relation(state: AwaitingSnapshot, ..) ->
        Error(Nil)
    }
  })
}

/// One player's landing on another: admitted by the kind's destination and source checks
/// (`relay.landing_kind_of`) and sent as `Relayed(to_stay, Landed(landing))`; a tell that
/// fails a check is dropped.
fn landing_told(
  state state: State,
  from from: ConnectionId,
  stay stay: Stay,
  to to: ConnectionId,
  to_stay to_stay: Stay,
  landing landing: Landing,
) -> #(State, ServiceStep(Outgoing)) {
  let relay.LandingKind(destination: relay.TellsCurrentStay, source:) =
    relay.landing_kind_of(landing:)
  let destination_admits =
    in_current_stay(state:, connection: to, stay: to_stay)
  let source_admits = case source {
    relay.NoLandingSourceCheck -> True
    relay.SenderStayIsCurrent ->
      in_current_stay(state:, connection: from, stay:)
  }
  case destination_admits && source_admits {
    True -> #(
      state,
      Effects([
        OwnEffect(Send(
          to: Connection(to),
          message: Relayed(
            stay: to_stay,
            delivered: map_message.Landed(landing:),
          ),
        )),
      ]),
    )
    False -> #(state, Effects([]))
  }
}

/// A local chat line of a player: relayed to each relaying viewer of the speaker, in
/// connection order, as `Relayed(stay, Said(said))` for the viewer's stay, and to no viewer
/// awaiting its snapshot or gone from the relations. A line from a player not in the map or
/// in another stay than the tell names is dropped; one whose speaker names another unit
/// than the sender's is dropped with an error line.
fn line_said(
  state state: State,
  from from: ConnectionId,
  stay stay: Stay,
  said said: ChatSaid,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, from) {
    Ok(owner) if owner.stay == stay ->
      case said.speaker.unit_id == player_unit.unit_id(unit: owner.unit) {
        True -> #(
          state,
          Effects(
            list.map(relaying_viewers(state:, from:, owner:), fn(viewer) {
              OwnEffect(Send(
                to: Connection(viewer.0),
                message: Relayed(
                  stay: viewer.1,
                  delivered: map_message.Said(said:),
                ),
              ))
            }),
          ),
        )
        False -> #(
          state,
          Effects([
            log_error(
              state:,
              about: step.About(..step.no_one, connection: Some(from)),
              text: "the player told a line spoken by unit "
                <> int.to_string(said.speaker.unit_id)
                <> ", which is not its unit "
                <> int.to_string(player_unit.unit_id(unit: owner.unit))
                <> ", so it is not relayed",
            ),
          ]),
        )
      }
    Ok(_) | Error(Nil) -> #(state, Effects([]))
  }
}

/// A creature's snapshot of the sight `generation` of the player of connection `by`:
/// when the creature `unit_id` of life `life` is running, the player holds a relation
/// with it of exactly that generation, the relation awaits its snapshot and the player
/// is still in the stay the relation was made in, the burst is relayed to the player in
/// the order the creature built it, each item as `Relayed(stay, News(item))`, and the
/// relation is `Relaying`. Any other snapshot is dropped: one of an earlier generation
/// (the pair left and came back), one taken twice, one after the player's `Unseen`, one
/// of an earlier life, one for a player that is in another stay now.
fn snapshot_taken(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  by by: UnitAddress,
  generation generation: Generation,
  burst burst: List(PeerNews),
) -> #(State, ServiceStep(Outgoing)) {
  let awaited = {
    use #(spawn, spawn_state) <- result.try(running(state:, unit_id:, life:))
    use relations <- result.try(relations_of(spawn_state:))
    use #(by, _) <- result.try(player_at(state:, address: by))
    use stay <- result.try(case dict.get(relations, by) {
      Ok(Relation(generation: held, stay:, state: AwaitingSnapshot))
        if held == generation
      -> Ok(stay)
      Ok(Relation(state: AwaitingSnapshot, ..))
      | Ok(Relation(state: Relaying, ..))
      | Error(Nil) -> Error(Nil)
    })
    use <- bool.guard(
      when: !in_current_stay(state:, connection: by, stay:),
      return: Error(Nil),
    )
    Ok(#(spawn, spawn_state, relations, stay, by))
  }
  case awaited {
    Ok(#(spawn, spawn_state, relations, stay, by)) -> #(
      State(
        ..state,
        spawns: dict.insert(
          state.spawns,
          spawn,
          with_relations(
            spawn_state:,
            relations: dict.insert(
              relations,
              by,
              Relation(generation:, stay:, state: Relaying),
            ),
          ),
        ),
      ),
      Effects(list.map(burst, news_relayed(to: by, stay:, news: _))),
    )
    Error(Nil) -> #(state, Effects([]))
  }
}

/// News the creature `unit_id` of life `life` tells every viewer: it is relayed to
/// each player whose relation with the creature is `Relaying` and who is still in the
/// stay of the relation, in connection order, as `Relayed(stay, News(news))` for that
/// stay; a player whose relation awaits its snapshot is sent none, since the snapshot
/// comes after everything the creature sent earlier, and a player that is not in the
/// relations is sent none.
fn broadcast(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  news news: PeerNews,
) -> #(State, ServiceStep(Outgoing)) {
  let relaying = {
    use #(_, spawn_state) <- result.try(running(state:, unit_id:, life:))
    use relations <- result.try(relations_of(spawn_state:))
    Ok(
      list.filter_map(sorted_by_connection(relations), fn(entry) {
        case entry.1 {
          Relation(state: Relaying, stay:, ..) ->
            case in_current_stay(state:, connection: entry.0, stay:) {
              True -> Ok(news_relayed(to: entry.0, stay:, news:))
              False -> Error(Nil)
            }
          Relation(state: AwaitingSnapshot, ..) -> Error(Nil)
        }
      }),
    )
  }
  #(state, Effects(result.unwrap(relaying, [])))
}

/// A creature's tell to one player: sent as `Relayed(stay, Tell(payload))` to the
/// connection that joined the unit `to`, for the stay of that join, when `admitted` finds
/// the creature running and `to` a unit of this run, and dropped otherwise.
fn relayed(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  to to: UnitAddress,
  payload payload: Payload,
) -> #(State, ServiceStep(Outgoing)) {
  case admitted(state:, unit_id:, life:, to:, payload:) {
    Ok(delivery) -> #(
      state,
      Effects([
        OwnEffect(Send(
          to: Connection(delivery.to),
          message: Relayed(
            stay: delivery.stay,
            delivered: map_message.Tell(payload: delivery.payload),
          ),
        )),
      ]),
    )
    Error(CreatureEnded) | Error(DestinationRefused) -> #(state, Effects([]))
  }
}

/// A relay the map delivers: to the connection that joined the unit the relay named, for
/// the stay of that join (the address-to-connection translation of `player_at`), the
/// payload.
pub type Delivery {
  Delivery(to: ConnectionId, stay: Stay, payload: Payload)
}

/// Why the map dropped a relay.
pub type Dropped {
  /// The spawn of the creature is not running under that unit id and life: it
  /// ended, or the relay is of an earlier life.
  CreatureEnded
  /// The destination check of the payload's kind failed: the unit the relay names is not
  /// a unit of this run, as one that left or ended is not (`relay.kind_of`).
  DestinationRefused
}

/// Whether a relay of the creature `unit_id` of life `life` is delivered: the spawn
/// of that unit must be live, retiring, respawning or releasing under that life (a creature
/// that has been told to end, or has expired, may still answer its last strikes), and then the destination
/// check of the payload's kind must pass (`relay.kind_of`): the unit `to` is a unit of
/// this run, and the delivery goes to the connection that joined it, for its stay.
pub fn admitted(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  to to: UnitAddress,
  payload payload: Payload,
) -> Result(Delivery, Dropped) {
  use _ <- result.try(result.replace_error(
    running(state:, unit_id:, life:),
    CreatureEnded,
  ))
  let relay.Kind(destination: relay.UnitOfRun, source: relay.NoSourceCheck) =
    relay.kind_of(payload:)
  case player_at(state:, address: to) {
    Ok(#(connection, player)) ->
      Ok(Delivery(to: connection, stay: player.stay, payload:))
    Error(Nil) -> Error(DestinationRefused)
  }
}

/// The connection and player that joined the unit `address`, while the unit is in this
/// run: the translation from a creature's name of a player to the connection and the
/// connection's stay the player interface still names (`Delivery`, the log's `About`).
/// Nothing is found for an address the map did not issue, or one whose unit left or
/// ended.
fn player_at(
  state state: State,
  address address: UnitAddress,
) -> Result(#(ConnectionId, Player), Nil) {
  use connection <- result.try(dict.get(state.by_address, address))
  use player <- result.map(dict.get(state.players, connection))
  #(connection, player)
}

/// A player's tell to a creature: sent as `ToldCreature(by, payload)` when
/// `admitted_inbound` finds the creature running and the payload's source check passed,
/// and dropped otherwise; a strike that names another striker than the relay's is
/// dropped with an error line.
fn told_creature(
  state state: State,
  from from: UnitAddress,
  unit_id unit_id: Int,
  life life: Int,
  payload payload: Inbound,
) -> #(State, ServiceStep(Outgoing)) {
  case admitted_inbound(state:, unit_id:, life:, from:, payload:) {
    Ok(delivery) -> #(
      state,
      Effects([
        OwnEffect(Send(
          to: step.Creature(
            map: state.settings.map,
            incarnation: state.settings.incarnation,
            unit_id: delivery.unit_id,
            life: delivery.life,
          ),
          message: ToldCreature(by: delivery.by, payload: delivery.payload),
        )),
      ]),
    )
    Error(NotRunning) | Error(SourceRefused) -> #(state, Effects([]))
    Error(StrikerRefused) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(
            ..step.no_one,
            connection: option.from_result(
              result.map(player_at(state:, address: from), fn(found) { found.0 }),
            ),
          ),
          text: "a connection told a creature a strike that names another striker than the unit the tell came from",
        ),
      ]),
    )
  }
}

/// A player's tell the map delivers to a creature: the creature's address, and what it
/// is told, with the sender's unit address the relay named.
pub type InboundDelivery {
  InboundDelivery(unit_id: Int, life: Int, by: UnitAddress, payload: Inbound)
}

/// Why the map dropped a player's tell to a creature.
pub type InboundDropped {
  /// The spawn of the creature is not running under that unit id and life: it ended,
  /// or the tell is of an earlier life.
  NotRunning
  /// The source check of the payload's kind failed: the sender is not a unit of this run
  /// (`relay.inbound_kind_of`).
  SourceRefused
  /// A strike names another unit or a creature as its striker than the relay's sender.
  StrikerRefused
}

/// Whether a tell of the player of the unit `from` to the creature `unit_id` of life
/// `life` is delivered: the spawn of that unit must be live, retiring, respawning or
/// releasing under that life, the payload's source check must pass
/// (`relay.inbound_kind_of`), and a strike must name the relay's sender as its striker. Whatever the sender sees does not matter, and a sender that left may still
/// strike or answer.
pub fn admitted_inbound(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  from from: UnitAddress,
  payload payload: Inbound,
) -> Result(InboundDelivery, InboundDropped) {
  use _ <- result.try(result.replace_error(
    running(state:, unit_id:, life:),
    NotRunning,
  ))
  let relay.InboundKind(destination: relay.RunningCreature, source:) =
    relay.inbound_kind_of(inbound: payload)
  use _ <- result.try(case source {
    relay.NoSenderCheck -> Ok(Nil)
    relay.SenderUnitOfRun ->
      case player_at(state:, address: from) {
        Ok(_) -> Ok(Nil)
        Error(Nil) -> Error(SourceRefused)
      }
  })
  use _ <- result.try(case payload {
    map_message.Strike(tell:) ->
      case strike_tell.player_sender(tell:) == Ok(from) {
        True -> Ok(Nil)
        False -> Error(StrikerRefused)
      }
    map_message.TargetMoved(..)
    | map_message.StrikeAnswered(..)
    | map_message.ModifierStarts(..)
    | map_message.ModifierEnds(..)
    | map_message.Thrown(..)
    | map_message.Despawn(..)
    | map_message.UnitStates(..)
    | map_message.CastViewSet(..)
    | map_message.CastViewEnds(..)
    | map_message.ControlsEnd(..) -> Ok(Nil)
  })
  Ok(InboundDelivery(unit_id:, life:, by: from, payload:))
}

/// The spawn whose creature runs as `unit_id` under `life`, with its state, while the
/// spawn is live, retiring, respawning or releasing; the creature's watch names the spawn, and
/// the watch goes when the creature ends.
fn running(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
) -> Result(#(SpawnId, SpawnState), Nil) {
  use spawn <- result.try(dict.get(state.creature_watches, WatchId(life)))
  use spawn_state <- result.try(dict.get(state.spawns, spawn))
  use #(held, held_life) <- result.try(running_creature(spawn_state:))
  case held == unit_id && held_life == life {
    True -> Ok(#(spawn, spawn_state))
    False -> Error(Nil)
  }
}

/// The unit id and life of the creature a spawn's state runs: live, retiring, respawning
/// or releasing. A spawn waiting for its restart or failed has none.
fn running_creature(
  spawn_state spawn_state: SpawnState,
) -> Result(#(Int, Int), Nil) {
  case spawn_state {
    Live(unit_id:, life:, ..)
    | Retiring(unit_id:, life:)
    | Respawning(unit_id:, life:)
    | Releasing(unit_id:, life:, ..) -> Ok(#(unit_id, life))
    WaitingForRestart | Failed -> Error(Nil)
  }
}

/// The relations a spawn holds: a live creature's, and a releasing one's as they were
/// when it was released. A retiring creature has none, since the sweep retires only a
/// spawn no one sees.
fn relations_of(
  spawn_state spawn_state: SpawnState,
) -> Result(Dict(ConnectionId, Relation), Nil) {
  case spawn_state {
    Live(relations:, ..) | Releasing(relations:, ..) -> Ok(relations)
    Retiring(..) | Respawning(..) | WaitingForRestart | Failed -> Error(Nil)
  }
}

/// The spawn's state with these relations, for a state that holds relations.
fn with_relations(
  spawn_state spawn_state: SpawnState,
  relations relations: Dict(ConnectionId, Relation),
) -> SpawnState {
  case spawn_state {
    Live(..) -> Live(..spawn_state, relations:)
    Releasing(..) -> Releasing(..spawn_state, relations:)
    Retiring(..) | Respawning(..) | WaitingForRestart | Failed -> spawn_state
  }
}

/// Whether the connection's player is in the map and in the stay `stay` now.
fn in_current_stay(
  state state: State,
  connection connection: ConnectionId,
  stay stay: Stay,
) -> Bool {
  case dict.get(state.players, connection) {
    Ok(player) -> player.stay == stay
    Error(Nil) -> False
  }
}

/// A map's start: its clock is set and the sweep timer starts. No creature
/// starts: a spawn gets one when a player first sees it.
fn started(state: State) -> #(State, ServiceStep(Outgoing)) {
  #(
    state,
    Effects([
      OwnEffect(StartServiceTimer(
        timer: sweep_timer,
        after_ms: state.settings.sweep_ms,
      )),
    ]),
  )
}

/// The next unit id, and the map that has given it. Ids start at 1 and go up to
/// `unit_id_limit` less one, about a million, one for each player that joins,
/// each spawn that first has a creature or object, each summoned spawn and each
/// creature that crashed and is replaced (after its kind's respawn time). A busy
/// map can reach the limit: 1,000 joins an hour give all of them in about 44
/// days. A map that has given them all crashes, which ends its run and its
/// players' connections; the next run starts from 1.
fn take_unit_id(state: State) -> #(State, Int) {
  let unit_id = state.next_unit_id
  case unit_id < unit_id_limit {
    True -> #(State(..state, next_unit_id: unit_id + 1), unit_id)
    False -> panic as "a map has given every unit id below 2^20"
  }
}

/// The next unit address, and the map that has issued it: the map, its run and the next
/// number, which only grows, so no join of a run is given an address another join had
/// (`unit_address`).
fn issue_address(
  state state: State,
  joiner joiner: ConnectionId,
) -> #(State, UnitAddress) {
  let ConnectionId(joiner_number) = joiner
  #(
    State(..state, next_address: state.next_address + 1),
    unit_address.issue(
      map: state.settings.map,
      incarnation: state.settings.incarnation,
      number: state.next_address,
      joiner: joiner_number,
    ),
  )
}

/// The unit id of the ghost of the player whose unit is `unit_id`: `unit_id_limit`
/// plus the player's id, so it is never an id a map gives (all are below the
/// limit), each player has one, and no map is asked for it. The server's choice:
/// the client takes any 32-bit id for a ghost's 0x262
/// (`0x140096970`), and a ghost never casts, so its id need not fit the cast id's
/// 2^20 (`0x140561c30`).
pub fn ghost_unit_id(unit_id unit_id: Int) -> Int {
  unit_id_limit + unit_id
}

/// A creature told it expired: a live spawn of that unit and life becomes `Respawning`,
/// holding no relations, with no one told, since the creature removed its unit from every
/// viewer before it expired. A spawn in any other state, or of another life, is left as it
/// is: the creature was told to retire or the player's use released it, and its end is
/// handled as that one's.
fn expired(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case running(state:, unit_id:, life:) {
    Ok(#(spawn, Live(..))) -> #(
      State(
        ..state,
        spawns: dict.insert(state.spawns, spawn, Respawning(unit_id:, life:)),
      ),
      Effects([]),
    )
    Ok(#(_, Retiring(..)))
    | Ok(#(_, Respawning(..)))
    | Ok(#(_, Releasing(..)))
    | Ok(#(_, WaitingForRestart))
    | Ok(#(_, Failed))
    | Error(Nil) -> #(state, Effects([]))
  }
}

/// A creature that did not start: an error line, and its spawn stays empty for
/// the rest of the run, with no later creature and no one told.
fn creature_not_started(
  state state: State,
  watch watch: WatchId,
  reason reason: String,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.creature_watches, watch) {
    Ok(spawn) -> {
      let SpawnId(number) = spawn
      use <- bool.lazy_guard(
        when: dict.has_key(state.run_spawns, spawn),
        return: fn() { summon_not_started(state:, spawn:, watch:, reason:) },
      )
      #(
        State(
          ..state,
          spawns: dict.insert(state.spawns, spawn, Failed),
          creature_watches: dict.delete(state.creature_watches, watch),
        ),
        Effects([
          log_error(
            state:,
            about: step.no_one,
            text: "the creature of spawn "
              <> int.to_string(number)
              <> " did not start, so its spawn stays empty: "
              <> reason,
          ),
        ]),
      )
    }
    Error(Nil) -> panic as "a creature that did not start was never started"
  }
}

/// A summoned creature that did not start: an error line, the asker is answered
/// `NotSummoned` with the reason, the timer that would have answered it is
/// cancelled, and the run-only spawn is dropped as if it had never been made.
fn summon_not_started(
  state state: State,
  spawn spawn: SpawnId,
  watch watch: WatchId,
  reason reason: String,
) -> #(State, ServiceStep(Outgoing)) {
  let SpawnId(number) = spawn
  let assert Ok(Summoning(caller:, ..)) = dict.get(state.summoning, spawn)
    as "a run-only creature is started for a summon whose asker waits"
  let state =
    State(
      ..without_run_spawn(state:, spawn:),
      creature_watches: dict.delete(state.creature_watches, watch),
      summoning: dict.delete(state.summoning, spawn),
    )
  #(
    state,
    Effects([
      log_error(
        state:,
        about: step.no_one,
        text: "the creature summoned as run-only spawn "
          <> int.to_string(number)
          <> " did not start: "
          <> reason,
      ),
      OwnEffect(CancelServiceTimer(timer: TimerId(number))),
      OwnEffect(Reply(caller, NotSummoned(reason: CreatureNotStarted(reason:)))),
    ]),
  )
}

/// The state with the run-only spawn, its spawn state and its unit id dropped,
/// and the spawn out of every player's `seen` and `inside`.
fn without_run_spawn(state state: State, spawn spawn: SpawnId) -> State {
  State(
    ..state,
    run_spawns: dict.delete(state.run_spawns, spawn),
    spawns: dict.delete(state.spawns, spawn),
    unit_of_spawn: dict.delete(state.unit_of_spawn, spawn),
    players: dict.map_values(state.players, fn(_connection, player) {
      Player(
        ..player,
        seen: set.delete(player.seen, spawn),
        inside: set.delete(player.inside, spawn),
      )
    }),
  )
}

/// The sweep: every live spawn idle for `idle_stop_ms` or more is sent `Retire`
/// and becomes retiring, in the order of the spawns, and the sweep timer starts
/// again. A run-only spawn is never retired: its spawn would go dormant and a
/// creature would stand there again at full health, which is a respawn.
fn swept(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let idle =
    dict.to_list(state.spawns)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        Live(unit_id:, life:, idle_since_ms: Some(since_ms), ..)
          if now_ms - since_ms >= state.settings.idle_stop_ms
        -> Ok(#(entry.0, unit_id, life))
        Live(..)
        | Retiring(..)
        | Respawning(..)
        | Releasing(..)
        | WaitingForRestart
        | Failed -> Error(Nil)
      }
    })
    |> list.filter(fn(idle) { !dict.has_key(state.run_spawns, idle.0) })
    |> list.sort(fn(first, second) { compare_spawns(first.0, second.0) })
  let spawns =
    list.fold(idle, state.spawns, fn(spawns, retired) {
      dict.insert(
        spawns,
        retired.0,
        Retiring(unit_id: retired.1, life: retired.2),
      )
    })
  #(
    State(..state, spawns:),
    Effects(
      list.append(
        list.map(idle, fn(retired) {
          tell_creature(
            state:,
            unit_id: retired.1,
            life: retired.2,
            message: Retire,
          )
        }),
        [
          OwnEffect(StartServiceTimer(
            timer: sweep_timer,
            after_ms: state.settings.sweep_ms,
          )),
        ],
      ),
    ),
  )
}

/// A creature's watch ended. A live creature crashed: every player is sent
/// `Gone` of its unit, the unit id is given up, and the spawn's restart timer
/// starts. A live run-only creature ended, by its corpse timer or a crash: every
/// player is sent `Gone`, and the run-only spawn is dropped with no timer. A retiring one ended cleanly, whatever the reason: the spawn is
/// dormant with its unit id kept, or, when a player sees it now, a creature
/// starts at once under the same unit id and a new life, with those players as
/// its first viewers. A respawning one (its creature told `Expired`) starts the same
/// way, and the players of the spawn's ring (`ring_of`) go in the start for the creature to
/// aggro in one step. A releasing one gives `Gone` to every player and waits the release time.
fn creature_ended(
  state state: State,
  spawn spawn: SpawnId,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  let state =
    State(..state, creature_watches: dict.delete(state.creature_watches, watch))
  case dict.get(state.spawns, spawn) {
    Ok(Live(unit_id:, ..)) -> {
      use <- bool.lazy_guard(
        when: dict.has_key(state.run_spawns, spawn),
        return: fn() {
          #(
            without_run_spawn(state:, spawn:),
            Effects(gone_to_every_player(state:, unit_id:)),
          )
        },
      )
      waiting_for_restart(
        state:,
        spawn:,
        unit_id:,
        after_ms: restart_ms(state:, spawn:),
      )
    }
    Ok(Retiring(..)) -> started_for_those_who_see(state:, spawn:, ring: [])
    Ok(Respawning(..)) ->
      started_for_those_who_see(state:, spawn:, ring: ring_of(state:, spawn:))
    Ok(Releasing(unit_id:, wait_ms:, ..)) ->
      waiting_for_restart(state:, spawn:, unit_id:, after_ms: wait_ms)
    Ok(WaitingForRestart) | Ok(Failed) | Error(Nil) ->
      panic as "a watch ended for a creature the map holds no live, retiring, respawning or released spawn for"
  }
}

/// How long a spawn whose creature crashed waits before a creature starts there
/// again: the respawn time of its creature's kind (genesis_prime/shared/creature_kind).
fn restart_ms(state state: State, spawn spawn: SpawnId) -> Int {
  case dict.get(state.settings.spawns.by_id, spawn) {
    Ok(found) ->
      creature_kind.kind_of(
        kinds: state.settings.kinds,
        creature2_id: { found.creature_id }.value,
      ).respawn_ms
    Error(Nil) ->
      panic as "a creature crashed for a spawn the map's world does not hold"
  }
}

/// A timer fired: the sweep's, a run-only spawn's summon settling, a released
/// static object's return, or a creature spawn's restart, told apart by the timer's
/// number (the sweep's own, then the spawn's).
fn timer_fired(
  state state: State,
  timer timer: TimerId,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let TimerId(number) = timer
  let spawn = SpawnId(number)
  use <- bool.lazy_guard(when: timer == sweep_timer, return: fn() {
    swept(state:, now_ms:)
  })
  use <- bool.lazy_guard(
    when: spawn_source.is_run_only_id(id: spawn),
    return: fn() { summon_settled(state:, spawn:) },
  )
  case set.contains(state.released_objects, spawn) {
    True -> object_returned(state:, spawn:, now_ms:)
    False -> restart_due(state:, spawn:)
  }
}

/// A spawn's restart timer fired: when a player sees the spawn from where it
/// stands, a creature starts there under the next unit id with those players as
/// its first viewers; when none does, the spawn is dormant.
fn restart_due(
  state state: State,
  spawn spawn: SpawnId,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.spawns, spawn) {
    Ok(WaitingForRestart) -> started_for_those_who_see(state:, spawn:, ring: [])
    Ok(Live(..))
    | Ok(Retiring(..))
    | Ok(Respawning(..))
    | Ok(Releasing(..))
    | Ok(Failed)
    | Error(Nil) ->
      panic as "a restart timer fired for a spawn that does not wait for one"
  }
}

/// A spawn whose creature a release can end, with that creature's unit and life.
type Releasable {
  /// A live creature: it is told `Retire`, and its relations stay as they were.
  LiveReleasable(
    spawn: SpawnId,
    unit_id: Int,
    life: Int,
    relations: Dict(ConnectionId, Relation),
  )
  /// A creature that expired and has not ended: it stops by itself, so it is told
  /// nothing, and it holds no relations.
  ExpiredReleasable(spawn: SpawnId, unit_id: Int, life: Int)
}

/// The spawn's creature when a release can end it: live or expired, and not one of a
/// fight's run spawns.
fn releasable(
  state state: State,
  spawn spawn: SpawnId,
) -> Result(Releasable, Nil) {
  use <- bool.guard(
    when: dict.has_key(state.run_spawns, spawn),
    return: Error(Nil),
  )
  case dict.get(state.spawns, spawn) {
    Ok(Live(unit_id:, life:, relations:, ..)) ->
      Ok(LiveReleasable(spawn:, unit_id:, life:, relations:))
    Ok(Respawning(unit_id:, life:)) ->
      Ok(ExpiredReleasable(spawn:, unit_id:, life:))
    Ok(Retiring(..))
    | Ok(Releasing(..))
    | Ok(WaitingForRestart)
    | Ok(Failed)
    | Error(Nil) -> Error(Nil)
  }
}

/// A player's use released the unit `unit_id` (`Released`). The release goes
/// ahead only when the unit's own spawn is a live creature, a creature that expired
/// and has not ended, or a static object not yet released; any other spawn (a retiring or releasing creature, a second
/// release of an object, a unit the map no longer holds) changes nothing. Then the
/// unit's spawn and the spawns that stand at its x and z (`spawn.captives`, found
/// when the map was built) go, each by its kind. A live creature's spawn becomes
/// `Releasing` with the release time as its wait and its creature is told
/// `Retire`, as the sweep tells an idle one; `creature_ended` then sends everyone
/// `Gone`. One that expired becomes `Releasing` with no relations and is told nothing, since it
/// stops by itself, and `creature_ended` does the same. A static object not yet released joins `released_objects`, every
/// player's objects are decided again so each who saw it is sent `ObjectsUnseen`,
/// and its timer starts for the release time. A captive of neither kind, or
/// already released, is left as it is.
fn released(
  state state: State,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let held = fn(spawn) {
    case dict.get(state.spawns, spawn) {
      Ok(Live(..)) | Ok(Respawning(..)) -> True
      Ok(Retiring(..))
      | Ok(Releasing(..))
      | Ok(WaitingForRestart)
      | Ok(Failed) -> False
      Error(Nil) -> releasable_object(state:, spawn:)
    }
  }
  case spawn_of_unit(state:, unit_id:) {
    Ok(spawn) -> {
      use <- bool.guard(when: !held(spawn), return: #(state, Effects([])))
      let group = [
        spawn,
        ..dict.get(state.captives, spawn)
        |> result.unwrap([])
      ]
      let creatures =
        list.filter_map(group, fn(spawn) { releasable(state:, spawn:) })
      let objects =
        list.filter(group, fn(spawn) { releasable_object(state:, spawn:) })
      let wait_ms = state.settings.numbers.used_object_release_ms
      let state =
        State(
          ..state,
          spawns: list.fold(creatures, state.spawns, fn(spawns, found) {
            dict.insert(
              spawns,
              found.spawn,
              Releasing(
                unit_id: found.unit_id,
                life: found.life,
                wait_ms:,
                relations: case found {
                  LiveReleasable(relations:, ..) -> relations
                  ExpiredReleasable(..) -> dict.new()
                },
              ),
            )
          }),
          released_objects: list.fold(
            objects,
            state.released_objects,
            set.insert,
          ),
        )
      let #(state, unseen) = case objects {
        [] -> #(state, [])
        [_, ..] -> objects_redecided(state:, now_ms:)
      }
      #(
        state,
        Effects(
          list.flatten([
            list.filter_map(creatures, fn(found) {
              case found {
                LiveReleasable(unit_id:, life:, ..) ->
                  Ok(tell_creature(state:, unit_id:, life:, message: Retire))
                ExpiredReleasable(..) -> Error(Nil)
              }
            }),
            unseen,
            list.map(objects, fn(spawn) {
              let SpawnId(number) = spawn
              OwnEffect(StartServiceTimer(
                timer: TimerId(number),
                after_ms: wait_ms,
              ))
            }),
          ]),
        ),
      )
    }
    Error(Nil) -> #(state, Effects([]))
  }
}

/// Whether `spawn` is a static object of the map's world that a use has not
/// released.
fn releasable_object(state state: State, spawn spawn: SpawnId) -> Bool {
  dict.has_key(state.settings.spawns.objects, spawn)
  && !set.contains(state.released_objects, spawn)
}

/// A released static object's timer fired: the spawn leaves `released_objects`
/// and every player's objects are decided again, so each who is in sight of it is
/// sent `ObjectsSeen` under its unit id. No timer is started.
fn object_returned(
  state state: State,
  spawn spawn: SpawnId,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, effects) =
    objects_redecided(
      state: State(
        ..state,
        released_objects: set.delete(state.released_objects, spawn),
      ),
      now_ms:,
    )
  #(state, Effects(effects))
}

/// Every player's objects decided again after `released_objects` changed: the
/// static objects each sees from where it stands, without the released ones, set
/// against those it was shown (`objects_decided`), in connection order.
fn objects_redecided(
  state state: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let #(state, effects) =
    list.fold(players_in_order(state), #(state, []), fn(held, entry) {
      let #(state, effects) = held
      let #(connection, player) = entry
      let objects =
        stored_in_sight(
          state:,
          place: player_unit.place(player.unit),
          hidden: player.hidden,
        ).1
      let #(state, decided) =
        objects_decided(
          state:,
          to: entry,
          was: player.objects,
          now: objects,
          now_ms:,
        )
      #(
        State(
          ..state,
          players: dict.insert(
            state.players,
            connection,
            Player(..player, objects:),
          ),
        ),
        list.append(effects, decided),
      )
    })
  #(state, effects)
}

/// The spawn whose creature or static object has the unit id `unit_id` this run,
/// the one `unit_of_spawn` holds it for.
fn spawn_of_unit(
  state state: State,
  unit_id unit_id: Int,
) -> Result(SpawnId, Nil) {
  dict.to_list(state.unit_of_spawn)
  |> list.find(fn(entry) { entry.1 == unit_id })
  |> result.map(fn(entry) { entry.0 })
}

/// Every player is sent `Gone` of the unit `unit_id`, the unit id is given up, and
/// the spawn waits `after_ms` for its restart timer.
fn waiting_for_restart(
  state state: State,
  spawn spawn: SpawnId,
  unit_id unit_id: Int,
  after_ms after_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let SpawnId(number) = spawn
  #(
    State(
      ..state,
      spawns: dict.insert(state.spawns, spawn, WaitingForRestart),
      unit_of_spawn: dict.delete(state.unit_of_spawn, spawn),
    ),
    Effects(
      list.append(gone_to_every_player(state:, unit_id:), [
        OwnEffect(StartServiceTimer(timer: TimerId(number), after_ms:)),
      ]),
    ),
  )
}

/// `Gone` of the unit `unit_id` to each player in the map, in connection order.
fn gone_to_every_player(
  state state: State,
  unit_id unit_id: Int,
) -> List(Effect(ServiceEffect(Outgoing))) {
  list.map(players_in_order(state), fn(player) {
    notify(to: player, notice: Gone(unit_id:))
  })
}

/// The spawn is dormant when no player sees it from where it stands, and
/// otherwise a creature starts there with those players as its first viewers. A
/// respawn passes the `ring` of the start, which the creature takes in one step; every
/// other start passes none and sends the creature an `Approached` for each player of
/// the ring after its start (`approaches_at_start`).
fn started_for_those_who_see(
  state state: State,
  spawn spawn: SpawnId,
  ring ring: List(RingMember),
) -> #(State, ServiceStep(Outgoing)) {
  case players_seeing(state:, spawn:) {
    [] -> #(
      State(..state, spawns: dict.delete(state.spawns, spawn)),
      Effects([]),
    )
    viewers -> {
      let #(state, start) = start_creature(state:, spawn:, viewers:, ring:)
      let approaches = case ring {
        [] -> approaches_at_start(state:, spawn:)
        [_, ..] -> []
      }
      #(state, Effects([start, ..approaches]))
    }
  }
}

/// The players in the ring of the spawn that a creature starting there is told of: each
/// ready player whose `inside` holds the spawn, in the order of their connections. The
/// ring was kept while no creature stood there to tell, and `inside` holds no dead and
/// no stealthed player (`noticeable_by_rings`).
fn ring_of(state state: State, spawn spawn: SpawnId) -> List(RingMember) {
  players_in_order(state)
  |> list.filter(fn(player) {
    { player.1 }.readiness == Loaded && set.contains({ player.1 }.inside, spawn)
  })
  |> list.map(fn(player) { ring_member(state:, player: player.1) })
}

/// `Approached` to the creature just started at the spawn from each player of its ring
/// (`ring_of`).
fn approaches_at_start(
  state state: State,
  spawn spawn: SpawnId,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case dict.get(state.spawns, spawn) {
    Ok(Live(unit_id:, life:, ..)) ->
      list.map(ring_of(state:, spawn:), fn(member) {
        tell_creature(state:, unit_id:, life:, message: Approached(member:))
      })
    Ok(Retiring(..))
    | Ok(Respawning(..))
    | Ok(Releasing(..))
    | Ok(WaitingForRestart)
    | Ok(Failed)
    | Error(Nil) -> []
  }
}

/// What a creature is told of a player in its ring (`step.RingMember`).
fn ring_member(state state: State, player player: Player) -> RingMember {
  RingMember(
    by: player.address,
    unit_id: player_unit.unit_id(player.unit),
    place: player_unit.place(player.unit),
    seq: player.seq,
    hit_radius: hit_radius.of_playing(
      tables: state.settings.tables,
      race_id: player_unit.race_id(player.unit),
    ),
  )
}

/// The connections of the players who see the spawn from where they stand, each
/// with its player's stay, in the order of their numbers.
fn players_seeing(
  state state: State,
  spawn spawn: SpawnId,
) -> List(#(ConnectionId, Stay, UnitAddress)) {
  players_in_order(state)
  |> list.filter(fn(player) { set.contains({ player.1 }.seen, spawn) })
  |> list.map(fn(player) {
    #(player.0, { player.1 }.stay, { player.1 }.address)
  })
}

/// The entries of a dict keyed by connection in the order of the connections'
/// numbers, so what is sent to each is the same on every run.
pub fn sorted_by_connection(
  entries: Dict(ConnectionId, value),
) -> List(#(ConnectionId, value)) {
  dict.to_list(entries)
  |> list.sort(fn(first, second) {
    compare_connections(first: first.0, second: second.0)
  })
}

/// The order of two connections by their numbers.
fn compare_connections(
  first first: ConnectionId,
  second second: ConnectionId,
) -> order.Order {
  let ConnectionId(first) = first
  let ConnectionId(second) = second
  int.compare(first, second)
}

/// The players by their connection's number.
fn players_in_order(state: State) -> List(#(ConnectionId, Player)) {
  sorted_by_connection(state.players)
}

fn compare_spawns(first: SpawnId, second: SpawnId) -> order.Order {
  let SpawnId(first) = first
  let SpawnId(second) = second
  int.compare(first, second)
}

/// Where the spawn's creature is started from: the run-only spawn the map keeps,
/// carried whole, or the stored spawn by its id.
fn source_of(
  state state: State,
  spawn spawn: SpawnId,
) -> spawn_source.SpawnSource {
  case dict.get(state.run_spawns, spawn) {
    Ok(run_spawn) ->
      spawn_source.RunOnly(summoned: spawn_source.Summoned(
        id: spawn,
        creature_id: run_spawn.creature_id,
        level: Some(run_spawn.level),
        place: run_spawn.place,
      ))
    Error(Nil) -> spawn_source.Stored(id: spawn)
  }
}

/// Starts a creature at the spawn with these players as its first viewers, each
/// by its connection and its stay: under the spawn's unit id for the run, taken
/// from the counter when the spawn has had none (the first creature there, or the
/// first after a crash gave its id up), and a new life, the number of the watch it
/// is started under. The spawn is then live with those viewers, each in a relation of
/// a generation of its own that awaits the creature's snapshot, which the creature
/// answers the start with (`CreatureStart.viewers`).
fn start_creature(
  state state: State,
  spawn spawn: SpawnId,
  viewers viewers: List(#(ConnectionId, Stay, UnitAddress)),
  ring ring: List(RingMember),
) -> #(State, Effect(ServiceEffect(Outgoing))) {
  let #(state, unit_id) = unit_of(state:, spawn:)
  let #(state, viewers) =
    list.map_fold(viewers, state, fn(state, viewer) {
      let #(state, generation) = issued(state:)
      #(state, #(viewer.0, viewer.1, viewer.2, generation))
    })
  let watch = WatchId(state.next_watch)
  let WatchId(life) = watch
  #(
    State(
      ..state,
      spawns: dict.insert(
        state.spawns,
        spawn,
        Live(
          unit_id:,
          life:,
          relations: dict.from_list(
            list.map(viewers, fn(viewer) {
              #(viewer.0, sight_begun(generation: viewer.3, stay: viewer.1))
            }),
          ),
          idle_since_ms: option.None,
        ),
      ),
      creature_watches: dict.insert(state.creature_watches, watch, spawn),
      next_watch: state.next_watch + 1,
    ),
    OwnEffect(StartCreature(
      watch:,
      creature: CreatureStart(
        map: state.settings.map,
        incarnation: state.settings.incarnation,
        unit_id:,
        life:,
        spawn: source_of(state:, spawn:),
        clock_origin_ms: state.started_ms,
        viewers: list.map(viewers, fn(viewer) { #(viewer.2, viewer.3) }),
        ring:,
      ),
    )),
  )
}

/// The next generation, and the map that has given it.
fn issued(state state: State) -> #(State, Generation) {
  let given = state.next_generation
  #(State(..state, next_generation: generation.after(given)), given)
}

/// What the player at `place` sees of the map's world: the creatures' spawns and
/// the static objects the cell index finds near it, with one `near`, that are
/// within sight, exactly, and the run-only spawns in sight, which the cell index
/// does not hold.
fn world_in_sight(
  state state: State,
  place place: Place,
  hidden hidden: Set(PrerequisiteId),
) -> #(Set(SpawnId), Set(SpawnId)) {
  let #(creatures, objects) = stored_in_sight(state:, place:, hidden:)
  #(
    dict.fold(state.run_spawns, creatures, fn(found, id, run_spawn) {
      case sight.sees(place, run_spawn.place) {
        True -> set.insert(found, id)
        False -> found
      }
    }),
    objects,
  )
}

/// The stored creature spawns and static objects of the map's world within sight
/// of `place`, through the cell index, but those whose visibility prerequisite is
/// in `hidden` (`shown`) and the static objects a use released
/// (`released_objects`). A run-only spawn names none.
fn stored_in_sight(
  state state: State,
  place place: Place,
  hidden hidden: Set(PrerequisiteId),
) -> #(Set(SpawnId), Set(SpawnId)) {
  let spawns = state.settings.spawns
  spawn_cell.near(
    cells: spawns.cells,
    x: start_place.x(place),
    z: start_place.z(place),
    range: sight.range,
  )
  |> list.fold(#(set.new(), set.new()), fn(found, id) {
    let #(creatures, objects) = found
    case dict.get(spawns.by_id, id), dict.get(spawns.objects, id) {
      Ok(spawn), _ ->
        case
          sight.sees(place, spawn.place)
          && shown(visibility: spawn.visibility, hidden:)
        {
          True -> #(set.insert(creatures, id), objects)
          False -> found
        }
      Error(Nil), Ok(object) ->
        case
          sight.sees(place, object.place)
          && shown(visibility: object.visibility, hidden:)
          && !set.contains(state.released_objects, id)
        {
          True -> #(creatures, set.insert(objects, id))
          False -> found
        }
      Error(Nil), Error(Nil) -> found
    }
  })
}

/// Whether a unit with this visibility prerequisite is shown to a player whose
/// failing prerequisites are `hidden`: it is unless its prerequisite is one of them.
fn shown(
  visibility visibility: Option(PrerequisiteId),
  hidden hidden: Set(PrerequisiteId),
) -> Bool {
  case visibility {
    Some(prerequisite_id) -> !set.contains(hidden, prerequisite_id)
    option.None -> True
  }
}

/// The notices of the static objects the player of `to` comes to see (`now`) and
/// stops seeing after it saw `was`, at monotonic time `now_ms`: one
/// `ObjectsSeen` of the objects entered, each as its 0x262 under its spawn's unit
/// id for the run (taken from the counter the first time), stamped with the map's
/// server time, and one `ObjectsUnseen` of the ids of the objects left, each in
/// spawn order; none when a list is empty.
fn objects_decided(
  state state: State,
  to player: #(ConnectionId, Player),
  was was: Set(SpawnId),
  now now: Set(SpawnId),
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  use <- bool.guard(when: was == now, return: #(state, []))
  let server_time_estimate_start =
    server_time(origin_ms: state.started_ms, monotonic_ms: now_ms)
  let #(state, entered) =
    list.map_fold(in_order(set.difference(now, was)), state, fn(state, spawn) {
      let #(state, unit_id) = unit_of(state:, spawn:)
      let assert Ok(object) = dict.get(state.settings.spawns.objects, spawn)
        as "an object in sight is an object of the map's world"
      #(
        state,
        #(
          spawn,
          static_object.create(object:, unit_id:, server_time_estimate_start:),
        ),
      )
    })
  let left =
    list.map(in_order(set.difference(was, now)), fn(spawn) {
      let assert Ok(unit_id) = dict.get(state.unit_of_spawn, spawn)
        as "an object a player saw was given its unit id"
      unit_id
    })
  #(
    state,
    list.flatten([
      case entered {
        [] -> []
        units -> [notify(to: player, notice: ObjectsSeen(units:))]
      },
      case left {
        [] -> []
        unit_ids -> [notify(to: player, notice: ObjectsUnseen(unit_ids:))]
      },
    ]),
  )
}

/// The spawn's unit id for the run, taken from the counter when the spawn has had
/// none, and the map that has given it.
fn unit_of(state state: State, spawn spawn: SpawnId) -> #(State, Int) {
  case dict.get(state.unit_of_spawn, spawn) {
    Ok(unit_id) -> #(state, unit_id)
    Error(Nil) -> {
      let #(state, unit_id) = take_unit_id(state)
      #(
        State(
          ..state,
          unit_of_spawn: dict.insert(state.unit_of_spawn, spawn, unit_id),
        ),
        unit_id,
      )
    }
  }
}

/// The state and effects of the player of `connection` coming to see the spawns
/// `now` after it saw `was`, at monotonic time `now_ms`: a dormant spawn it now
/// sees starts a creature with the player as its first viewer (the creature
/// answers the start with its snapshot), a live one is told `Seen` under a generation
/// of its own, and a retiring, respawning, releasing, waiting or failed one is not told, for the player is
/// found among its viewers when it needs them; for each spawn it no longer sees, a live
/// creature is told `Unseen` of the generation the pair held, the player is sent the
/// notice that the unit is unseen, and the spawn is idle from `now_ms` when the player
/// was its last viewer. The starts come first, in the order of the spawns, then the sends. A
/// spawn the player saw and sees is not told. `stay` is the player's, which a
/// creature names in everything it sends the player.
fn spawns_decided(
  state state: State,
  connection connection: ConnectionId,
  stay stay: Stay,
  address address: UnitAddress,
  was was: Set(SpawnId),
  now now: Set(SpawnId),
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  use <- bool.guard(when: was == now, return: #(state, []))
  let entered = in_order(set.difference(now, was))
  let left = in_order(set.difference(was, now))
  let #(state, starts, sends) =
    list.fold(entered, #(state, [], []), fn(held, spawn) {
      let #(state, starts, sends) = held
      case dict.get(state.spawns, spawn) {
        Error(Nil) -> {
          let #(state, start) =
            start_creature(
              state:,
              spawn:,
              viewers: [#(connection, stay, address)],
              ring: [],
            )
          #(state, [start, ..starts], sends)
        }
        Ok(Live(unit_id:, life:, relations:, ..)) -> {
          let #(state, seen) =
            sight_began(
              state:,
              spawn:,
              unit_id:,
              life:,
              relations:,
              idle_since_ms: option.None,
              connection:,
              stay:,
              address:,
            )
          #(state, starts, [seen, ..sends])
        }
        Ok(Retiring(..))
        | Ok(Respawning(..))
        | Ok(Releasing(..))
        | Ok(WaitingForRestart)
        | Ok(Failed) -> held
      }
    })
  let #(state, sends) =
    list.fold(left, #(state, sends), fn(held, spawn) {
      let #(state, sends) = held
      case dict.get(state.spawns, spawn) {
        Ok(Live(unit_id:, life:, relations:, idle_since_ms:)) -> {
          let ended =
            unseen_sends(
              state:,
              unit_id:,
              life:,
              connection:,
              stay:,
              address:,
              relation: dict.get(relations, connection),
            )
          let relations = dict.delete(relations, connection)
          let idle_since_ms = case dict.is_empty(relations) {
            True -> Some(now_ms)
            False -> idle_since_ms
          }
          #(
            State(
              ..state,
              spawns: dict.insert(
                state.spawns,
                spawn,
                Live(unit_id:, life:, relations:, idle_since_ms:),
              ),
            ),
            list.append(list.reverse(ended), sends),
          )
        }
        Ok(Retiring(..))
        | Ok(Respawning(..))
        | Ok(Releasing(..))
        | Ok(WaitingForRestart)
        | Ok(Failed)
        | Error(Nil) -> #(state, sends)
      }
    })
  #(state, list.append(list.reverse(starts), list.reverse(sends)))
}

/// A player's sight of a live creature begins: under a generation never given before the
/// pair's relation awaits the creature's snapshot, and the creature is told `Seen`.
fn sight_began(
  state state: State,
  spawn spawn: SpawnId,
  unit_id unit_id: Int,
  life life: Int,
  relations relations: Dict(ConnectionId, Relation),
  idle_since_ms idle_since_ms: Option(Int),
  connection connection: ConnectionId,
  stay stay: Stay,
  address address: UnitAddress,
) -> #(State, Effect(ServiceEffect(Outgoing))) {
  let #(state, generation) = issued(state:)
  #(
    State(
      ..state,
      spawns: dict.insert(
        state.spawns,
        spawn,
        Live(
          unit_id:,
          life:,
          relations: dict.insert(
            relations,
            connection,
            sight_begun(generation:, stay:),
          ),
          idle_since_ms:,
        ),
      ),
    ),
    tell_creature(
      state:,
      unit_id:,
      life:,
      message: Seen(by: address, generation:),
    ),
  )
}

/// The sends that end a player's sight of a live creature: the creature is told
/// `Unseen` of the generation the pair held, and the player, in its stay `stay`, is sent
/// the notice that the unit is unseen. Nothing when the pair held no relation.
fn unseen_sends(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  connection connection: ConnectionId,
  stay stay: Stay,
  address address: UnitAddress,
  relation relation: Result(Relation, Nil),
) -> List(Effect(ServiceEffect(Outgoing))) {
  case relation {
    Ok(Relation(generation:, ..)) -> [
      tell_creature(
        state:,
        unit_id:,
        life:,
        message: Unseen(by: address, generation:),
      ),
      OwnEffect(Send(
        to: Connection(connection),
        message: Noticed(stay:, notice: UnitUnseen(unit_id:, generation:)),
      )),
    ]
    Error(Nil) -> []
  }
}

/// The spawns of a set in the order of their numbers.
fn in_order(spawns: Set(SpawnId)) -> List(SpawnId) {
  set.to_list(spawns) |> list.sort(compare_spawns)
}

/// The spawns the player sees by their number, so the sends about them are in
/// one order.
fn seen_in_order(player: Player) -> List(SpawnId) {
  in_order(player.seen)
}

/// The send that tells the creature `unit_id` under `life` that the player of
/// connection `by` sees it (`Seen`) or no longer does (`Unseen`), or that
/// it ends (`Retire`).
fn tell_creature(
  state state: State,
  unit_id unit_id: Int,
  life life: Int,
  message message: Outgoing,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: step.Creature(
      map: state.settings.map,
      incarnation: state.settings.incarnation,
      unit_id:,
      life:,
    ),
    message:,
  ))
}

/// The map's server time at monotonic time `monotonic_ms`, for a map started at
/// `origin_ms` on the same clock: milliseconds on the map's own clock, which
/// started at 0 when the map started (the monotonic time of `Started`), taken mod
/// 2^32 because the client's fields hold 32 bits (opcode.0x638). A player's
/// connection stamps its unit's 0x262 and 0x638s with it from the origin
/// `Joined` carries, in the order it takes its inputs, so they share one clock
/// and for a viewer only go forward. It only goes forward until the map is 49.7
/// days old, when it
/// counts from 0 again: the client takes a time sample only when its signed
/// 32-bit difference from the last is at least half the send interval, and
/// ignores one that is not (FitServerTime 0x14079ab90); its fit across the wrap
/// is not read.
pub fn server_time(
  origin_ms origin_ms: Int,
  monotonic_ms monotonic_ms: Int,
) -> Int {
  { monotonic_ms - origin_ms } % server_time_modulus
}

/// The relation of a sight that has begun: its generation and the viewer's stay, awaiting
/// the owner's snapshot of that generation.
fn sight_begun(generation generation: Generation, stay stay: Stay) -> Relation {
  Relation(generation:, stay:, state: AwaitingSnapshot)
}

/// What a move decides of one pair: the pair that comes into sight is given the two
/// generations of its sights and told both ways, the pair that leaves is told both
/// ways with the generations it held, and a pair that stays as it was changes nothing.
/// `held` is the map, the mover's `sees`, the players and the effects so far.
fn pair_decided(
  held held: #(
    State,
    Dict(ConnectionId, Relation),
    Dict(ConnectionId, Player),
    List(Effect(ServiceEffect(Outgoing))),
  ),
  mover mover: #(ConnectionId, Player),
  other other: #(ConnectionId, Player),
  place place: Place,
) -> #(
  State,
  Dict(ConnectionId, Relation),
  Dict(ConnectionId, Player),
  List(Effect(ServiceEffect(Outgoing))),
) {
  let #(state, mover_sees, players, effects) = held
  let #(connection, mover_player) = mover
  let #(other_connection, player) = other
  let was = dict.has_key(mover_player.sees, other_connection)
  let is = sight.sees(place, player_unit.place(player.unit))
  case was, is {
    False, True -> {
      let #(state, mover_sight) = issued(state:)
      let #(state, other_sight) = issued(state:)
      #(
        state,
        dict.insert(
          mover_sees,
          other_connection,
          sight_begun(generation: mover_sight, stay: mover_player.stay),
        ),
        dict.insert(
          players,
          other_connection,
          Player(
            ..player,
            sees: dict.insert(
              player.sees,
              connection,
              sight_begun(generation: other_sight, stay: player.stay),
            ),
          ),
        ),
        list.append(
          effects,
          comes_into_sight(
            newcomer: mover,
            other:,
            newcomer_sight: mover_sight,
            other_sight:,
          ),
        ),
      )
    }
    True, False -> {
      let #(mover_sight, other_sight) =
        sights_of_pair(
          first: mover_player,
          second: player,
          first_connection: connection,
          second_connection: other_connection,
        )
      #(
        state,
        dict.delete(mover_sees, other_connection),
        dict.insert(
          players,
          other_connection,
          Player(..player, sees: dict.delete(player.sees, connection)),
        ),
        list.append(
          effects,
          goes_out_of_sight(
            first: mover,
            second: other,
            first_sight: mover_sight,
            second_sight: other_sight,
          ),
        ),
      )
    }
    True, True | False, False -> held
  }
}

/// A connection's move: its unit is placed at `place`, and each pair it makes
/// or breaks with a player, by the place it ends at, is told: `SeenBy` both ways
/// for a pair that comes into sight, `UnseenBy` both ways for one that leaves
/// it, each in one step. The map sends no unit and no move. A connection not in
/// the map is an error line and changes nothing.
fn moved(
  state state: State,
  connection connection: ConnectionId,
  place place: Place,
  seq seq: Int,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(..step.no_one, connection: Some(connection)),
          text: "the connection moved in the map, but it is not in it",
        ),
      ]),
    )
    Ok(mover) -> {
      let unit = player_unit.moved(mover.unit, place)
      let #(state, mover_sees, others, effects) =
        dict.fold(
          state.players,
          #(state, mover.sees, state.players, []),
          fn(held, other_connection, player) {
            use <- bool.guard(
              when: other_connection == connection,
              return: held,
            )
            pair_decided(
              held:,
              mover: #(connection, mover),
              other: #(other_connection, player),
              place:,
            )
          },
        )
      let #(seen, objects) =
        world_in_sight(state:, place:, hidden: mover.hidden)
      let #(state, object_effects) =
        objects_decided(
          state:,
          to: #(connection, mover),
          was: mover.objects,
          now: objects,
          now_ms:,
        )
      let #(state, spawn_effects) =
        spawns_decided(
          state:,
          connection:,
          stay: mover.stay,
          address: mover.address,
          was: mover.seen,
          now: seen,
          now_ms:,
        )
      let mover =
        Player(..mover, unit:, sees: mover_sees, seen:, objects:, seq:)
      let #(mover, ring_effects) = case mover.readiness {
        StillLoading -> #(mover, [])
        Loaded -> rings_decided(state:, player: mover)
      }
      #(
        State(..state, players: dict.insert(others, connection, mover)),
        Effects(
          list.flatten([effects, object_effects, spawn_effects, ring_effects]),
        ),
      )
    }
  }
}

/// The player of `connection` is ready: each Live hostile creature whose ring it
/// stands in is sent `Approached`, and its later moves are checked against the
/// rings. A second `Ready` in one stay, or one from a connection not in the map,
/// changes nothing.
fn ready(
  state state: State,
  connection connection: ConnectionId,
  seq seq: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(Player(readiness: StillLoading, ..) as player) -> {
      let #(player, effects) =
        rings_decided(
          state:,
          player: Player(
            ..player,
            readiness: Loaded,
            seq: int.max(player.seq, seq),
          ),
        )
      #(
        State(..state, players: dict.insert(state.players, connection, player)),
        Effects(effects),
      )
    }
    Ok(Player(readiness: Loaded, ..)) | Error(Nil) -> #(state, Effects([]))
  }
}

/// The player of `connection` entered stealth or left it. A connection not in the
/// map is an error line and changes nothing, as for `Moved`; a value the map
/// already holds changes nothing and sends nothing. A change is kept, and a ready
/// player's rings are decided again (`rings_decided`): entering stealth sends
/// `Withdrew` to each Live creature whose ring held the player, and leaving it
/// sends `Approached` to each Live creature whose ring holds it, in spawn order. A
/// player still loading is only marked: `ready` decides its rings.
fn stealth_changed(
  state state: State,
  connection connection: ConnectionId,
  stealthed stealthed: Bool,
) -> #(State, ServiceStep(Outgoing)) {
  let stealth = case stealthed {
    True -> Stealthed
    False -> NotStealthed
  }
  told_about_player(
    state:,
    connection:,
    about: "stealth",
    change: fn(player) { Player(..player, stealth:) },
    decided: fn(player) {
      case player.readiness {
        StillLoading -> #(player, [])
        Loaded -> rings_decided(state:, player:)
      }
    },
  )
}

/// A connection's tell about its player's own state (`StealthChanged`, `LifeChanged`):
/// from a connection not in the map it is an error line naming `about` and changes
/// nothing, as for `Moved`; a `change` that leaves the player as it is changes nothing and
/// sends nothing; else the changed player is `decided` (its rings, or its creatures' news)
/// and kept with that decision's sends.
fn told_about_player(
  state state: State,
  connection connection: ConnectionId,
  about about: String,
  change change: fn(Player) -> Player,
  decided decided: fn(Player) ->
    #(Player, List(Effect(ServiceEffect(Outgoing)))),
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(..step.no_one, connection: Some(connection)),
          text: "the connection told its "
            <> about
            <> " to the map, but it is not in it",
        ),
      ]),
    )
    Ok(player) -> {
      let changed = change(player)
      use <- bool.guard(when: changed == player, return: #(state, Effects([])))
      let #(player, effects) = decided(changed)
      #(
        State(..state, players: dict.insert(state.players, connection, player)),
        Effects(effects),
      )
    }
  }
}

/// The connection's player now has `hidden` as the visibility prerequisites that
/// fail for it: the units whose prerequisite left the set are shown within its
/// sight and the units whose prerequisite entered it are hidden, with the same
/// unit ids, as the module's `VisibilityChanged` says. A connection with no player
/// here, or a set equal to the held one, changes nothing.
fn visibility_changed(
  state state: State,
  connection connection: ConnectionId,
  hidden hidden: Set(PrerequisiteId),
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(..step.no_one, connection: Some(connection)),
          text: "the connection told its visibility to the map, but it is not in it",
        ),
      ]),
    )
    Ok(player) -> {
      use <- bool.guard(when: hidden == player.hidden, return: #(
        state,
        Effects([]),
      ))
      let player = Player(..player, hidden:)
      let #(seen, objects) =
        world_in_sight(state:, place: player_unit.place(player.unit), hidden:)
      let #(state, object_effects) =
        objects_decided(
          state:,
          to: #(connection, player),
          was: player.objects,
          now: objects,
          now_ms:,
        )
      let #(state, spawn_effects) =
        spawns_decided(
          state:,
          connection:,
          stay: player.stay,
          address: player.address,
          was: player.seen,
          now: seen,
          now_ms:,
        )
      let player = Player(..player, seen:, objects:)
      let #(player, ring_effects) = case player.readiness {
        StillLoading -> #(player, [])
        Loaded -> rings_decided(state:, player:)
      }
      #(
        State(..state, players: dict.insert(state.players, connection, player)),
        Effects(list.flatten([object_effects, spawn_effects, ring_effects])),
      )
    }
  }
}

/// The player of `connection` died or woke where its body lies. A connection not in
/// the map is an error line and changes nothing, as for `Moved`; a value the map
/// already holds changes nothing and sends nothing. A death is kept, empties the
/// player's `inside` with no `Withdrew`, and sends `PlayerDied` to each Live creature
/// whose spawn the player sees, in spawn order, a ring or not. A waking is kept and a
/// ready player's rings are decided again (`rings_decided`): `Approached` to each Live
/// creature whose ring holds it, in spawn order; a player still loading is only marked,
/// and `ready` decides its rings.
fn life_changed(
  state state: State,
  connection connection: ConnectionId,
  alive alive: Bool,
) -> #(State, ServiceStep(Outgoing)) {
  let life = life_of(alive:)
  told_about_player(
    state:,
    connection:,
    about: "life",
    change: fn(player) { Player(..player, life:) },
    decided: fn(player) {
      case life, player.readiness {
        Dead, _ -> #(
          Player(..player, inside: set.new()),
          players_told_of_death(state:, player:),
        )
        Alive, StillLoading -> #(player, [])
        Alive, Loaded -> rings_decided(state:, player:)
      }
    },
  )
}

/// The life a connection's `alive` names.
fn life_of(alive alive: Bool) -> Life {
  use <- bool.guard(when: alive, return: Alive)
  Dead
}

/// `PlayerDied` to each Live creature whose spawn the dead player sees, in spawn order:
/// a creature that chased the player out of its ring, or whose `Threatened` the dead
/// player dropped, may still hold it. A spawn whose creature is not Live is sent nothing:
/// its next start reads `inside`, which holds no dead player.
fn players_told_of_death(
  state state: State,
  player player: Player,
) -> List(Effect(ServiceEffect(Outgoing))) {
  list.flat_map(seen_in_order(player), fn(spawn) {
    tell_live(state:, spawn:, message: PlayerDied(by: player.address))
  })
}

/// The send of `message` to the creature of the spawn, when its creature is Live: a
/// spawn waiting for its creature, retiring, respawning or failed is sent nothing.
fn tell_live(
  state state: State,
  spawn spawn: SpawnId,
  message message: Outgoing,
) -> List(Effect(ServiceEffect(Outgoing))) {
  case dict.get(state.spawns, spawn) {
    Ok(Live(unit_id:, life:, ..)) -> [
      tell_creature(state:, unit_id:, life:, message:),
    ]
    Ok(Retiring(..))
    | Ok(Respawning(..))
    | Ok(Releasing(..))
    | Ok(WaitingForRestart)
    | Ok(Failed)
    | Error(Nil) -> []
  }
}

/// The rings the ready `player` of `connection` stands in at its place, against
/// the ones it stood in (`inside`): `Approached` to each Live creature whose ring it
/// entered and `Withdrew` to each whose ring it left, in the order of the spawns,
/// and the player with its new `inside`.
fn rings_decided(
  state state: State,
  player player: Player,
) -> #(Player, List(Effect(ServiceEffect(Outgoing)))) {
  let now = rings_holding(state:, player:)
  let entered = in_order(set.difference(now, player.inside))
  let left = in_order(set.difference(player.inside, now))
  let player = Player(..player, inside: now)
  #(
    player,
    list.append(
      list.flat_map(entered, fn(spawn) {
        tell_live(
          state:,
          spawn:,
          message: Approached(member: ring_member(state:, player:)),
        )
      }),
      list.flat_map(left, fn(spawn) {
        tell_live(state:, spawn:, message: Withdrew(by: player.address))
      }),
    ),
  )
}

/// The spawns hostile to the player's faction whose ring holds its place: within
/// the aggro range of the spawn's place, in three dimensions, found through the cell
/// index for the stored spawns and by a scan of the run-only ones. A player that
/// `noticeable_by_rings` refuses stands in no ring: a stealthed one is left out of every
/// creature's ring, the server's choice: a creature does not aggro a
/// stealthed player it is not already fighting. The client holds no rule for it
/// (`UnitProperty2.stealth_detection`).
fn rings_holding(state state: State, player player: Player) -> Set(SpawnId) {
  use <- bool.guard(when: !noticeable_by_rings(player:), return: set.new())
  let spawns = state.settings.spawns
  let place = player_unit.place(player.unit)
  let range = state.settings.numbers.aggro_range
  let faction_id = player_unit.faction_id(player.unit)
  let holds = fn(found: spawn.Spawn) {
    in_ring(spawn: found, place:, faction_id:, range:)
    && shown(visibility: found.visibility, hidden: player.hidden)
  }
  let stored =
    spawn_cell.near(
      cells: spawns.cells,
      x: start_place.x(place),
      z: start_place.z(place),
      range:,
    )
    |> list.filter(fn(id) {
      case dict.get(spawns.by_id, id) {
        Ok(found) -> holds(found)
        Error(Nil) -> False
      }
    })
    |> set.from_list
  dict.fold(state.run_spawns, stored, fn(found, id, run_spawn) {
    case holds(run_spawn) {
      True -> set.insert(found, id)
      False -> found
    }
  })
}

/// Whether a ring can notice the player: it is ready, not stealthed and alive. The one
/// predicate `rings_holding` and `standing_for_players` (a summon's ring entry) share, so
/// a creature that starts beside a stealthed or a dead player is told nothing of it.
fn noticeable_by_rings(player player: Player) -> Bool {
  case player.readiness {
    Loaded -> player.stealth == NotStealthed && player.life == Alive
    StillLoading -> False
  }
}

/// Whether the place is in the spawn's ring for a player of the faction: the
/// spawn is hostile to the faction and the place is within `range` of the spawn's
/// place, in three dimensions.
fn in_ring(
  spawn spawn: spawn.Spawn,
  place place: Place,
  faction_id faction_id: Int,
  range range: Float,
) -> Bool {
  hostile(spawn:, faction_id:)
  && sight.squared_distance(first: place, second: spawn.place)
  <=. range *. range
}

/// Whether a creature's `hostile_to` holds for a player of the faction: Exile's and
/// Dominion's by their Faction2 ids (`spawn.exile_faction`, `spawn.dominion_faction`),
/// and no other faction is a player's.
pub fn hostile_to_player_faction(
  hostile_to hostile_to: Hostile,
  faction_id faction_id: Int,
) -> Bool {
  case faction_id == spawn.exile_faction, faction_id == spawn.dominion_faction {
    True, _ -> hostile_to.exile
    _, True -> hostile_to.dominion
    False, False -> False
  }
}

/// Whether the spawn's creature fights a player of the faction on sight: it takes part in
/// combat (`Combat.fights`) and its faction is Hostile to the player's.
fn hostile(spawn spawn: spawn.Spawn, faction_id faction_id: Int) -> Bool {
  spawn.combat.fights
  && hostile_to_player_faction(hostile_to: spawn.combat.hostile_to, faction_id:)
}

/// A connection's leave: its player is removed with its unit and its watch,
/// each player who saw it is sent `UnseenBy` and `PlayerUnseen`, and `Left` is
/// answered. A connection that is not in the map is an error line and the same
/// answer.
fn left(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.players, connection) {
    Ok(player) -> {
      let #(state, told) =
        without(state:, connection:, player:, why: Camped, now_ms:)
      #(
        state,
        Effects(
          list.flatten([
            [Unwatch(watch: player.watch)],
            told,
            [OwnEffect(Reply(caller, Left))],
          ]),
        ),
      )
    }
    Error(Nil) -> #(
      state,
      Effects([
        log_error(
          state:,
          about: step.About(..step.no_one, connection: Some(connection)),
          text: "the connection left the map, but it is not in it",
        ),
        OwnEffect(Reply(caller, Left)),
      ]),
    )
  }
}

/// A connection's join: its player's unit is built with the next unit id and
/// the body of the character's look and the worn visuals of its Novice set
/// (genesis_prime/shared/loadout), kept under the next address of the run, and answered
/// as 0x262's record with that address, and the connection is watched. The joiner is then
/// sent a `SeenBy` for each player in sight, and each of them a `SeenBy` of the joiner. A
/// connection already in the map has its first unit removed as a `Leave` removes it (its
/// watch dropped, its creatures told `Unseen` and `CasterGone` of the old address, the
/// players who saw it `UnseenBy` and `PlayerUnseen`) and then joins as a new unit: the
/// connection joins again only after its `Left`, so this is the rule for a join the
/// connection never sends.
fn joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
  stay stay: Stay,
  alive alive: Bool,
  hidden hidden: Set(PrerequisiteId),
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let #(state, removal) = case dict.get(state.players, connection) {
    Ok(player) -> {
      let #(state, told) =
        without(state:, connection:, player:, why: Camped, now_ms:)
      #(state, [Unwatch(watch: player.watch), ..told])
    }
    Error(Nil) -> #(state, [])
  }
  let #(state, joining) =
    joined_new(
      state:,
      caller:,
      connection:,
      character:,
      place:,
      stay:,
      life: life_of(alive:),
      hidden:,
      now_ms:,
    )
  #(state, effects_after(removal:, joining:))
}

/// The step with the effects of a removal carried out first.
fn effects_after(
  removal removal: List(Effect(ServiceEffect(Outgoing))),
  joining joining: ServiceStep(Outgoing),
) -> ServiceStep(Outgoing) {
  case joining {
    Effects(effects:) -> Effects(list.append(removal, effects))
    step.EffectsThenAsk(effects:, ask:) ->
      step.EffectsThenAsk(effects: list.append(removal, effects), ask:)
  }
}

/// A join of a connection that is not in the map: the unit is built, kept and answered,
/// the connection watched, and each pair with a player in sight made: `SeenBy`
/// both ways.
fn joined_new(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  place place: Place,
  stay stay: Stay,
  life life: Life,
  hidden hidden: Set(PrerequisiteId),
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  let tables = state.settings.tables
  case loadout_of(tables:, character:) {
    Error(reason) ->
      not_joined(state:, caller:, connection:, character:, reason:)
    Ok(loadout) -> {
      let #(state, unit_id) = take_unit_id(state)
      let #(state, address) = issue_address(state:, joiner: connection)
      let watch = WatchId(state.next_watch)
      let state = State(..state, next_watch: state.next_watch + 1)
      let unit =
        player_unit.new(
          character:,
          place:,
          unit_id:,
          body: appearance.character_body_visuals(
            index: appearance.index(tables:),
            character:,
          ),
          loadout:,
        )
      joined_with(
        state:,
        caller:,
        connection:,
        place:,
        now_ms:,
        player: Player(
          stay:,
          address:,
          unit:,
          watch:,
          sees: dict.new(),
          seen: set.new(),
          objects: set.new(),
          readiness: StillLoading,
          seq: 0,
          inside: set.new(),
          stealth: NotStealthed,
          life:,
          hidden:,
        ),
      )
    }
  }
}

/// The loadout of the character's class and faction, or why the character cannot
/// be in the map.
fn loadout_of(
  tables tables: table_store.Tables,
  character character: Character,
) -> Result(Loadout, NotJoined) {
  loadout.of(
    tables:,
    class_id: character.class_id,
    faction_id: character.faction_id,
  )
  |> result.replace_error(NoLoadout(
    class_id: character.class_id.value,
    faction_id: character.faction_id,
  ))
}

/// A join the map refuses: an error line naming the character and why, and the
/// answer `NotJoined`. No unit id is taken and nothing is kept.
fn not_joined(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  character character: Character,
  reason reason: NotJoined,
) -> #(State, ServiceStep(Outgoing)) {
  let CharacterId(character_id) = character.character_id
  #(
    state,
    Effects([
      log_error(
        state:,
        about: step.About(
          ..step.no_one,
          connection: Some(connection),
          character_id: Some(character_id),
        ),
        text: "the character cannot join the map: "
          <> describe_not_joined(reason:),
      ),
      OwnEffect(Reply(caller, NotJoined(reason:))),
    ]),
  )
}

/// A sentence that says why a join is refused, for the log.
pub fn describe_not_joined(reason reason: NotJoined) -> String {
  let NoLoadout(class_id:, faction_id:) = reason
  "no Novice set holds class "
  <> int.to_string(class_id)
  <> " and faction "
  <> int.to_string(faction_id)
}

/// The rest of the first join, once the player is built with its unit and its
/// watch, seeing nothing: its sight, its watch and its answer.
fn joined_with(
  state state: State,
  caller caller: CallerId,
  connection connection: ConnectionId,
  place place: Place,
  now_ms now_ms: Int,
  player player: Player,
) -> #(State, ServiceStep(Outgoing)) {
  let unit = player.unit
  let watch = player.watch
  let in_sight =
    list.filter(others_of(state:, connection:), fn(other) {
      sight.sees(place, player_unit.place({ other.1 }.unit))
    })
  let #(state, sights) =
    list.map_fold(in_sight, state, fn(state, other) {
      let #(state, joiner_sight) = issued(state:)
      let #(state, other_sight) = issued(state:)
      #(state, #(other, joiner_sight, other_sight))
    })
  let players =
    list.fold(sights, state.players, fn(players, sight) {
      let #(other, _, other_sight) = sight
      dict.insert(
        players,
        other.0,
        Player(
          ..other.1,
          sees: dict.insert(
            { other.1 }.sees,
            connection,
            sight_begun(generation: other_sight, stay: other.1.stay),
          ),
        ),
      )
    })
  let sees =
    list.map(sights, fn(sight) {
      #(sight.0.0, sight_begun(generation: sight.1, stay: player.stay))
    })
    |> dict.from_list
  let pairs =
    list.flat_map(sights, fn(sight) {
      let #(other, joiner_sight, other_sight) = sight
      comes_into_sight(
        newcomer: #(connection, player),
        other:,
        newcomer_sight: joiner_sight,
        other_sight:,
      )
    })
  let #(seen, objects) = world_in_sight(state:, place:, hidden: player.hidden)
  let #(state, object_effects) =
    objects_decided(
      state:,
      to: #(connection, player),
      was: set.new(),
      now: objects,
      now_ms:,
    )
  let #(state, spawn_effects) =
    spawns_decided(
      state:,
      connection:,
      stay: player.stay,
      address: player.address,
      was: set.new(),
      now: seen,
      now_ms:,
    )
  #(
    State(
      ..state,
      players: dict.insert(
        players,
        connection,
        Player(..player, sees:, seen:, objects:),
      ),
      watches: dict.insert(state.watches, watch, connection),
      by_address: dict.insert(state.by_address, player.address, connection),
    ),
    Effects(
      list.flatten([
        [
          Watch(watch:, target: Connection(connection)),
          OwnEffect(Reply(
            caller,
            answer(state:, unit:, address: player.address),
          )),
        ],
        object_effects,
        pairs,
        spawn_effects,
      ]),
    ),
  )
}

/// The send that tells the player `to` that the player `by`, in its stay, sees
/// it.
fn watched(
  to to: #(ConnectionId, Player),
  by by: #(ConnectionId, Player),
  generation generation: Generation,
) -> Effect(ServiceEffect(Outgoing)) {
  notify(
    to:,
    notice: SeenBy(
      by: by.0,
      stay: { by.1 }.stay,
      unit_id: player_unit.unit_id(unit: { by.1 }.unit),
      generation:,
    ),
  )
}

/// The send that tells the player `to` that the player of connection `by` no
/// longer sees it.
fn unwatched(
  to to: #(ConnectionId, Player),
  by by: ConnectionId,
  generation generation: Generation,
) -> Effect(ServiceEffect(Outgoing)) {
  notify(to:, notice: UnseenBy(by:, generation:))
}

/// The sends of a pair that comes into sight, in one step: each of the two is
/// told the other sees it, in the other's stay. A joiner and a mover are the
/// newcomer.
fn comes_into_sight(
  newcomer newcomer: #(ConnectionId, Player),
  other other: #(ConnectionId, Player),
  newcomer_sight newcomer_sight: Generation,
  other_sight other_sight: Generation,
) -> List(Effect(ServiceEffect(Outgoing))) {
  [
    watched(to: other, by: newcomer, generation: newcomer_sight),
    watched(to: newcomer, by: other, generation: other_sight),
  ]
}

/// The send that tells the player `viewer`, in the stay its sight began in, that the unit
/// of the player `owner` is out of its sight from the generation `relation` holds, whether
/// or not the viewer took the owner's snapshot of it.
fn player_unseen(
  viewer viewer: ConnectionId,
  relation relation: Relation,
  owner owner: Player,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: Connection(viewer),
    message: Noticed(
      stay: relation.stay,
      notice: PlayerUnseen(
        unit_id: player_unit.unit_id(unit: owner.unit),
        generation: relation.generation,
      ),
    ),
  ))
}

/// The sends of a pair that leaves sight, in one step: each of the two is told the other's
/// unit is unseen (`PlayerUnseen`) and then that the other no longer sees it (`UnseenBy`),
/// each from the sight that ended. The viewer's end comes first so that its connection
/// still holds the other as one of its viewers when it ends what the other put on it.
fn goes_out_of_sight(
  first first: #(ConnectionId, Player),
  second second: #(ConnectionId, Player),
  first_sight first_sight: Relation,
  second_sight second_sight: Relation,
) -> List(Effect(ServiceEffect(Outgoing))) {
  [
    player_unseen(viewer: first.0, relation: first_sight, owner: second.1),
    unwatched(to: first, by: second.0, generation: second_sight.generation),
    player_unseen(viewer: second.0, relation: second_sight, owner: first.1),
    unwatched(to: second, by: first.0, generation: first_sight.generation),
  ]
}

/// The two sights of a pair that sees each other: what the first sees of the second, and
/// what the second sees of the first. The relation is symmetric, so a pair in one player's
/// `sees` is in the other's.
fn sights_of_pair(
  first first: Player,
  second second: Player,
  first_connection first_connection: ConnectionId,
  second_connection second_connection: ConnectionId,
) -> #(Relation, Relation) {
  let assert Ok(first_sight) = dict.get(first.sees, second_connection)
    as "a pair that sees each other is in both players' sees"
  let assert Ok(second_sight) = dict.get(second.sees, first_connection)
    as "a pair that sees each other is in both players' sees"
  #(first_sight, second_sight)
}

/// The answer to a join: the unit as message 0x262's record in the map's
/// realm, the address the map issued for the join, the map's incarnation and the origin
/// of its clock.
fn answer(
  state state: State,
  unit unit: PlayerUnit,
  address address: UnitAddress,
) -> Outgoing {
  Joined(
    unit: player_unit.create(unit:, realm_id: state.settings.realm_id),
    loadout: player_unit.loadout(unit:),
    address:,
    incarnation: state.settings.incarnation,
    clock_origin_ms: state.started_ms,
  )
}

/// The end of a player's connection: its player is removed, as a leave removes
/// it, and each player who saw it is sent `UnseenBy`, `PlayerUnseen` and `Gone`, since the
/// connection that ended sent their clients nothing. A watch that names no
/// player is a bug: an error log line, and nothing changes.
fn ended(
  state state: State,
  watch watch: WatchId,
  now_ms now_ms: Int,
) -> #(State, ServiceStep(Outgoing)) {
  case dict.get(state.watches, watch) {
    Ok(connection) ->
      case dict.get(state.players, connection) {
        Ok(player) -> {
          let #(state, told) =
            without(state:, connection:, player:, why: Ended, now_ms:)
          #(state, Effects(told))
        }
        Error(Nil) -> no_player_for_watch(state)
      }
    Error(Nil) -> no_player_for_watch(state)
  }
}

fn no_player_for_watch(state: State) -> #(State, ServiceStep(Outgoing)) {
  #(
    state,
    Effects([
      log_error(
        state:,
        about: step.no_one,
        text: "a watch ended that names no player of the map",
      ),
    ]),
  )
}

/// The map with the connection's player and its watch removed, the player out of
/// the `sees` of each player who saw it, and each of them sent `UnseenBy` of its
/// connection. When the connection ended, every player in the map is sent `Gone`
/// of its unit, those who saw it as well as those who no longer do: the
/// connection that ended sent nobody a 0x355, and a player that stopped seeing it
/// a moment before may not have taken the notice that would have had it sent
/// (an end saves the place first), so its client may still show the unit. A
/// connection that does not show the unit ignores it.
fn without(
  state state: State,
  connection connection: ConnectionId,
  player player: Player,
  why why: Removal,
  now_ms now_ms: Int,
) -> #(State, List(Effect(ServiceEffect(Outgoing)))) {
  let others = others_of(state:, connection:)
  let viewers =
    list.filter_map(others, fn(other) {
      dict.get(player.sees, other.0)
      |> result.map(fn(sight) { #(other, sight) })
    })
  let players =
    list.fold(viewers, dict.delete(state.players, connection), fn(players, v) {
      let #(viewer, _) = v
      dict.insert(
        players,
        viewer.0,
        Player(..viewer.1, sees: dict.delete({ viewer.1 }.sees, connection)),
      )
    })
  let #(state, spawn_effects) =
    spawns_decided(
      state:,
      connection:,
      stay: player.stay,
      address: player.address,
      was: player.seen,
      now: set.new(),
      now_ms:,
    )
  // What each player that saw the connection's player is told of the end: the owner's
  // notice that the connection no longer sees it, and the viewer's that the unit is unseen.
  let sights_ended = fn(other: #(ConnectionId, Player)) {
    case
      dict.get(player.sees, other.0),
      dict.get({ other.1 }.sees, connection)
    {
      Ok(own_sight), Ok(other_sight) -> [
        player_unseen(viewer: other.0, relation: other_sight, owner: player),
        unwatched(to: other, by: connection, generation: own_sight.generation),
      ]
      Ok(_), Error(Nil) | Error(Nil), Ok(_) | Error(Nil), Error(Nil) -> []
    }
  }
  #(
    State(
      ..state,
      players:,
      watches: dict.delete(state.watches, player.watch),
      by_address: dict.delete(state.by_address, player.address),
    ),
    list.append(
      case why {
        Camped -> list.flat_map(others, sights_ended)
        Ended ->
          list.flat_map(others, fn(other) {
            list.append(sights_ended(other), [
              notify(
                to: other,
                notice: Gone(unit_id: player_unit.unit_id(unit: player.unit)),
              ),
            ])
          })
      },
      list.append(
        spawn_effects,
        caster_gone_sends(state:, address: player.address),
      ),
    ),
  )
}

/// The `CasterGone` of the connection for each running creature (live, retiring,
/// respawning or releasing: the states `running` admits), in spawn order: the removal's
/// last sends, after the `Unseen`s of `spawns_decided`. A spawn with no creature (waiting
/// for its restart, failed) is sent nothing.
fn caster_gone_sends(
  state state: State,
  address address: UnitAddress,
) -> List(Effect(ServiceEffect(Outgoing))) {
  dict.keys(state.spawns)
  |> list.sort(compare_spawns)
  |> list.filter_map(fn(spawn) {
    use spawn_state <- result.try(dict.get(state.spawns, spawn))
    use #(unit_id, life) <- result.map(running_creature(spawn_state:))
    tell_creature(state:, unit_id:, life:, message: CasterGone(by: address))
  })
}

/// The players other than the connection's, in the order the map's table
/// gives them: a step's sends are in that order, which a test of a few players
/// can name, and no sort is made on each move.
fn others_of(
  state state: State,
  connection connection: ConnectionId,
) -> List(#(ConnectionId, Player)) {
  dict.to_list(state.players)
  |> list.filter(fn(entry) { entry.0 != connection })
}

/// A send to the connection of a player in the map: the notice, for the
/// player's stay.
fn notify(
  to player: #(ConnectionId, Player),
  notice notice: Notice,
) -> Effect(ServiceEffect(Outgoing)) {
  OwnEffect(Send(
    to: Connection(player.0),
    message: Noticed(stay: { player.1 }.stay, notice:),
  ))
}

/// An error line about the map, and what `about` adds.
fn log_error(
  state state: State,
  about about: step.About,
  text text: String,
) -> Effect(ServiceEffect(Outgoing)) {
  Log(LogLine(
    level: LogError,
    text:,
    about: step.About(..about, map: Some(state.settings.map)),
  ))
}
