//// The spells a tooltip names that no row reaches (`genesis_prime/coverage/named_unreached`).
//// Expected values come from these places.
//// - A value token's spell: `eff=E.field` and `cc=E.field` read Spell4Effects row E, and
////   `spell=N.field` reads Spell4 N (`FormatSpellTooltipToken` `0x1404df2c0`; the
////   decoder's records of `FormatTextTokens` `0x1400c12b0`). A `spell=N` with no field
////   prints the spell's name as a link, which reads no value.
//// - Pulse Blast's text 376222 (the list `test/fixture/tooltip_tokens/tokens.tsv`, rows
////   `376222 eff 79090/79092/79093 input0pct`, `376222 spell 37302 aoetc` and
////   `376222 eff 95337 data02rawint`): effect 95337 is in the hidden spell 42148, which
////   the client's tables cast from nothing (`Spell4.42148`); the `server_proxy` row of
////   migration 0018 (base 26468, go 1, spell 42148) plants it into the tree.
//// - The real tables (coverage tag, skipped where the client's files are absent): the
////   rows of the measured table of the step's design, each from the list and the
////   tables. Quick Draw 43468 holds text 404550, whose `eff 196652` is in 76003 (Quick
////   Draw surged). Nano Skin: Lethal 60769 holds text 519096, whose `eff 97462` and
////   `cc 97462` are in 42736 (Cripple). Eradication ExoSuit 47860 holds text 466631,
////   whose `eff 123743` and `spell 52370` name 52370, which only the Proc 123744 of
////   52371 casts, a kind of 12 the plan does not read (`ProcKindNotRead`). Spell Surge
////   47273 holds text 445006, with the link `spell 72652`; Impale 38779 holds text
////   311077, with the link `spell 48584`. The same text 445006 also holds
////   `eff 187681 durationms` and `ticktimems`, and Spell4Effects 187681 has spellId 72652
////   (`table_rows Spell4Effects 187681`), so 72652 is counted as well as linked. Spell4
////   47866 holds text 450095, whose `spell=47860.ctooltip` shows 47860's text 466631, so
////   52370 is named by 47866 too.
//// The planted Spell4 rows are those of `test/spell_tables`; only their text columns differ.

import client_tables
import genesis_prime/coverage/named_unreached.{Entry, Naming, NoRow}
import genesis_prime/coverage/starting_ability.{ProcKindNotRead}
import genesis_prime/game/server_proxy
import genesis_prime/game/spell_plan
import genesis_prime/table/loader/store
import genesis_prime/tooltip_token.{Token}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

const header = "text_id\tkind\tid\tfield"

fn list_of(rows: List(String)) -> tooltip_token.Tokens {
  let assert Ok(tokens) =
    tooltip_token.parse(string.join([header, ..rows], "\n") <> "\n")
    as "the planted list parses"
  tokens
}

/// The migration 0018 row: Pulse Blast's base 26468, go 1, spell 42148.
const volatility =
  server_proxy.Row(spell4_base_id: 26_468, phase: 1, spell4_id: 42_148)

/// The planted Volatility rows with Pulse Blast's text columns set.
fn rows_with_blast_texts(columns: List(#(String, Int))) -> spell_tables.Rows {
  let rows = spell_tables.rows_with_volatility()
  spell_tables.Rows(
    ..rows,
    spell4: list.map(rows.spell4, fn(row) {
      case row {
        [Integer(42_276), ..] ->
          list.fold(columns, row, fn(row, column) {
            spell_tables.with_column(
              row:,
              name: column.0,
              cell: Integer(column.1),
            )
          })
        other -> other
      }
    }),
  )
}

/// What the tokens name among the spells the planted tables' walk reaches, with these
/// server Proxy rows planted and these parts left out.
fn named_in(
  rows rows: spell_tables.Rows,
  tokens tokens: tooltip_token.Tokens,
  proxies proxies: List(server_proxy.Row),
  left_out left_out: List(starting_ability.LeftOut),
) -> #(named_unreached.Named, List(Int)) {
  spell_tables.with_loaded_deriving(
    rows:,
    derivations: [spell_plan.derivation()],
    body: fn(tables) {
      let reached = reached_ids(tables:, proxies:)
      #(named_unreached.find(tables:, tokens:, reached:, left_out:), reached)
    },
  )
}

fn reached_ids(
  tables tables: store.Tables,
  proxies proxies: List(server_proxy.Row),
) -> List(Int) {
  let plans = spell_plan.plans(tables:)
  let plans = case proxies {
    [] -> plans
    [_, ..] -> {
      let assert Ok(selected) =
        server_proxy.select(rows: proxies, tables:, plans:)
        as "the Proxy rows select over the planted tables"
      server_proxy.planted_into(plans:, proxies: selected)
    }
  }
  let assert Ok(spells) = starting_ability.spells_in(tables:, plans:)
    as "the planted tables hold the rows the walk names"
  list.map(spells, fn(spell) { spell.spell4_id.value })
}

