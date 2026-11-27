import gleam/list

/// `count` whole numbers from `from` up; none when `count` is 0 or below.
pub fn counting(from from: Int, count count: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, times: count), fn(_, index) { from + index })
}
