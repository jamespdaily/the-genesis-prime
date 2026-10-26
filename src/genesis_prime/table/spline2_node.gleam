//// STUB of the generated module for the client table Spline2Node: the types and signatures only.

import genesis_prime/table/store
import genesis_prime/table/tbl_file

pub type Spline2Node {
  Spline2Node(
    id: Int,
    spline_id: Int,
    ordinal: Int,
    position0: Float,
    position1: Float,
    position2: Float,
    facing0: Float,
    facing1: Float,
    facing2: Float,
    facing3: Float,
    event_id: Int,
    frame_time: Float,
    delay: Float,
    fovy: Float,
  )
}

pub const schema =
  tbl_file.Schema(
    table: "Spline2Node",
    file: "Spline2Node",
    record_size: 56,
    columns: [
      tbl_file.Column(name: "ID", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "splineId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "ordinal", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "position0", column_type: tbl_file.Float32),
      tbl_file.Column(name: "position1", column_type: tbl_file.Float32),
      tbl_file.Column(name: "position2", column_type: tbl_file.Float32),
      tbl_file.Column(name: "facing0", column_type: tbl_file.Float32),
      tbl_file.Column(name: "facing1", column_type: tbl_file.Float32),
      tbl_file.Column(name: "facing2", column_type: tbl_file.Float32),
      tbl_file.Column(name: "facing3", column_type: tbl_file.Float32),
      tbl_file.Column(name: "eventId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "frameTime", column_type: tbl_file.Float32),
      tbl_file.Column(name: "delay", column_type: tbl_file.Float32),
      tbl_file.Column(name: "fovy", column_type: tbl_file.Float32),
    ],
  )

const index = 327

pub fn entry() -> store.Entry {
  todo
}

pub fn get(tables: store.Tables, id: Int) -> Result(Spline2Node, Nil) {
  todo
}

pub fn all(tables: store.Tables) -> List(Spline2Node) {
  todo
}