/// Pulse Blast's text 376222 as the client's list holds it.
const pulse_blast_text = [
  "376222\teff\t79090\tinput0pct", "376222\teff\t79092\tinput0pct",
  "376222\teff\t79093\tinput0pct", "376222\tspell\t37302\taoetc",
  "376222\teff\t95337\tdata02rawint",
]

fn volatility_naming() -> named_unreached.Naming {
  Naming(
    token: Token(tooltip_token.Eff, 95_337, "data02rawint"),
    text_id: 376_222,
    named_by: [42_276],
  )
}

pub fn a_value_token_naming_a_spell_no_tree_reaches_is_listed_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(named, reached) =
    named_in(
      rows: rows_with_blast_texts([
        #("localizedTextIdActionBarTooltip", 376_222),
      ]),
      tokens: list_of(pulse_blast_text),
      proxies: [],
      left_out: [],
    )
  assert list.contains(reached, 42_276)
    as "Pulse Blast, whose tooltip holds the token, is reached"
  assert list.contains(reached, 37_302)
    as "its damage spell, named by three of the tokens, is reached"
  assert !list.contains(reached, 42_148)
  assert named.counted
    == [Entry(spell: 42_148, namings: [volatility_naming()], reason: None)]
  assert named.links == []
  assert named.no_row == []
}

pub fn a_server_proxy_row_that_casts_the_spell_removes_it_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(named, reached) =
    named_in(
      rows: rows_with_blast_texts([
        #("localizedTextIdActionBarTooltip", 376_222),
      ]),
      tokens: list_of(pulse_blast_text),
      proxies: [volatility],
      left_out: [],
    )
  assert list.contains(reached, 42_148)
    as "the Proxy row of migration 0018 plants 42148 into Pulse Blast's tree"
  assert named.counted == []
  assert named.links == []
  assert named.no_row == []
}

pub fn an_entry_a_left_out_part_explains_carries_its_reason_test() -> Nil {
  use <- owned_test.run(20_000)
  let reason =
    ProcKindNotRead(
      spell4_id: 37_302,
      effect_id: 79_090,
      kind: 12,
      casts: 42_148,
    )
  let #(named, _) =
    named_in(
      rows: rows_with_blast_texts([
        #("localizedTextIdActionBarTooltip", 376_222),
      ]),
      tokens: list_of(pulse_blast_text),
      proxies: [],
      left_out: [reason],
    )
  assert named.counted
    == [
      Entry(spell: 42_148, namings: [volatility_naming()], reason: Some(reason)),
    ]
}

pub fn a_link_token_is_listed_apart_and_not_counted_test() -> Nil {
  use <- owned_test.run(20_000)
  let link =
    Naming(
      token: Token(tooltip_token.Spell, 42_148, ""),
      text_id: 377_001,
      named_by: [42_276],
    )
  let #(named, _) =
    named_in(
      rows: rows_with_blast_texts([
        #("localizedTextIdCasterIconSpellText", 377_001),
      ]),
      tokens: list_of(["377001\tspell\t42148\t"]),
      proxies: [],
      left_out: [],
    )
  assert named.counted == []
  assert named.links == [Entry(spell: 42_148, namings: [link], reason: None)]
  assert named.no_row == []
}

pub fn a_link_to_a_spell_a_tree_reaches_is_not_listed_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(named, _) =
    named_in(
      rows: rows_with_blast_texts([
        #("localizedTextIdCasterIconSpellText", 377_001),
      ]),
      tokens: list_of(["377001\tspell\t37302\t", "377001\tspell\t37302\taoetc"]),
      proxies: [],
      left_out: [],
    )
  assert named == named_unreached.Named(counted: [], links: [], no_row: [])
}

pub fn a_token_naming_a_row_the_tables_lack_is_listed_as_naming_no_row_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(named, _) =
    named_in(
      rows: rows_with_blast_texts([
        #("localizedTextIdActionBarTooltip", 378_001),
      ]),
      tokens: list_of([
        "378001\teff\t77777777\tinput0pct", "378001\tcc\t77777778\tdurationms",
        "378001\tspell\t88888888\taoetc",
      ]),
      proxies: [],
      left_out: [],
    )
  assert named.counted == []
  assert named.links == []
  assert named.no_row
    == [
      NoRow(
        table: "Spell4Effects",
        id: 77_777_777,
        token: Token(tooltip_token.Eff, 77_777_777, "input0pct"),
        text_id: 378_001,
        named_by: [42_276],
      ),
      NoRow(
        table: "Spell4Effects",
        id: 77_777_778,
        token: Token(tooltip_token.Cc, 77_777_778, "durationms"),
        text_id: 378_001,
        named_by: [42_276],
      ),
      NoRow(
        table: "Spell4",
        id: 88_888_888,
        token: Token(tooltip_token.Spell, 88_888_888, "aoetc"),
        text_id: 378_001,
        named_by: [42_276],
      ),
    ]
}

