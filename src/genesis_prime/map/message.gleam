//// What crosses between a map and the processes that talk to it: the map's inbox
//// (`Message`), what it answers and sends (`Outgoing`, `Notice`, `NotJoined`,
//// `NotSummoned`), and the payloads a creature and a player tell through it
//// (`Payload`, `Delivered`, `Inbound`, `Landing`). Types only: the map's rules and state
//// are in genesis_prime/world_map/map, and the checks the map makes of each payload's kind
//// in genesis_prime/world_map/relay (`code_rule/message_module` holds the module to types).
////
//// ```
//// connection, creature ─ Message ─▶ map ─ Outgoing ─▶ connection, creature
////                                    (Noticed, Relayed(Delivered) to a player;
////                                     ToldCreature(Inbound) to a creature)
//// ```

import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/shared/chat_tell.{type Said as ChatSaid}
import genesis_prime/shared/forced_move
import genesis_prime/shared/kill_credit.{type Credit}
import genesis_prime/shared/loadout.{type Loadout}
import genesis_prime/shared/player_change.{type PlayerChange}
import genesis_prime/shared/strike_tell.{
  type Answered, type Fight, type PlayerAnswered, type PlayerEvent,
  type PlayerStrike, type Tell as StrikeTell,
}
import genesis_prime/shared/unit_casts
import genesis_prime/shared/unit_news.{type PeerNews}
import genesis_prime/shared/unit_properties
import genesis_prime/shared/unit_state
import genesis_prime/step.{type ConnectionId, type RingMember}
import genesis_prime/store.{type Character}
import genesis_prime/table/id.{type Creature2Id, type PrerequisiteId}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{type SpawnId}
import genesis_prime/world_map/static_object
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/option.{type Option}
import gleam/set.{type Set}

/// What a creature tells one player through the map.
pub type Payload {
  /// The answer to the player's strike on the creature.
  Struck(answered: Answered)
  /// The credit for the kill the player's blow made.
  KillCredit(credit: Credit)
  /// The creature threatens, releases or strikes the player.
  Fight(told: Fight)
}

/// What the map sends a player's connection for a creature: the creature's news,
/// which it relays through a relation, or a payload the creature told.
pub type Delivered {
  /// News of the creature's unit, from a snapshot's burst or a broadcast, for a
  /// viewer whose relation the map holds as relaying.
  News(news: PeerNews)
  /// A payload the creature told the player.
  Tell(payload: Payload)
  /// What another player's cast landed on the player, or the answer to what the player
  /// did to it, which the map admitted by its kind (`landing_kind_of`).
  Landed(landing: Landing)
  /// A local chat line (Say, Yell or Emote) of a player the told player sees, for a
  /// viewer whose relation relays.
  Said(said: ChatSaid)
}

/// What a player's connection tells one running creature through the map. No payload
/// names its sender but `Strike`, whose `from` the map checks against the relay's: the map
/// names the sender to the creature (`ToldCreature`).
pub type Inbound {
  /// The strike of a cast's go, which the creature's owner process decides
  /// (genesis_prime/shared/strike_tell).
  Strike(tell: StrikeTell)
  /// The player stands at `place`, its move `seq`, with its race's hit radius, for a
  /// creature that holds it on its threat list.
  TargetMoved(place: Place, seq: Int, hit_radius: Float)
  /// The player's answer to the creature's strike on it.
  StrikeAnswered(answered: Answered)
  /// A property modifier of the player's spell starts on the creature.
  ModifierStarts(
    source: unit_properties.Source,
    modifier: unit_properties.Modifier,
  )
  /// The property modifier of `source` ends on the creature.
  ModifierEnds(source: unit_properties.Source)
  /// A ForcedMove effect of the player's cast throws the creature.
  Thrown(throw: forced_move.Throw)
  /// A DespawnUnit effect of the player's cast removes the creature `delay_ms` after
  /// `went_at_ms`, the monotonic time of the go.
  Despawn(delay_ms: Int, went_at_ms: Int)
  /// The UnitStateSet rows of the player's cast hold their states on the creature, each
  /// from `went_at_ms`, the monotonic time of the go, plus its delay.
  UnitStates(rows: List(unit_state.Row), went_at_ms: Int)
  /// The player's cast holds `view` on the creature: its one target, the whole of it.
  CastViewSet(view: unit_casts.CastView)
  /// The player's cast `cast_id` holds nothing on the creature any more.
  CastViewEnds(cast_id: Int)
  /// The player's cast `cast_id` no longer holds a node on the creature that holds the
  /// states the cast landed, so each of those states ends.
  ControlsEnd(cast_id: Int)
}

