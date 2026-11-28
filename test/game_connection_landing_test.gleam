//// What the game connection does with a heal another player's connection tells it
//// (`genesis_prime/game/connection/landing`), as the connection's rule takes it with no
//// socket. Expected values come from these places.
//// - A level 1 Engineer has 736 health and 450 shield; the Beast's 12 Physical strike
////   leaves 448 and 735 (`game_connection_held_map_test`, `game_connection_fight_test`).
//// - A heal moves the vitals by its split and the server tells them as 0x938 (stat 20, the
////   shield) and 0x92F (the health) to the player's client and as the Shield and Health
////   news to its viewers (`Spell4Effects.effectType.10`, `.118`: the client never changes
////   a vital on a heal result).
//// - The splits are worked by hand from `heal_parts.Split`'s definition: the shield row of
////   10 has room for 2 (overheal 8), the health row of 40 has room for 1 (overheal 39).
//// - Effect ids are Mind Over Body's heal rows (Spell4Effects 62019 on); the target echoes
////   them and reads none.
//// - The answer is told to the caster's connection for the caster's stay, with the strike's
////   key, before the player's own news.

import connection_rule_support as rule_support
import game_connection_support as support
import genesis_prime/client_connection.{type Request}
import genesis_prime/map/message as map_message
import genesis_prime/message/player_health.{type PlayerHealth, PlayerHealth}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{type UnitStatChanged}
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/shared/effect_kind
import genesis_prime/shared/heal_parts.{Split}
import genesis_prime/shared/strike_tell.{
  HealLanded, HealsLanded, Key, PlayerAnswered,
}
import genesis_prime/shared/unit_news
import genesis_prime/step.{type ConnectionStep, ConnectionId}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/list
import owned_test
import strike_support

/// The 0x938 shield stats the step writes to the player's own client, in order.
fn shields_written(taken taken: ConnectionStep(Request)) -> List(Int) {
  list.filter_map(
    support.decoded(
      support.heard(taken, support.keyed()),
      0x0938,
      unit_stat_changed.decode,
    ),
    fn(message: UnitStatChanged) {
      assert message.unit_id == support.own_unit_id
        as "the message names the player's own unit (opcode.0x938)"
      case message.change {
        unit_stat_change.Shield(UnitStatShield(value:)) -> Ok(value)
        unit_stat_change.Absorption(..)
        | unit_stat_change.InterruptArmor(..)
        | unit_stat_change.Level(..) -> Error(Nil)
      }
    },
  )
}

/// The 0x92F healths the step writes to the player's own client, in order.
fn healths_written(taken taken: ConnectionStep(Request)) -> List(PlayerHealth) {
  support.decoded(
    support.heard(taken, support.keyed()),
    0x092F,
    player_health.decode,
  )
}

