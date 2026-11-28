//// What the caster's game connection does with the changes its cast rule tells another
//// player (`genesis_prime/game/connection/casting` `cast_effects`): it tells the connection
//// of that player, for the stay the cast's address names, `TellLanding` to the map of a
//// `Change` with its own connection and stay as the caster, and writes nothing to its own client. The
//// shell decides nothing: the rule chose the change, the source and whether it outlives
//// sight. Expected values come from these places.
//// - `genesis_prime/game/held_changes`: a start names the caster's connection and stay
////   (`from`, `from_stay`), which the player holds the change against; an end names the
////   caster's connection and the source.
//// - `genesis_prime/client_connection` `TellLanding(.., to_stay, ChangeStart | ChangeEnd |
////   CastWent)`: the stay is the player's, from the address the go used (the map's `SeenBy`).
//// - The caster is the tests' connection 1 in the stay `world_entry_support` gives its
////   `Entered`; the ally is connection 2 in the stay `map_support.stay(count: 2)`.

import game_connection_support as support
import genesis_prime/client_connection
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/effects as connection_effects
import genesis_prime/game/connection/state.{type Session, InWorld}
import genesis_prime/game/held_changes.{
  Absorb, KeptWhenUnseen, PlayerCastWent, PlayerChangeEnds, PlayerChangeStarts,
  Property,
}
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/world_entry
import genesis_prime/shared/lasting
import genesis_prime/shared/unit_casts.{type HeldEffect, EndsAt, HeldEffect}
import genesis_prime/shared/unit_properties.{type Source, Change, Source}
import genesis_prime/step.{type Effect, ConnectionId, Now, OwnEffect}
import genesis_prime/table/id.{
  type Spell4Id, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import genesis_prime/world_map/relay
import gleam/dict
import gleam/list
import gleam/result
import map_support
import owned_test
import world_entry_support

const ally_connection = 2

fn address() -> PlayerAddress {
  PlayerAddress(
    connection: ConnectionId(ally_connection),
    unit_id: 40,
    stay: map_support.stay(count: ally_connection),
  )
}

fn source() -> Source {
  Source(cast_id: 2_147_500_000, effect_id: Spell4EffectsId(130_470))
}

fn modifier() -> unit_properties.Modifier {
  Change(
    property: UnitProperty2Id(161),
    mode: 3,
    multiplier: 0.86,
    flat: 0.0,
    per_level: 0.0,
  )
}

/// The spell of the cast that holds the change: Phantasmal Armor tier 9 (Spell4 54806).
fn spell4_id() -> Spell4Id {
  Spell4Id(54_806)
}

/// The effect the rule tells with the change, its start a monotonic time before the clock
/// origin so that a start taken as a delay, or as 0, differs from it.
fn held_effect() -> HeldEffect {
  HeldEffect(
    effect_id: source().effect_id,
    starts_ms: -4000,
    ends: EndsAt(ms: 6000),
  )
}

/// The tests' caster, in the world.
fn entered() -> world_entry.Entered {
  world_entry_support.entered_after(clock_origin_ms: 600)
}

fn in_the_world() -> Session {
  support.session_in(status: InWorld(
    holder: support.holder(),
    entered: entered(),
  ))
}

/// What a tell to the ally's connection is, as the caster's connection sends it: to the
/// map, for the ally's connection and stay, with the caster's own connection and stay.
fn told_to_the_ally(
  change change: held_changes.PlayerChange,
) -> Effect(step.ConnectionEffect(client_connection.Request)) {
  let landing = case change {
    PlayerChangeStarts(..) -> relay.ChangeStart(change:)
    PlayerChangeEnds(..) -> relay.ChangeEnd(change:)
    PlayerCastWent(..) -> relay.CastWent(change:)
  }
  OwnEffect(step.Tell(
    to: step.Map(map: entered().map, incarnation: entered().incarnation),
    request: client_connection.TellLanding(
      connection: ConnectionId(1),
      stay: entered().stay,
      to: address().connection,
      to_stay: address().stay,
      landing:,
    ),
  ))
}

fn carried(
  session session: Session,
  effects effects: List(cast_state.Effect),
) -> List(Effect(step.ConnectionEffect(client_connection.Request))) {
  casting.cast_effects(
    session:,
    now: Now(monotonic_ms: 0, filetime: 0),
    effects:,
  ).1
}

pub fn a_change_the_cast_rule_tells_a_player_is_sent_to_the_map_for_that_players_connection_and_stay_from_the_casters_own_connection_and_stay_test() -> Nil {
  use <- owned_test.run(10_000)
  let own_stay = entered().stay
  let from = ConnectionId(1)
  // The effect, what it tells and to whom; nothing is written to the caster's client.
  let rows = [
    #(
      "an absorb start: one tell to the map for the ally's connection and stay, from the caster's connection and stay, the sight as the rule gave it",
      cast_state.OtherPlayerChangeStarts(
        address: address(),
        source: source(),
        change: held_changes.Applies(Absorb(amount: 300, mask: 7)),
        sight: KeptWhenUnseen,
        spell4_id: spell4_id(),
        effect: held_effect(),
      ),
      [
        told_to_the_ally(change: PlayerChangeStarts(
          from:,
          from_stay: own_stay,
          source: source(),
          change: held_changes.Applies(Absorb(amount: 300, mask: 7)),
          sight: KeptWhenUnseen,
          spell4_id: spell4_id(),
          effect: held_effect(),
        )),
      ],
    ),
    #(
      "a property modifier start with the sight that ends when unseen",
      cast_state.OtherPlayerChangeStarts(
        address: address(),
        source: source(),
        change: held_changes.Applies(Property(modifier: modifier())),
        sight: held_changes.EndsWhenUnseen,
        spell4_id: spell4_id(),
        effect: held_effect(),
      ),
      [
        told_to_the_ally(change: PlayerChangeStarts(
          from:,
          from_stay: own_stay,
          source: source(),
          change: held_changes.Applies(Property(modifier: modifier())),
          sight: held_changes.EndsWhenUnseen,
          spell4_id: spell4_id(),
          effect: held_effect(),
        )),
      ],
    ),
    #(
      "a went: one tell to the map for the ally's connection and stay, from the caster's own connection, with the cast id as the rule gave it",
      cast_state.OtherPlayerCastWent(
        address: address(),
        cast_id: source().cast_id,
      ),
      [
        told_to_the_ally(change: PlayerCastWent(
          from:,
          cast_id: source().cast_id,
        )),
      ],
    ),
    #(
      "an end: one tell for the ally's stay naming the caster's connection and the source",
      cast_state.OtherPlayerChangeEnds(address: address(), source: source()),
      [
        told_to_the_ally(change: PlayerChangeEnds(from:, source: source())),
      ],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, effect, expected) = row
    assert carried(session: in_the_world(), effects: [effect]) == expected
      as reason
  })
  // A connection with no player in the world has nothing to tell from.
  let before_the_world = support.session_in(status: state.AwaitingHelloReply)
  assert carried(session: before_the_world, effects: [
      cast_state.OtherPlayerChangeStarts(
        address: address(),
        source: source(),
        change: held_changes.Applies(Absorb(amount: 300, mask: 7)),
        sight: KeptWhenUnseen,
        spell4_id: spell4_id(),
        effect: held_effect(),
      ),
      cast_state.OtherPlayerChangeEnds(address: address(), source: source()),
      cast_state.OtherPlayerCastWent(
        address: address(),
        cast_id: source().cast_id,
      ),
    ])
    == []
    as "a connection with no player in the world drops the tells and does not crash"
  // The player leaves the world holding a change it told: its end is carried out first,
  // before the leave's cancelling of the stay's timers, and for the ally's own stay.
  let held =
    cast_state.HeldOnPlayer(
      source: source(),
      address: address(),
      sight: KeptWhenUnseen,
      spell4_id: spell4_id(),
      stack: lasting.Stack(group_id: 387, cap: 1),
      started_ms: 0,
    )
  let leaving =
    world_entry.Entered(
      ..entered(),
      cast: cast_state.State(
        ..entered().cast,
        on_units: dict.from_list([#(source().cast_id, [held])]),
      ),
    )
  let #(_, _, left) =
    connection_effects.world_left(
      session: support.session_in(status: InWorld(
        holder: support.holder(),
        entered: leaving,
      )),
      now: Now(monotonic_ms: 0, filetime: 0),
      entered: leaving,
    )
  let tell = told_to_the_ally(change: PlayerChangeEnds(from:, source: source()))
  let index_of = fn(
    wanted: fn(Effect(step.ConnectionEffect(client_connection.Request))) -> Bool,
  ) {
    list.index_map(left, fn(effect, index) { #(effect, index) })
    |> list.find(fn(entry) { wanted(entry.0) })
    |> result.map(fn(entry) { entry.1 })
  }
  let assert Ok(told_at) = index_of(fn(effect) { effect == tell })
    as "the connection's leaving tells the ally the end of the change it holds, for the ally's stay"
  let assert Ok(cancelled_at) =
    index_of(fn(effect) {
      case effect {
        OwnEffect(step.CancelTimer(..)) -> True
        _ -> False
      }
    })
    as "the leave cancels the stay's timers"
  assert told_at < cancelled_at
    as "the end is carried out before the leave's cancelling of the stay's timers"
  assert list.all(left, fn(effect) {
    case effect {
      OwnEffect(step.Write(..)) -> False
      _ -> True
    }
  })
    as "nothing is written to the caster's client by it"
}
