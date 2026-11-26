//// What the game connection does with a change another player's connection tells it
//// (`genesis_prime/game/connection/landing`, `viewers`, `life`), as the connection's rule
//// takes it with no socket: it applies the change as the player's own cast's change of
//// that kind is applied, holds it per caster, and ends it by the caster's end tell, the
//// map's notices of the caster and its own death. Expected values come from these places.
//// - Spell4Effects 203798 (`table_rows -- Spell4Effects 203798`): Phantasmal Armor's modifier
////   on UnitProperty2 161 (DamageTakenMultiplierMagic, default 1.0), mode 3, multiplier
////   dataBits02 1062836634 (0.86f), flat 0, 10 000 ms. A player's 0x93a entry for it holds
////   base 1.0 and value 1062836634, and the same entry with the value 1.0 restores it
////   (`opcode.0x93a`: a base and a value as 32-bit floats).
//// - Spell4Effects 62024: an Absorption row, mask 7, whose amount the caster's formula gave
////   at the go and the tell carries. The player's client is told the sum of its pools as stat
////   22 of 0x938 and its viewers as the `Absorption` news
////   (`game_connection_absorption_test`).
//// - The own-path tests state what a modifier and a pool write
////   (`game_connection_properties_test`, `player_life_absorb_test`); a told change writes
////   the same.
//// - `map.Notice`: `UnseenBy` is sent by distance, by leaving the map or by the caster's
////   connection ending; `Gone` is sent to every player when a connection's unit is gone.
//// - Client fact `cast.target_node_end`: the removal of a caster's unit finishes the casts it
////   made and so ends their buffs on other units, unless the spell's propertyFlags hold
////   0x100. The 18 tiers of Phantasmal Armor and Bolster hold it.
//// - The viewers are connections 2 and 3, as `game_connection_landing_test` has them; the
////   player's unit is 5 and the unit of viewer `n` is 100 + `n`.

import cast_support
import connection_rule_support as rule_support
import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, TellPeer,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/landing as connection_landing
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/held_changes.{
  type PlayerChange, type Sight, type Told, EndsWhenUnseen, KeptWhenUnseen,
  PlayerCastWent, PlayerChangeEnds, PlayerChangeStarts,
}
import genesis_prime/game/hit
import genesis_prime/game/proc
import genesis_prime/game/spell_plan
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts.{type HeldEffect, EndsAt, HeldEffect}
import genesis_prime/game/unit_news.{
  type News, Absorption, Appeared, CastFinished, CastStarted, HeldCastEnded,
  HeldCastStarted, InterruptArmor, PropertiesChanged, Removed,
}
import genesis_prime/game/unit_properties.{type Source, Change, Source}
import genesis_prime/game/world_entry
import genesis_prime/message/float32
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat_absorption.{UnitStatAbsorption}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_interrupt_armor.{UnitStatInterruptArmor}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, ConnectionId, OwnEffect,
}
import genesis_prime/table/id.{
  type Spell4Id, Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import genesis_prime/world_map/generation
import genesis_prime/world_map/map
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import place_support
import planted_table
import spawn_support
import world_entry_support

/// UnitProperty2 161's default, 1.0, and the value row 203798 gives it, 0.86f.
const one_bits = 0x3F800000

const armored_bits = 1_062_836_634

/// The modifier of row 203798.
fn armor() -> Told {
  let assert Ok(multiplier) = float32.of_column(armored_bits)
    as "dataBits02 of row 203798 is a finite float"
  held_changes.Applies(
    held_changes.Property(Change(
      property: UnitProperty2Id(161),
      mode: 3,
      multiplier:,
      flat: 0.0,
      per_level: 0.0,
    )),
  )
}

/// The pool of an absorb row, `amount` taking every damage type (mask 7, row 62024).
fn pool(amount amount: Int) -> Told {
  held_changes.Applies(held_changes.Absorb(amount:, mask: 7))
}

/// The Proc row 86457 a caster holds on the player (Healing Salve's allies' row, kind 16 takes
/// damage, Spell4 39386, 12 000 ms): the player applies nothing of it.
fn watches() -> Told {
  held_changes.Awaits(trigger: spell_plan.TakesDamage)
}

fn watch_source(cast_id cast_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(86_457))
}

/// The hold of the Proc row of caster 3's cast `cast_id`, as the go of Spell4 39386 at the
/// monotonic time 1000 tells it: 12 000 ms from the go, kept when the caster is unseen.
fn watch_hold(cast_id cast_id: Int) -> Hold {
  Hold(
    ..held(caster: 3, source: watch_source(cast_id:), change: watches()),
    sight: KeptWhenUnseen,
    spell4_id: Spell4Id(39_386),
    effect: HeldEffect(
      effect_id: Spell4EffectsId(86_457),
      starts_ms: 1000,
      ends: EndsAt(ms: 13_000),
    ),
  )
}

fn armor_source(cast_id cast_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(203_798))
}

fn pool_source(cast_id cast_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(62_024))
}

/// The entry of property 161 with `value` bits and its default as base.
fn armor_entry(value value: Int) -> UnitProperty {
  UnitProperty(property_id: 161, base: one_bits, value:)
}

/// The Interrupt Armor row 199192 (`table_rows -- Spell4Effects 199192`): +1 flat on property
/// 44, the armor's maximum (default 0.0), for 5000 ms.
fn interrupt_armor() -> Told {
  held_changes.Applies(
    held_changes.Property(unit_properties.Change(
      property: unit_properties.interrupt_armor_threshold,
      mode: 0,
      multiplier: 1.0,
      flat: 1.0,
      per_level: 0.0,
    )),
  )
}

fn interrupt_armor_source(cast_id cast_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(199_192))
}

/// The entry of property 44 with its default 0.0 as base and `value`.
fn maximum_entry(value value: Float) -> UnitProperty {
  UnitProperty(
    property_id: 44,
    base: float32.to_bits(0.0),
    value: float32.to_bits(value),
  )
}

/// What a held change is: the caster's connection number, the source and the change.
type Hold {
  Hold(
    caster: Int,
    source: Source,
    change: Told,
    sight: Sight,
    spell4_id: Spell4Id,
    effect: HeldEffect,
  )
}

/// The spell a hold is told for unless a test states it: Phantasmal Armor tier 9.
fn armor_spell() -> Spell4Id {
  Spell4Id(54_806)
}

/// The effect of `source` as a go at the monotonic time 1000 tells it, 10 000 ms long,
/// unless a test states it.
fn effect_of(source source: Source) -> HeldEffect {
  HeldEffect(effect_id: source.effect_id, starts_ms: 1000, ends: EndsAt(11_000))
}

fn held(
  caster caster: Int,
  source source: Source,
  change change: Told,
) -> Hold {
  Hold(
    caster:,
    source:,
    change:,
    sight: EndsWhenUnseen,
    spell4_id: armor_spell(),
    effect: effect_of(source:),
  )
}

fn starts(hold hold: Hold) -> PlayerChange {
  PlayerChangeStarts(
    from: ConnectionId(hold.caster),
    from_stay: support.viewer_stay(hold.caster),
    source: hold.source,
    change: hold.change,
    sight: hold.sight,
    spell4_id: hold.spell4_id,
    effect: hold.effect,
  )
}

fn tell(change: PlayerChange) -> Event(ConnectionEvent(Message, Answer)) {
  support.for_stay(
    stay: support.own_stay(),
    sent: client_connection.SentByPlayer(tell: client_connection.Change(change:)),
  )
}

/// The player of `state` seen by connections `viewers`, holding `holds` as the tells
/// gave them, in order.
fn holding_on(
  state state: game_connection.State,
  viewers viewers: List(Int),
  holds holds: List(Hold),
) -> game_connection.State {
  feed_all(
    state: support.watched_by(state:, viewers:),
    events: list.map(holds, fn(hold) { tell(starts(hold:)) }),
  ).0
}

/// A player in the world seen by connections 2 and 3, holding `holds`, in order.
fn holding(holds holds: List(Hold)) -> game_connection.State {
  holding_on(state: support.in_world(), viewers: [2, 3], holds:)
}

/// The state after each event, and the steps they took.
fn feed_all(
  state state: game_connection.State,
  events events: List(Event(ConnectionEvent(Message, Answer))),
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  let #(state, taken) =
    list.fold(events, #(state, []), fn(so_far, event) {
      let #(state, taken) = so_far
      let #(state, one) = support.feed(state:, event:)
      #(state, [one, ..taken])
    })
  #(state, list.reverse(taken))
}

/// The entries of each 0x93a the steps write to the player's client, in order.
fn properties_written(
  steps steps: List(ConnectionStep(Request)),
) -> List(List(UnitProperty)) {
  list.flat_map(steps, fn(taken) {
    support.decoded(
      support.heard(taken, support.keyed()),
      0x093A,
      unit_properties_changed.decode,
    )
  })
  |> list.map(fn(message: unit_properties_changed.UnitPropertiesChanged) {
    assert message.unit_id == support.own_unit_id
      as "the message names the player's own unit (opcode.0x93a)"
    message.properties
  })
}

/// The absorption each 0x938 of stat 22 the steps write to the player's client carries,
/// in order.
fn absorptions_written(
  steps steps: List(ConnectionStep(Request)),
) -> List(Int) {
  list.flat_map(steps, fn(taken) {
    support.decoded(
      support.heard(taken, support.keyed()),
      0x0938,
      unit_stat_changed.decode,
    )
  })
  |> list.filter_map(fn(message: unit_stat_changed.UnitStatChanged) {
    assert message.unit_id == support.own_unit_id
      as "the message names the player's own unit (opcode.0x938)"
    case message.change {
      unit_stat_change.Absorption(UnitStatAbsorption(value:)) -> Ok(value)
      unit_stat_change.Shield(..)
      | unit_stat_change.InterruptArmor(..)
      | unit_stat_change.Level(..) -> Error(Nil)
    }
  })
}

/// The news the steps tell the viewer connection `viewer`, in order.
fn news_told(
  steps steps: List(ConnectionStep(Request)),
  viewer viewer: Int,
) -> List(News) {
  list.flat_map(steps, support.news_told(_, viewer:))
}

/// The tells of the steps that are not news to a viewer: a change is told and ended with
/// no answer, so none leaves the connection.
fn tells_but_news(
  steps steps: List(ConnectionStep(Request)),
) -> List(#(step.Address, Request)) {
  list.flat_map(steps, support.tells)
  |> list.filter(fn(told) {
    case told.1 {
      TellPeer(..) -> False
      _ -> True
    }
  })
}