pub fn a_token_a_nested_tooltip_names_counts_for_the_spell_that_nests_it_test() -> Nil {
  use <- owned_test.run(20_000)
  // Pulse Blast's ActionBarTooltip names the Caster text of the unreached 42148, whose
  // text holds a token of effect 95337 (in 42148 itself).
  let rows =
    rows_with_blast_texts([#("localizedTextIdActionBarTooltip", 379_001)])
  let rows =
    spell_tables.Rows(
      ..rows,
      spell4: list.map(rows.spell4, fn(row) {
        case row {
          [Integer(42_148), ..] ->
            spell_tables.with_column(
              row:,
              name: "localizedTextIdCasterIconSpellText",
              cell: Integer(379_002),
            )
          other -> other
        }
      }),
    )
  let #(named, _) =
    named_in(
      rows:,
      tokens: list_of([
        "379001\tspell\t42148\tctooltip",
        "379002\teff\t95337\tdata02rawint",
      ]),
      proxies: [],
      left_out: [],
    )
  assert named.counted
    == [
      Entry(
        spell: 42_148,
        namings: [
          Naming(
            token: Token(tooltip_token.Spell, 42_148, "ctooltip"),
            text_id: 379_001,
            named_by: [42_276],
          ),
          Naming(
            token: Token(tooltip_token.Eff, 95_337, "data02rawint"),
            text_id: 379_002,
            named_by: [42_276],
          ),
        ],
        reason: None,
      ),
    ]
    as "the nested text is read for the spell that nests it, and the namings run by text id"
}

// ---- the real tables ----

fn real_named() -> named_unreached.Named {
  let tables = client_tables.every_table()
  let assert Ok(tokens) = tooltip_token.load()
    as "the committed list of tooltip tokens loads"
  let reached = reached_ids(tables:, proxies: [volatility])
  let assert Ok(left_out) = starting_ability.left_out(tables:)
    as "the real tables hold the rows the walk names"
  named_unreached.find(tables:, tokens:, reached:, left_out:)
}

fn spells_of(entries: List(named_unreached.Entry)) -> List(Int) {
  list.map(entries, fn(entry) { entry.spell })
}

fn entry_of(
  entries: List(named_unreached.Entry),
  spell: Int,
) -> named_unreached.Entry {
  let assert Ok(entry) = list.find(entries, fn(entry) { entry.spell == spell })
    as { "the list holds spell " <> string.inspect(spell) }
  entry
}

pub fn the_real_tables_count_76003_and_42736_with_no_reason_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let named = real_named()
  assert entry_of(named.counted, 76_003)
    == Entry(
      spell: 76_003,
      namings: [
        Naming(
          token: Token(tooltip_token.Eff, 196_652, "input0pct"),
          text_id: 404_550,
          named_by: [43_468],
        ),
      ],
      reason: None,
    )
  assert entry_of(named.counted, 42_736)
    == Entry(
      spell: 42_736,
      namings: [
        Naming(
          token: Token(tooltip_token.Cc, 97_462, "datafloat00pct"),
          text_id: 519_096,
          named_by: [60_769],
        ),
        Naming(
          token: Token(tooltip_token.Eff, 97_462, "durationms"),
          text_id: 519_096,
          named_by: [60_769],
        ),
      ],
      reason: None,
    )
}

pub fn the_real_tables_give_52370_its_reason_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert entry_of(real_named().counted, 52_370)
    == Entry(
      spell: 52_370,
      namings: [
        Naming(
          token: Token(tooltip_token.Eff, 123_743, "input0pct"),
          text_id: 466_631,
          named_by: [47_860, 47_866],
        ),
        Naming(
          token: Token(tooltip_token.Spell, 52_370, "aoetc"),
          text_id: 466_631,
          named_by: [47_860, 47_866],
        ),
      ],
      reason: Some(ProcKindNotRead(
        spell4_id: 52_371,
        effect_id: 123_744,
        kind: 12,
        casts: 52_370,
      )),
    )
}

pub fn the_real_tables_list_72652_and_48584_as_links_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let named = real_named()
  assert spells_of(named.links) == [48_584, 72_652]
  assert entry_of(named.links, 72_652).namings
    == [
      Naming(
        token: Token(tooltip_token.Spell, 72_652, ""),
        text_id: 445_006,
        named_by: [47_273],
      ),
    ]
  assert entry_of(named.links, 48_584).namings
    == [
      Naming(
        token: Token(tooltip_token.Spell, 48_584, ""),
        text_id: 311_077,
        named_by: [38_779],
      ),
    ]
  assert !list.contains(spells_of(named.counted), 48_584)
}

pub fn the_real_tables_count_72652_by_the_effect_of_its_tooltip_and_list_it_as_a_link_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  assert entry_of(real_named().counted, 72_652)
    == Entry(
      spell: 72_652,
      namings: [
        Naming(
          token: Token(tooltip_token.Eff, 187_681, "durationms"),
          text_id: 445_006,
          named_by: [47_273],
        ),
        Naming(
          token: Token(tooltip_token.Eff, 187_681, "ticktimems"),
          text_id: 445_006,
          named_by: [47_273],
        ),
      ],
      reason: None,
    )
}

pub fn the_real_tables_hold_exactly_four_counted_and_no_missing_row_with_volatility_planted_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let named = real_named()
  assert spells_of(named.counted) == [42_736, 52_370, 72_652, 76_003]
    as "42148 is absent: the Proxy row of migration 0018 casts it"
  assert named.no_row == []
}
