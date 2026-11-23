//// What the sitting bot is told of casts, heals, absorbs, buffs and its own
//// vitals: each such message of the server read as the client reads it, and the
//// one line a person reads for each.
////
//// ```
//// frame ─▶ read (with the book of the casts begun) ─▶ effects ─▶ describe ─▶ a line
//// ```
////
//// - 0x7fc, 0x7fd, 0x7ff and 0x7fe come from `game_client.casts_in`, 0x92f and
////   0x938 from `game_client.fight_in`, and 0x811 from
////   `game_client.targets_removed_in`. A go (0x7f4), a tick (0x7f8) and a unit's
////   property changes (0x93a) are read here with the generated codecs, since
////   `game_client.Blow` keeps neither the damage type nor the overkill that tell
////   a heal and its overheal from a hit (opcode.0x7f4, opcode.0x7f8, opcode.0x93a).
//// - A heal or a hit is a damage description of kind 1 in an effect's result; the
////   amount is its health damage with the overkill and the overheal its overkill
////   (the client logs them as `nHealAmount` and `nOverheal`, spell.heal_result_log).
////   An effect of kind 0 carries no numbers and is shown as an effect bit.
//// - A cast's spell and caster are known from its 0x7ff, so the book keeps them
////   by cast id until its 0x7fe: a go, a tick, a removal and the end of a buff
////   each name its spell. A cast the bot was never told the start of is shown as
////   spell 0, which no Spell4 row has.
//// - Gap: 0x937 (another unit's health) is not read; the bot's own vitals are
////   0x92f and 0x938.