/// One write of the player's armor in a step: a 0x93a entry of property 44, the armor's
/// maximum, or a 0x938 of stat 21, the armor itself.
type ArmorWrite {
  Maximum(entry: UnitProperty)
  Armor(value: Int)
}

/// The writes of the armor the steps give the player's client, in the order of the frames:
/// the client clamps the armor to the maximum when a 0x938 arrives (`opcode.0x938` armor),
/// so the maximum goes first when the armor rises and last when it falls.
fn armor_written(
  steps steps: List(ConnectionStep(Request)),
) -> List(ArmorWrite) {
  list.flat_map(steps, fn(taken) {
    list.flat_map(support.heard(taken, support.keyed()), armor_written_by)
  })
}

/// What one frame writes of the armor.
fn armor_written_by(frame frame: Frame) -> List(ArmorWrite) {
  case frame.message_id {
    0x093A -> {
      let assert Ok(changed) = unit_properties_changed.decode(frame.body)
        as "a 0x93a decodes"
      list.filter(changed.properties, fn(entry) { entry.property_id == 44 })
      |> list.map(fn(entry) { Maximum(entry:) })
    }
    0x0938 -> {
      let assert Ok(changed) = unit_stat_changed.decode(frame.body)
        as "a 0x938 decodes"
      case changed.change {
        unit_stat_change.InterruptArmor(UnitStatInterruptArmor(value:)) -> [
          Armor(value:),
        ]
        unit_stat_change.Shield(..)
        | unit_stat_change.Absorption(..)
        | unit_stat_change.Level(..) -> []
      }
    }
    _ -> []
  }
}

/// What a step wrote and told, as the things a held change writes.
type Seen {
  Seen(
    properties: List(List(UnitProperty)),
    absorptions: List(Int),
    armor: List(ArmorWrite),
  )
}

fn seen(steps steps: List(ConnectionStep(Request))) -> Seen {
  Seen(
    properties: properties_written(steps:),
    absorptions: absorptions_written(steps:),
    armor: armor_written(steps:),
  )
}

pub fn a_change_a_player_in_sight_tells_is_applied_as_the_players_own_change_of_that_kind_is_test() -> Nil {
  use <- owned_test.run(10_000)
  // The change told, what the player's client is written, and the news the viewers get.
  let rows = [
    #(
      "a property modifier writes the 0x93a entry with the new value and tells each viewer",
      held(caster: 3, source: armor_source(cast_id: 100), change: armor()),
      Seen(
        properties: [[armor_entry(value: armored_bits)]],
        absorptions: [],
        armor: [],
      ),
      [PropertiesChanged(properties: [armor_entry(value: armored_bits)])],
    ),
    #(
      "an absorb writes the pool's amount as the absorption stat and tells each viewer",
      held(
        caster: 3,
        source: pool_source(cast_id: 101),
        change: pool(amount: 300),
      ),
      Seen(properties: [], absorptions: [300], armor: []),
      [Absorption(absorption: 300)],
    ),
    #(
      "a Proc row the caster holds on the player applies nothing: no property, absorb or armor is written and no viewer is told",
      watch_hold(cast_id: 103),
      Seen(properties: [], absorptions: [], armor: []),
      [],
    ),
    #(
      "an Interrupt Armor change (property 44, +1) writes the armor's maximum, then the armor stat at 1, to the player and tells each viewer both",
      held(
        caster: 3,
        source: interrupt_armor_source(cast_id: 102),
        change: interrupt_armor(),
      ),
      Seen(properties: [[maximum_entry(value: 1.0)]], absorptions: [], armor: [
        Maximum(entry: maximum_entry(value: 1.0)),
        Armor(value: 1),
      ]),
      [
        PropertiesChanged(properties: [maximum_entry(value: 1.0)]),
        InterruptArmor(armor: 1),
      ],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, hold, written, news) = row
    let state = support.watched_by(state: support.in_world(), viewers: [2, 3])
    let #(_, taken) = support.feed(state:, event: tell(starts(hold:)))
    assert seen(steps: [taken]) == written as reason
    list.each([2, 3], fn(viewer) {
      assert news_told(steps: [taken], viewer:) == news as reason
    })
    assert tells_but_news(steps: [taken]) == []
      as "nothing is asked or answered: no tell but the viewers' news leaves the connection"
  })
}

/// The cast of Healing Salve's child 39386 caster 3's connection started, as the create of a
/// player that holds its Proc row lists it at the monotonic time `at_ms`: caster 3's unit, the
/// player as primary and only target, row 86457 at delay 0 with the time left of its 13 000 ms end.
fn watch_entry(cast_id cast_id: Int, at_ms at_ms: Int) -> UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: support.viewer_unit_id(3),
    primary_target_unit_id: support.own_unit_id,
    cast_id:,
    spell4_id: 39_386,
    started: 0,
    targets: [
      cast_support.listed_target_info(
        unit_id: support.own_unit_id,
        index: 0,
        count: 1,
        effects: [
          cast_support.listed_effect_info(
            effect_id: 86_457,
            instance_id: 1,
            delay_ms: 0,
            lifetime_ms: 13_000 - at_ms,
          ),
        ],
      ),
    ],
    initial_positions: [],
    telegraph_positions: [],
  )
}

pub fn a_start_is_refused_with_nothing_written_for_a_caster_that_does_not_see_the_player_a_caster_in_another_stay_and_a_dead_player_test() -> Nil {
  use <- owned_test.run(10_000)
  let armored = fn(caster, from_stay) {
    PlayerChangeStarts(
      from: ConnectionId(caster),
      from_stay:,
      source: armor_source(cast_id: 100),
      change: armor(),
      sight: EndsWhenUnseen,
      spell4_id: armor_spell(),
      effect: effect_of(source: armor_source(cast_id: 100)),
    )
  }
  let pooled = fn(caster, from_stay) {
    PlayerChangeStarts(
      from: ConnectionId(caster),
      from_stay:,
      source: pool_source(cast_id: 101),
      change: pool(amount: 300),
      sight: EndsWhenUnseen,
      spell4_id: armor_spell(),
      effect: effect_of(source: pool_source(cast_id: 101)),
    )
  }
  let watched = fn(caster, from_stay) {
    let hold = watch_hold(cast_id: 103)
    PlayerChangeStarts(
      from: ConnectionId(caster),
      from_stay:,
      source: hold.source,
      change: hold.change,
      sight: hold.sight,
      spell4_id: hold.spell4_id,
      effect: hold.effect,
    )
  }
  let seen_by_two_and_three =
    support.watched_by(state: support.in_world(), viewers: [2, 3])
  let dead = support.killed(seen_by_two_and_three).0
  // The player, the caster whose change is told and whose unseen notice follows, and the
  // changes told it.
  let rows = [
    #(
      "a caster that is not among the viewers",
      seen_by_two_and_three,
      4,
      armored(4, support.viewer_stay(4)),
      pooled(4, support.viewer_stay(4)),
      watched(4, support.viewer_stay(4)),
    ),
    #(
      "a caster whose stay is not the one the map named for it",
      seen_by_two_and_three,
      3,
      armored(3, support.viewer_stay(9)),
      pooled(3, support.viewer_stay(9)),
      watched(3, support.viewer_stay(9)),
    ),
    #(
      "a dead player",
      dead,
      3,
      armored(3, support.viewer_stay(3)),
      pooled(3, support.viewer_stay(3)),
      watched(3, support.viewer_stay(3)),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, state, caster, armor_tell, pool_tell, watch_tell) = row
    let #(state, armor_taken) = support.feed(state:, event: tell(armor_tell))
    let #(state, pool_taken) = support.feed(state:, event: tell(pool_tell))
    let #(state, watch_taken) = support.feed(state:, event: tell(watch_tell))
    assert rule_support.effects_of(armor_taken) == [] as reason
    assert rule_support.effects_of(pool_taken) == [] as reason
    assert rule_support.effects_of(watch_taken) == [] as reason
    // The Proc row was not held either: the create of a viewer lists no cast of it.
    assert held_from_caster_3(created: support.created_at(
        state:,
        viewer: 4,
        ms: 2500,
      ))
      == []
      as reason
    // Nothing was held either: the caster's notice that it is unseen ends nothing.
    let #(_, unseen) =
      support.feed(
        state:,
        event: support.sent_by_the_map(map.UnseenBy(
          by: ConnectionId(caster),
          generation: support.viewer_sight(caster),
        )),
      )
    assert seen(steps: [unseen])
      == Seen(properties: [], absorptions: [], armor: [])
      as reason
  })
  // The went has a guard of its own, the ledger's, not the rows' (the caster among the
  // viewers): it starts a cast only for an ally that holds a source of it from the
  // connection the went came from. A dead ally holds none because its death clears the
  // ledger (`the_allys_ledger_clears_every_caster_at_its_death_test` pins that clear).
  let armor_of_three =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let holding_armor = holding_for_caster_4(holds: [armor_of_three])
  let went_rows = [
    #(
      "a went from a connection that holds no source of that cast (4 holds none of cast 100)",
      holding_armor,
      went(caster: 4, cast_id: 100, audience: []),
    ),
    #(
      "a went for a cast the ally holds nothing of",
      holding_armor,
      went(caster: 3, cast_id: 999, audience: []),
    ),
    #(
      "a went to a dead ally, whose death cleared its ledger",
      support.killed(holding_armor).0,
      went(caster: 3, cast_id: 100, audience: []),
    ),
  ]
  list.each(went_rows, fn(row) {
    let #(reason, state, event) = row
    let #(_, taken) = support.at(state:, ms: went_at_ms, event:)
    assert told_a_held_cast_start(taken:) == [] as reason
  })
  let #(_, taken) =
    support.at(
      state: holding_armor,
      ms: went_at_ms,
      event: went(caster: 3, cast_id: 100, audience: []),
    )
  assert told_a_held_cast_start(taken:) == [2, 4]
    as "the same went from the connection that holds the source starts the cast for the viewers outside its audience, so the refusals above are the guard's"
}