/// What one player's connection tells another's through the map: what a cast lands on
/// the other player, or the other's answer to it. Each kind is admitted by the map
/// with the checks of `landing_kind_of`, and delivered to the told unit's address.
pub type Landing {
  /// The heal rows of the caster's cast, for the told player's life.
  HealStrike(strike: PlayerStrike)
  /// The told player's answer to a heal strike, for the caster's round.
  HealAnswer(answered: PlayerAnswered)
  /// A change the caster's cast puts on the told player.
  ChangeStart(change: PlayerChange)
  /// The end of a change the caster's cast put on the told player.
  ChangeEnd(change: PlayerChange)
  /// The caster's go has told the told player each of its changes.
  CastWent(change: PlayerChange)
  /// The events of a blow on the told player that the caster's Proc rows on it wait for.
  AllyEvent(event: PlayerEvent)
}

/// What a connection asks or tells a map.
pub type Message {
  /// Put the character in the map as the connection's player, placed at
  /// `place`, the bounded place the client is told, as one unit the map issues an address
  /// for (`Joined`). `joiner` is the connection that hosts the player: the map registers it
  /// as the member of the address's group (`step.Register`) and watches it. `alive` is False for a player that
  /// enters dead (its saved health is 0, genesis_prime/game/player_life `entering`),
  /// True otherwise and for the Holocrypt's join. `hidden` is the visibility
  /// prerequisites of the world that fail for the player (genesis_prime/game/visibility
  /// `hidden_at_entry`): the map shows it no static object and no creature whose
  /// visibility prerequisite is in it, from the join on. An ask, answered `Joined`.
  Join(
    joiner: ConnectionId,
    character: Character,
    place: Place,
    alive: Bool,
    hidden: Set(PrerequisiteId),
  )
  /// Take the player of the unit `unit` out of the map, with its unit, the watch on its
  /// connection and the registration of its address. An ask, answered `Left` whether the
  /// unit was in the map or not.
  Leave(unit: UnitAddress)
  /// The player of the unit `unit` now stands at `place`. A tell: the map answers no
  /// one, so a connection's rule goes on at once (8 moves a second per player).
  /// The map decides sight from it and sends no move: the connection sends its
  /// own player's moves to the players who see it. Taken only from a connection
  /// that is in the map. `seq` is the connection's move sequence number, which
  /// grows by one with each accepted 0x637, and which the map passes on with the
  /// place to a creature whose ring the player enters.
  Moved(unit: UnitAddress, place: Place, seq: Int)
  /// The connection's player is ready: its client sent the stay's first 0xF2
  /// (`opcode.0xf2`), so a creature may fight it. `seq` is the connection's move
  /// sequence number then, which counts for the connection's life: a player that
  /// entered again and has not moved is told to creatures with it, not with an
  /// earlier stay's lower one. A tell.
  Ready(unit: UnitAddress, seq: Int)
  /// The connection's player entered stealth (`stealthed` True) or left it, as its
  /// cast rule decided (genesis_prime/game/cast `StealthChanged`). A tell. A
  /// stealthed player stands in no creature's ring, so no creature is told
  /// `Approached` for it, and one that held it in its ring is told `Withdrew`
  /// (a server choice: the client holds no rule, `UnitProperty2.stealth_detection`).
  /// Taken only from a connection that is in the map.
  StealthChanged(unit: UnitAddress, stealthed: Bool)
  /// The connection's player died (`alive` False) or woke where its body lies
  /// (`alive` True), as its life rule decided (genesis_prime/game/player_life). A
  /// tell. A dead player stands in no creature's ring, and each creature it sees is
  /// told `PlayerDied` (a server choice: the client holds no creature rule). A player
  /// that wakes inside a ring is told to its creatures as `Approached`. Taken only
  /// from a connection that is in the map.
  LifeChanged(unit: UnitAddress, alive: Bool)
  /// The visibility prerequisites that fail for the connection's player are now
  /// `hidden`, as its connection's end-of-step check found
  /// (genesis_prime/game/visibility `hidden`). A tell, sent only when the set
  /// changed. The map shows the player each unit whose prerequisite left the set
  /// and hides each unit whose prerequisite entered it, within the player's sight:
  /// a shown static object is `ObjectsSeen`, a hidden one `ObjectsUnseen`; a shown
  /// creature's spawn is seen as when it first comes in sight (`Seen`, and a
  /// creature is started for it if none lives), a hidden one is `Unseen` and its
  /// ring `Withdrew`, as when the player leaves its sight; a unit out of sight is
  /// sent nothing. Taken only from a connection that is in the map, and a set equal
  /// to the one held changes nothing.
  VisibilityChanged(unit: UnitAddress, hidden: Set(PrerequisiteId))
  /// A player's use of the unit `unit_id` counted a unit new to an objective that counts
  /// each unit once (genesis_prime/game/objective `ReleaseUnit`): the
  /// spawn of that unit, and each spawn standing at its x and z (`spawn.captives`),
  /// vanish for every player in the map and stand again after the release time
  /// (`GameNumbers.used_object_release_ms`): a creature under a new unit id, a
  /// static object under the one it had. A tell, with no answer. A unit with
  /// neither a live creature nor an unreleased static object in the map changes
  /// nothing (a second release of it, or a unit the map does not hold).
  Released(unit_id: Int)
  /// A development command of the connection's player: start `creature_id` as a
  /// run-only spawn at the place and facing the map holds for the player, and
  /// show it to the players who see that place, at `level` when there is one and
  /// else at the creature's own minLevel. An ask, answered `Summoned` or
  /// `NotSummoned`, with the connection's ask deadline; a map that is not running
  /// or ends before it answers is the asker's outcome, not a `NotSummoned`.
  /// Taken only from a connection that is in the map.
  Summon(unit: UnitAddress, creature_id: Creature2Id, level: Option(Int))
  /// A creature's answer to the map's `Seen`: the picture the creature `unit_id` of
  /// life `life` builds for the player of the unit `by` from its state when it took
  /// the `Seen` of `generation`, `burst` in the order the player's connection writes it
  /// (empty for a creature that is not shown). A tell, from a creature. The map relays
  /// the burst when the pair holds that generation and awaits its snapshot, and drops it
  /// otherwise (`snapshot_taken`).
  Snapshot(
    unit_id: Int,
    life: Int,
    by: UnitAddress,
    generation: Generation,
    burst: List(PeerNews),
  )
  /// News of the creature `unit_id` of life `life` for every player that holds a
  /// relation with it in the state of relaying. A tell, from a creature. The map relays
  /// it to each such player, in the order of their addresses, and to no player awaiting its snapshot
  /// (`broadcast`).
  Broadcast(unit_id: Int, life: Int, news: PeerNews)
  /// A tell of the creature `unit_id` of life `life` to the player of the unit `to`: an
  /// answer, a credit or a fight tell (`relay`). A tell, from a creature. The map admits
  /// it by the creature's state, the payload's kind and whether `to` is a unit of this run
  /// (one that left or ended is not: the tell is dropped), and sends it as `Relayed` to
  /// `Unit(to)` (`relayed`).
  Relay(unit_id: Int, life: Int, to: UnitAddress, payload: Payload)
  /// The creature `unit_id` of life `life` lay dead or despawned until its corpse timer
  /// and stops now. A tell, from a creature. A live spawn of that unit and life becomes
  /// `Respawning`; when the creature has ended the map starts its next life
  /// (`expired`).
  Expired(unit_id: Int, life: Int)
  /// A tell of the player of the unit `from` to the creature `unit_id` of life `life`: a
  /// strike, a move, an answer or an effect of its casts (`map_message.Inbound`). A tell,
  /// from a connection. The map admits it by the creature's state, the payload's kind and
  /// whether `from` is a unit of this run (only a `TargetMoved`, `ModifierStarts` or `CastViewSet`
  /// of a unit that ended is dropped; the other kinds are delivered), and
  /// sends the creature `ToldCreature` (`told_creature`).
  TellCreature(from: UnitAddress, unit_id: Int, life: Int, payload: Inbound)
  /// The owner's snapshot of the sight `generation` that the unit `viewer` has of the unit
  /// `by` (a snapshot from an address that is not a unit of this run is dropped): the
  /// picture the owner built when it took the
  /// map's `SeenBy` of that generation, `burst` in the order the viewer's connection
  /// writes it (the 0x262 first, then what its client needs of the unit's live casts and
  /// state). A tell, from a connection. The map relays the burst when the pair holds
  /// that generation and awaits its snapshot, and drops it otherwise
  /// (`player_snapshot_taken`).
  PlayerSnapshot(
    by: UnitAddress,
    viewer: UnitAddress,
    generation: Generation,
    burst: List(PeerNews),
  )
  /// News of the unit `from` (news from an address that is not a unit of this run is
  /// dropped), for every viewer whose relation with it
  /// relays. A tell, from a connection. The news names the
  /// unit it is about, and the map drops news that names another unit than the sender's;
  /// a move is no news (`unit_news.News` holds none), the mover tells its viewers
  /// itself. The map relays it to each relaying viewer in the order of their addresses
  /// (`player_broadcast`).
  PlayerBroadcast(from: UnitAddress, news: PeerNews)
  /// What the unit `from` lands on the unit `to`, or answers it: a heal, a change, the end
  /// of one, a go's tell or an event. A tell, from a connection. The map admits it by the
  /// kind's checks (`relay.landing_kind_of`) and sends it as `Relayed(Landed(landing))` to
  /// `Unit(to)` (`landing_told`).
  TellLanding(from: UnitAddress, to: UnitAddress, landing: Landing)
  /// A local chat line of the unit `from`, for every viewer whose relation relays. A tell,
  /// from a connection. The map relays it as `Relayed(Said(said))` to `Unit(viewer)`, in the
  /// order of the viewers' addresses (`line_said`); a line from an address that is not a
  /// unit of this run is dropped, and one whose speaker names
  /// another unit than the sender's is dropped with an error line.
  Say(from: UnitAddress, said: ChatSaid)
}

