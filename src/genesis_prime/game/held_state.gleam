//// The crowd-control states a shown unit holds as its viewer's client was told: a 0x87f
//// gives a state an instance id, and the 0x880 that ends it names that instance, so two
//// holds of one state end one at a time.
////
//// ```
//// 0x87f (state, instance id) ─▶ applied ─▶ held list         the unit's death ─▶ held list emptied
//// 0x880 (instance id)        ─▶ ended   ─▶ held list         states ─▶ what a press's crowd-control conditions read
//// ```

import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import gleam/list

/// A crowd-control state a shown unit holds, with the instance id its 0x87f gave.
pub type HeldState {
  HeldState(state: CrowdControlState, instance_id: Int)
}

/// The list with the state added after the ones held.
pub fn applied(
  held held: List(HeldState),
  state state: CrowdControlState,
  instance_id instance_id: Int,
) -> List(HeldState) {
  list.append(held, [HeldState(state:, instance_id:)])
}

/// The list without the state of that instance id; the other instances stay.
pub fn ended(
  held held: List(HeldState),
  instance_id instance_id: Int,
) -> List(HeldState) {
  list.filter(held, fn(one) { one.instance_id != instance_id })
}

/// The states held, in the order they were applied.
pub fn states(held held: List(HeldState)) -> List(CrowdControlState) {
  list.map(held, fn(one) { one.state })
}
