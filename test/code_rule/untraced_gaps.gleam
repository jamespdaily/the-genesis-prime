//// The fields and union kinds of messages the server sends that the schema
//// does not trace yet, each entry naming the open issue whose work removes it.
//// `schema_evidence` fails a field of a sent message that is neither traced nor
//// open and a union kind that is none of a traced variant, a never tag and an
//// open tag, unless an entry lists it; and it fails an entry that lists what is
//// traced now, so naming a field or classifying a kind removes its line.

/// What one owner of the schema holds that is untraced today.
pub type Gap {
  /// Fields of one message or record that have no name beyond their position
  /// and are not marked open, or are constants with neither `named_by` nor
  /// `open`.
  UntracedFields(owner: String, fields: List(String), issue: Int)
  /// Kinds of one union below its `refused_from` that are no variant, no never
  /// tag and no open tag, or are variants with neither `named_by` nor `open`.
  UnclassifiedTags(union: String, tags: List(Int), issue: Int)
}

/// Every untraced field and kind in a message the server sends, by owner or
/// union, and the open issue whose work removes it.
pub const known_gaps: List(Gap) = [
  UntracedFields(
    owner: "buyback_entry",
    fields: [
      "field_5",
      "field_6",
      "field_7",
      "field_8",
      "field_14",
      "field_15",
      "field_16",
      "field_17",
      "field_18",
      "field_19",
      "field_20",
      "field_21",
      "field_26",
    ],
    issue: 979,
  ),
  UntracedFields(
    owner: "currency_changed",
    fields: ["field_3", "field_4"],
    issue: 979,
  ),
  UntracedFields(owner: "item_action_failed", fields: ["item_guid"], issue: 979),
  UntracedFields(
    owner: "player_character_state",
    fields: ["field_23"],
    issue: 979,
  ),
  UntracedFields(
    owner: "player_pet",
    fields: ["field_2", "field_3", "field_4"],
    issue: 979,
  ),
  UntracedFields(owner: "reputation_list", fields: ["field_1"], issue: 979),
  UntracedFields(
    owner: "reward_property_modifier",
    fields: ["kind", "data"],
    issue: 979,
  ),
  UntracedFields(
    owner: "shared_item",
    fields: [
      "field_2",
      "field_9",
      "field_10",
      "field_12",
      "field_13",
      "field_14",
      "field_15",
      "field_16",
      "field_17",
      "field_18",
      "field_19",
      "field_20",
      "field_21",
      "field_22",
      "field_23",
      "list_a",
      "list_b",
      "field_27",
    ],
    issue: 979,
  ),
  UntracedFields(
    owner: "vendor_item",
    fields: ["field_10", "field_11"],
    issue: 979,
  ),
  UntracedFields(
    owner: "vendor_tab",
    fields: ["field_1", "field_2"],
    issue: 979,
  ),
  UnclassifiedTags(
    union: "combat_log_entry",
    tags: [
      0,
      5,
      8,
      9,
      10,
      11,
      15,
      16,
      19,
      20,
      21,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
      33,
      35,
    ],
    issue: 979,
  ),
  UnclassifiedTags(
    union: "unit_stat_change",
    tags: [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
    ],
    issue: 979,
  ),
  UnclassifiedTags(union: "unit_stat_value", tags: [2], issue: 979),
]
