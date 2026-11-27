//// What another player's cast lands on this connection's player: the heal rows a
//// caster's connection told it (genesis_prime/game/strike_tell `PlayerStrike`), applied to
//// its own life and answered, and the changes a caster's cast holds on it
//// (genesis_prime/game/held_changes), applied as the player's own cast's change of that
//// kind is and held per caster until one of the ends below.
////
//// ```
//// caster's connection C                        this connection T (the healed player)
////   Tell(map, TellLanding(C, stay_C, T, stay_T, HealStrike(PlayerStrike(key, C, stay_C, outgoing, heals))))
////                      ─▶ the map: Relayed(stay_T, Landed(..)) ─▶ ForStay(stay_T, SentByPlayer(Strike(strike)))   (the stay fence; held through an ask)
////                      ─▶ player_life.heals_taken: each row in order on the life the one before left
////   ForStay(stay_C, SentByPlayer(Answer(PlayerAnswered(key, HealsLanded(splits) | PlayerDead))))
////                      ◀─ Tell(map, TellLanding(T, stay_T, C, stay_C, HealAnswer(answered))), then T's own news
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
////   Tell(map, TellLanding(C, stay_C, T, stay_T, ChangeStart(PlayerChangeStarts(C, stay_C, source, change, sight, spell4_id, effect))))
////                      ─▶ the map (T in stay_T and C in stay_C): Relayed(stay_T, Landed(..))
////                      ─▶ ForStay(stay_T, SentByPlayer(Change(..)))   (the stay fence; held through an ask)
////                      ─▶ changed: the change through the function the player's own cast uses
////                         (properties.started, absorption.started), held for C
////   Tell(map, TellLanding(C, stay_C, T, stay_T, ChangeEnd(PlayerChangeEnds(C, source))))
////                      ─▶ changed: the source taken off, when C holds it
////   Tell(map, TellLanding(C, stay_C, T, stay_T, CastWent(PlayerCastWent(C, cast_id))))
////                      ─▶ cast_went: Tell(map, TellBroadcast(PeerNews(T, HeldCastStarted(0x7ff, 0x7f4)))), after the rows
////   the map's UnseenBy(C) ─▶ caster_unseen: C's sources with `EndsWhenUnseen` taken off
////   the map's Gone(C's unit) ─▶ caster_removed: every source of that unit taken off
////   T dies                ─▶ ended_at_death: every source T holds taken off
////   each of the three, once a cast has no source left
////                         ─▶ Tell(map, TellBroadcast(PeerNews(T, HeldCastEnded(cast_id)))), after T's own writes
//// ```
////
//// ```
//// a creature's blow lands on T, T alive, C among T's viewers and waiting for an event it raises
////   Tell(map, TellLanding(T, stay_T, C, stay_C, AllyEvent(PlayerEvent(T's unit, the events C waits for))))
////                      ◀─ events_told: after T's own procs are raised, one tell per waiting caster
//// ```
////
//// - **An ally tells its caster the events of a creature's blow** (`events_told`): the events
////   `cast_proc.blow_events` gives, those the caster's Proc sources on T wait for
////   (`held_changes.events_awaited`), to each such caster among T's viewers with the stay the
////   viewer holds. The tell is never asked and nothing waits for it. The life is checked, not
////   the ledger: a lethal blow is carried while the life is already dead and before the
////   death clears the ledger, and a dying ally is not healed.
//// - **A change is taken only from a caster T sees**: C is among T's viewers with the stay
////   the tell names, and T is alive. The caster addresses a tell from the players in its
////   own sight, and sight is symmetric. An end is taken from the caster that holds the source
////   whether or not T still sees it: a change of a spell with propertyFlags 0x100 stays
////   after T lost sight of C, and C's end tell addressed from the go's address ends it.
//// - **A source of a spell with propertyFlags 0x100 survives `UnseenBy`** and ends by the
////   caster's end tell or the caster's unit gone: the client's removal of the caster's unit
////   keeps the casts that flag marks, with their buffs on other units (fact
////   `cast.target_node_end`). The viewers' `Removed` therefore does not finish such a cast
////   (genesis_prime/game/connection/viewers), and this module writes its 0x7fe, once, when
////   the last source of it ends, by any of the ends above (`orphans_finished`): the caster's
////   own frames no longer reach the client.
//// - **A cast is started for a viewer only from the ledger**: the went is taken when T
////   holds a source of the cast that the connection it came from started, not when that
////   connection is still among T's viewers, since a source of a spell with propertyFlags
////   0x100 stays after its caster left T's sight. T's death clears the ledger
////   (`ended_at_death`), so a dead T holds none and takes no went. The start lists each effect
////   the ledger holds of the cast (`held_changes.cast_views`), at the clock the went is
////   taken, and goes to the map, which relays it to each viewer; a viewer writes it only when its
////   own ledger holds the cast in no state and the cast's caster is not its own unit, whose client
////   holds the cast from its own go (`opcode.0x7ff`).
//// - **The tell carries what a create lists**: the cast's Spell4 id and the change's
////   effect with the go's own monotonic time as its start, which the ledger keeps
////   (`held_changes.started`) so that the player's create lists the cast
////   (`held_changes.cast_views`).
//// - **The viewers are told when a cast's last source ends** (`viewers_told_ended`,
////   `held_changes.casts_left`): a viewer that was listed the cast by T's create and not told
////   it by its caster writes a 0x811 naming T, and any other viewer drops the news
////   (genesis_prime/game/client_casts). T keeps no per-viewer record, so every viewer is told.
//// - **A source told again goes to the player's own function again**: an absorb pool is
////   refilled, a property modifier already held changes nothing
////   (genesis_prime/game/unit_properties `apply`).
//// - **A held change ends at its holder's death**, as the player's own casts' changes do
////   (`cast.died`); the client has no path that ends a buff on a unit's death, so the
////   death is the server's choice.
////
//// Gaps for the coverage measure: `gaps()`.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/client_casts
import genesis_prime/game/connection/absorption as connection_absorption
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/look as connection_look
import genesis_prime/game/connection/properties as connection_properties
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/held_changes
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/proc
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/gap
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/world_map/relay
import gleam/bool
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
    connection_state.tells_the_landing(
      session:,
      entered:,
      to: strike.from,
      to_stay: strike.stay,
      landing: relay.HealAnswer(answered: strike_tell.PlayerAnswered(
        key: strike.key,
        outcome:,
      )),
    )
  Continue(session, [answer, ..news])
}