/// Why a join is refused: the data of the one character, which the load's
/// requirements cannot rule out for a character stored with a class, a faction
/// or a level no table holds.
pub type NotJoined {
  /// No Novice set holds the character's class and faction
  /// (genesis_prime/shared/loadout).
  NoLoadout(class_id: Int, faction_id: Int)
}

/// Why a summon is refused: the data of the one request, since the command's
/// text is the player's to get wrong.
pub type NotSummoned {
  /// The connection has no player in this run of the map (it left, or it never
  /// joined), so there is no place to stand the creature at.
  NoPlayerHere
  /// The creature does not pass a spawn's checks (genesis_prime/world_map/spawn
  /// `summoned`).
  CreatureRefused(refusal: spawn.SummonRefusal)
  /// The creature was made a run-only spawn and its start failed, as the creature
  /// supervisor reported it (`step.CreatureNotStarted`): the spawn was dropped and
  /// nothing stands there.
  CreatureNotStarted(reason: String)
}

/// What a map answers and sends.
pub type Outgoing {
  /// The player is in this run of the map as this unit, which the map keeps, and as
  /// the unit `address`, which the map issued for this join, registered the joiner as
  /// `Unit(address)` before this answer and watches the joiner there; the joiner names
  /// `address` in every tell it makes of its player and takes only a message sent to it
  /// as its own; it watches `Map(map, incarnation)`. `unit` is the player's own
  /// 0x262, which its connection sends the players who see it, at its place and
  /// stamped from the map's clock; `clock_origin_ms` is the monotonic time the
  /// map started at, from which the connection stamps (`server_time`).
  Joined(
    unit: UnitCreatePlayer,
    loadout: Loadout,
    address: UnitAddress,
    incarnation: Int,
    clock_origin_ms: Int,
  )
  /// The character cannot be in the map: nothing was kept, no unit id was
  /// given and no watch was opened. An answer to a join, never a send.
  NotJoined(reason: NotJoined)
  /// The summoned creature starts under this unit id, as a run-only spawn at the
  /// player's place and facing: the answer to a `Summon`, never a send.
  Summoned(unit_id: Int)
  /// No creature was started and nothing in the map changed: an answer to a
  /// `Summon`, never a send.
  NotSummoned(reason: NotSummoned)
  /// The unit is not in the map any more, whether it was there or not, and nothing is
  /// registered under its address.
  Left
  /// A send to `Unit(address)` of a player, never an answer: the notice.
  Noticed(notice: Notice)
  /// A send to a creature: the player of the unit `by` sees it from the sight
  /// `generation` names, so it answers with a snapshot of that generation.
  Seen(by: UnitAddress, generation: Generation)
  /// A send to a creature: the sight `generation` of the player of the unit `by`
  /// ended, so the creature drops the player from its copy of its viewers and from its
  /// threat list.
  Unseen(by: UnitAddress, generation: Generation)
  /// A send to `Unit(address)` of a player, never an answer: what a creature or another
  /// player told it, news through the player's relation or a payload.
  Relayed(delivered: Delivered)
  /// A send to a creature, never to a connection: no player has seen it for the
  /// idle stop, so it ends (genesis_prime/world_map/creature).
  Retire
  /// A send to a creature: the ready player `member` entered the creature's ring at
  /// its place and move; or stood in it when it became ready or when the creature
  /// started.
  Approached(member: RingMember)
  /// A send to a creature: the player of the unit `by` left its ring.
  Withdrew(by: UnitAddress)
  /// A send to a creature: the player of the unit `by` died. It leaves the
  /// creature's ring's players and its threat list.
  PlayerDied(by: UnitAddress)
  /// A send to a creature: the player of the unit `by` told it `payload`. `by` is the
  /// relay's, never the payload's.
  ToldCreature(by: UnitAddress, payload: Inbound)
  /// A send to a creature in any running state: the player of the unit `by` is gone
  /// from the map, by its leave or by its connection's end, so the sources and views it
  /// held on the creature end. The map sends it once for each running
  /// creature, in spawn order, after the sends the removal makes.
  CasterGone(by: UnitAddress)
}

