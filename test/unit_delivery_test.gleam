//// How a map's send to a unit becomes the message its host takes, and how the host's fence
//// treats a message for an earlier address (`genesis_prime/server.map_message`,
//// `genesis_prime/game/connection` `unit_sent`). Expected values are the part 3c shape of
//// issue 1483: a message names the address it was sent to, and a connection takes only
//// a message for its player's own address.

import connection_rule_support as rule_support
import game_connection_support as support
import genesis_prime/client_connection.{
  ForUnit, FromMap, SentByFoe, SentByKill, SentByLine, SentByMap, SentByMove,
  SentByPeer,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/map/message.{Left} as map_message
import genesis_prime/server
import genesis_prime/shared/chat_channel
import genesis_prime/shared/chat_tell
import genesis_prime/shared/effect_kind
import genesis_prime/shared/kill_credit.{Credit}
import genesis_prime/shared/strike_tell
import genesis_prime/shared/unit_news.{Appeared, PeerNews, Removed}
import genesis_prime/step.{EndedBeforeAnswer, NotRunning, OwnEvent, Woken}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, Creature2Id, Faction2Id}
import genesis_prime/world_map/generation
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/list
import gleam/result
import map_player_support as players
import map_support
import owned_test

/// One kind of what a map sends to a unit, with the message the host takes it as for an
/// address.
fn kinds() -> List(#(String, map_message.Outgoing)) {
  let key =
    strike_tell.Key(
      cast_id: 1,
      occasion: strike_tell.AtGo(phase: 0),
      unit_id: 5,
    )
  [
    #("a notice", map_message.Noticed(notice: map_message.Gone(unit_id: 9))),
    #(
      "news",
      map_message.Relayed(
        delivered: map_message.News(news: PeerNews(unit_id: 9, news: Removed)),
      ),
    ),
    #(
      "a fight tell",
      map_message.Relayed(
        delivered: map_message.Tell(
          payload: map_message.Fight(told: strike_tell.Released(unit_id: 9)),
        ),
      ),
    ),
    #(
      "an answer",
      map_message.Relayed(
        delivered: map_message.Tell(
          payload: map_message.Struck(answered: strike_tell.Answered(
            key:,
            outcome: strike_tell.Deflected(gates_passed: []),
          )),
        ),
      ),
    ),
    #(
      "a kill credit",
      map_message.Relayed(
        delivered: map_message.Tell(
          payload: map_message.KillCredit(credit: Credit(
            unit_id: 9,
            creature_id: Creature2Id(1),
            faction_id: Faction2Id(0),
            level: 1,
          )),
        ),
      ),
    ),
    #(
      "a landing",
      map_message.Relayed(
        delivered: map_message.Landed(landing: players.answer(
          cast_id: 5,
          unit_id: 2,
        )),
      ),
    ),
    #(
      "a chat line",
      map_message.Relayed(
        delivered: map_message.Said(said: players.said_by(
          connection: 1,
          text: "Hi",
        )),
      ),
    ),
  ]
}

/// The address a message was sent to, as the host's message names it.
fn named(message: client_connection.Message) -> Result(UnitAddress, Nil) {
  case message {
    ForUnit(address:, ..) -> Ok(address)
    _ -> Error(Nil)
  }
}

pub fn a_delivered_message_names_the_address_it_was_sent_to_for_each_kind_test() -> Nil {
  use <- owned_test.run(5000)
  let first = map_support.address(number: 1)
  let second = map_support.address(number: 2)
  list.each(kinds(), fn(row) {
    let #(kind, outgoing) = row
    // A process that is a member of two groups: each message names its own `to`.
    assert server.map_message(to: step.Unit(first), outgoing:)
      |> result.try(named)
      == Ok(first)
      as { kind <> ": sent to the first address, the message names it" }
    assert server.map_message(to: step.Unit(second), outgoing:)
      |> result.try(named)
      == Ok(second)
      as { kind <> ": sent to the second address, the message names that one" }
    assert server.map_message(
        to: step.Connection(step.ConnectionId(1)),
        outgoing:,
      )
      == Error(Nil)
      as { kind <> ": a send to a connection is no unit's message" }
  })
}

