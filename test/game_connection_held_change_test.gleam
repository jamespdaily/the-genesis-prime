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

import connection_rule_support as rule_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type Answer, type Message, type News, type Request, Absorption, Appeared,
  CastFinished, CastStarted, InterruptArmor, PropertiesChanged, Removed,
  TellPeer,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/landing as connection_landing
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/held_changes.{
  type Change, type PlayerChange, type Sight, EndsWhenUnseen, KeptWhenUnseen,
  PlayerChangeEnds, PlayerChangeStarts,
}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties.{type Source, Change, Source}
import genesis_prime/game/world_entry
import genesis_prime/message/float32
import genesis_prime/message/spell_finished
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat_absorption.{UnitStatAbsorption}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_interrupt_armor.{UnitStatInterruptArmor}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, ConnectionId, OwnEffect,
}
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import genesis_prime/world_map/map
import gleam/list
import gleam/option.{Some}
import owned_test
import world_entry_support

/// UnitProperty2 161's default, 1.0, and the value row 203798 gives it, 0.86f.
const one_bits = 0x3F800000

const armored_bits = 1_062_836_634

/// The modifier of row 203798.
fn armor() -> Change {
  let assert Ok(multiplier) = float32.of_column(armored_bits)
    as "dataBits02 of row 203798 is a finite float"
  held_changes.Property(Change(
    property: UnitProperty2Id(161),
    mode: 3,
    multiplier:,
    flat: 0.0,
    per_level: 0.0,
  ))
}

/// The pool of an absorb row, `amount` taking every damage type (mask 7, row 62024).
fn pool(amount amount: Int) -> Change {
  held_changes.Absorb(amount:, mask: 7)
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
fn interrupt_armor() -> Change {
  held_changes.Property(unit_properties.Change(
    property: unit_properties.interrupt_armor_threshold,
    mode: 0,
    multiplier: 1.0,
    flat: 1.0,
    per_level: 0.0,
  ))
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
  Hold(caster: Int, source: Source, change: Change, sight: Sight)
}

fn held(
  caster caster: Int,
  source source: Source,
  change change: Change,
) -> Hold {
  Hold(caster:, source:, change:, sight: EndsWhenUnseen)
}

fn starts(hold hold: Hold) -> PlayerChange {
  PlayerChangeStarts(
    from: ConnectionId(hold.caster),
    from_stay: support.viewer_stay(hold.caster),
    source: hold.source,
    change: hold.change,
    sight: hold.sight,
  )
}

fn tell(change: PlayerChange) -> Event(ConnectionEvent(Message, Answer)) {
  support.for_stay(
    stay: support.own_stay(),
    sent: client_connection.SentByCaster(change:),
  )
}

/// A player in the world seen by connections 2 and 3, holding `holds`, in order.
fn holding(holds holds: List(Hold)) -> game_connection.State {
  feed_all(
    state: support.watched_by(state: support.in_world(), viewers: [2, 3]),
    events: list.map(holds, fn(hold) { tell(starts(hold:)) }),
  ).0
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

pub fn a_start_is_refused_with_nothing_written_for_a_caster_that_does_not_see_the_player_a_caster_in_another_stay_and_a_dead_player_test() -> Nil {
  use <- owned_test.run(10_000)
  let armored = fn(caster, from_stay) {
    PlayerChangeStarts(
      from: ConnectionId(caster),
      from_stay:,
      source: armor_source(cast_id: 100),
      change: armor(),
      sight: EndsWhenUnseen,
    )
  }
  let pooled = fn(caster, from_stay) {
    PlayerChangeStarts(
      from: ConnectionId(caster),
      from_stay:,
      source: pool_source(cast_id: 101),
      change: pool(amount: 300),
      sight: EndsWhenUnseen,
    )
  }
  let seen_by_two_and_three =
    support.watched_by(state: support.in_world(), viewers: [2, 3])
  let dead = support.killed(seen_by_two_and_three).0
  // The player, the caster whose change is told and whose unseen notice follows, and the
  // change told it.
  let rows = [
    #(
      "a caster that is not among the viewers",
      seen_by_two_and_three,
      4,
      armored(4, support.viewer_stay(4)),
      pooled(4, support.viewer_stay(4)),
    ),
    #(
      "a caster whose stay is not the one the map named for it",
      seen_by_two_and_three,
      3,
      armored(3, support.viewer_stay(9)),
      pooled(3, support.viewer_stay(9)),
    ),
    #(
      "a dead player",
      dead,
      3,
      armored(3, support.viewer_stay(3)),
      pooled(3, support.viewer_stay(3)),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, state, caster, armor_tell, pool_tell) = row
    let #(state, armor_taken) = support.feed(state:, event: tell(armor_tell))
    let #(state, pool_taken) = support.feed(state:, event: tell(pool_tell))
    assert rule_support.effects_of(armor_taken) == [] as reason
    assert rule_support.effects_of(pool_taken) == [] as reason
    // Nothing was held either: the caster's notice that it is unseen ends nothing.
    let #(_, unseen) =
      support.feed(
        state:,
        event: support.sent_by_the_map(map.UnseenBy(by: ConnectionId(caster))),
      )
    assert seen(steps: [unseen])
      == Seen(properties: [], absorptions: [], armor: [])
      as reason
  })
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
      "a held property: the 0x93a restores the value and the viewers get the entry",
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
      [PropertiesChanged(properties: [armor_entry(value: one_bits)])],
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
      [Absorption(absorption: 0)],
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
      [PropertiesChanged(properties: [armor_entry(value: one_bits)])],
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
      event: support.sent_by_the_map(map.UnseenBy(by: ConnectionId(3))),
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
    Unseen(caster:) -> map.UnseenBy(by: ConnectionId(caster))
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
    case notice, rule_support.effects_of(taken) {
      Unseen(caster:), [first, ..] if caster == 3 -> {
        assert first
          == OwnEffect(step.Tell(
            to: step.Connection(connection: ConnectionId(3)),
            request: TellPeer(
              stay: support.viewer_stay(3),
              news: client_connection.PeerNews(
                unit_id: support.own_unit_id,
                news: client_connection.Removed,
              ),
            ),
          ))
          as "the viewer's removal is told first, the ends after it"
      }
      _, _ -> Nil
    }
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
        event: from_caster(caster:, news: Appeared(unit: unit(caster))),
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
    Hold(caster: 3, source: armor_source(cast_id:), change: armor(), sight:),
    Hold(
      caster: 3,
      source: pool_source(cast_id:),
      change: pool(amount: 300),
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
              ),
            )
          CasterSeenListing(cast_id:) ->
            from_caster(
              caster: 3,
              news: Appeared(unit: support.another_unit_casting(
                casts: [
                  support.listed_cast(
                    cast_id:,
                    caster: support.viewer_unit_id(3),
                  ),
                ],
                cast_id: 0,
              )),
            )
          CasterFinishes ->
            from_caster(caster: 3, news: CastFinished(cast_id: 100))
          MapUnseen ->
            support.sent_by_the_map(map.UnseenBy(by: ConnectionId(3)))
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