pub fn a_change_ended_by_its_caster_ends_in_the_players_own_way_and_an_end_that_names_no_held_source_of_that_caster_changes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let armor_held =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let pool_held =
    held(
      caster: 3,
      source: pool_source(cast_id: 101),
      change: pool(amount: 300),
    )
  // What the player holds, the ends told in order, what the ends write and the news the
  // viewer 2 gets.
  let rows = [
    #(
      "a held property: the 0x93a restores the value and the viewers get the entry, then that the cast ended",
      [armor_held],
      [
        PlayerChangeEnds(
          from: ConnectionId(3),
          source: armor_source(cast_id: 100),
        ),
      ],
      Seen(
        properties: [[armor_entry(value: one_bits)]],
        absorptions: [],
        armor: [],
      ),
      [
        PropertiesChanged(properties: [armor_entry(value: one_bits)]),
        HeldCastEnded(cast_id: 100),
      ],
    ),
    #(
      "a held Interrupt Armor change: the armor stat returns to 0 before the 0x93a that lowers the maximum, and the viewers get both in that order",
      [
        held(
          caster: 3,
          source: interrupt_armor_source(cast_id: 102),
          change: interrupt_armor(),
        ),
      ],
      [
        PlayerChangeEnds(
          from: ConnectionId(3),
          source: interrupt_armor_source(cast_id: 102),
        ),
      ],
      Seen(properties: [[maximum_entry(value: 0.0)]], absorptions: [], armor: [
        Armor(value: 0),
        Maximum(entry: maximum_entry(value: 0.0)),
      ]),
      [
        InterruptArmor(armor: 0),
        PropertiesChanged(properties: [maximum_entry(value: 0.0)]),
        HeldCastEnded(cast_id: 102),
      ],
    ),
    #(
      "a held absorb: the absorption stat returns to 0 and the viewers get it",
      [pool_held],
      [
        PlayerChangeEnds(
          from: ConnectionId(3),
          source: pool_source(cast_id: 101),
        ),
      ],
      Seen(properties: [], absorptions: [0], armor: []),
      [Absorption(absorption: 0), HeldCastEnded(cast_id: 101)],
    ),
    #(
      "a source never started",
      [armor_held],
      [
        PlayerChangeEnds(
          from: ConnectionId(3),
          source: armor_source(cast_id: 7),
        ),
      ],
      Seen(properties: [], absorptions: [], armor: []),
      [],
    ),
    #(
      "a source held by caster 3 named by caster 2",
      [armor_held],
      [
        PlayerChangeEnds(
          from: ConnectionId(2),
          source: armor_source(cast_id: 100),
        ),
      ],
      Seen(properties: [], absorptions: [], armor: []),
      [],
    ),
    #(
      "the same end twice writes the restore once",
      [armor_held],
      [
        PlayerChangeEnds(
          from: ConnectionId(3),
          source: armor_source(cast_id: 100),
        ),
        PlayerChangeEnds(
          from: ConnectionId(3),
          source: armor_source(cast_id: 100),
        ),
      ],
      Seen(
        properties: [[armor_entry(value: one_bits)]],
        absorptions: [],
        armor: [],
      ),
      [
        PropertiesChanged(properties: [armor_entry(value: one_bits)]),
        HeldCastEnded(cast_id: 100),
      ],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, holds, ends, written, news) = row
    let #(_, taken) =
      feed_all(state: holding(holds:), events: list.map(ends, tell))
    assert seen(steps: taken) == written as reason
    assert news_told(steps: taken, viewer: 2) == news as reason
    assert tells_but_news(steps: taken) == [] as "an end is answered by nothing"
  })
  // The end of caster 2 left the source of caster 3 held: its sight's end takes it.
  let #(_, unseen) =
    support.feed(
      state: feed_all(state: holding(holds: [armor_held]), events: [
        tell(PlayerChangeEnds(
          from: ConnectionId(2),
          source: armor_source(cast_id: 100),
        )),
      ]).0,
      event: support.sent_by_the_map(map.UnseenBy(
        by: ConnectionId(3),
        generation: support.viewer_sight(3),
      )),
    )
  assert properties_written(steps: [unseen]) == [[armor_entry(value: one_bits)]]
    as "the source another caster named stays held, and the holder's unseen notice ends it"
}

/// How the map says a caster is gone from the player.
type Notice {
  Unseen(caster: Int)
  UnitGone(caster: Int)
}

fn notice_of(notice notice: Notice) -> map.Notice {
  case notice {
    Unseen(caster:) ->
      map.UnseenBy(
        by: ConnectionId(caster),
        generation: support.viewer_sight(caster),
      )
    UnitGone(caster:) -> map.Gone(unit_id: support.viewer_unit_id(caster))
  }
}

pub fn a_caster_the_map_says_no_longer_sees_the_player_ends_each_change_it_held_and_no_other_casters_test() -> Nil {
  use <- owned_test.run(10_000)
  let armor_of_three =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let pool_of_three =
    held(
      caster: 3,
      source: pool_source(cast_id: 101),
      change: pool(amount: 300),
    )
  let pool_of_two =
    held(
      caster: 2,
      source: pool_source(cast_id: 102),
      change: pool(amount: 200),
    )
  let kept_armor_of_three = Hold(..armor_of_three, sight: KeptWhenUnseen)
  // What the player holds, the notice, the writes the notice makes, in the order the
  // 0x93a and the 0x938 come.
  let rows = [
    #(
      "caster 3 unseen ends its property and its absorb in start order, and keeps caster 2's pool",
      [armor_of_three, pool_of_three, pool_of_two],
      Unseen(3),
      [0x093A, 0x0938],
      Seen(
        properties: [[armor_entry(value: one_bits)]],
        absorptions: [200],
        armor: [],
      ),
    ),
    #(
      "caster 3 holding nothing: nothing is written",
      [pool_of_two],
      Unseen(3),
      [],
      Seen(properties: [], absorptions: [], armor: []),
    ),
    #(
      "a change of a spell with propertyFlags 0x100 survives its caster's sight",
      [kept_armor_of_three, pool_of_three],
      Unseen(3),
      [0x0938],
      Seen(properties: [], absorptions: [0], armor: []),
    ),
    #(
      "a change of a spell with propertyFlags 0x100 ends with its caster's unit",
      [kept_armor_of_three, pool_of_three, pool_of_two],
      UnitGone(3),
      [0x093A, 0x0938],
      Seen(
        properties: [[armor_entry(value: one_bits)]],
        absorptions: [200],
        armor: [],
      ),
    ),
    #(
      "the unit of a connection that is no caster's ends nothing",
      [armor_of_three],
      UnitGone(4),
      [],
      Seen(properties: [], absorptions: [], armor: []),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, holds, notice, ids, written) = row
    let #(_, taken) =
      support.feed(
        state: holding(holds:),
        event: support.sent_by_the_map(notice_of(notice:)),
      )
    assert support.written_ids(taken) == ids as reason
    assert seen(steps: [taken]) == written as reason
  })
  // The notice a second time finds nothing held.
  let state = holding(holds: [armor_of_three, pool_of_three])
  let #(state, _) =
    support.feed(
      state:,
      event: support.sent_by_the_map(notice_of(notice: Unseen(3))),
    )
  let #(_, again) =
    support.feed(
      state:,
      event: support.sent_by_the_map(notice_of(notice: Unseen(3))),
    )
  assert seen(steps: [again])
    == Seen(properties: [], absorptions: [], armor: [])
    as "a second notice for the same caster ends nothing"
  // The change that outlived sight still ends by its caster's end tell.
  let state = holding(holds: [kept_armor_of_three])
  let #(state, _) =
    support.feed(
      state:,
      event: support.sent_by_the_map(notice_of(notice: Unseen(3))),
    )
  let #(_, ended) =
    support.feed(
      state:,
      event: tell(PlayerChangeEnds(
        from: ConnectionId(3),
        source: armor_source(cast_id: 100),
      )),
    )
  assert properties_written(steps: [ended]) == [[armor_entry(value: one_bits)]]
    as "the end tell reaches a player that no longer sees the caster, which the 0x100 change relies on"
}

pub fn a_player_that_dies_ends_every_change_it_holds_from_other_players_test() -> Nil {
  use <- owned_test.run(10_000)
  let armor_of_three =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let pool_of_two =
    held(
      caster: 2,
      source: pool_source(cast_id: 102),
      change: pool(amount: 200),
    )
  // What the player holds, and the 0x93a entries the killing blow writes: the restore of
  // the held property, and nothing for a player that holds none.
  let rows = [
    #(
      "a property from caster 3 and an absorb from caster 2 both end with the death",
      [armor_of_three, pool_of_two],
      [[armor_entry(value: one_bits)]],
    ),
    #("a player that holds nothing writes no 0x93a", [], []),
  ]
  list.each(rows, fn(row) {
    let #(reason, holds, written) = row
    let #(_, taken) = support.killed(holding(holds:))
    assert properties_written(steps: [taken]) == written as reason
  })
}

pub fn a_second_tell_of_the_same_source_replaces_what_the_ally_holds_test() -> Nil {
  use <- owned_test.run(10_000)
  let first_pool =
    held(
      caster: 3,
      source: pool_source(cast_id: 101),
      change: pool(amount: 300),
    )
  let second_pool = Hold(..first_pool, change: pool(amount: 200))
  let armored =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  // What is held, the second tell, what it writes, and what one end then writes.
  let rows = [
    #(
      "an absorb told again refills the one pool: the stat reads the second amount, and one end empties it",
      first_pool,
      second_pool,
      Seen(properties: [], absorptions: [200], armor: []),
      Seen(properties: [], absorptions: [0], armor: []),
    ),
    #(
      "a property told again writes nothing, and one end restores it",
      armored,
      armored,
      Seen(properties: [], absorptions: [], armor: []),
      Seen(
        properties: [[armor_entry(value: one_bits)]],
        absorptions: [],
        armor: [],
      ),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, first, second, again, ended) = row
    let #(state, taken) =
      support.feed(
        state: holding(holds: [first]),
        event: tell(starts(hold: second)),
      )
    assert seen(steps: [taken]) == again as reason
    let #(_, ended_by) =
      support.feed(
        state:,
        event: tell(PlayerChangeEnds(
          from: ConnectionId(second.caster),
          source: second.source,
        )),
      )
    assert seen(steps: [ended_by]) == ended as reason
  })
}

