//// What the map does with the group of each unit's address (`Register`, `Unregister`) and
//// in what order, run as the pure rule it is. Expected values are the part 3c shape of
//// issue 1483: the join registers the joiner's connection under the new address, watches it
//// there, answers `Joined`, then sends the notices; a removal empties the group first.

import connection_rule_support as support
import genesis_prime/map/message.{Joined} as map_message
import genesis_prime/shared/player_change
import genesis_prime/shared/unit_casts.{EndsAt, HeldEffect}
import genesis_prime/shared/unit_properties.{Source}
import genesis_prime/step.{type ServiceStep, OwnEvent, Started, Told, WatchEnded}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/world_map/generation
import genesis_prime/world_map/map
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/list
import gleam/option
import gleam/set
import map_player_support as player_support
import map_spawn_support as spawns
import map_support
import owned_test

fn started() -> map.State {
  let state = map_support.empty(incarnation: 1)
  let #(state, _) = spawns.feed(state:, at_ms: 5000, event: OwnEvent(Started))
  state
}

fn joined_address(
  taken: ServiceStep(map_message.Outgoing),
) -> Result(UnitAddress, Nil) {
  list.find_map(support.replies(taken), fn(reply) {
    case reply.1 {
      Joined(address:, ..) -> Ok(address)
      _ -> Error(Nil)
    }
  })
}

fn watch_of(
  taken: ServiceStep(map_message.Outgoing),
) -> Result(step.WatchId, Nil) {
  list.find_map(support.effects_of(taken), fn(effect) {
    case effect {
      step.Watch(watch:, ..) -> Ok(watch)
      _ -> Error(Nil)
    }
  })
}

/// The kind of each effect of a step, in order.
fn kinds(taken: ServiceStep(map_message.Outgoing)) -> List(String) {
  list.map(support.effects_of(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.Register(
        group: step.Unit(_),
        member: step.Connection(_),
      )) -> "Register"
      step.OwnEffect(step.Register(..)) -> "Register of another kind"
      step.OwnEffect(step.Unregister(..)) -> "Unregister"
      step.Watch(target: step.Unit(_), ..) -> "Watch"
      step.Watch(..) -> "Watch of another kind"
      step.Unwatch(..) -> "Unwatch"
      step.OwnEffect(step.Reply(answer: Joined(..), ..)) -> "Joined"
      step.OwnEffect(step.Reply(answer: map_message.Left, ..)) -> "Left"
      step.OwnEffect(step.Reply(..)) -> "Reply"
      step.OwnEffect(step.Send(to: step.Unit(_), ..)) -> "Send to a unit"
      step.OwnEffect(step.Send(..)) -> "Send"
      step.OwnEffect(step.StartCreature(..))
      | step.OwnEffect(step.StartServiceTimer(..))
      | step.OwnEffect(step.CancelServiceTimer(..)) -> "other"
      step.Log(..) -> "Log"
      step.Stop -> "Stop"
    }
  })
}

pub fn a_join_registers_the_joiner_then_watches_its_address_then_replies_then_sends_the_notices_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    spawns.join(state: started(), at_ms: 6000, connection: 1, x: 0.0)
  let #(_, second) = spawns.join(state:, at_ms: 6100, connection: 2, x: 10.0)
  assert kinds(second)
    == ["Register", "Watch", "Joined", "Send to a unit", "Send to a unit"]
    as "the joiner is registered under its address, then watched there, then answered, then each notice is sent"
  let assert Ok(address) = joined_address(second)
  assert list.take(support.effects_of(second), 1)
    == [
      step.OwnEffect(step.Register(
        group: step.Unit(address),
        member: step.Connection(step.ConnectionId(2)),
      )),
    ]
    as "the group is the unit's address and the member the joiner's connection"
  assert list.map(support.watches(second), fn(watch) { watch.1 })
    == [step.Unit(address)]
    as "the watch is on the unit's address"
}

pub fn a_leave_unregisters_unwatches_and_answers_left_whether_the_unit_was_there_or_not_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    spawns.join(state: started(), at_ms: 6000, connection: 1, x: 0.0)
  let #(state, second) =
    spawns.join(state:, at_ms: 6100, connection: 2, x: 10.0)
  let assert Ok(address) = joined_address(second)
  let #(state, left) = spawns.leave(state:, at_ms: 6200, connection: 2)
  assert list.take(kinds(left), 2) == ["Unregister", "Unwatch"]
    as "the group is emptied, then the watch dropped, before any send"
  assert list.last(kinds(left)) == Ok("Left")
    as "and the leave is answered last"
  assert list.contains(
    support.effects_of(left),
    step.OwnEffect(step.Unregister(group: step.Unit(address))),
  )
    as "the group emptied is the unit's"
  let #(_, again) = spawns.leave(state:, at_ms: 6300, connection: 2)
  assert kinds(again) == ["Log", "Left"]
    as "a leave of a unit that is not there logs one error, empties no group and is answered"
}

