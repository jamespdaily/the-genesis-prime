//// How a map's send to a unit becomes the message its host takes, and how the host's fence
//// treats a message for an earlier address (`genesis_prime/server.map_message`,
//// `genesis_prime/game/connection` `unit_sent`). Expected values are the part 3c shape of
//// issue 1483: a message names the address it was sent to, and a connection takes only
//// a message for its player's own address.

import connection_rule_support as rule_support
import game_connection_support as support
import genesis_prime/client_connection.{
  ForUnit, SentByFoe, SentByKill, SentByLine, SentByMap, SentByMove, SentByPeer,
  SentByPlayer, SentByTarget,
}
import genesis_prime/map/message as map_message
import genesis_prime/server
import genesis_prime/shared/chat_tell
import genesis_prime/shared/kill_credit.{Credit}
import genesis_prime/shared/strike_tell
import genesis_prime/shared/unit_news.{PeerNews, Removed}
import genesis_prime/step
import genesis_prime/table/id.{Creature2Id, Faction2Id}
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

/// The messages a connection takes for its player, one of each kind of what it is sent
/// (`StaySent`), for the address `address`.
fn sent_to(address) -> List(#(String, client_connection.Message)) {
  let kinds = [
    #("a notice", SentByMap(map_message.Gone(unit_id: 9))),
    #("news", SentByPeer(PeerNews(unit_id: 9, news: Removed))),
    #(
      "a move",
      SentByMove(support.moved_for(viewer: 2, server_time_ms: 1, commands: [])),
    ),
    #(
      "a line",
      SentByLine(chat_tell.Said(
        speaker: players.said_by(connection: 1, text: "Hi").speaker,
        line: players.said_by(connection: 1, text: "Hi").line,
      )),
    ),
    #("a foe", SentByFoe(strike_tell.Released(unit_id: 9))),
    #(
      "an answer",
      SentByTarget(strike_tell.Answered(
        key: strike_tell.Key(
          cast_id: 1,
          occasion: strike_tell.AtGo(phase: 0),
          unit_id: 5,
        ),
        outcome: strike_tell.Deflected(gates_passed: []),
      )),
    ),
    #(
      "a kill",
      SentByKill(Credit(
        unit_id: 9,
        creature_id: Creature2Id(1),
        faction_id: Faction2Id(0),
        level: 1,
      )),
    ),
    #(
      "a player's tell",
      SentByPlayer(
        client_connection.Answer(answered: strike_tell.PlayerAnswered(
          key: strike_tell.Key(
            cast_id: 1,
            occasion: strike_tell.AtGo(phase: 0),
            unit_id: 5,
          ),
          outcome: strike_tell.PlayerDead,
        )),
      ),
    ),
  ]
  list.map(kinds, fn(kind) { #(kind.0, ForUnit(address:, sent: kind.1)) })
}

pub fn a_message_for_an_earlier_address_reaches_no_unit_for_each_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  // After a camp and a new entry the player's address is the next one; every kind sent to
  // the earlier address finds the fence, in the world and while the join waits.
  let #(camped, _) = support.camped_out()
  let #(again, _) =
    support.entered_again_from(camped, support.world_character())
  list.each(sent_to(support.own_address()), fn(row) {
    let #(kind, message) = row
    let #(_, taken) = support.feed(again, step.OwnEvent(step.Woken(message)))
    assert rule_support.effects_of(taken) == []
      as {
        kind
        <> ": a message for the earlier address sends, asks and tells nothing"
      }
  })
  let #(_, taken) =
    support.feed(
      again,
      support.in_second_unit(support.event_of(support.Appears)),
    )
  assert support.written_ids(taken) == [0x0262]
    as "control: the same news sent to the present address is taken and written"
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