import game_client
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type.{type DamageType}
import genesis_prime/message/float32
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription,
}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{type SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_effect_tick
import genesis_prime/message/spell_go
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// The casts the bot has been told the start of and not the end: each cast id
/// with its spell and its caster's unit.
pub opaque type Book {
  Book(started: Dict(Int, Started))
}

/// A cast as its 0x7ff gave it.
type Started {
  Started(spell4_id: Int, caster_unit_id: Int)
}

/// A book of no casts.
pub fn new_book() -> Book {
  Book(started: dict.new())
}

/// One effect row of a go or a tick: what a damage description says, or only
/// that the effect happened.
pub type Row {
  /// An effect of kind 0, which carries no numbers.
  EffectBit(effect_id: Int)
  /// An effect of kind 1: a heal or a hit.
  Described(
    effect_id: Int,
    damage_type: DamageType,
    amount: Int,
    overkill: Int,
    absorbed: Int,
    shield_absorbed: Int,
    combat_result: Int,
  )
}

/// One property a 0x93a changes: its id and its base and value as floats, or
/// `Error` with the bits when a float is infinite or not a number.
pub type Property {
  Property(
    property_id: Int,
    base: Result(Float, Int),
    value: Result(Float, Int),
  )
}

/// What the bot is told, as one thing to print.
pub type Effect {
  /// 0x7fc: a press was refused.
  PressRefused(client_cast_id: Int, spell4_id: Int, result: Int)
  /// 0x7fd: a press was accepted and has a server cast id.
  PressConfirmed(client_cast_id: Int, server_cast_id: Int)
  /// 0x7ff: a unit's cast starts; a buff is the cast's spell.
  CastStarted(
    cast_id: Int,
    spell4_id: Int,
    root_spell4_id: Int,
    parent_spell4_id: Int,
    caster_unit_id: Int,
  )
  /// 0x7f4: a cast goes off in this phase, with each target's effect rows.
  CastWent(
    cast_id: Int,
    spell4_id: Int,
    phase: Int,
    rows: List(#(Int, List(Row))),
  )
  /// 0x7f8: a periodic effect of a cast ticks on a unit.
  CastTicked(
    cast_id: Int,
    spell4_id: Int,
    effect_id: Int,
    unit_id: Int,
    rows: List(Row),
  )
  /// 0x7fe: a cast ends; the end of a buff is its cast's.
  CastFinished(cast_id: Int, spell4_id: Int, caster_unit_id: Int)
  /// 0x811: units taken off a cast.
  TargetsRemoved(cast_id: Int, spell4_id: Int, unit_ids: List(Int))
  /// 0x92f: the bot's own health.
  OwnHealth(unit_id: Int, health: Int)
  /// 0x938: a unit's level, shield, interrupt armor or absorption.
  UnitStat(unit_id: Int, stat: String, value: Int)
  /// 0x93a: a unit's properties change, as a buff sets or restores them.
  PropertiesChanged(unit_id: Int, properties: List(Property))
}

/// The effects a message of the server is, none for a message this module does
/// not follow, and the book after it.
pub fn read(book book: Book, frame frame: Frame) -> #(Book, List(Effect)) {
  case frame.message_id {
    0x07FC | 0x07FD | 0x07FF | 0x07FE ->
      list.fold(
        game_client.casts_in(frames: [frame]),
        #(book, []),
        fn(so_far, event) {
          let #(book, effects) = so_far
          let #(book, effect) = cast_effect(book:, event:)
          #(book, list.append(effects, effect))
        },
      )
    0x07F4 -> {
      let assert Ok(go) = spell_go.decode(frame.body) as "0x7f4 decodes"
      #(book, [
        CastWent(
          cast_id: go.cast_id,
          spell4_id: spell_of(book:, cast_id: go.cast_id),
          phase: go.phase,
          rows: list.map(go.targets, fn(target) {
            #(target.unit_id, list.filter_map(target.effects, row_of))
          }),
        ),
      ])
    }
    0x07F8 -> {
      let assert Ok(tick) = spell_effect_tick.decode(frame.body)
        as "0x7f8 decodes"
      #(book, [
        CastTicked(
          cast_id: tick.cast_id,
          spell4_id: spell_of(book:, cast_id: tick.cast_id),
          effect_id: tick.spell4_effects_id,
          unit_id: tick.unit_id,
          rows: list.map(tick.descriptions, fn(description) {
            described(effect_id: tick.spell4_effects_id, description:)
          }),
        ),
      ])
    }
    0x0811 -> #(
      book,
      list.map(game_client.targets_removed_in(frames: [frame]), fn(removed) {
        let #(cast_id, unit_ids) = removed
        TargetsRemoved(
          cast_id:,
          spell4_id: spell_of(book:, cast_id:),
          unit_ids:,
        )
      }),
    )
    0x093A -> {
      let assert Ok(changed) = unit_properties_changed.decode(frame.body)
        as "0x93a decodes"
      #(book, [
        PropertiesChanged(
          unit_id: changed.unit_id,
          properties: list.map(changed.properties, property_of),
        ),
      ])
    }
    0x092F | 0x0938 -> #(
      book,
      list.filter_map(game_client.fight_in(frames: [frame]), vitals_effect),
    )
    _ -> #(book, [])
  }
}

/// The effect a cast message is, and the book after it: a start is kept, an end
/// is dropped.
fn cast_effect(
  book book: Book,
  event event: game_client.CastEvent,
) -> #(Book, List(Effect)) {
  case event {
    game_client.CastRefused(client_cast_id:, spell4_id:, result:) -> #(book, [
      PressRefused(client_cast_id:, spell4_id:, result:),
    ])
    game_client.CastConfirmed(client_cast_id:, server_cast_id:) -> #(book, [
      PressConfirmed(client_cast_id:, server_cast_id:),
    ])
    game_client.CastStarted(
      cast_id:,
      spell4_id:,
      root_spell4_id:,
      parent_spell4_id:,
      caster_unit_id:,
    ) -> #(
      Book(started: dict.insert(
        book.started,
        cast_id,
        Started(spell4_id:, caster_unit_id:),
      )),
      [
        CastStarted(
          cast_id:,
          spell4_id:,
          root_spell4_id:,
          parent_spell4_id:,
          caster_unit_id:,
        ),
      ],
    )
    game_client.CastFinished(cast_id:) -> {
      let caster_unit_id = case dict.get(book.started, cast_id) {
        Ok(Started(caster_unit_id:, ..)) -> caster_unit_id
        Error(Nil) -> 0
      }
      #(Book(started: dict.delete(book.started, cast_id)), [
        CastFinished(
          cast_id:,
          spell4_id: spell_of(book:, cast_id:),
          caster_unit_id:,
        ),
      ])
    }
    game_client.CastWent(..)
    | game_client.ThresholdOpened(..)
    | game_client.ThresholdIndex(..)
    | game_client.ThresholdClosed(..)
    | game_client.ThresholdEnded(..) -> #(book, [])
  }
}