/// What a message of each kind of what a connection is sent (`StaySent`) does at a connection
/// whose player is a Medic in its second unit, `key` its open cast on the Beast 40: each is one
/// the player would take, with a state or effect to show for it.
fn sent_of_each_kind(
  key key: strike_tell.Key,
) -> List(#(String, client_connection.StaySent)) {
  let assert OwnEvent(Woken(ForUnit(sent: answered, ..))) = support.landed(key:)
    as "an answer is a creature's message for a unit"
  [
    #(
      "a notice",
      SentByMap(map_message.SeenBy(
        by: map_support.address(number: 3),
        unit_id: support.viewer_unit_id(3),
        generation: support.viewer_sight(3),
      )),
    ),
    #(
      "news",
      SentByPeer(PeerNews(
        unit_id: 9,
        news: Appeared(
          unit: support.another_unit(),
          generation: generation.first(),
        ),
      )),
    ),
    #(
      "a move",
      SentByMove(support.moving(
        unit_id: 9,
        generation: generation.first(),
        server_time_ms: 1,
        commands: support.moved_unit_commands(),
      )),
    ),
    #(
      "a line",
      SentByLine(chat_tell.Said(
        speaker: chat_tell.Speaker(
          realm_id: 1,
          character_id: 7,
          name: "Zed Other",
          faction_id: 167,
          unit_id: 9,
          map: support.camp_map(),
          incarnation: support.incarnation,
        ),
        line: chat_tell.Line(
          channel_type: chat_channel.Say,
          channel_id: 0,
          text: [0x48, 0x69],
          formats: [],
        ),
      )),
    ),
    #("a foe", SentByFoe(strike_tell.Threatened(unit_id: 7, life: 3))),
    #("an answer", answered),
    #(
      "a kill",
      SentByKill(Credit(
        unit_id: 9,
        creature_id: Creature2Id(73_464),
        faction_id: Faction2Id(0),
        level: 1,
      )),
    ),
    #(
      "a player's tell",
      support.a_player_strike(from: 3, cast_id: 100, outgoing: 1.0, heals: [
        #(effect_kind.Health, 40),
      ]),
    ),
  ]
}

