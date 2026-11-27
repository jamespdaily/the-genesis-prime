//// The real rows of the order cover: one row for the listed variants of a told type, with
//// the cover that names the test or the reason. `told` lists the types whose every variant
//// has a row (`rows`), `families` the other inputs of the relation table, which are read
//// from their types or, for the connection's timers, from the arms that tell them apart
//// (`family_rows`).

import code_rule/order_coverage.{type Row}
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/list
import gleam/string

const connection = "genesis_prime/client_connection"

const news = "genesis_prime/game/unit_news"

const map = "genesis_prime/world_map/map"

const relay = "genesis_prime/world_map/relay"

const creature = "genesis_prime/world_map/creature"

const fight = "genesis_prime/world_map/creature_fight"

const guard = "genesis_prime/world_map/creature_guard"

const the_connection = "genesis_prime/game/connection"

/// The types whose every variant has a row in `rows`: `#(module, type name)`.
pub fn told() -> List(#(String, String)) {
  [
    #(connection, "StaySent"),
    #(news, "News"),
    #(map, "Notice"),
    #(relay, "Delivered"),
    #(relay, "Payload"),
    #(relay, "Inbound"),
    #(relay, "Landing"),
    #(creature, "Message"),
    #(map, "Message"),
  ]
}

/// The rows for the types the map and the processes tell each other.
pub fn rows() -> List(Row) {
  []
}

/// The families of inputs the relation table names besides the told types, as
/// `order_coverage.breaches_of` takes them: `#(#(module, name), members)`. The members of
/// a type are its variants; those of `Request` are the variants that start `Ask`, the
/// connection's asks (its other variants are its tells to the map, which `Message` of the
/// map covers); those of `timer_due` are the timers `order_coverage.connection_timers`
/// reads from the connection's source.
pub fn families(
  sources sources: List(SourceFile),
) -> List(#(#(String, String), List(String))) {
  let variants = fn(module, type_name) {
    case
      list.find(sources, fn(file) { syntax.module_name(file.path) == module })
    {
      Ok(file) -> syntax.variants_of(file:, type_names: [type_name])
      Error(Nil) -> []
    }
  }
  let types =
    list.map(
      [
        #(connection, "Message"),
        #(fight, "Input"),
        #(fight, "Timer"),
        #(guard, "Input"),
        #(guard, "Timer"),
      ],
      fn(type_) { #(type_, variants(type_.0, type_.1)) },
    )
  let timers = case
    list.find(sources, fn(file) {
      syntax.module_name(file.path) == the_connection
    })
  {
    Ok(file) -> order_coverage.connection_timers(file:)
    Error(Nil) -> []
  }
  [
    #(
      #(connection, "Request"),
      list.filter(variants(connection, "Request"), string.starts_with(_, "Ask")),
    ),
    #(#(the_connection, "timer_due"), timers),
    ..types
  ]
}

/// The rows for the families of `families`.
pub fn family_rows() -> List(Row) {
  []
}