pub fn the_allys_ledger_clears_every_caster_at_its_death_test() -> Nil {
  use <- owned_test.run(10_000)
  let armor_of_three =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let pool_of_three =
    Hold(
      ..held(
        caster: 3,
        source: pool_source(cast_id: 101),
        change: pool(amount: 300),
      ),
      sight: KeptWhenUnseen,
    )
  let pool_of_two =
    held(
      caster: 2,
      source: pool_source(cast_id: 102),
      change: pool(amount: 200),
    )
  // What the player holds: after its death its ledger holds no source of any caster, a
  // caster that keeps its change when unseen included, so no later notice of a caster ends
  // a change the death already ended, and no caster is counted as one that holds a change.
  let rows = [
    #("changes of two casters, one of them kept when unseen", [
      armor_of_three,
      pool_of_three,
      pool_of_two,
    ]),
    #("a player that holds nothing", []),
  ]
  list.each(rows, fn(row) {
    let #(reason, holds) = row
    let held_by_a_player_in_the_world =
      world_entry.Entered(
        ..world_entry_support.entered_after(clock_origin_ms: 600),
        held: list.fold(holds, held_changes.new(), fn(ledger, hold) {
          held_changes.started(
            held: ledger,
            by: ConnectionId(hold.caster),
            unit_id: support.viewer_unit_id(hold.caster),
            source: hold.source,
            sight: hold.sight,
            spell4_id: hold.spell4_id,
            effect: hold.effect,
            trigger: None,
          ).0
        }),
      )
    assert list.length(held_changes.all(
        held: held_by_a_player_in_the_world.held,
      ))
      == list.length(holds)
      as { reason <> ": the ledger holds each source before the death" }
    let #(session, _) =
      connection_landing.ended_at_death(
        session: support.session_in(status: connection_state.InWorld(
          holder: support.holder(),
          entered: held_by_a_player_in_the_world,
        )),
        now: step.Now(monotonic_ms: 0, filetime: 0),
      )
    let assert Some(after) = connection_state.entered_of(session.status)
      as "the player is still in the world"
    assert held_changes.all(held: after.held) == []
      as { reason <> ": the death clears every source" }
    assert held_changes.connections(held: after.held) == []
      as { reason <> ": and no caster holds a change on the player" }
  })
}

/// A frame the player's client is written, as the tests below tell them apart: the 0x7fe
/// of a cast, or any other frame by its opcode.
type Wrote {
  Finished(cast_id: Int)
  Wrote(opcode: Int)
}

/// The 0x7fe, 0x355, 0x262, 0x93a and 0x938 frames the steps write, in order, each step's
/// frames in a list of their own.
fn wrote(steps steps: List(ConnectionStep(Request))) -> List(List(Wrote)) {
  list.map(steps, fn(taken) {
    list.filter_map(support.heard(taken, support.keyed()), fn(frame) {
      case frame.message_id {
        0x07FE -> {
          let assert Ok(finished) = spell_finished.decode(frame.body)
            as "a 0x7fe the connection wrote decodes"
          Ok(Finished(cast_id: finished.cast_id))
        }
        0x0355 | 0x0262 | 0x093A | 0x0938 -> Ok(Wrote(opcode: frame.message_id))
        _ -> Error(Nil)
      }
    })
  })
}

/// The cast ids of the 0x7fe frames the steps write, in order.
fn finished_in(steps steps: List(ConnectionStep(Request))) -> List(Int) {
  list.flat_map(wrote(steps:), fn(frames) {
    list.filter_map(frames, fn(frame) {
      case frame {
        Finished(cast_id:) -> Ok(cast_id)
        Wrote(..) -> Error(Nil)
      }
    })
  })
}

/// News of the unit of the viewer connection `caster`, as that connection sends it.
fn from_caster(
  caster caster: Int,
  news news: News,
) -> Event(ConnectionEvent(Message, Answer)) {
  support.sent_by_a_peer(support.news_of(
    unit_id: support.viewer_unit_id(caster),
    news:,
  ))
}

/// The state with the unit of each caster shown (its 0x262 written) and the casts listed
/// for it started, as its connection tells them: the client holds those casts.
fn showing_casts(
  state state: game_connection.State,
  casters casters: List(#(Int, List(Int))),
) -> game_connection.State {
  let unit = fn(caster) {
    UnitCreatePlayer(
      ..support.another_unit(),
      unit_id: support.viewer_unit_id(caster),
    )
  }
  list.fold(casters, state, fn(state, shown) {
    let #(caster, cast_ids) = shown
    let #(state, _) =
      support.feed(
        state:,
        event: from_caster(
          caster:,
          news: Appeared(unit: unit(caster), generation: generation.first()),
        ),
      )
    list.fold(cast_ids, state, fn(state, cast_id) {
      support.feed(
        state:,
        event: from_caster(
          caster:,
          news: CastStarted(start: support.spell_started_of(
            cast_id:,
            caster: support.viewer_unit_id(caster),
          )),
        ),
      ).0
    })
  })
}

/// The armor and the pool of Phantasmal Armor's cast `cast_id` held from caster 3, each
/// with the sight `sight`.
fn armor_and_pool(cast_id cast_id: Int, sight sight: Sight) -> List(Hold) {
  [
    Hold(
      ..held(caster: 3, source: armor_source(cast_id:), change: armor()),
      sight:,
    ),
    Hold(
      ..held(
        caster: 3,
        source: pool_source(cast_id:),
        change: pool(amount: 300),
      ),
      sight:,
    ),
  ]
}

/// How the caster's unit leaves the ally's client: its own connection's removal news, or
/// the map saying its unit is gone.
type Departure {
  Removal
  UnitGoneFromTheMap
}

fn departed(
  caster caster: Int,
  departure departure: Departure,
) -> Event(ConnectionEvent(Message, Answer)) {
  case departure {
    Removal -> from_caster(caster:, news: Removed)
    UnitGoneFromTheMap ->
      support.sent_by_the_map(map.Gone(unit_id: support.viewer_unit_id(caster)))
  }
}

fn ending(hold hold: Hold) -> Event(ConnectionEvent(Message, Answer)) {
  tell(PlayerChangeEnds(from: ConnectionId(hold.caster), source: hold.source))
}

pub fn a_caster_leaving_the_sight_of_a_player_that_holds_its_kept_change_is_not_finished_on_the_players_client_test() -> Nil {
  use <- owned_test.run(10_000)
  // Client fact `cast.target_node_end`: the removal of a caster's unit keeps the casts of a
  // spell with propertyFlags 0x100 and finishes the others, so the viewer writes the
  // 0x7fe of the casts the client does not keep, before the 0x355. Each row: what the
  // player holds, the casters shown and the casts of each its client was sent the start
  // of, how the caster 3 (or the one named) leaves, what the player's client is written
  // (0x7fe, 0x355, 0x93a and 0x938 only), and the 0x7fe the ends of the held sources then
  // write.
  let rows = [
    #(
      "a removal with the cast held kept writes the 0x355 and no 0x7fe of it",
      list.take(armor_and_pool(cast_id: 100, sight: KeptWhenUnseen), 1),
      [#(3, [100])],
      #(3, Removal),
      [Wrote(0x0355)],
      [100],
    ),
    #(
      "a removal with the cast held ending with sight writes its 0x7fe, then the 0x355",
      list.take(armor_and_pool(cast_id: 100, sight: EndsWhenUnseen), 1),
      [#(3, [100])],
      #(3, Removal),
      [Finished(100), Wrote(0x0355)],
      [],
    ),
    #(
      "of two written casts the one held kept stays and the other is finished",
      list.take(armor_and_pool(cast_id: 100, sight: KeptWhenUnseen), 1),
      [#(3, [100, 101])],
      #(3, Removal),
      [Finished(101), Wrote(0x0355)],
      [100],
    ),
    #(
      "a kept source of a cast the client was never sent writes the 0x355 only, and its end no 0x7fe",
      list.take(armor_and_pool(cast_id: 100, sight: KeptWhenUnseen), 1),
      [#(3, [])],
      #(3, Removal),
      [Wrote(0x0355)],
      [],
    ),
    #(
      "the unit gone while shown ends the sources, so its cast is finished once, before the 0x355",
      armor_and_pool(cast_id: 100, sight: KeptWhenUnseen),
      [#(3, [100])],
      #(3, UnitGoneFromTheMap),
      [Finished(100), Wrote(0x0355), Wrote(0x093A), Wrote(0x0938)],
      [],
    ),
    #(
      "a removal of one caster reads only that caster's casts: another caster's kept cast does not hold it",
      list.take(armor_and_pool(cast_id: 100, sight: KeptWhenUnseen), 1),
      [#(3, [100]), #(2, [200])],
      #(2, Removal),
      [Finished(200), Wrote(0x0355)],
      [],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, holds, casters, departure, written, after_ends) = row
    let state = showing_casts(state: holding(holds:), casters:)
    let #(state, departed) =
      support.feed(
        state:,
        event: departed(caster: departure.0, departure: departure.1),
      )
    let #(_, ended) =
      feed_all(state:, events: list.map(holds, fn(hold) { ending(hold:) }))
    let writes = wrote(steps: [departed])
    assert writes == [written] as reason
    assert finished_in(steps: ended) == after_ends as reason
  })
}

/// What reaches the ally after the point a row starts from.
type Reaches {
  /// The end tell of the source of a hold.
  End(hold: Hold)
  /// The caster's unit is seen again (its 0x262).
  CasterSeenAgain
  /// The caster's unit is seen again with the cast `cast_id` in its 0x262's list.
  CasterSeenListing(cast_id: Int)
  /// The caster's finish of cast 100 reaches the ally.
  CasterFinishes
  /// The map says the caster no longer sees the ally.
  MapUnseen
  /// The map says the caster's unit is gone.
  MapGone
  /// The caster's connection sends the removal of its unit.
  CasterRemoved
}