/// The Medic after a camp and its entry again, in its second unit, with a cast pressed on
/// the Beast 40 (its key), and the state of its camp, in character select.
fn medic_after_a_camp() -> #(
  game_connection.State,
  game_connection.State,
  strike_tell.Key,
) {
  let medic = Character(..support.world_character(), class_id: ClassId(4))
  let #(first, _) =
    support.feed(support.medic_in_world(), support.beast_appears(unit_id: 40))
  let camped = support.camp_from(first)
  let #(again, _) = support.entered_again_from(camped, medic)
  let #(again, _) =
    support.feed(
      again,
      support.in_second_unit(support.beast_appears(unit_id: 40)),
    )
  let #(again, pressed) =
    support.press_paralytic_surge(state: again, client_cast_id: 1)
  let assert [#(40, key)] = support.strikes_told(pressed)
    as "the cast on the Beast tells its strike"
  #(camped, again, key)
}

pub fn a_message_for_an_earlier_address_reaches_no_unit_for_each_kind_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(camped, again, key) = medic_after_a_camp()
  let kinds = sent_of_each_kind(key:)
  // In the world after `Joined`: each kind sent to the earlier address leaves the
  // connection as it was, and the same kind sent to its present address does not.
  list.each(kinds, fn(row) {
    let #(kind, sent) = row
    let #(own_state, own) =
      support.feed(again, support.for_unit(support.own_address_again(), sent))
    assert own_state != again || rule_support.effects_of(own) != []
      as {
        kind <> ": control: sent to the present address it changes something"
      }
    let #(after, taken) =
      support.feed(again, support.for_unit(support.own_address(), sent))
    assert rule_support.effects_of(taken) == [] && after == again
      as {
        kind
        <> ": sent to the earlier address, nothing is sent and nothing changes"
      }
  })
  // In character select after a camp, or after the leave was answered by a map that had
  // ended: the player is in no unit, and nothing is held for the unit that comes.
  list.each(
    [step.Answer(FromMap(Left)), NotRunning, EndedBeforeAnswer],
    fn(outcome) {
      let #(selecting, _) = case outcome {
        step.Answer(_) -> #(camped, Nil)
        _ -> {
          let #(state, taken) = support.leaving_the_map()
          #(support.answer(state:, taken:, outcome:).0, Nil)
        }
      }
      list.each(kinds, fn(row) {
        let #(kind, sent) = row
        let #(after, taken) =
          support.feed(selecting, support.for_unit(support.own_address(), sent))
        assert rule_support.effects_of(taken) == [] && after == selecting
          as {
            kind
            <> ": in character select, a message for the unit before is dropped and held for none"
          }
      })
    },
  )
  // While the join after the camp waits for the map, the connection has no address: each
  // kind sent to the earlier one is dropped (the shell keeps a delivery behind the ask and
  // sends it again after the answer, where the first block's fence takes it), and the answer
  // is as it is with no message.
  let #(waiting, joining) =
    support.joining_from(
      support.camp_from(support.medic_in_world()),
      support.world_character(),
    )
  let answer_of =
    support.mapped(map_state: support.map_after_a_stay(), taken: joining).1
  let #(_, baseline) =
    support.answer(
      state: waiting,
      taken: joining,
      outcome: step.Answer(FromMap(answer_of)),
    )
  list.each(kinds, fn(row) {
    let #(kind, sent) = row
    let #(held, taken) =
      support.feed(waiting, support.for_unit(support.own_address(), sent))
    assert rule_support.effects_of(taken) == []
      as { kind <> ": while the join waits, nothing is sent, written or held" }
    let #(_, taken) =
      support.answer(
        state: held,
        taken: joining,
        outcome: step.Answer(FromMap(answer_of)),
      )
    assert rule_support.effects_of(taken) == rule_support.effects_of(baseline)
      as {
        kind
        <> ": sent for the earlier address while the join waited, it changes nothing the answer does"
      }
  })
  let #(entered, _) =
    support.answer(
      state: waiting,
      taken: joining,
      outcome: step.Answer(FromMap(answer_of)),
    )
  let #(_, taken) =
    support.feed(
      entered,
      support.in_second_unit(support.event_of(support.Appears)),
    )
  assert support.written_ids(taken) == [0x0262]
    as "control: a message for the address Joined gave is taken"
}

pub fn a_connection_takes_its_address_from_joined_and_holds_none_while_it_waits_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(waiting, joining) = support.joining()
  let answer = support.map_answer(joining)
  let entered_with = fn(event) {
    let #(held, taken) = support.feed(waiting, event)
    assert rule_support.effects_of(taken) == []
      as "while the join waits, a message is held and nothing is written or asked"
    let #(_, taken) =
      support.answer(
        state: held,
        taken: joining,
        outcome: step.Answer(client_connection.FromMap(answer)),
      )
    support.written_ids(taken)
  }
  let #(_, baseline) =
    support.answer(
      state: waiting,
      taken: joining,
      outcome: step.Answer(client_connection.FromMap(answer)),
    )
  let for_another_address =
    entered_with(support.for_unit(
      support.viewer_address(3),
      SentByPeer(PeerNews(unit_id: 9, news: Removed)),
    ))
  let for_the_earlier_address =
    entered_with(support.in_unit(
      count: 2,
      event: support.event_of(support.Appears),
    ))
  assert for_another_address == support.written_ids(baseline)
    as "a message held for an address Joined did not give is dropped after the answer: nothing is written beyond the burst"
  assert for_the_earlier_address == support.written_ids(baseline)
    as "a message held for an earlier address of the connection is dropped the same way"
}
