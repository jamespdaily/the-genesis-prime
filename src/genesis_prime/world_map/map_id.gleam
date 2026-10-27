//// The key of one map: a world of the client's World table and one instance
//// of it. Open worlds have one instance that every player shares; an
//// instanced world has one per group.

/// One map: its World row's id and its instance.
pub type MapId {
  MapId(world_id: Int, instance: Int)
}