/// The effect a fight event is when it is the bot's own vitals, a unit's level,
/// shield, interrupt armor or absorption.
fn vitals_effect(event: game_client.FightEvent) -> Result(Effect, Nil) {
  case event {
    game_client.OwnHealthIs(unit_id:, health:) ->
      Ok(OwnHealth(unit_id:, health:))
    game_client.LevelIs(unit_id:, level:) ->
      Ok(UnitStat(unit_id:, stat: "level", value: level))
    game_client.ShieldIs(unit_id:, shield:) ->
      Ok(UnitStat(unit_id:, stat: "shield", value: shield))
    game_client.InterruptArmorIs(unit_id:, armor:) ->
      Ok(UnitStat(unit_id:, stat: "interrupt armor", value: armor))
    game_client.AbsorptionIs(unit_id:, absorption:) ->
      Ok(UnitStat(unit_id:, stat: "absorption", value: absorption))
    game_client.Targeted(..)
    | game_client.Threatens(..)
    | game_client.InCombat(..)
    | game_client.Moves(..)
    | game_client.Went(..)
    | game_client.Started(..)
    | game_client.HealthIs(..) -> Error(Nil)
  }
}

/// The spell a cast was started with, 0 for a cast the book has not.
fn spell_of(book book: Book, cast_id cast_id: Int) -> Int {
  case dict.get(book.started, cast_id) {
    Ok(Started(spell4_id:, ..)) -> spell4_id
    Error(Nil) -> 0
  }
}

fn row_of(effect: SpellEffectInfo) -> Result(Row, Nil) {
  case effect.result {
    spell_effect_result.Bit(_) ->
      Ok(EffectBit(effect_id: effect.spell4_effects_id))
    spell_effect_result.Damage(SpellEffectDamage(description:)) ->
      Ok(described(effect_id: effect.spell4_effects_id, description:))
  }
}

fn described(
  effect_id effect_id: Int,
  description description: SpellDamageDescription,
) -> Row {
  Described(
    effect_id:,
    damage_type: description.damage_type,
    amount: description.health_damage_with_overkill,
    overkill: description.overkill,
    absorbed: description.absorbed,
    shield_absorbed: description.shield_absorbed,
    combat_result: combat_result.to_value(description.combat_result),
  )
}

fn property_of(property: UnitProperty) -> Property {
  Property(
    property_id: property.property_id,
    base: float_of(property.base),
    value: float_of(property.value),
  )
}

/// The float a property field's 32 bits hold, or the bits when no float is.
fn float_of(number: Int) -> Result(Float, Int) {
  let assert Ok(bits) = float32.bits(number) as "a property field is 32 bits"
  case float32.value(bits) {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error(number)
  }
}

// ---- the lines ----

