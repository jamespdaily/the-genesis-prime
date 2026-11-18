//// What a scripted objective that asks the player for an item wants: the item worn, or the
//// item bought from a vendor. A QuestObjective of type 5 is done only by the server's 0x361
//// (`QuestObjective.type.5`) and the client holds nothing for these beyond the objective's
//// text ("Equip the $(item=12631)", "Buy a $(item=54409) from $(creature=47172) in
//// Thayd"), so the server's rule (`objective.wears`, `objective.purchased`) reads the
//// Item2 and Creature2 rows the text names, from the rows of the `item_objective` content
//// table (genesis_prime/game/item_objective_table).

import genesis_prime/table/id.{type Creature2Id, type Item2Id}

/// What the objective asks, with the rows its text names: an item worn, or an item bought
/// from the vendor of the Creature2 row. The two cannot be mixed up: only a buy holds a
/// vendor.
pub type Wanted {
  Wear(item2_id: Item2Id)
  BuyFrom(item2_id: Item2Id, vendor: Creature2Id)
}
