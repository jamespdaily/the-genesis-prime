//// What the tests of the quest requests share: the asker, the player and the body of an
//// accept.

import game_connection_support as connection_support
import genesis_prime/game/interaction
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest.{type Asker, Asker}
import genesis_prime/game/shown
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/id.{RaceId}
import prerequisite_support
import quest_support

const exile = 167

/// A level 20 Exile of race 3, class 5 and path 1 whose log holds these rows.
pub fn asker(log log: List(QuestRow)) -> Asker {
  Asker(
    player: prerequisite_support.player(),
    factions: Factions(current: exile, base: exile),
    log: quest_support.log_of(rows: log),
    checker: prerequisite_support.empty_checker(),
  )
}

/// The Exile of race 3 standing at the entry place.
pub fn standing() -> interaction.Player {
  interaction.Player(
    race_id: RaceId(3),
    faction: shown.Exile,
    place: connection_support.entry_place(),
  )
}

/// The body of the client's accept of a quest from an item at a place.
pub fn accept_body(
  location location: Int,
  bag_index bag_index: Int,
  quest_id quest_id: Int,
) -> BitArray {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location:, bag_index:),
      quest_id:,
    ))
    as "the request fits its fields"
  body
}
