//// The bounds on a create request, against the client's own tables through the
//// context the game server builds: the bone values of a race 1 male (48) and a
//// race 12 female (41), the labels of the label table, and the two character
//// slots of an account (records opcode.0x25b.counts,
//// lua.CharacterSelection.OnLoadFromCharacter and
//// RewardPropertyPremiumModifier.rewardPropertyId). The tests read the client's
//// files, so they skip where `GENESIS_NO_CLIENT=1`.

import character_support
import client_tables
import environment
import genesis_prime/character/character_slots
import genesis_prime/character/customisation
import genesis_prime/character/select.{
  type Effect, CreateRequested, Idle, Log, Requested, Send, State, Store,
}
import genesis_prime/character/server_message.{CreateResult}
import genesis_prime/game/game_context
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/character_customization_label
import genesis_prime/table/loader/store as table_store
import gleam/list
import owned_test
import unitest

const male = 0

const female = 1

/// The context the game server builds from the client's tables, with the row
/// offered to the account whatever its enabled column says.
fn context_for(
  tables tables: table_store.Tables,
  row row: CharacterCreation,
) -> select.Context {
  let context =
    game_context.build(
      tables:,
      start: fn(_row) { Ok(character_support.start_place()) },
      customisation: customisation.of(tables),
      character_slots: character_slots.hybrid(tables),
      realm_id: 1,
      server_time: 0,
    )
  select.Context(..context.select, creation: fn(_id) { Ok(row) })
}

fn row_of(
  tables tables: table_store.Tables,
  race race: Int,
  sex sex: Int,
) -> CharacterCreation {
  let assert Ok(row) =
    list.find(character_creation.all(tables), fn(row) {
      row.race_id == race && row.sex == sex
    })
    as "CharacterCreation.tbl holds a row of the race and sex"
  character_creation.CharacterCreation(
    ..row,
    enabled: True,
    entitlement_id_required: 0,
    account_currency_amount_cost: 0,
  )
}

fn create(
  context context: select.Context,
  row row: CharacterCreation,
  bones bones: Int,
  labels labels: List(Int),
  characters characters: Int,
) -> List(Effect) {
  let #(_, effects) =
    select.decide(
      State(
        account_id: character_support.account_id,
        characters: list.index_map(list.repeat(Nil, characters), fn(_, id) {
          character_support.character(id:, name: "Ab Cd")
        }),
        status: Idle,
      ),
      Requested(
        CreateRequested(CreateCharacter(
          creation_id: row.id,
          name: "Ab Cd",
          path: 1,
          customisation_labels: labels,
          customisation_values: list.map(labels, fn(_) { 1 }),
          bone_values: list.repeat(0x3F800000, bones),
        )),
      ),
      context,
    )
  effects
}

fn is_created(effects: List(Effect)) -> Bool {
  list.any(effects, fn(effect) {
    case effect {
      Store(select.InsertCharacter(_)) -> True
      Store(select.LoadCharacters(_))
      | Store(select.RenameStored(..))
      | Store(select.DeleteStored(..))
      | Send(_)
      | select.BeginWorldEntry(_)
      | Log(_)
      | select.Close(_)
      | select.Abandon(_) -> False
    }
  })
}

fn result_of(effects: List(Effect)) -> Int {
  let assert [CreateResult(answer)] =
    list.filter_map(effects, fn(effect) {
      case effect {
        Send(CreateResult(_) as message) -> Ok(message)
        Send(_)
        | Store(_)
        | select.BeginWorldEntry(_)
        | Log(_)
        | select.Close(_)
        | select.Abandon(_) -> Error(Nil)
      }
    })
    as "one create answer is sent"
  answer.result
}

pub fn a_race_1_male_sends_48_bone_values_and_a_race_12_female_41_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let male_row = row_of(tables:, race: 1, sex: male)
  let female_row = row_of(tables:, race: 12, sex: female)
  let male_context = context_for(tables:, row: male_row)
  let female_context = context_for(tables:, row: female_row)
  assert is_created(create(
    context: male_context,
    row: male_row,
    bones: 48,
    labels: [1],
    characters: 0,
  ))
    as "opcode.0x25b.counts: 48 for race 1 male"
  assert is_created(create(
    context: female_context,
    row: female_row,
    bones: 41,
    labels: [1],
    characters: 0,
  ))
    as "opcode.0x25b.counts: 41 for race 12 female"
  list.each([47, 49, 0], fn(bones) {
    let effects =
      create(
        context: male_context,
        row: male_row,
        bones:,
        labels: [1],
        characters: 0,
      )
    assert !is_created(effects) && result_of(effects) == 4
      as "opcode.0x25b.counts: a race 1 male with another number than 48 is refused with CreateFailed, 4"
  })
  // 41 is a race 12 female's number, and a race 1 male's request holds 48.
  let effects =
    create(
      context: male_context,
      row: male_row,
      bones: 41,
      labels: [1],
      characters: 0,
    )
  assert result_of(effects) == 4
    && list.any(effects, fn(effect) {
      effect == Log(select.BoneCountWrong(expected: 48, given: 41))
    })
    as "the refusal names the count the race and sex have and the count it was given"
  let effects =
    create(
      context: female_context,
      row: female_row,
      bones: 48,
      labels: [1],
      characters: 0,
    )
  assert result_of(effects) == 4
    as "opcode.0x25b.counts: 48 is the most, and a race 12 female does not send it"
}

pub fn the_labels_of_the_client_s_table_are_checked_against_the_characters_faction_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let row = row_of(tables:, race: 1, sex: male)
  let context = context_for(tables:, row:)
  let faction = row.faction_id
  let other = case faction {
    166 -> 167
    _ -> 166
  }
  let assert Ok(own_label) =
    list.find(character_customization_label.all(tables), fn(label) {
      label.faction2_id == faction
    })
    as "the label table has a label of the faction"
  let assert Ok(other_label) =
    list.find(character_customization_label.all(tables), fn(label) {
      label.faction2_id == other
    })
    as "the label table has a label of the other faction"
  assert is_created(create(
    context:,
    row:,
    bones: 48,
    labels: [1, own_label.id],
    characters: 0,
  ))
    as "CharacterCustomizationLabel: a label of no faction and one of the character's are accepted"
  assert result_of(create(
      context:,
      row:,
      bones: 48,
      labels: [other_label.id],
      characters: 0,
    ))
    == 4
    as "CharacterCustomizationLabel: a label whose faction2Id is the other faction is refused with 4"
  assert result_of(create(
      context:,
      row:,
      bones: 48,
      labels: [1, 1],
      characters: 0,
    ))
    == 4
    as "opcode.0x25b.counts: a label given twice is refused with 4"
}

pub fn an_account_with_2_characters_is_full_under_the_hybrid_system_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let row = row_of(tables:, race: 1, sex: male)
  let context = context_for(tables:, row:)
  assert is_created(create(
    context:,
    row:,
    bones: 48,
    labels: [1],
    characters: 1,
  ))
    as "RewardPropertyPremiumModifier row 117: 2 slots, so an account with 1 character may create"
  let effects = create(context:, row:, bones: 48, labels: [1], characters: 2)
  assert !is_created(effects) && result_of(effects) == 9
    as "PreGameLib.CodeEnumCharacterModifyResults: 9 is CreateFailed_AccountFull, for an account with as many characters as the 2 slots of row 117"
  assert list.contains(effects, Log(select.AccountFull(2)))
}
