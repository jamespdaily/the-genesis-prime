//// What another player's cast lands on this connection's player: the heal rows a
//// caster's connection told it (genesis_prime/game/strike_tell `PlayerStrike`), applied to
//// its own life and answered, and the changes a caster's cast holds on it
//// (genesis_prime/game/held_changes), applied as the player's own cast's change of that
//// kind is and held per caster until one of the ends below.
////
//// ```
//// caster's connection C                        this connection T (the healed player)
////   Tell(Connection(T), TellPlayerStrike(stay_T, PlayerStrike(key, C, stay_C, outgoing, heals)))
////                      ─▶ ForStay(stay_T, SentByStriker(strike))   (the stay fence; held through an ask)
////                      ─▶ player_life.heals_taken: each row in order on the life the one before left
////   ForStay(stay_C, SentByHealed(PlayerAnswered(key, HealsLanded(splits) | PlayerDead)))
////                      ◀─ Tell(Connection(C), TellPlayerAnswer(stay_C, answered)), then T's own news
//// ```
////
//// - **The answer is told before T's own news**, in the order a creature answers a strike
////   (genesis_prime/game/strike). C holds the healed unit's news while its place in a
////   round waits, so the order decides nothing C's client sees.
//// - **A heal reads the healer's outgoing multiplier from the tell** and T's own incoming
////   multiplier and heal-to-shield conversion (genesis_prime/game/heal_split).
//// - **Nothing here reads the caster**, its sight or the time: a strike arrives for T's
////   stay or is dropped by the stay fence, and is applied when it is taken.
////
//// ```
//// caster's connection C                        this connection T (the ally)
////   Tell(Connection(T), TellPlayerChange(stay_T, PlayerChangeStarts(C, stay_C, source, change, sight)))
////                      ─▶ ForStay(stay_T, SentByCaster(..))   (the stay fence; held through an ask)
////                      ─▶ changed: the change through the function the player's own cast uses
////                         (properties.started, absorption.started), held for C
////   Tell(Connection(T), TellPlayerChange(stay_T, PlayerChangeEnds(C, source)))
////                      ─▶ changed: the source taken off, when C holds it
////   the map's UnseenBy(C) ─▶ caster_unseen: C's sources with `EndsWhenUnseen` taken off
////   the map's Gone(C's unit) ─▶ caster_removed: every source of that unit taken off
////   T dies                ─▶ ended_at_death: every source T holds taken off
//// ```
////
//// - **A change is taken only from a caster T sees**: C is among T's viewers with the stay
////   the tell names, and T is alive. The caster addresses a tell from the players in its
////   own sight, and sight is symmetric, so after T lost sight of C no end tell can reach T
////   (`UnseenBy` is that end).
//// - **A source of a spell with propertyFlags 0x100 survives `UnseenBy`** and ends by the
////   caster's end tell or the caster's unit gone: the client's removal of the caster's unit
////   keeps the casts that flag marks (fact `cast.target_node_end`).
//// - **A source told again goes to the player's own function again**: an absorb pool is
////   refilled, a property modifier already held changes nothing
////   (genesis_prime/game/unit_properties `apply`).
//// - **A held change ends at its holder's death**, as the player's own casts' changes do
////   (`cast.died`); the client has no path that ends a buff on a unit's death, so the
////   death is the server's choice.
////
//// Gaps for the coverage measure: `gaps()`.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/game/connection/absorption as connection_absorption
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/look as connection_look
import genesis_prime/game/connection/properties as connection_properties
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/held_changes
import genesis_prime/game/player_life
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/gap
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, OwnEffect,
}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