/// The change `change` of `source` put on the player, as the player's own cast's change of
/// that kind is: a property modifier by the properties' function, an absorb pool by the
/// life's.
pub fn started(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
  change change: held_changes.Told,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case change {
    held_changes.Applies(change: held_changes.Property(modifier:)) ->
      connection_properties.started(session:, now:, source:, modifier:)
    held_changes.Applies(change: held_changes.Absorb(amount:, mask:)) ->
      connection_absorption.started(session:, now:, source:, amount:, mask:)
    held_changes.Awaits(..) -> #(session, [])
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

/// What a caster's connection told the player (`PlayerTell.Change`). A start is taken
/// only while the player is alive and the caster is one of its viewers with the stay the
/// tell names; it is applied (`started`) and held for the caster. An end is taken only
/// from the caster that holds the source. A went is taken only from the caster that holds
/// a source of the cast, and starts the cast for the viewers (`cast_went`).
pub fn changed(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  change change: held_changes.PlayerChange,
) -> client_connection.Handled(Session) {
  case change {
    held_changes.PlayerChangeStarts(
      from:,
      from_stay:,
      source:,
      change:,
      sight:,
      spell4_id:,
      effect:,
    ) ->
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
                  spell4_id:,
                  effect:,
                  trigger: held_changes.trigger_of(told: change),
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
          let #(session, finished) = orphans_finished(session:)
          Continue(
            session,
            list.flatten([
              effects,
              finished,
              viewers_told_ended(session:, sources: [source]),
            ]),
          )
        }
        Ok(_) | Error(Nil) -> Continue(session, [])
      }
    held_changes.PlayerCastWent(from:, cast_id:) ->
      cast_went(session:, now:, entered:, from:, cast_id:)
  }
}