pub fn the_end_of_a_kept_change_whose_caster_left_the_players_sight_writes_the_casts_0x7fe_once_after_its_last_source_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [armor_hold, pool_hold] =
    armor_and_pool(cast_id: 100, sight: KeptWhenUnseen)
    as "Phantasmal Armor's cast holds its armor and its pool"
  // Client fact `cast.target_node_end`: with the cast kept and its caster gone, only a
  // 0x7fe from the server ends the buff on the ally; the ally writes it once, after the
  // write of the last source's own end. Each row: what reaches the ally in
  // order, and the frames it writes for each (0x7fe, 0x93a, 0x938, 0x262 and 0x355 only).
  let rows = [
    #(
      "the pool's end writes its own stat only, the armor's end then its own entry and the cast's 0x7fe",
      [CasterRemoved, End(pool_hold), End(armor_hold)],
      [[Wrote(0x0355)], [Wrote(0x0938)], [Wrote(0x093A), Finished(100)]],
    ),
    #(
      "a second end of either source writes nothing",
      [
        CasterRemoved,
        End(pool_hold),
        End(armor_hold),
        End(armor_hold),
        End(pool_hold),
      ],
      [
        [Wrote(0x0355)],
        [Wrote(0x0938)],
        [Wrote(0x093A), Finished(100)],
        [],
        [],
      ],
    ),
    #(
      "the caster seen again before the end: the end of the last source writes the 0x7fe",
      [CasterRemoved, CasterSeenAgain, End(armor_hold), End(pool_hold)],
      [
        [Wrote(0x0355)],
        [Wrote(0x0262)],
        [Wrote(0x093A)],
        [Wrote(0x0938), Finished(100)],
      ],
    ),
    #(
      "a later notice of the caster after the end writes no second 0x7fe",
      [
        CasterRemoved,
        End(pool_hold),
        End(armor_hold),
        MapUnseen,
        MapGone,
      ],
      [
        [Wrote(0x0355)],
        [Wrote(0x0938)],
        [Wrote(0x093A), Finished(100)],
        [],
        [],
      ],
    ),
    #(
      "the caster seen again with the cast listed: the end writes the 0x7fe and the caster's later finish writes none",
      [
        CasterRemoved,
        CasterSeenListing(cast_id: 100),
        End(armor_hold),
        End(pool_hold),
        CasterFinishes,
      ],
      [
        [Wrote(0x0355)],
        [Wrote(0x0262)],
        [Wrote(0x093A)],
        [Wrote(0x0938), Finished(100)],
        [],
      ],
    ),
    #(
      "the caster seen again with the cast listed finishes it itself before the ends: its finish writes the 0x7fe once and the end of the last source writes none",
      [
        CasterRemoved,
        CasterSeenListing(cast_id: 100),
        CasterFinishes,
        End(armor_hold),
        End(pool_hold),
      ],
      [
        [Wrote(0x0355)],
        [Wrote(0x0262)],
        [Finished(100)],
        [Wrote(0x093A)],
        [Wrote(0x0938)],
      ],
    ),
    #(
      "the caster's lingering finish after its removal writes nothing and the end writes the 0x7fe later",
      [CasterRemoved, CasterFinishes, End(armor_hold), End(pool_hold)],
      [
        [Wrote(0x0355)],
        [],
        [Wrote(0x093A)],
        [Wrote(0x0938), Finished(100)],
      ],
    ),
    #(
      "the map's unseen notice of the caster keeps the kept sources, and the end writes the 0x7fe",
      [CasterRemoved, MapUnseen, End(armor_hold), End(pool_hold)],
      [
        [Wrote(0x0355)],
        [],
        [Wrote(0x093A)],
        [Wrote(0x0938), Finished(100)],
      ],
    ),
    #(
      "the caster's unit gone ends both sources and writes the 0x7fe once, with no second 0x355",
      [CasterRemoved, MapGone, End(armor_hold)],
      [
        [Wrote(0x0355)],
        [Wrote(0x093A), Wrote(0x0938), Finished(100)],
        [],
      ],
    ),
    #(
      "the ends before the caster's removal write no 0x7fe, and the removal writes it once",
      [End(pool_hold), End(armor_hold), CasterRemoved],
      [[Wrote(0x0938)], [Wrote(0x093A)], [Finished(100), Wrote(0x0355)]],
    ),
    #(
      "the caster shown, the end of the last source writes no 0x7fe and the caster's finish writes it once",
      [End(pool_hold), End(armor_hold), CasterFinishes, CasterFinishes],
      [[Wrote(0x0938)], [Wrote(0x093A)], [Finished(100)], []],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, events, expected) = row
    let state =
      showing_casts(state: holding(holds: [armor_hold, pool_hold]), casters: [
        #(3, [100]),
      ])
    let events =
      list.map(events, fn(event) {
        case event {
          End(hold:) -> ending(hold:)
          CasterSeenAgain ->
            from_caster(
              caster: 3,
              news: Appeared(
                unit: UnitCreatePlayer(
                  ..support.another_unit(),
                  unit_id: support.viewer_unit_id(3),
                ),
                generation: generation.first(),
              ),
            )
          CasterSeenListing(cast_id:) ->
            from_caster(
              caster: 3,
              news: Appeared(
                unit: support.another_unit_casting(
                  casts: [
                    support.listed_cast(
                      cast_id:,
                      caster: support.viewer_unit_id(3),
                    ),
                  ],
                  cast_id: 0,
                ),
                generation: generation.first(),
              ),
            )
          CasterFinishes ->
            from_caster(caster: 3, news: CastFinished(cast_id: 100))
          MapUnseen ->
            support.sent_by_the_map(map.UnseenBy(
              by: ConnectionId(3),
              generation: support.viewer_sight(3),
            ))
          MapGone ->
            support.sent_by_the_map(
              map.Gone(unit_id: support.viewer_unit_id(3)),
            )
          CasterRemoved -> from_caster(caster: 3, news: Removed)
        }
      })
    let #(_, taken) = feed_all(state:, events:)
    assert wrote(steps: taken) == expected as reason
  })
}

pub fn the_death_of_an_ally_whose_kept_change_lost_its_caster_ends_its_sources_in_start_order_and_writes_the_casts_0x7fe_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [armor_hold, pool_hold] =
    armor_and_pool(cast_id: 100, sight: KeptWhenUnseen)
    as "Phantasmal Armor's cast holds its armor and its pool"
  let state =
    showing_casts(
      state: support.feed(
        state: holding(holds: [armor_hold, pool_hold]),
        event: support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
      ).0,
      casters: [#(3, [100])],
    )
  let #(state, _) =
    support.feed(state:, event: from_caster(caster: 3, news: Removed))
  let #(_, killed) = support.feed(state:, event: support.a_killing_strike())
  let frames = list.flatten(wrote(steps: [killed]))
  assert list.filter(frames, fn(frame) { frame == Finished(100) })
    == [Finished(100)]
    as "the cast is finished once"
  assert list.drop_while(frames, fn(frame) { frame != Wrote(0x093A) })
    |> list.take(2)
    == [Wrote(0x093A), Finished(100)]
    as "the armor's end is written, then the cast's 0x7fe after the last source"
}

// ---- the create the ally sends a viewer that comes into sight ----

/// Gamma Rays (Spell4 29874: castTime 1250 ms, a Normal cast with a cast bar), the Medic's
/// level-1 ability, by Spell4Base.
const gamma_rays_base = 16_322

/// The Interrupt Armor of caster 3's cast `cast_id`, as the go of Spell4 76766 at the
/// monotonic time 1000 tells it: row 199192, 5000 ms from the go.
fn interrupt_armor_hold(cast_id cast_id: Int) -> Hold {
  Hold(
    ..held(
      caster: 3,
      source: interrupt_armor_source(cast_id:),
      change: interrupt_armor(),
    ),
    spell4_id: Spell4Id(76_766),
    effect: HeldEffect(
      effect_id: Spell4EffectsId(199_192),
      starts_ms: 1000,
      ends: EndsAt(ms: 6000),
    ),
  )
}

/// The cast of Interrupt Armor caster 3's connection started, as the create of a player that
/// holds it lists it at the monotonic time `at_ms`: caster 3's unit, the player as primary and
/// only target, state 0 (a landed change is told at the go), the row at delay 0 with the time
/// left of its 6000 ms end (`opcode.0x262.casts`, `opcode.0x7f4.effect_delay`,
/// `opcode.0x7f4.effect_time`).
fn interrupt_armor_entry(
  cast_id cast_id: Int,
  at_ms at_ms: Int,
) -> UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: support.viewer_unit_id(3),
    primary_target_unit_id: support.own_unit_id,
    cast_id:,
    spell4_id: 76_766,
    started: 0,
    targets: [
      cast_support.listed_target_info(
        unit_id: support.own_unit_id,
        index: 0,
        count: 1,
        effects: [
          cast_support.listed_effect_info(
            effect_id: 199_192,
            instance_id: 1,
            delay_ms: 0,
            lifetime_ms: 6000 - at_ms,
          ),
        ],
      ),
    ],
    initial_positions: [],
    telegraph_positions: [],
  )
}

/// The entries of a create that name caster 3's unit as their caster: what the create lists
/// beside the player's own casts and passive.
fn held_from_caster_3(
  created created: UnitCreatePlayer,
) -> List(UnitCreateCast) {
  list.filter(created.tail.casts, fn(cast) {
    cast.caster_unit_id == support.viewer_unit_id(3)
  })
}

pub fn a_player_that_comes_into_sight_lists_the_casts_other_players_hold_on_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // The ally holds the Interrupt Armor of caster 3's cast 100: the viewer that arrives at
  // 2500 ms is sent a create that lists the cast, whether or not it sees the caster.
  let created =
    support.created_at(
      state: holding(holds: [interrupt_armor_hold(cast_id: 100)]),
      viewer: 4,
      ms: 2500,
    )
  assert held_from_caster_3(created:)
    == [interrupt_armor_entry(cast_id: 100, at_ms: 2500)]
    as "the create lists the cast another player's connection holds on the ally"
  // A Proc row the caster holds on the ally is held as any source is and listed in the create
  // with the cast of its spell and the row's effect.
  assert held_from_caster_3(created: support.created_at(
      state: holding(holds: [watch_hold(cast_id: 103)]),
      viewer: 4,
      ms: 2500,
    ))
    == [watch_entry(cast_id: 103, at_ms: 2500)]
    as "the create lists the Proc row's cast as any held source's"
  assert created.tail.cast_id == 0 as "no cast bar: the ally casts nothing"
  // The ally's own cast and the held casts are one list in cast id order; the tail's cast id
  // is the ally's own cast, never a held one.
  let #(state, _, bag_index) =
    support.entered_with_spell_trees(class_id: 4, ability: gamma_rays_base)
  let #(state, steps) =
    support.pressed_until(
      state: support.watched_by(state:, viewers: [2, 3]),
      bag_index:,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1000,
    )
  let assert [own_cast, ..] =
    list.flat_map(steps, fn(taken) {
      support.cast_starts(support.news_told(taken:, viewer: 2))
    })
    as "the watcher is told the Gamma Rays cast started"
  let below = own_cast.cast_id - 1000
  let above = own_cast.cast_id + 1000
  let #(state, _) =
    feed_all(
      state:,
      events: list.map(
        [
          interrupt_armor_hold(cast_id: above),
          interrupt_armor_hold(cast_id: below),
        ],
        fn(hold) { tell(starts(hold:)) },
      ),
    )
  let created = support.created_at(state:, viewer: 4, ms: 1000)
  assert list.map(created.tail.casts, fn(cast) { cast.cast_id })
    == [below, own_cast.cast_id, above]
    as "the ally's own cast stands between the held casts, in cast id order"
  assert held_from_caster_3(created:)
    == [
      interrupt_armor_entry(cast_id: below, at_ms: 1000),
      interrupt_armor_entry(cast_id: above, at_ms: 1000),
    ]
    as "each held cast is listed as the first is"
  assert created.tail.cast_id == own_cast.cast_id
    as "the tail's cast id is the ally's own cast, never a held one"
  // The list's count is 9 bits: 512 casts held list 511, the lowest cast ids first.
  let casts =
    int.range(from: 1, to: 513, with: [], run: fn(acc, i) { [i, ..acc] })
    |> list.reverse
  let created =
    support.created_at(
      state: holding(
        holds: list.map(casts, fn(cast_id) { interrupt_armor_hold(cast_id:) }),
      ),
      viewer: 4,
      ms: 2500,
    )
  assert list.map(created.tail.casts, fn(cast) { cast.cast_id })
    == int.range(from: 1, to: 512, with: [], run: fn(acc, i) { [i, ..acc] })
    |> list.reverse
    as "the list is cut at 511 entries (opcode.0x262.casts: a 9-bit count)"
}