pub fn a_heal_told_by_another_player_raises_the_targets_health_and_is_answered_to_the_caster_for_its_stay_before_the_news_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    support.feed(
      state: support.watched_by(support.in_world(), [2]),
      event: support.a_beast_strike(support.own_unit_id),
    )
  let #(state, taken) =
    support.feed(
      state:,
      event: support.for_stay(
        stay: support.own_stay(),
        sent: support.a_player_strike(
          from: 3,
          stay: support.viewer_stay(3),
          cast_id: 100,
          outgoing: 1.0,
          heals: [#(effect_kind.Shield, 10), #(effect_kind.Health, 40)],
        ),
      ),
    )
  assert support.written_ids(taken) == [0x0938, 0x092F]
    as "the shield's 0x938 then the health's 0x92F, and no frame of a cast: the go is the caster's"
  assert shields_written(taken:) == [450]
    as "448 and 2, to the shield's maximum"
  assert healths_written(taken:)
    == [
      PlayerHealth(unit_id: support.own_unit_id, health: 736, reason_mask: 0),
    ]
    as "735 and 1, to the health's maximum"
  assert support.news_broadcast(taken)
    == [
      unit_news.Shield(shield: 450),
      unit_news.Health(health: 736, dead: False),
    ]
    as "the viewer is told the Shield and the Health news"
  let answered =
    PlayerAnswered(
      key: Key(
        cast_id: 100,
        occasion: strike_tell.AtGo(phase: 0),
        unit_id: support.own_unit_id,
      ),
      outcome: HealsLanded(heals: [
        HealLanded(
          effect_id: Spell4EffectsId(62_019),
          vital: effect_kind.Shield,
          split: Split(amount: 10, shield: 2, health: 0, overheal: 8),
        ),
        HealLanded(
          effect_id: Spell4EffectsId(62_020),
          vital: effect_kind.Health,
          split: Split(amount: 40, shield: 0, health: 1, overheal: 39),
        ),
      ]),
    )
  assert support.player_answers(taken)
    == [#(3, support.viewer_stay(3), answered)]
    as "one answer, to the caster's connection for the caster's stay, with the key unchanged and each row's split"
  assert list.first(rule_support.effects_of(taken))
    == Ok(
      support.map_tell(client_connection.TellLanding(
        connection: ConnectionId(1),
        stay: support.own_stay(),
        to: ConnectionId(3),
        to_stay: support.viewer_stay(3),
        landing: map_message.HealAnswer(answered:),
      )),
    )
    as "the answer is the first effect, before the player's own news, as a creature's is"
  // A second caster's strike finds the life the first left: the state holds 450 and 736.
  let #(_, second) =
    support.feed(
      state:,
      event: support.for_stay(
        stay: support.own_stay(),
        sent: support.a_player_strike(
          from: 4,
          stay: support.viewer_stay(4),
          cast_id: 101,
          outgoing: 1.0,
          heals: [#(effect_kind.Health, 40)],
        ),
      ),
    )
  assert support.written_ids(second) == []
    as "the player is full: nothing is written"
  assert support.player_answers(second)
    == [
      #(
        4,
        support.viewer_stay(4),
        PlayerAnswered(
          key: Key(
            cast_id: 101,
            occasion: strike_tell.AtGo(phase: 0),
            unit_id: support.own_unit_id,
          ),
          outcome: HealsLanded(heals: [
            HealLanded(
              effect_id: Spell4EffectsId(62_019),
              vital: effect_kind.Health,
              split: Split(amount: 40, shield: 0, health: 0, overheal: 40),
            ),
          ]),
        ),
      ),
    ]
    as "the second strike heals nothing on the life the first left, and is answered to its own caster for its own stay"
  // A strike keyed by a tick of a periodic row is applied and answered as a go's: the rule
  // reads nothing of the occasion, so the answer echoes the tick's key.
  let tick_key =
    Key(
      cast_id: 102,
      occasion: strike_tell.AtTick(
        effect_id: Spell4EffectsId(80_077),
        go: 1,
        tick: 3,
      ),
      unit_id: support.own_unit_id,
    )
  let #(hurt, _) =
    support.feed(
      state: support.watched_by(support.in_world(), [2]),
      event: support.a_beast_strike(support.own_unit_id),
    )
  let #(_, ticked) =
    support.feed(
      state: hurt,
      event: support.for_stay(
        stay: support.own_stay(),
        sent: client_connection.SentByPlayer(tell: client_connection.Strike(
          strike: strike_tell.PlayerStrike(
            ..strike_support.heal_strike(
              from: ConnectionId(5),
              stay: support.viewer_stay(5),
              cast_id: 102,
              unit_id: support.own_unit_id,
              outgoing: 1.0,
              heals: [],
            ),
            key: tick_key,
            heals: [
              strike_tell.HealTell(
                effect_id: Spell4EffectsId(80_077),
                vital: effect_kind.Health,
                amount: 40,
              ),
            ],
          ),
        )),
      ),
    )
  assert support.player_answers(ticked)
    == [
      #(
        5,
        support.viewer_stay(5),
        PlayerAnswered(
          key: tick_key,
          outcome: HealsLanded(heals: [
            HealLanded(
              effect_id: Spell4EffectsId(80_077),
              vital: effect_kind.Health,
              split: Split(amount: 40, shield: 0, health: 1, overheal: 39),
            ),
          ]),
        ),
      ),
    ]
    as "a heal told for a tick is applied (the Beast's strike leaves the health at 735 of 736: room for 1, overheal 39, as the header works the 40) and answered to its caster under the tick's own key"
}