/// The go of the cast `cast_id` that the caster of connection `from` started has told the
/// player its changes: the player tells the map the cast's start, built from the changes it
/// holds of the cast, for the map to relay to its viewers. The ledger
/// is the whole guard: a dead player holds nothing (`ended_at_death`).
fn cast_went(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  from from: step.ConnectionId,
  cast_id cast_id: Int,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !held_changes.holds_cast_from(held: entered.held, cast_id:, by: from),
    return: Continue(session, []),
  )
  case
    list.find(
      held_changes.cast_views(
        held: entered.held,
        holder_unit_id: entered.unit_id,
        now_ms: now.monotonic_ms,
      ),
      fn(view) { view.cast_id == cast_id },
    )
  {
    Ok(view) -> {
      let #(start, go) =
        cast_frame.held_start(
          view:,
          place: movement.place(entered.movement),
          now_ms: now.monotonic_ms,
        )
      Continue(session, [
        connection_state.broadcast(
          session:,
          entered:,
          news: unit_news.HeldCastStarted(start:, go:),
        ),
      ])
    }
    Error(Nil) -> Continue(session, [])
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

/// What the player tells the casters of Proc rows it holds, for a creature's blow that raised
/// `events` (`cast_proc.blow_events`): each caster among its viewers whose sources wait for
/// one of them gets one tell with the stay it holds the viewer by, the player's unit and the
/// events it waits for in the order they were raised. A dead player tells nobody.
pub fn events_told(
  session session: Session,
  entered entered: world_entry.Entered,
  events events: List(proc.Event),
) -> List(Effect(ConnectionEffect(Request))) {
  use <- bool.guard(
    when: player_life.state(life: entered.life) != player_life.Alive,
    return: [],
  )
  list.filter_map(held_changes.events_awaited(held: entered.held), fn(awaiting) {
    let #(caster, triggers) = awaiting
    let waited_for =
      list.filter(events, fn(event) { list.contains(triggers, event.trigger) })
    case dict.get(entered.viewers, caster), waited_for {
      Ok(viewer), [_, ..] ->
        Ok(connection_state.tells_the_landing(
          session:,
          entered:,
          to: caster,
          to_stay: viewer.stay,
          landing: relay.AllyEvent(event: strike_tell.PlayerEvent(
            unit_id: entered.unit_id,
            events: waited_for,
          )),
        ))
      Ok(_), [] | Error(Nil), _ -> Error(Nil)
    }
  })
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
      let #(session, effects) =
        list.fold(sources, #(session, []), fn(so_far, source) {
          let #(session, done) = so_far
          let #(session, more) = ended(session:, now:, source:)
          #(session, list.append(done, more))
        })
      let #(session, finished) = orphans_finished(session:)
      #(
        session,
        list.flatten([
          effects,
          finished,
          viewers_told_ended(session:, sources:),
        ]),
      )
    }
  }
}

/// The tell of `HeldCastEnded` to the map for each cast of `sources` of
/// which the player holds no source any more, in cast id order, after the writes to the
/// player's own client: the viewers that were listed the cast by the player's create and
/// not told it by its caster end it themselves (genesis_prime/game/connection/viewers).
fn viewers_told_ended(
  session session: Session,
  sources sources: List(unit_properties.Source),
) -> List(Effect(ConnectionEffect(Request))) {
  case connection_state.entered_of(session.status) {
    None -> []
    Some(entered) ->
      list.map(
        held_changes.casts_left(held: entered.held, released: sources),
        fn(cast_id) {
          connection_state.broadcast(
            session:,
            entered:,
            news: unit_news.HeldCastEnded(cast_id:),
          )
        },
      )
  }
}