/// The line a person reads for the effect: numbers and ids as the client's
/// tables name them.
pub fn describe(effect: Effect) -> String {
  case effect {
    PressRefused(client_cast_id:, spell4_id:, result:) ->
      "cast 0x7fc: press "
      <> int.to_string(client_cast_id)
      <> " of spell "
      <> int.to_string(spell4_id)
      <> " refused with result "
      <> int.to_string(result)
    PressConfirmed(client_cast_id:, server_cast_id:) ->
      "cast 0x7fd: press "
      <> int.to_string(client_cast_id)
      <> " is cast "
      <> int.to_string(server_cast_id)
    CastStarted(
      cast_id:,
      spell4_id:,
      root_spell4_id:,
      parent_spell4_id:,
      caster_unit_id:,
    ) ->
      "cast 0x7ff: cast "
      <> int.to_string(cast_id)
      <> " of spell "
      <> int.to_string(spell4_id)
      <> " (root "
      <> int.to_string(root_spell4_id)
      <> ", parent "
      <> int.to_string(parent_spell4_id)
      <> ") by unit "
      <> int.to_string(caster_unit_id)
    CastWent(cast_id:, spell4_id:, phase:, rows:) ->
      "cast 0x7f4: cast "
      <> int.to_string(cast_id)
      <> " of spell "
      <> int.to_string(spell4_id)
      <> " goes, phase "
      <> int.to_string(phase)
      <> case rows {
        [] -> ", no targets"
        _ ->
          string.join(
            list.map(rows, fn(target) {
              let #(unit_id, rows) = target
              "; unit "
              <> int.to_string(unit_id)
              <> ": "
              <> case rows {
                [] -> "no effects"
                _ -> string.join(list.map(rows, describe_row), ", ")
              }
            }),
            "",
          )
      }
    CastTicked(cast_id:, spell4_id:, effect_id:, unit_id:, rows:) ->
      "cast 0x7f8: cast "
      <> int.to_string(cast_id)
      <> " of spell "
      <> int.to_string(spell4_id)
      <> " ticks effect "
      <> int.to_string(effect_id)
      <> " on unit "
      <> int.to_string(unit_id)
      <> ": "
      <> string.join(list.map(rows, describe_row), ", ")
    CastFinished(cast_id:, spell4_id:, caster_unit_id:) ->
      "cast 0x7fe: cast "
      <> int.to_string(cast_id)
      <> " of spell "
      <> int.to_string(spell4_id)
      <> " by unit "
      <> int.to_string(caster_unit_id)
      <> " ends"
    TargetsRemoved(cast_id:, spell4_id:, unit_ids:) ->
      "cast 0x811: cast "
      <> int.to_string(cast_id)
      <> " of spell "
      <> int.to_string(spell4_id)
      <> " loses units "
      <> string.join(list.map(unit_ids, int.to_string), " ")
    OwnHealth(unit_id:, health:) ->
      "own health 0x92f: unit "
      <> int.to_string(unit_id)
      <> " health "
      <> int.to_string(health)
    UnitStat(unit_id:, stat:, value:) ->
      "stat 0x938: unit "
      <> int.to_string(unit_id)
      <> " "
      <> stat
      <> " "
      <> int.to_string(value)
    PropertiesChanged(unit_id:, properties:) ->
      "properties 0x93a: unit "
      <> int.to_string(unit_id)
      <> case properties {
        [] -> " none"
        _ ->
          " "
          <> string.join(
            list.map(properties, fn(property) {
              "property "
              <> int.to_string(property.property_id)
              <> " base "
              <> describe_float(property.base)
              <> " value "
              <> describe_float(property.value)
            }),
            ", ",
          )
      }
  }
}

fn describe_row(row: Row) -> String {
  case row {
    EffectBit(effect_id:) -> "effect " <> int.to_string(effect_id) <> " bit"
    Described(
      effect_id:,
      damage_type:,
      amount:,
      overkill:,
      absorbed:,
      shield_absorbed:,
      combat_result:,
    ) ->
      "effect "
      <> int.to_string(effect_id)
      <> " "
      <> damage_type_name(damage_type)
      <> " amount "
      <> int.to_string(amount)
      <> case damage_type {
        damage_type.Heal | damage_type.HealShields -> " overheal "
        _ -> " overkill "
      }
      <> int.to_string(overkill)
      <> " absorbed "
      <> int.to_string(absorbed)
      <> " shield absorbed "
      <> int.to_string(shield_absorbed)
      <> " result "
      <> int.to_string(combat_result)
  }
}

fn damage_type_name(type_: DamageType) -> String {
  case type_ {
    damage_type.Physical -> "physical"
    damage_type.Tech -> "tech"
    damage_type.Magic -> "magic"
    damage_type.Heal -> "heal"
    damage_type.HealShields -> "heal shields"
    damage_type.Fall -> "fall"
    damage_type.Suffocate -> "suffocate"
    damage_type.Other(number) -> "damage type " <> int.to_string(number)
  }
}

fn describe_float(value: Result(Float, Int)) -> String {
  case value {
    Ok(value) -> float.to_string(value)
    Error(bits) -> "bits 0x" <> int.to_base16(bits)
  }
}