/// The cast ids each step tells the viewer connection `viewer` ended (`HeldCastEnded`), a
/// list for each step, in order.
fn held_casts_ended(
  steps steps: List(ConnectionStep(Request)),
  viewer viewer: Int,
) -> List(List(Int)) {
  list.map(steps, fn(taken) {
    list.filter_map(support.news_told(taken:, viewer:), fn(news) {
      case news {
        HeldCastEnded(cast_id:) -> Ok(cast_id)
        _ -> Error(Nil)
      }
    })
  })
}

/// Whether the effect is the tell of a `HeldCastEnded` to a viewer.
fn tells_a_held_cast_ended(
  effect effect: step.Effect(step.ConnectionEffect(Request)),
) -> Bool {
  case effect {
    OwnEffect(step.Tell(
      request: TellPeer(
        news: unit_news.PeerNews(news: HeldCastEnded(..), ..),
        ..,
      ),
      ..,
    )) -> True
    _ -> False
  }
}

/// What happens to the ally in a row of the test below.
type AllyEvent {
  CasterEnds(hold: Hold)
  MapNotice(notice: Notice)
  AllyDies
}

/// The Design's end paths of #570 Part 7, and `landing.changed`, `caster_unseen`,
/// `caster_removed` and `ended_at_death`: when the ledger's last source of a cast leaves,
/// the ally tells each of its viewers `HeldCastEnded` with the cast id, once per cast, in
/// cast id order, after what it writes for its own client. The ledger's own ends are tested
/// above; this tests what the ally then tells.
pub fn the_last_source_of_a_cast_that_ends_on_an_ally_tells_each_of_its_viewers_the_cast_ended_test() -> Nil {
  use <- owned_test.run(10_000)
  let armor_of_three =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let kept_armor_of_three = Hold(..armor_of_three, sight: KeptWhenUnseen)
  let assert [armor_hold, pool_hold] =
    armor_and_pool(cast_id: 100, sight: EndsWhenUnseen)
    as "Phantasmal Armor's cast holds its armor and its pool"
  // What the ally holds, what happens to it, and the casts each step tells connection 2 and
  // connection 3 ended, a list for each step.
  let rows = [
    #(
      "the end tell of the only source tells each viewer the cast ended",
      [armor_of_three],
      [CasterEnds(armor_of_three)],
      [[100]],
      [[100]],
    ),
    #(
      "the end tell of one of two sources tells none, and of the second tells one",
      [armor_hold, pool_hold],
      [CasterEnds(armor_hold), CasterEnds(pool_hold)],
      [[], [100]],
      [[], [100]],
    ),
    #(
      "the unseen notice of the caster ends an unkept source and tells the viewers that remain, not the caster that left",
      [armor_of_three],
      [MapNotice(Unseen(3))],
      [[100]],
      [[]],
    ),
    #(
      "the unseen notice of the caster leaves a kept source and tells none",
      [kept_armor_of_three],
      [MapNotice(Unseen(3))],
      [[]],
      [[]],
    ),
    #(
      "the gone notice of the caster's unit ends a kept source and tells",
      [kept_armor_of_three],
      [MapNotice(UnitGone(3))],
      [[100]],
      [[100]],
    ),
    #(
      "the ally's death with two casts held tells one per cast in cast id order",
      list.append(armor_and_pool(cast_id: 200, sight: EndsWhenUnseen), [
        interrupt_armor_hold(cast_id: 100),
      ]),
      [AllyDies],
      [[100, 200]],
      [[100, 200]],
    ),
    #(
      "an ally with no viewer left tells nobody",
      [kept_armor_of_three],
      [
        MapNotice(Unseen(3)),
        MapNotice(Unseen(2)),
        CasterEnds(kept_armor_of_three),
      ],
      [[], [], []],
      [[], [], []],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, holds, events, to_two, to_three) = row
    let #(_, steps) =
      list.fold(events, #(holding(holds:), []), fn(so_far, event) {
        let #(state, steps) = so_far
        let #(state, taken) = case event {
          CasterEnds(hold:) -> support.feed(state:, event: ending(hold:))
          MapNotice(notice:) ->
            support.feed(
              state:,
              event: support.sent_by_the_map(notice_of(notice:)),
            )
          AllyDies -> support.killed(state)
        }
        #(state, list.append(steps, [taken]))
      })
    assert held_casts_ended(steps:, viewer: 2) == to_two as reason
    assert held_casts_ended(steps:, viewer: 3) == to_three as reason
  })
  // The tell comes after every write to the ally's own client, as the cast's 0x7fe of a kept
  // change does.
  let #(_, ended) =
    support.feed(
      state: holding(holds: [armor_of_three]),
      event: ending(hold: armor_of_three),
    )
  let effects = rule_support.effects_of(ended)
  let #(before, from_the_first_tell) =
    list.split_while(effects, fn(effect) { !tells_a_held_cast_ended(effect:) })
  assert list.any(before, fn(effect) {
    case effect {
      OwnEffect(step.Write(..)) -> True
      _ -> False
    }
  })
    as "the end of the armor writes its 0x93a to the ally's own client first"
  assert list.all(from_the_first_tell, fn(effect) {
    case effect {
      OwnEffect(step.Write(..)) -> False
      _ -> True
    }
  })
    as "no write to the ally's own client follows the first tell"
}