/// The heal rows of `strike` applied to the player `entered`, and the answer told to
/// the caster's connection for the stay the strike names, before the player's own news.
pub fn struck(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  strike strike: strike_tell.PlayerStrike,
) -> client_connection.Handled(Session) {
  let #(life, outcome, effects) =
    player_life.heals_taken(
      life: entered.life,
      properties: entered.properties,
      strike:,
    )
  let #(session, news) =
    life_effect.life_changed(session:, now:, change: fn(_) { #(life, effects) })
  let answer: Effect(ConnectionEffect(Request)) =
    OwnEffect(step.Tell(
      to: step.Connection(connection: strike.from),
      request: client_connection.TellPlayerAnswer(
        stay: strike.stay,
        answered: strike_tell.PlayerAnswered(key: strike.key, outcome:),
      ),
    ))
  Continue(session, [answer, ..news])
}

/// The change `change` of `source` put on the player, as the player's own cast's change of
/// that kind is: a property modifier by the properties' function, an absorb pool by the
/// life's.
pub fn started(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
  change change: held_changes.Change,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case change {
    held_changes.Property(modifier:) ->
      connection_properties.started(session:, now:, source:, modifier:)
    held_changes.Absorb(amount:, mask:) ->
      connection_absorption.started(session:, now:, source:, amount:, mask:)
  }
}

/// What `source` held on the player is taken off: its property modifier, its disguise and
/// its absorb pool, each by the function the player's own cast's end uses, which ignores
/// a source it does not hold.
pub fn ended(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(session, properties) =
    connection_properties.ended(session:, now:, source:)
  let #(session, look) = connection_look.ended(session:, source:)
  let #(session, absorption) =
    connection_absorption.ended(session:, now:, source:)
  #(session, list.flatten([properties, look, absorption]))
}

/// What a caster's connection told the player (`TellPlayerChange`). A start is taken
/// only while the player is alive and the caster is one of its viewers with the stay the
/// tell names; it is applied (`started`) and held for the caster. An end is taken only
/// from the caster that holds the source.
pub fn changed(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  change change: held_changes.PlayerChange,
) -> client_connection.Handled(Session) {
  case change {
    held_changes.PlayerChangeStarts(from:, from_stay:, source:, change:, sight:) ->
      case
        player_life.state(life: entered.life),
        dict.get(entered.viewers, from)
      {
        player_life.Alive, Ok(viewer) if viewer.stay == from_stay -> {
          let #(session, effects) = started(session:, now:, source:, change:)
          let session =
            connection_state.with_entered(session:, change: fn(entered) {
              let #(held, _) =
                held_changes.started(
                  held: entered.held,
                  by: from,
                  unit_id: viewer.unit_id,
                  source:,
                  sight:,
                )
              world_entry.Entered(..entered, held:)
            })
          Continue(session, effects)
        }
        player_life.Alive, Ok(_)
        | player_life.Alive, Error(Nil)
        | player_life.Dead, _
        -> Continue(session, [])
      }
    held_changes.PlayerChangeEnds(from:, source:) ->
      case held_changes.released(held: entered.held, source:) {
        Ok(#(held, by)) if by == from -> {
          let session =
            connection_state.with_entered(session:, change: fn(entered) {
              world_entry.Entered(..entered, held:)
            })
          let #(session, effects) = ended(session:, now:, source:)
          Continue(session, effects)
        }
        Ok(_) | Error(Nil) -> Continue(session, [])
      }
  }
}

/// The caster of connection `by` is no longer one of the player's viewers: each source of
/// `by` that ends with its caster's sight is taken off, in the order they started; a
/// source of a spell that outlives sight stays.
pub fn caster_unseen(
  session session: Session,
  now now: Now,
  by by: step.ConnectionId,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  released_ended(session:, now:, release: held_changes.released_unseen(
    held: _,
    by:,
  ))
}

/// The unit `unit_id` is gone (the map's `Gone`): each source whose caster it is is taken
/// off, in the order they started, whether or not its spell outlives sight.
pub fn caster_removed(
  session session: Session,
  now now: Now,
  unit_id unit_id: Int,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  released_ended(session:, now:, release: held_changes.released_with_unit(
    held: _,
    unit_id:,
  ))
}

/// The player has died: every source it holds from other players is taken off, in the
/// order they started.
pub fn ended_at_death(
  session session: Session,
  now now: Now,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  released_ended(session:, now:, release: fn(held) {
    #(held_changes.new(), held_changes.all(held:))
  })
}

fn released_ended(
  session session: Session,
  now now: Now,
  release release: fn(held_changes.Held) ->
    #(held_changes.Held, List(unit_properties.Source)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let #(held, sources) = release(entered.held)
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, held:)
        })
      list.fold(sources, #(session, []), fn(so_far, source) {
        let #(session, done) = so_far
        let #(session, more) = ended(session:, now:, source:)
        #(session, list.append(done, more))
      })
    }
  }
}

/// What a change or a heal told by another player does not do that the player's own does.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Casting",
      missing: "A heal told to a player raises neither the healer's LandsHeal nor the healed player's ReceivesHeal event, because the tell carries no spell identity. The client's tables hold such procs in the spells of three abilities (23414, 25595 and 47091: 21 ReceivesHeal rows in their Proxy children) and 38 proc rows in 37 spells that an AMP, an item on equip, an item on activate (70104 and 211223) or a set bonus gives; the server starts no AMP, on-equip or set-bonus spell, and only an item's on-activate spell.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A cast held on a player from another player is not in the 0x262 a viewer that comes later is sent: the player lists only its own casts (genesis_prime/game/connection/viewers `appearance`), so that viewer sees the buff from the next change.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A change a caster tells a player before the player has taken its sight notice of that caster is dropped, because the player holds a change only from a caster it sees; the map's notice and the caster's tell come from two senders with no order. A caster that joins again under a new stay, with no unseen notice between, keeps the sources of its earlier stay.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A change held on a player ends at the player's death, a server choice: the client has no path that ends a buff on a unit's death. A change is applied as told, with no scaling by the player's own stats, a guess. Two casters whose spells share a stack group (Phantasmal Armor, group 387, one instance per unit) both apply, as the creature's modifiers do.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A caster that dies while the player sees it sends no end of its own: the player holds the change until the caster's end tell.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A heal told to a player is applied whenever it arrives, also after the round of the caster that waits for its answer has closed, because the tell carries no deadline.",
    ),
  ]
}
