//// The id-cost workload with a unit's id held as a plain `Int` and one more
//// dictionary lookup per message than the plain variant. The harness runs it
//// to show that it can see a difference.

import genesis_prime/id_cost/measurement
import genesis_prime/id_cost/message_stream
import genesis_prime/id_cost/workload.{type Prepared, Prepared}
import gleam/dict.{type Dict}
import gleam/list

type Unit {
  Unit(id: Int, x: Int, y: Int, hit_points: Int)
}

/// Builds the dictionary of units and the list of nearby ids a reply carries.
pub fn prepare() -> Prepared {
  let units =
    message_stream.indexes(message_stream.unit_count)
    |> list.fold(dict.new(), fn(units, index) {
      let id = message_stream.unit_number(index)
      dict.insert(units, id, Unit(id:, x: index, y: index, hit_points: 100))
    })
  let nearby =
    message_stream.indexes(message_stream.nearby_count)
    |> list.map(message_stream.unit_number)
  Prepared(units_size: measurement.sizes_of(units), run: fn(stream) {
    let #(units, reply) = handle_messages(stream:, units:, nearby:, reply: [])
    dict.size(units) + list.length(reply)
  })
}

fn handle_messages(
  stream stream: BitArray,
  units units: Dict(Int, Unit),
  nearby nearby: List(Int),
  reply reply: List(Int),
) -> #(Dict(Int, Unit), List(Int)) {
  case stream {
    <<
      id:32-little,
      move_x:16-signed-little,
      move_y:16-signed-little,
      amount:16-little,
      rest:bytes,
    >> -> {
      let assert Ok(unit) = dict.get(units, id) as "a message named no unit"
      let assert Ok(_) = dict.get(units, id) as "a message named no unit"
      let moved =
        Unit(
          ..unit,
          x: unit.x + move_x,
          y: unit.y + move_y,
          hit_points: unit.hit_points + amount,
        )
      handle_messages(
        stream: rest,
        units: dict.insert(units, id, moved),
        nearby:,
        reply: [id, ..nearby],
      )
    }
    _ -> #(units, reply)
  }
}