/// The starts of a held cast the step tells the viewer connection `viewer` (`HeldCastStarted`),
/// each as its 0x7ff and its 0x7f4, in order.
fn held_casts_started(
  taken taken: ConnectionStep(Request),
  viewer viewer: Int,
) -> List(#(SpellStarted, SpellGo)) {
  list.filter_map(support.news_told(taken:, viewer:), fn(news) {
    case news {
      HeldCastStarted(start:, go:) -> Ok(#(start, go))
      _ -> Error(Nil)
    }
  })
}

/// The connection numbers the step tells a `HeldCastStarted`, in order.
fn told_a_held_cast_start(taken taken: ConnectionStep(Request)) -> List(Int) {
  list.filter_map(support.peer_tells(taken), fn(tell) {
    case { tell.1 }.news {
      HeldCastStarted(..) -> Ok(tell.0)
      _ -> Error(Nil)
    }
  })
}

/// The go of caster connection `caster`'s cast `cast_id`, as the caster's connection tells the
/// ally after its rows, with the connections it told the cast's 0x7ff.
fn went(
  caster caster: Int,
  cast_id cast_id: Int,
  audience audience: List(Int),
) -> Event(ConnectionEvent(Message, Answer)) {
  tell(PlayerCastWent(
    from: ConnectionId(caster),
    cast_id:,
    audience: set.from_list(list.map(audience, ConnectionId)),
  ))
}

/// The ally, seen by connections 2, 3 and 4 (the caster's), holding `holds` as the caster's
/// tells gave them.
fn holding_for_caster_4(holds holds: List(Hold)) -> game_connection.State {
  holding_on(state: support.in_world(), viewers: [2, 3, 4], holds:)
}

/// Caster 4's holds of the cast `cast_id`, Phantasmal Armor's armor and its pool, each kept
/// or not when its caster is unseen as `sight` says.
fn armor_and_pool_of_4(cast_id cast_id: Int, sight sight: Sight) -> List(Hold) {
  list.map(armor_and_pool(cast_id:, sight:), fn(hold) {
    Hold(..hold, caster: 4)
  })
}

/// The monotonic time of the go, after the rows were told for the go's time 1000.
const went_at_ms = 2500

pub fn a_went_tell_makes_the_ally_start_the_cast_for_each_of_its_viewers_outside_the_audience_except_the_caster_test() -> Nil {
  use <- owned_test.run(10_000)
  let armor_of_four =
    Hold(
      ..held(caster: 4, source: armor_source(cast_id: 100), change: armor()),
      sight: KeptWhenUnseen,
    )
  // Row 1: viewers 2 (outside the audience), 3 (inside it) and 4 (the caster).
  let #(_, taken) =
    support.at(
      state: holding_for_caster_4(holds: [armor_of_four]),
      ms: went_at_ms,
      event: went(caster: 4, cast_id: 100, audience: [3]),
    )
  assert told_a_held_cast_start(taken:) == [2]
    as "only connection 2 is told the start: 3 is in the audience and 4 is the caster"
  let assert [#(start, go)] = held_casts_started(taken:, viewer: 2)
    as "connection 2 is told one start"
  assert start.cast_id == 100
    && start.caster_unit_id == support.viewer_unit_id(4)
    && start.primary_target_unit_id == support.own_unit_id
    && start.spell4_id == 54_806
    as "the start names the caster's unit, the cast, its spell and the ally as the target"
  assert go.cast_id == 100
    && list.map(go.targets, fn(target) { target.unit_id })
    == [support.own_unit_id]
    as "the go is the cast's, listing the ally"
  assert list.map(go.targets, fn(target) {
      list.map(target.effects, fn(effect) {
        #(effect.spell4_effects_id, effect.delay_ms, effect.lifetime_ms)
      })
    })
    == [[#(203_798, 0, 8500)]]
    as "the effect 203798 at delay 0 with the time left of its 10 000 ms from the go at 1000, at 2500"
  // Row 2: the caster's connection is not told though it is outside the audience.
  let #(_, taken) =
    support.at(
      state: holding_for_caster_4(holds: [armor_of_four]),
      ms: went_at_ms,
      event: went(caster: 4, cast_id: 100, audience: []),
    )
  assert told_a_held_cast_start(taken:) == [2, 3]
    as "with an empty audience both other viewers are told, and the caster is not: its client has the cast from its own go, and a 0x7ff naming its own unit starts its global cooldown (opcode.0x7ff)"
  // Row 3: an audience that names a connection that is not a viewer of the ally (9) tells
  // nobody for it, and a viewer that left before the went (2) is told nothing.
  let #(left, _) =
    support.feed(
      state: holding_for_caster_4(holds: [armor_of_four]),
      event: support.sent_by_the_map(map.UnseenBy(
        by: ConnectionId(2),
        generation: support.viewer_sight(2),
      )),
    )
  let #(_, taken) =
    support.at(
      state: left,
      ms: went_at_ms,
      event: went(caster: 4, cast_id: 100, audience: [9]),
    )
  assert told_a_held_cast_start(taken:) == [3]
    as "connection 9 is no viewer and is told nothing; connection 2 left before the went and is told nothing"
  // Row 4: two rows of one cast, then the went: one start holding both effects, told once.
  let #(_, taken) =
    support.at(
      state: holding_for_caster_4(holds: armor_and_pool_of_4(
        cast_id: 100,
        sight: KeptWhenUnseen,
      )),
      ms: went_at_ms,
      event: went(caster: 4, cast_id: 100, audience: [3]),
    )
  let assert [#(_, both)] = held_casts_started(taken:, viewer: 2)
    as "one start holding both effects is told once"
  assert list.map(both.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
    == [[203_798, 62_024]]
    as "both effects of the cast are listed on the one target, in the order they were told"
  // Row 5: a viewer made a viewer after the went is told no start: its create lists the cast.
  let #(state, _) =
    support.at(
      state: holding_for_caster_4(holds: [armor_of_four]),
      ms: went_at_ms,
      event: went(caster: 4, cast_id: 100, audience: [3]),
    )
  let #(_, arrived) =
    support.feed(
      state:,
      event: support.sent_by_the_map(map.SeenBy(
        by: ConnectionId(6),
        stay: support.viewer_stay(6),
        unit_id: support.viewer_unit_id(6),
        generation: support.viewer_sight(6),
      )),
    )
  assert told_a_held_cast_start(taken: arrived) == []
    as "a viewer that arrives after the went is told no start"
  // Row 6: every effect of the cast ended before the went (its end tell came first), or ended
  // by the clock: nobody is told.
  let #(ended, _) =
    support.feed(
      state: holding_for_caster_4(holds: [armor_of_four]),
      event: ending(hold: armor_of_four),
    )
  let #(_, taken) =
    support.at(
      state: ended,
      ms: went_at_ms,
      event: went(caster: 4, cast_id: 100, audience: [3]),
    )
  assert told_a_held_cast_start(taken:) == []
    as "a cast whose only source ended before the went is started for nobody"
  let #(_, taken) =
    support.at(
      state: holding_for_caster_4(holds: [armor_of_four]),
      ms: 11_000,
      event: went(caster: 4, cast_id: 100, audience: [3]),
    )
  assert told_a_held_cast_start(taken:) == []
    as "a cast whose every effect ended at the clock is started for nobody"
  // Row 7: the caster's unseen notice taken between the rows and the went. A kept cast
  // (Phantasmal Armor, propertyFlags 257) is still started for the outside viewer; an unkept
  // one (Interrupt Armor 76766), already ended by the notice, is not.
  let unkept_armor = Hold(..interrupt_armor_hold(cast_id: 101), caster: 4)
  list.each(
    [
      #("a kept cast", armor_of_four, 100, [2]),
      #("an unkept cast", unkept_armor, 101, []),
    ],
    fn(row) {
      let #(reason, hold, cast_id, told) = row
      let #(unseen, _) =
        support.feed(
          state: holding_for_caster_4(holds: [hold]),
          event: support.sent_by_the_map(map.UnseenBy(
            by: ConnectionId(4),
            generation: support.viewer_sight(4),
          )),
        )
      let #(_, taken) =
        support.at(
          state: unseen,
          ms: went_at_ms,
          event: went(caster: 4, cast_id:, audience: [3]),
        )
      assert told_a_held_cast_start(taken:) == told
        as {
          reason
          <> " after the caster's unseen notice is started for the outside viewer only when the ally still holds it"
        }
    },
  )
}

/// What the player's connection tells casters of a blow on it: each `PlayerTell.Event` a step
/// sends, as the caster's connection number, the stay it is told for and the tell.
fn events_told(
  taken taken: ConnectionStep(Request),
) -> List(#(Int, Stay, strike_tell.PlayerEvent)) {
  list.filter_map(support.tells(taken), fn(told) {
    case told {
      #(
        step.Connection(connection: ConnectionId(caster)),
        client_connection.TellPlayer(
          stay:,
          tell: client_connection.Event(event:),
        ),
      ) -> Ok(#(caster, stay, event))
      _ -> Error(Nil)
    }
  })
}

/// The Proc row `trigger` that caster `caster`'s cast `cast_id` holds on the player, kept when
/// the caster is unseen as Healing Salve's is.
fn waits(
  caster caster: Int,
  cast_id cast_id: Int,
  trigger trigger: spell_plan.Trigger,
) -> Hold {
  Hold(..watch_hold(cast_id:), caster:, change: held_changes.Awaits(trigger:))
}

/// A creature's strike on the player of the Beast's attack Spell4 5649, each blow dealing
/// `damage`.
fn beast_blow(
  damage damage: Int,
) -> fn(game_connection.State) -> ConnectionStep(Request) {
  fn(state) {
    support.feed(
      state:,
      event: support.a_strike_of(
        striker: spawn_support.beast_striker(),
        offence: spawn_support.dealing(
          offence: spawn_support.beast_attack().offence,
          damage:,
        ),
        unit_id: support.own_unit_id,
      ),
    ).1
  }
}

/// The event of a creature's blow that lowered the player's shield or health, as the Beast's
/// attack Spell4 5649 raises it: the Beast 7 as the other unit, and the spell's groups 6, 9,
/// 134 and 333 (Spell4GroupList 657) and school 1 (Spell4Base 4947), read with
/// `table_rows -- Spell4 5649`, `Spell4GroupList 657` and `Spell4Base 4947`.
fn beast_takes_damage() -> proc.Event {
  proc.Event(
    trigger: spell_plan.TakesDamage,
    other_unit: Some(7),
    spell: Some(proc.EventSpell(
      spell4_id: Spell4Id(5649),
      spell4_base_id: Spell4BaseId(4947),
      groups: [6, 9, 134, 333],
      school: 1,
    )),
    holder: None,
  )
}

/// The event of the same blow of kind `trigger`: the Beast 7 and its attack Spell4 5649 name
/// each event of one blow alike (`cast_proc.blow_events`).
fn beast_event(trigger trigger: spell_plan.Trigger) -> proc.Event {
  proc.Event(..beast_takes_damage(), trigger:)
}

/// A creature's blow of the Beast's attack Spell4 5649 that is a critical (a crit chance of 1.0
/// draws a roll below it) and deals `damage`.
fn beast_critical_blow(
  damage damage: Int,
) -> fn(game_connection.State) -> ConnectionStep(Request) {
  fn(state) {
    support.feed(
      state:,
      event: support.a_strike_of(
        striker: spawn_support.beast_striker(),
        offence: hit.Offence(
          ..spawn_support.dealing(
            offence: spawn_support.beast_attack().offence,
            damage:,
          ),
          crit_chance: 1.0,
        ),
        unit_id: support.own_unit_id,
      ),
    ).1
  }
}

/// The tell of `events` caster `caster` is sent for the player, as the caster's stay names it.
fn told_to(
  caster caster: Int,
  events events: List(proc.Event),
) -> #(Int, Stay, strike_tell.PlayerEvent) {
  #(
    caster,
    support.viewer_stay(caster),
    strike_tell.PlayerEvent(unit_id: support.own_unit_id, events:),
  )
}

pub fn a_creatures_blow_on_a_player_tells_each_caster_among_its_viewers_the_events_it_waits_for_and_a_lethal_blow_tells_none_test() -> Nil {
  use <- owned_test.run(10_000)
  let a_players_blow = fn(state) {
    support.feed(
      state:,
      event: support.a_strike_of(
        striker: strike_tell.PlayerStriker(
          unit_id: 9,
          place: place_support.at(
            world_id: 3460,
            world_zone_id: 5967,
            x: 0.0,
            y: 0.0,
            z: 0.0,
          ),
          seq: 1,
          stay: support.viewer_stay(9),
          hit_radius: place_support.player_hit_radius,
          rolls: hit.Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
        ),
        offence: spawn_support.beast_attack().offence,
        unit_id: support.own_unit_id,
      ),
    ).1
  }
  let the_tables_lack_the_spell = fn(state) {
    support.feed(
      state:,
      event: support.a_strike_of(
        striker: strike_tell.CreatureStriker(
          unit_id: 7,
          spell4_id: Spell4Id(99_999_999),
        ),
        offence: spawn_support.beast_attack().offence,
        unit_id: support.own_unit_id,
      ),
    ).1
  }
  let a_lethal_blow = fn(state) { support.killed(state).1 }
  let casters_three_and_two = [
    waits(caster: 3, cast_id: 103, trigger: spell_plan.TakesDamage),
    waits(caster: 2, cast_id: 104, trigger: spell_plan.TakesDamage),
  ]
  // The holds, the player's blow-taking step, the tells to casters it sends in order, and
  // the warnings it writes.
  let rows = [
    #(
      "a landed blow that lowered health tells the caster that waits for TakesDamage: its stay, the player's unit and the one event",
      [waits(caster: 3, cast_id: 103, trigger: spell_plan.TakesDamage)],
      beast_blow(damage: 12),
      [told_to(caster: 3, events: [beast_takes_damage()])],
      0,
    ),
    #(
      "two casters that wait for it get a tell each, in the order their sources started",
      casters_three_and_two,
      beast_blow(damage: 12),
      [
        told_to(caster: 3, events: [beast_takes_damage()]),
        told_to(caster: 2, events: [beast_takes_damage()]),
      ],
      0,
    ),
    #(
      "a caster that waits for another event is told nothing of a blow that raises none of it",
      [waits(caster: 3, cast_id: 103, trigger: spell_plan.DeflectsAttack)],
      beast_blow(damage: 12),
      [],
      0,
    ),
    #(
      "a blow that lowered nothing and was no critical raises nothing to tell",
      casters_three_and_two,
      beast_blow(damage: 0),
      [],
      0,
    ),
    #(
      "a blow of a player is not a creature's blow: nothing is told",
      casters_three_and_two,
      a_players_blow,
      [],
      0,
    ),
    #(
      "an attack Spell4 the tables cannot read tells nothing and the procs of the blow are logged as skipped",
      casters_three_and_two,
      the_tables_lack_the_spell,
      [],
      1,
    ),
    #(
      "a lethal blow: the player is dead when its blow is carried, before the death clears the ledger, so no caster is told",
      casters_three_and_two,
      a_lethal_blow,
      [],
      0,
    ),
    #(
      "a critical blow that took the shield to 0 tells a caster that waits for all three of its events one tell: TakesDamage, SuffersCritical and ShieldDepleted, in that order",
      [
        waits(caster: 3, cast_id: 103, trigger: spell_plan.TakesDamage),
        waits(caster: 3, cast_id: 104, trigger: spell_plan.SuffersCritical),
        waits(caster: 3, cast_id: 105, trigger: spell_plan.ShieldDepleted),
      ],
      beast_critical_blow(damage: 3000),
      [
        told_to(caster: 3, events: [
          beast_event(trigger: spell_plan.TakesDamage),
          beast_event(trigger: spell_plan.SuffersCritical),
          beast_event(trigger: spell_plan.ShieldDepleted),
        ]),
      ],
      0,
    ),
    #(
      "a caster that waits for SuffersCritical alone is told that event of the same blow and no other",
      [waits(caster: 3, cast_id: 103, trigger: spell_plan.SuffersCritical)],
      beast_critical_blow(damage: 3000),
      [
        told_to(caster: 3, events: [
          beast_event(trigger: spell_plan.SuffersCritical),
        ]),
      ],
      0,
    ),
    #(
      "a caster that waits for ShieldDepleted alone is told that event of the same blow and no other",
      [waits(caster: 3, cast_id: 103, trigger: spell_plan.ShieldDepleted)],
      beast_critical_blow(damage: 3000),
      [
        told_to(caster: 3, events: [
          beast_event(trigger: spell_plan.ShieldDepleted),
        ]),
      ],
      0,
    ),
    #(
      "a critical blow that took the shield to 0 is no deflect: a caster that waits for DeflectsAttack is told nothing of it",
      [waits(caster: 3, cast_id: 103, trigger: spell_plan.DeflectsAttack)],
      beast_critical_blow(damage: 3000),
      [],
      0,
    ),
    #(
      "a player that holds no Proc source tells nobody",
      [],
      beast_blow(damage: 12),
      [],
      0,
    ),
  ]
  let check = fn(holding_in, row) {
    let #(reason, holds, blow, told, warnings) = row
    let taken = blow(holding_in(holds))
    assert events_told(taken:) == told as reason
    assert list.length(rule_support.logs_of(step: taken, level: step.LogWarning))
      == warnings
      as reason
  }
  list.each(rows, check(fn(holds) { holding(holds:) }, _))
  // A tell adds nothing else: the blow's other effects are those of the same blow on a
  // player that holds nothing.
  let without_tells = fn(taken) {
    list.filter(rule_support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(step.Tell(
          request: client_connection.TellPlayer(
            tell: client_connection.Event(..),
            ..,
          ),
          ..,
        )) -> False
        _ -> True
      }
    })
  }
  assert without_tells(
      beast_blow(damage: 12)(holding(holds: casters_three_and_two)),
    )
    == without_tells(beast_blow(damage: 12)(holding(holds: [])))
    as "the blow's other effects do not depend on what the player holds"
  // A caster that is not among the player's viewers is told nothing, and its source stays: it
  // is told again once it is back among the viewers.
  let gone =
    support.feed(
      state: holding(holds: [
        waits(caster: 3, cast_id: 103, trigger: spell_plan.TakesDamage),
      ]),
      event: support.sent_by_the_map(map.UnseenBy(
        by: ConnectionId(3),
        generation: support.viewer_sight(3),
      )),
    ).0
  assert events_told(taken: beast_blow(damage: 12)(gone)) == []
    as "a caster the player no longer sees is not told, though its source of a spell with propertyFlags 0x100 is kept"
  assert events_told(
      taken: beast_blow(damage: 12)(
        support.watched_by(state: gone, viewers: [3]),
      ),
    )
    == [told_to(caster: 3, events: [beast_takes_damage()])]
    as "the kept source is awaited again when the caster is back among the viewers"
  // A deflect: GameFormula 1235 gives the deflect chance (`rating.formulas`), an intercept of
  // 100 with the knee above it makes it 100% at level 1, so every roll deflects the blow (an
  // edit of the real row: no client row gives a player a deflect chance at level 1).
  use tables <- fixture_tables.changed(table: "GameFormula", id: 1235, with: [
    #("dataint0", planted_table.Integer(100)),
    #("datafloat02", planted_table.Integer(float32.to_bits(200.0))),
  ])
  let deflecting = fn(holds) {
    holding_on(
      state: support.entered_with_quests_on(tables:, quests: []).0,
      viewers: [2, 3],
      holds:,
    )
  }
  check(deflecting, #(
    "a deflect tells a caster that waits for all four events DeflectsAttack only: it lowered nothing, was no critical and took no shield",
    [
      waits(caster: 3, cast_id: 103, trigger: spell_plan.TakesDamage),
      waits(caster: 3, cast_id: 104, trigger: spell_plan.SuffersCritical),
      waits(caster: 3, cast_id: 105, trigger: spell_plan.DeflectsAttack),
      waits(caster: 3, cast_id: 106, trigger: spell_plan.ShieldDepleted),
    ],
    beast_critical_blow(damage: 3000),
    [
      told_to(caster: 3, events: [
        beast_event(trigger: spell_plan.DeflectsAttack),
      ]),
    ],
    0,
  ))
}