pub fn a_joiner_that_ends_before_the_map_registers_it_is_removed_by_the_watch_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, joined) =
    spawns.join(state: started(), at_ms: 6000, connection: 1, x: 0.0)
  let assert Ok(watch) = watch_of(joined)
  let #(state, ended) =
    spawns.feed(state:, at_ms: 6100, event: WatchEnded(watch))
  assert list.take(kinds(ended), 1) == ["Unregister"]
    as "the watch's end removes the unit and empties its group"
  assert !list.contains(kinds(ended), "Unwatch")
    as "no watch is dropped: it has fired"
  let #(_, after) = spawns.move(state:, at_ms: 6200, connection: 1, x: 5.0)
  assert support.logs_of(step: after, level: step.LogError) != []
    as "the unit is gone: a move of it logs an error and changes nothing"
}

pub fn relays_to_the_viewers_of_a_unit_go_in_the_order_of_their_addresses_test() -> Nil {
  use <- owned_test.run(5000)
  // Connections 3, 1 and 2 join in that order: their addresses are numbers 1, 2 and 3 with
  // ranks 3, 1 and 2.
  let state = started()
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 3, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6010, connection: 1, x: 10.0)
  let #(state, _) = spawns.join(state:, at_ms: 6020, connection: 2, x: 20.0)
  let owner = map_support.unit(state:, connection: 3)
  let viewers = [
    map_support.unit(state:, connection: 1),
    map_support.unit(state:, connection: 2),
  ]
  let relaying =
    list.fold(viewers, state, fn(state, viewer) {
      let assert option.Some(map.Relation(generation:, ..)) =
        map.player_relation(state:, owner:, viewer:)
        as "the viewer holds a relation with the owner"
      let #(state, _) =
        spawns.feed(
          state:,
          at_ms: 6100,
          event: OwnEvent(
            Told(
              message: map_message.PlayerSnapshot(
                by: owner,
                viewer:,
                generation:,
                burst: [player_support.appeared(owner: 1, generation:)],
              ),
            ),
          ),
        )
      state
    })
  let #(_, taken) =
    spawns.feed(
      state: relaying,
      at_ms: 6200,
      event: OwnEvent(
        Told(message: map_message.PlayerBroadcast(
          from: owner,
          news: player_support.health(connection: 1, health: 7),
        )),
      ),
    )
  let to =
    list.filter_map(support.effects_of(taken), fn(effect) {
      case effect {
        step.OwnEffect(step.Send(to: step.Unit(address), ..)) -> Ok(address)
        _ -> Error(Nil)
      }
    })
  assert to == unit_address.sorted(set.from_list(viewers))
    as "the relays go to the viewers in the order of their addresses"
  assert list.map(to, unit_address.rank) == [1, 2]
    as "an order that is the connections' order, as the creatures' ties are"
}

pub fn a_rejoined_player_has_its_relation_under_its_new_address_and_none_under_its_old_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    spawns.join(state: started(), at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6010, connection: 2, x: 10.0)
  let old_viewer = map_support.unit(state:, connection: 2)
  let owner = map_support.unit(state:, connection: 1)
  assert map.player_relation(state:, owner:, viewer: old_viewer) != option.None
    as "guard: the pair holds a relation under the first addresses"
  let #(state, _) = spawns.leave(state:, at_ms: 6100, connection: 2)
  let #(state, _) = spawns.join(state:, at_ms: 6110, connection: 2, x: 10.0)
  let new_viewer = map_support.unit(state:, connection: 2)
  assert new_viewer != old_viewer as "the second join is a new address"
  assert map.player_relation(state:, owner:, viewer: new_viewer) != option.None
    as "the relation is held under the viewer's new address"
  assert map.player_relation(state:, owner:, viewer: old_viewer) == option.None
    as "and none under its old address"
}