/// The 0x7fe of each cast the client holds with no caster (`client_casts.orphans`) of
/// which the player holds no source any more, in cast id order, written after the write of
/// the source that ended last: with the caster's unit removed, no frame of the caster
/// reaches the client, so the player's connection ends the cast (`cast.target_node_end`).
fn orphans_finished(
  session session: Session,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let done =
        held_changes.casts_without_source(
          held: entered.held,
          cast_ids: client_casts.orphans(casts: entered.client_casts),
        )
      use <- bool.guard(when: done == [], return: #(session, []))
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            client_casts: client_casts.orphans_ended(
              casts: entered.client_casts,
              cast_ids: done,
            ),
          )
        })
      #(
        session,
        list.map(done, fn(cast_id) {
          connection_state.to_client(
            session,
            cast_frame.finished_frame(cast_id:),
          )
        }),
      )
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
      missing: "A caster that comes back into the sight of a player that still holds its kept change is shown no buff on it, since no rule of the caster stands behind the entry (`proc.nodes_left`, `unit_removed`). The entry names the holder as the cast's primary and only target, which is wrong for a cast whose primary target is another unit (a child Barrier's Proxy started on an ally, whose area found others around that ally).",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A cast a viewer borrowed from a player's create or from the start the player tells it (genesis_prime/game/client_casts) is ended by that player alone: its caster's later create, start, frames and removal write nothing for it, so a tick or a 0x813 of its stack does not reach that viewer, and a second go of the cast would not either (the whole-table check `no_spell_that_lands_a_change_on_another_player_and_restricts_its_caster_has_a_second_go_test` reads every spell the plan keeps that lands a change on a player and restricts its caster; a viewer writes the caster's restriction news by its own ledger of the cast), and a cast held with no caster by the player's own client that another player lists is ended by the player's own end alone. A dead viewer is written the start a player tells as a live one is. The Fluff rows of another player's press (Spell4 bases 26762, 35526, 63087, the children of 47675 and 19030) and the one heal row a spell that lands a change lists on its target, the HealShields row 145873 of Spell4 60416 (Protection Probes tier 9, started by a Proxy on each ally; players hold tier 1 of each ability, `ability_book_frame.first_tier`), are not changes and are listed to no viewer, though the viewer is told the buff's icon and its 10 000 ms by the cast's four type 11 rows. A cast whose method is Channeled, ChanneledField, Multiphase or 10 would stay filed after the 0x811; a spell that lands a change on a player by a press is a Normal cast (`cast_player_change_test`), and Energy Auger's aura (Spell4 82830, method 10), which lands one on each ally its area selects, would stay filed in a viewer that borrowed its cast.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A kept change (a spell with propertyFlags 0x100) that a caster put on a player stays on the player after the caster joins again under a new stay, as after the caster left sight: only the caster's end tell or the removal of its unit takes it off (`held_changes.released_unseen`); the change's other sources end with the caster's earlier sight.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A change held on a player ends at the player's death, a server choice: the client has no path that ends a buff on a unit's death. A change is applied as told, with no scaling by the player's own stats, a guess. Two casters whose spells share a stack group (Phantasmal Armor, group 387, one instance per unit) both apply, as the creature's modifiers do.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "The buff icon of a kept cast (a spell with propertyFlags 0x100) that holds a change on a player from another player ends in the client of each viewer of that player that was told the cast by its caster, other than the player, which is written the cast's 0x7fe when the caster leaves its sight, while the change lasts, because only the player's own connection learns the end of a kept change (a viewer that borrowed the cast from the player's create keeps it until the player's end); and a kept cast that holds a change on two players the player sees ends in the player's client with the player's own end, because the player cannot know the other node.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A Proc row the caster holds on an ally is told as a change that applies nothing and is listed as the cast's effect on the ally; it is held for the allies the round selected at the go, so an ally who walks into the area later is given none, and it ends with the change on that ally, the ally's death included, a server choice. An ally whose caster is not among its viewers tells its blows to no one, so the proc it holds fires only once the caster sees it again.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A heal told to a player is applied whenever it arrives, also after the round of the caster that waits for its answer has closed, because the tell carries no deadline.",
    ),
  ]
}