/// The viewer `viewer` of the player (connection 3's unit) is shown the caster's unit and the
/// start of its cast `cast_id`, as the caster's snapshot and news give them.
fn caster_shown_casting(
  state state: game_connection.State,
  cast_id cast_id: Int,
) -> game_connection.State {
  let caster_unit = support.viewer_unit_id(3)
  feed_all(state:, events: [
    support.sent_by_a_peer(support.news_of(
      unit_id: caster_unit,
      news: Appeared(
        unit: UnitCreatePlayer(..support.another_unit(), unit_id: caster_unit),
        generation: support.viewer_sight(3),
      ),
    )),
    support.sent_by_a_peer(support.news_of(
      unit_id: caster_unit,
      news: unit_news.CastStarted(start: support.spell_started_of(
        cast_id:,
        caster: caster_unit,
      )),
    )),
  ]).0
}

pub fn a_unit_leaves_a_viewer_by_one_message_that_finishes_its_casts_removes_it_and_ends_its_sources_in_that_order_test() -> Nil {
  use <- owned_test.run(10_000)
  // Caster 3, whose unit the player shows and whose cast 100 the player's client holds as
  // written by it. The player holds, from that caster, an armor that ends with its sight
  // (cast 100) and a pool of a spell with propertyFlags 0x100, kept (cast 101).
  let armor_of_three =
    held(caster: 3, source: armor_source(cast_id: 100), change: armor())
  let kept_pool_of_three =
    Hold(
      ..held(
        caster: 3,
        source: pool_source(cast_id: 101),
        change: pool(amount: 300),
      ),
      sight: KeptWhenUnseen,
    )
  let state =
    caster_shown_casting(
      state: holding(holds: [armor_of_three, kept_pool_of_three]),
      cast_id: 100,
    )
  let unseen =
    support.sent_by_the_map(map.PlayerUnseen(
      unit_id: support.viewer_unit_id(3),
      generation: support.viewer_sight(3),
    ))
  let #(state, taken) = support.feed(state:, event: unseen)
  assert support.written_ids(taken) == [0x07FE, 0x0355, 0x093A]
    as "the 0x7fe of the cast the caster wrote, the caster's 0x355, then the end of the armor that ends with its sight"
  assert seen(steps: [taken]).absorptions == []
    as "the kept pool is not ended: its spell keeps its buff after the caster's removal (cast.target_node_end)"
  let #(_, again) = support.feed(state:, event: unseen)
  assert support.written_ids(again) == []
    as "a second message for the same sight writes nothing: the unit is removed once"
}

pub fn a_caster_that_joins_again_ends_the_sources_of_its_earlier_stay_that_end_with_its_sight_and_keeps_a_kept_one_and_a_creatures_test() -> Nil {
  use <- owned_test.run(10_000)
  // The player holds from caster 3: a pool that ends with its sight (cast 101), an armor
  // of a spell with propertyFlags 0x100 (cast 100); and from caster 4 a pool (cast 102),
  // which stands for a source the caster's sight does not end. Caster 3's connection joins
  // again: its earlier sight of the player ends (`PlayerUnseen`) and a new one begins.
  let pool_of_three =
    held(
      caster: 3,
      source: pool_source(cast_id: 101),
      change: pool(amount: 300),
    )
  let kept_armor_of_three =
    Hold(
      ..held(caster: 3, source: armor_source(cast_id: 100), change: armor()),
      sight: KeptWhenUnseen,
    )
  let pool_of_four =
    held(
      caster: 4,
      source: pool_source(cast_id: 102),
      change: pool(amount: 200),
    )
  let state =
    caster_shown_casting(
      state: holding_on(state: support.in_world(), viewers: [2, 3, 4], holds: [
        pool_of_three,
        kept_armor_of_three,
        pool_of_four,
      ]),
      cast_id: 100,
    )
  let #(state, unseen) =
    support.feed(
      state:,
      event: support.sent_by_the_map(map.PlayerUnseen(
        unit_id: support.viewer_unit_id(3),
        generation: support.viewer_sight(3),
      )),
    )
  assert seen(steps: [unseen]).absorptions == [200]
    as "caster 3's pool, which ends with its sight, is taken off: the player's absorption falls to caster 4's 200"
  assert seen(steps: [unseen]).properties == []
    as "the armor of the spell that keeps its buff is not taken off"
  let new_stay = stay.next(support.viewer_stay(3))
  let new_sight = generation.after(support.viewer_sight(5))
  let #(state, _) =
    support.feed(
      state:,
      event: support.sent_by_the_map(map.SeenBy(
        by: ConnectionId(3),
        stay: new_stay,
        unit_id: support.viewer_unit_id(3),
        generation: new_sight,
      )),
    )
  let #(_, started) =
    support.feed(
      state:,
      event: tell(PlayerChangeStarts(
        from: ConnectionId(3),
        from_stay: new_stay,
        source: pool_source(cast_id: 103),
        change: pool(amount: 300),
        sight: EndsWhenUnseen,
        spell4_id: armor_spell(),
        effect: effect_of(source: pool_source(cast_id: 103)),
      )),
    )
  assert seen(steps: [started]).absorptions == [500]
    as "a start of the caster's new stay is held: caster 4's 200 and the new 300"
}