pub fn a_relay_after_a_rejoin_goes_to_the_new_address_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    spawns.join(state: started(), at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6010, connection: 2, x: 10.0)
  let old_viewer = map_support.unit(state:, connection: 2)
  let #(state, _) = spawns.leave(state:, at_ms: 6100, connection: 2)
  let #(state, _) = spawns.join(state:, at_ms: 6110, connection: 2, x: 10.0)
  let new_viewer = map_support.unit(state:, connection: 2)
  let owner = map_support.unit(state:, connection: 1)
  let assert option.Some(map.Relation(generation:, ..)) =
    map.player_relation(state:, owner:, viewer: new_viewer)
    as "the pair holds a relation after the rejoin"
  let #(_, taken) =
    spawns.feed(
      state:,
      at_ms: 6200,
      event: OwnEvent(
        Told(
          message: map_message.PlayerSnapshot(
            by: owner,
            viewer: new_viewer,
            generation:,
            burst: [player_support.appeared(owner: 1, generation:)],
          ),
        ),
      ),
    )
  let to =
    list.filter_map(support.effects_of(taken), fn(effect) {
      case effect {
        step.OwnEffect(step.Send(to: step.Unit(address), ..)) -> Ok(address)
        _ -> Error(Nil)
      }
    })
  assert to == [new_viewer]
    as "the snapshot is relayed to the viewer's new address"
  let #(_, stale) =
    spawns.feed(
      state:,
      at_ms: 6300,
      event: OwnEvent(
        Told(
          message: map_message.PlayerSnapshot(
            by: owner,
            viewer: old_viewer,
            generation:,
            burst: [player_support.appeared(owner: 1, generation:)],
          ),
        ),
      ),
    )
  assert support.sends(stale) == []
    as "and a snapshot for its old address is relayed to no one"
}

pub fn a_player_tell_from_an_address_not_in_the_map_changes_nothing_for_each_kind_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    spawns.join(state: started(), at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6010, connection: 2, x: 10.0)
  let stranger = map_support.address_for(incarnation: 1, number: 99, rank: 9)
  let place = spawns.at(50.0)
  let rows = [
    #("Moved", map_message.Moved(unit: stranger, place:, seq: 1)),
    #("Ready", map_message.Ready(unit: stranger, seq: 1)),
    #(
      "StealthChanged",
      map_message.StealthChanged(unit: stranger, stealthed: True),
    ),
    #("LifeChanged", map_message.LifeChanged(unit: stranger, alive: False)),
    #(
      "VisibilityChanged",
      map_message.VisibilityChanged(unit: stranger, hidden: set.new()),
    ),
    #(
      "PlayerSnapshot",
      map_message.PlayerSnapshot(
        by: stranger,
        viewer: map_support.unit(state:, connection: 2),
        generation: generation.first(),
        burst: [
          player_support.appeared(owner: 1, generation: generation.first()),
        ],
      ),
    ),
    #(
      "PlayerBroadcast",
      map_message.PlayerBroadcast(
        from: stranger,
        news: player_support.health(connection: 1, health: 3),
      ),
    ),
    #(
      "TellLanding",
      map_message.TellLanding(
        from: stranger,
        to: map_support.unit(state:, connection: 2),
        landing: map_message.ChangeStart(
          change: player_change.PlayerChangeStarts(
            from: stranger,
            source: Source(cast_id: 5, effect_id: Spell4EffectsId(62_024)),
            change: player_change.Applies(player_change.Absorb(
              amount: 5,
              mask: 7,
            )),
            sight: player_change.EndsWhenUnseen,
            spell4_id: Spell4Id(1),
            effect: HeldEffect(
              effect_id: Spell4EffectsId(62_024),
              starts_ms: 1000,
              ends: EndsAt(ms: 11_000),
            ),
          ),
        ),
      ),
    ),
    #(
      "Say",
      map_message.Say(
        from: stranger,
        said: player_support.said_by(connection: 1, text: "Hi"),
      ),
    ),
  ]
  list.each(rows, fn(row) {
    let #(kind, message) = row
    let #(after, taken) =
      spawns.feed(state:, at_ms: 6100, event: OwnEvent(Told(message:)))
    assert after == state as { kind <> ": the map is as it was" }
    assert support.sends(taken) == [] as { kind <> ": nothing is sent" }
  })
  let #(after, taken) =
    spawns.feed(
      state:,
      at_ms: 6100,
      event: OwnEvent(step.Asked(
        caller: step.CallerId(5),
        message: map_message.Summon(
          unit: stranger,
          creature_id: id.Creature2Id(73_464),
          level: option.None,
        ),
      )),
    )
  assert after == state as "Summon: the map is as it was"
  assert support.replies(taken)
    == [#(step.CallerId(5), map_message.NotSummoned(map_message.NoPlayerHere))]
    as "Summon: refused, the player is not here"
}