/// What a map tells the connection of a player in it about who sees whom, sent to the
/// player's `Unit` (`Noticed`).
pub type Notice {
  /// The unit `by`, as the unit id `unit_id`, sees this connection's player, from the
  /// sight `generation` names, so this connection sends `by` its 0x262 at its place and
  /// then its moves, each to `Unit(by)` and stamped with `generation`, and knows `unit_id`
  /// as the client's name of that player.
  SeenBy(by: UnitAddress, unit_id: Int, generation: Generation)
  /// The unit `by` no longer sees this connection's player, from the
  /// sight `generation` names, by distance, by leaving the map or by its connection
  /// ending, so this connection sends `by` its 0x355 and no more moves. A notice of
  /// an earlier generation than the one this connection holds for `by` changes
  /// nothing.
  UnseenBy(by: UnitAddress, generation: Generation)
  /// The player no longer sees the creature `unit_id`, from the sight `generation`
  /// names: the connection writes the 0x355 of the unit if its client shows it, after
  /// the finishes of its casts.
  UnitUnseen(unit_id: Int, generation: Generation)
  /// The player of unit `unit_id` is out of the viewer's sight from the sight `generation`
  /// names: by distance, by leaving the map, by its connection ending or by a second
  /// join, whether or not the viewer took the unit's snapshot of that generation. The
  /// connection finishes the unit's casts, writes its 0x355 if its client shows it, ends
  /// the sources the unit's sight ended, and remembers that generation as the last that
  /// ended, so a late move of it is dropped (genesis_prime/game/move_stamp).
  PlayerUnseen(unit_id: Int, generation: Generation)
  /// The unit `unit_id` has no owner any more, since its connection or its
  /// creature ended, which sends nothing as it ends. It goes to every player in
  /// the map, also one that stopped seeing the unit a moment before. The
  /// connection of a player removes the unit from its client if it shows it, and
  /// shows it no more.
  Gone(unit_id: Int)
  /// The player sees these static objects now, each as its 0x262 under the unit
  /// id the map gave its spawn for the run, with the spawn's id, in spawn order:
  /// the connection writes each one its client does not show
  /// (genesis_prime/world_map/static_object).
  ObjectsSeen(units: List(#(SpawnId, static_object.Created)))
  /// The player no longer sees the static objects of these unit ids: the
  /// connection writes a 0x355 for each one its client shows.
  ObjectsUnseen(unit_ids: List(Int))
}
