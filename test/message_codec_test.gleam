//// The generated codec matches the schema. CLAUDE.md: the codec is generated,
//// states the size and byte order of every field, and is never edited by hand.
//// The full check runs this module with the other tests; `gleam run -m
//// genesis_prime/generate_messages -- check` makes the same comparison by
//// hand. These tests prove it sees a hand edit, a missing file and a stale one,
//// and that the committed files are the generated ones. Every case is planted from the generated files, so
//// no expected text is written here.

import genesis_prime/gap
import genesis_prime/message/ability_points.{AbilityPoints}
import genesis_prime/message/bit_stream
import genesis_prime/message/cast_result
import genesis_prime/message/item_charges_changed.{ItemChargesChanged}
import genesis_prime/message/item_flags_changed.{ItemFlagsChanged}
import genesis_prime/message/movement_kind_4
import genesis_prime/message/movement_path
import genesis_prime/message/movement_timed_path
import genesis_prime/message/quest_log
import genesis_prime/message/replay_level_up.{ReplayLevelUp}
import genesis_prime/message/reward_property_integer
import genesis_prime/message/shared_item
import genesis_prime/message/spell_damage_description
import genesis_prime/message/spell_missed
import genesis_prime/message/spell_started
import genesis_prime/message/vendor_items
import genesis_prime/message_generator.{
  type GeneratedFile, Edited, GeneratedFile, Missing, Stale,
}
import genesis_prime/message_schema
import gleam/list
import gleam/result
import gleam/string
import message_support
import owned_test
import simplifile

fn generated() -> List(GeneratedFile) {
  let assert Ok(files) = message_generator.generated_files()
    as "the schema file reads and is a schema"
  files
}

fn committed() -> List(GeneratedFile) {
  let assert Ok(files) = message_generator.committed_files()
    as "the committed codec files read"
  files
}

fn file_named(files: List(GeneratedFile), name: String) -> GeneratedFile {
  let assert Ok(file) =
    list.find(files, fn(file) { string.ends_with(file.path, "/" <> name) })
    as { "the schema generates " <> name }
  file
}

pub fn the_schema_generates_one_module_for_each_message_and_record_and_the_client_and_server_message_modules_test() -> Nil {
  use <- owned_test.run(5000)
  let paths =
    generated()
    |> list.map(fn(file) { file.path })
    |> list.sort(string.compare)
  assert paths
    == [
      "src/genesis_prime/message/ability_hold.gleam",
      "src/genesis_prime/message/ability_points.gleam",
      "src/genesis_prime/message/ability_tier.gleam",
      "src/genesis_prime/message/ability_tiers.gleam",
      "src/genesis_prime/message/account_entitlements.gleam",
      "src/genesis_prime/message/action_set.gleam",
      "src/genesis_prime/message/action_shortcut.gleam",
      "src/genesis_prime/message/buyback_added.gleam",
      "src/genesis_prime/message/buyback_entry.gleam",
      "src/genesis_prime/message/buyback_list.gleam",
      "src/genesis_prime/message/buyback_removed.gleam",
      "src/genesis_prime/message/camp_countdown.gleam",
      "src/genesis_prime/message/camp_finished.gleam",
      "src/genesis_prime/message/camp_request.gleam",
      "src/genesis_prime/message/cancel_cast.gleam",
      "src/genesis_prime/message/cast_ability.gleam",
      "src/genesis_prime/message/cast_activate.gleam",
      "src/genesis_prime/message/cast_objective_ability.gleam",
      "src/genesis_prime/message/cast_result.gleam",
      "src/genesis_prime/message/character_entitlement.gleam",
      "src/genesis_prime/message/character_list.gleam",
      "src/genesis_prime/message/character_list_entry.gleam",
      "src/genesis_prime/message/character_select_start.gleam",
      "src/genesis_prime/message/chat_channel_joined.gleam",
      "src/genesis_prime/message/chat_channel_result.gleam",
      "src/genesis_prime/message/chat_format.gleam",
      "src/genesis_prime/message/chat_format_article_id.gleam",
      "src/genesis_prime/message/chat_format_filter_mask.gleam",
      "src/genesis_prime/message/chat_format_item_guid.gleam",
      "src/genesis_prime/message/chat_format_item_id.gleam",
      "src/genesis_prime/message/chat_format_item_record.gleam",
      "src/genesis_prime/message/chat_format_kind_0.gleam",
      "src/genesis_prime/message/chat_format_kind_1.gleam",
      "src/genesis_prime/message/chat_format_kind_11.gleam",
      "src/genesis_prime/message/chat_format_kind_2.gleam",
      "src/genesis_prime/message/chat_format_kind_3.gleam",
      "src/genesis_prime/message/chat_format_navigation_point.gleam",
      "src/genesis_prime/message/chat_format_quest_id.gleam",
      "src/genesis_prime/message/chat_line.gleam",
      "src/genesis_prime/message/chat_line_accepted.gleam",
      "src/genesis_prime/message/chat_result.gleam",
      "src/genesis_prime/message/chat_zone_named.gleam",
      "src/genesis_prime/message/choose_realm.gleam",
      "src/genesis_prime/message/choose_resurrection.gleam",
      "src/genesis_prime/message/client_activate_unit.gleam",
      "src/genesis_prime/message/client_control_echoed.gleam",
      "src/genesis_prime/message/client_control_granted.gleam",
      "src/genesis_prime/message/client_control_withdrawn.gleam",
      "src/genesis_prime/message/client_message.gleam",
      "src/genesis_prime/message/client_option.gleam",
      "src/genesis_prime/message/client_side_interaction_result.gleam",
      "src/genesis_prime/message/client_wrapper.gleam",
      "src/genesis_prime/message/close_notice.gleam",
      "src/genesis_prime/message/combat_log.gleam",
      "src/genesis_prime/message/combat_log_cc_state.gleam",
      "src/genesis_prime/message/combat_log_cc_state_break.gleam",
      "src/genesis_prime/message/combat_log_death.gleam",
      "src/genesis_prime/message/combat_log_entry.gleam",
      "src/genesis_prime/message/combat_log_immunity.gleam",
      "src/genesis_prime/message/combat_log_modify_interrupt_armor.gleam",
      "src/genesis_prime/message/combat_log_resurrect.gleam",
      "src/genesis_prime/message/combat_log_stealth.gleam",
      "src/genesis_prime/message/combat_result.gleam",
      "src/genesis_prime/message/create_character.gleam",
      "src/genesis_prime/message/create_character_carrier.gleam",
      "src/genesis_prime/message/create_character_result.gleam",
      "src/genesis_prime/message/create_result.gleam",
      "src/genesis_prime/message/credd_exchange_request.gleam",
      "src/genesis_prime/message/crowd_control_result.gleam",
      "src/genesis_prime/message/crowd_control_state.gleam",
      "src/genesis_prime/message/currency_changed.gleam",
      "src/genesis_prime/message/currency_gained.gleam",
      "src/genesis_prime/message/damage_type.gleam",
      "src/genesis_prime/message/delete_character.gleam",
      "src/genesis_prime/message/delete_character_result.gleam",
      "src/genesis_prime/message/delete_result.gleam",
      "src/genesis_prime/message/dialog_responses_shown.gleam",
      "src/genesis_prime/message/disconnect_notice.gleam",
      "src/genesis_prime/message/disconnect_reason.gleam",
      "src/genesis_prime/message/enter_world.gleam",
      "src/genesis_prime/message/experience_gained.gleam",
      "src/genesis_prime/message/fall_value.gleam",
      "src/genesis_prime/message/fell_below_floor.gleam",
      "src/genesis_prime/message/frame_time_report.gleam",
      "src/genesis_prime/message/game_hello_reply.gleam",
      "src/genesis_prime/message/game_server_handoff.gleam",
      "src/genesis_prime/message/generic_error.gleam",
      "src/genesis_prime/message/graphics_report.gleam",
      "src/genesis_prime/message/held_entitlement.gleam",
      "src/genesis_prime/message/held_item.gleam",
      "src/genesis_prime/message/innate_index_chosen.gleam",
      "src/genesis_prime/message/innate_index_set.gleam",
      "src/genesis_prime/message/input_key_set_request.gleam",
      "src/genesis_prime/message/interaction_request.gleam",
      "src/genesis_prime/message/interaction_result.gleam",
      "src/genesis_prime/message/item_action_failed.gleam",
      "src/genesis_prime/message/item_added.gleam",
      "src/genesis_prime/message/item_charges_changed.gleam",
      "src/genesis_prime/message/item_count_changed.gleam",
      "src/genesis_prime/message/item_delete.gleam",
      "src/genesis_prime/message/item_flags_changed.gleam",
      "src/genesis_prime/message/item_move.gleam",
      "src/genesis_prime/message/item_moved.gleam",
      "src/genesis_prime/message/item_place.gleam",
      "src/genesis_prime/message/item_removed.gleam",
      "src/genesis_prime/message/item_split.gleam",
      "src/genesis_prime/message/item_use.gleam",
      "src/genesis_prime/message/item_visual.gleam",
      "src/genesis_prime/message/items_swapped.gleam",
      "src/genesis_prime/message/leave_world.gleam",
      "src/genesis_prime/message/login_accepted.gleam",
      "src/genesis_prime/message/login_refused.gleam",
      "src/genesis_prime/message/login_request.gleam",
      "src/genesis_prime/message/max_character_level.gleam",
      "src/genesis_prime/message/miss_reason.gleam",
      "src/genesis_prime/message/move_speed_setting.gleam",
      "src/genesis_prime/message/movement_command.gleam",
      "src/genesis_prime/message/movement_face_point.gleam",
      "src/genesis_prime/message/movement_face_unit.gleam",
      "src/genesis_prime/message/movement_float_vector.gleam",
      "src/genesis_prime/message/movement_half_vector.gleam",
      "src/genesis_prime/message/movement_kind_10.gleam",
      "src/genesis_prime/message/movement_kind_12.gleam",
      "src/genesis_prime/message/movement_kind_13.gleam",
      "src/genesis_prime/message/movement_kind_15.gleam",
      "src/genesis_prime/message/movement_kind_16.gleam",
      "src/genesis_prime/message/movement_kind_17.gleam",
      "src/genesis_prime/message/movement_kind_20.gleam",
      "src/genesis_prime/message/movement_kind_21.gleam",
      "src/genesis_prime/message/movement_kind_22.gleam",
      "src/genesis_prime/message/movement_kind_23.gleam",
      "src/genesis_prime/message/movement_kind_25.gleam",
      "src/genesis_prime/message/movement_kind_26.gleam",
      "src/genesis_prime/message/movement_kind_28.gleam",
      "src/genesis_prime/message/movement_kind_29.gleam",
      "src/genesis_prime/message/movement_kind_3.gleam",
      "src/genesis_prime/message/movement_kind_4.gleam",
      "src/genesis_prime/message/movement_kind_5.gleam",
      "src/genesis_prime/message/movement_kind_6.gleam",
      "src/genesis_prime/message/movement_kind_7.gleam",
      "src/genesis_prime/message/movement_kind_9.gleam",
      "src/genesis_prime/message/movement_mode.gleam",
      "src/genesis_prime/message/movement_move_asked.gleam",
      "src/genesis_prime/message/movement_path.gleam",
      "src/genesis_prime/message/movement_platform.gleam",
      "src/genesis_prime/message/movement_rotation.gleam",
      "src/genesis_prime/message/movement_send_interval.gleam",
      "src/genesis_prime/message/movement_send_interval_answer.gleam",
      "src/genesis_prime/message/movement_state_flags.gleam",
      "src/genesis_prime/message/movement_time.gleam",
      "src/genesis_prime/message/movement_timed_path.gleam",
      "src/genesis_prime/message/movement_velocity.gleam",
      "src/genesis_prime/message/network_report.gleam",
      "src/genesis_prime/message/own_auctions_request.gleam",
      "src/genesis_prime/message/own_commodity_orders_request.gleam",
      "src/genesis_prime/message/ping.gleam",
      "src/genesis_prime/message/play_character.gleam",
      "src/genesis_prime/message/play_character_refused.gleam",
      "src/genesis_prime/message/play_refusal.gleam",
      "src/genesis_prime/message/player_character_state.gleam",
      "src/genesis_prime/message/player_entered_world.gleam",
      "src/genesis_prime/message/player_health.gleam",
      "src/genesis_prime/message/player_movement.gleam",
      "src/genesis_prime/message/player_path.gleam",
      "src/genesis_prime/message/player_pet.gleam",
      "src/genesis_prime/message/pong.gleam",
      "src/genesis_prime/message/pre_game_activity.gleam",
      "src/genesis_prime/message/premium_tier.gleam",
      "src/genesis_prime/message/quest_abandon.gleam",
      "src/genesis_prime/message/quest_accept.gleam",
      "src/genesis_prime/message/quest_active.gleam",
      "src/genesis_prime/message/quest_completed.gleam",
      "src/genesis_prime/message/quest_ignore.gleam",
      "src/genesis_prime/message/quest_known.gleam",
      "src/genesis_prime/message/quest_log.gleam",
      "src/genesis_prime/message/quest_mention.gleam",
      "src/genesis_prime/message/quest_objective_progress.gleam",
      "src/genesis_prime/message/quest_periodic_reset.gleam",
      "src/genesis_prime/message/quest_retry.gleam",
      "src/genesis_prime/message/quest_spell_shortcut.gleam",
      "src/genesis_prime/message/quest_state.gleam",
      "src/genesis_prime/message/quest_track.gleam",
      "src/genesis_prime/message/quest_turn_in.gleam",
      "src/genesis_prime/message/realm_entry.gleam",
      "src/genesis_prime/message/realm_handoff.gleam",
      "src/genesis_prime/message/realm_list.gleam",
      "src/genesis_prime/message/realm_select_start.gleam",
      "src/genesis_prime/message/relayed_movement.gleam",
      "src/genesis_prime/message/rename_character.gleam",
      "src/genesis_prime/message/rename_character_result.gleam",
      "src/genesis_prime/message/rename_result.gleam",
      "src/genesis_prime/message/replay_level_up.gleam",
      "src/genesis_prime/message/reputation.gleam",
      "src/genesis_prime/message/reputation_list.gleam",
      "src/genesis_prime/message/resurrection_window.gleam",
      "src/genesis_prime/message/reward_properties.gleam",
      "src/genesis_prime/message/reward_property_entry.gleam",
      "src/genesis_prime/message/reward_property_integer.gleam",
      "src/genesis_prime/message/reward_property_modifier.gleam",
      "src/genesis_prime/message/scanbot_request.gleam",
      "src/genesis_prime/message/send_chat_line.gleam",
      "src/genesis_prime/message/send_whisper.gleam",
      "src/genesis_prime/message/server_hello.gleam",
      "src/genesis_prime/message/server_message.gleam",
      "src/genesis_prime/message/server_tutorial.gleam",
      "src/genesis_prime/message/shared_item.gleam",
      "src/genesis_prime/message/spell_cast_confirmed.gleam",
      "src/genesis_prime/message/spell_cast_refused.gleam",
      "src/genesis_prime/message/spell_damage_description.gleam",
      "src/genesis_prime/message/spell_effect_bit.gleam",
      "src/genesis_prime/message/spell_effect_damage.gleam",
      "src/genesis_prime/message/spell_effect_info.gleam",
      "src/genesis_prime/message/spell_effect_result.gleam",
      "src/genesis_prime/message/spell_effect_tick.gleam",
      "src/genesis_prime/message/spell_failed.gleam",
      "src/genesis_prime/message/spell_finished.gleam",
      "src/genesis_prime/message/spell_go.gleam",
      "src/genesis_prime/message/spell_hit_entry.gleam",
      "src/genesis_prime/message/spell_initial_position.gleam",
      "src/genesis_prime/message/spell_miss.gleam",
      "src/genesis_prime/message/spell_missed.gleam",
      "src/genesis_prime/message/spell_missile_info.gleam",
      "src/genesis_prime/message/spell_position.gleam",
      "src/genesis_prime/message/spell_stack_removed.gleam",
      "src/genesis_prime/message/spell_started.gleam",
      "src/genesis_prime/message/spell_target_info.gleam",
      "src/genesis_prime/message/spell_targets_removed.gleam",
      "src/genesis_prime/message/spell_telegraph_position.gleam",
      "src/genesis_prime/message/spell_threshold_closed.gleam",
      "src/genesis_prime/message/spell_threshold_ended.gleam",
      "src/genesis_prime/message/spell_threshold_index.gleam",
      "src/genesis_prime/message/spell_threshold_opened.gleam",
      "src/genesis_prime/message/start_movement.gleam",
      "src/genesis_prime/message/static_unit_type.gleam",
      "src/genesis_prime/message/terrain_loaded.gleam",
      "src/genesis_prime/message/text_group.gleam",
      "src/genesis_prime/message/trade_cancel.gleam",
      "src/genesis_prime/message/unit_cc_state_applied.gleam",
      "src/genesis_prime/message/unit_cc_state_ended.gleam",
      "src/genesis_prime/message/unit_combat_state.gleam",
      "src/genesis_prime/message/unit_create_creature.gleam",
      "src/genesis_prime/message/unit_create_door.gleam",
      "src/genesis_prime/message/unit_create_ghost.gleam",
      "src/genesis_prime/message/unit_create_mailbox.gleam",
      "src/genesis_prime/message/unit_create_player.gleam",
      "src/genesis_prime/message/unit_create_portal.gleam",
      "src/genesis_prime/message/unit_create_static.gleam",
      "src/genesis_prime/message/unit_create_tail.gleam",
      "src/genesis_prime/message/unit_death_state.gleam",
      "src/genesis_prime/message/unit_destroyed.gleam",
      "src/genesis_prime/message/unit_dialog_open.gleam",
      "src/genesis_prime/message/unit_float_stat_changed.gleam",
      "src/genesis_prime/message/unit_health.gleam",
      "src/genesis_prime/message/unit_is_player.gleam",
      "src/genesis_prime/message/unit_item_visuals_changed.gleam",
      "src/genesis_prime/message/unit_movement.gleam",
      "src/genesis_prime/message/unit_position_command.gleam",
      "src/genesis_prime/message/unit_properties_changed.gleam",
      "src/genesis_prime/message/unit_property.gleam",
      "src/genesis_prime/message/unit_stat.gleam",
      "src/genesis_prime/message/unit_stat_absorption.gleam",
      "src/genesis_prime/message/unit_stat_change.gleam",
      "src/genesis_prime/message/unit_stat_changed.gleam",
      "src/genesis_prime/message/unit_stat_float.gleam",
      "src/genesis_prime/message/unit_stat_integer.gleam",
      "src/genesis_prime/message/unit_stat_interrupt_armor.gleam",
      "src/genesis_prime/message/unit_stat_level.gleam",
      "src/genesis_prime/message/unit_stat_shield.gleam",
      "src/genesis_prime/message/unit_stat_value.gleam",
      "src/genesis_prime/message/unit_stealth.gleam",
      "src/genesis_prime/message/unit_target.gleam",
      "src/genesis_prime/message/unit_tether_anchor.gleam",
      "src/genesis_prime/message/unit_threat.gleam",
      "src/genesis_prime/message/vendor_buyback.gleam",
      "src/genesis_prime/message/vendor_item.gleam",
      "src/genesis_prime/message/vendor_items.gleam",
      "src/genesis_prime/message/vendor_price_slot.gleam",
      "src/genesis_prime/message/vendor_purchase.gleam",
      "src/genesis_prime/message/vendor_sale.gleam",
      "src/genesis_prime/message/vendor_sell_junk.gleam",
      "src/genesis_prime/message/vendor_tab.gleam",
      "src/genesis_prime/message/watchdog_report.gleam",
      "src/genesis_prime/message/whisper_failed.gleam",
      "src/genesis_prime/message/window_opened.gleam",
      "src/genesis_prime/message/world_loading_screen_shown.gleam",
      "src/genesis_prime/message/world_message.gleam",
      "src/genesis_prime/message/world_zone_changed.gleam",
    ]
    as "the schema holds the 13 Milestone 1 messages of the issue and the 2 records inside the realm list, the 21 messages and 5 records of character select and entering the world, the network layer's 3 messages (ping, pong and close notice), the auth server's login refusal 0x63d, the 5 modules of the named values (the disconnect reasons, the create results, the play refusals, the delete results and the rename results), the 6 messages of the player moving that the client sends (0x637, 0x63a, 0xd5, 0x63b, 0xfb and 0xfc) with the union of the 30 movement commands, the 29 records its kinds read (kind 2 is the unit position command of 0x262) and the 2 records of their lists of vectors, the union of the two movement commands the server writes in 0x262 (kinds 2 and 14), the account's premium tier 0x97f and entitlements 0x968 with the record of one held entitlement, the 8 chat messages (0x1c3, 0x1d4, 0x1c2, 0x1c8, 0x1d3, 0x1d9, 0x1bc and 0x1da) with the union of the chat formats the client's reader takes (the 12 types, with the 12 records of their data) and the module of the chat results' named values, the 27 messages of combat core (the press 0x9a, the activate cast 0x97, the ability item 0x111, the ability tiers 0x1a0, the action set 0x19d, a creature's and a ghost's 0x262, the cast messages 0x7fc, 0x7fd, 0x7ff, 0x7f4, 0x7fe and 0x801, the cast taken off units 0x811 and the stack removed 0x813, the threshold messages 0x814 to 0x817, health 0x937 and 0x92f, a stat 0x938 and a float stat 0x935, the properties changed 0x93a, death 0x88c, threat 0x908 and 0x90a, combat 0x89a, the resurrection window 0x1b3 and choice 0x15a, and the combat log 0x247), the tick of a periodic effect 0x7f8, the unit stealth 0x8f5 with the combat log record of type 24, the one of type 18 (an immunity) and the one of type 14 (interrupt armor lost), the tether anchor 0x881, the unit's item visuals changed 0x933 (with the item visual record the 0x262's list also holds), the player character's own state 0x25e with the records of its items, reputations, pets and entitlements, with the records and unions inside them, the kind 4 path of the unit's move, the one record of the tail every unit create ends with and the union of a stat's two forms with their two records, and the modules of the named values (the cast results, the combat results and the damage types), the 13 reports and requests the client sends and the server drops (genesis_prime/game/dropped), the quest log 0x35f with the records of its completed, known and active quests and the periodic reset 0x362, the experience gained 0x1ac with the level form of a stat's value, the vendor's window 0x90b with the records of its tab, item and price slot, the buyback list 0xbc, the entry added 0xba with its record and the entry removed 0xbd, the credits' new total 0x919, the vendor purchase 0xbe, the vendor sale 0x166, the sale of junk 0x167 and the buy back 0xbb and the generic error 0x106, the cast's client-side interaction answer 0x805 with its result values, the two frames of an in-world move only the server writes (the loading screen shown 0x83c and the control withdrawn 0x639), and the client message module that decodes every message the client sends by its number"
}

pub fn the_committed_codec_is_what_the_schema_generates_test() -> Nil {
  use <- owned_test.run(10_000)
  assert message_generator.mismatches(generated(), committed()) == []
    as "CLAUDE.md: the codec is generated and never edited by hand; run `gleam run -m genesis_prime/generate_messages`"
}

pub fn a_planted_hand_edit_to_a_generated_file_is_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let target = file_named(files, "server_hello.gleam")
  let edited =
    list.map(files, fn(file) {
      case file == target {
        True -> GeneratedFile(..file, text: file.text <> "\n// a hand edit\n")
        False -> file
      }
    })
  assert message_generator.mismatches(files, edited) == [Edited(target.path)]
    as "a committed file that differs from the generated text is named"
  let narrowed =
    list.map(files, fn(file) {
      case file == target {
        True ->
          GeneratedFile(
            ..file,
            text: string.replace(
              file.text,
              "\"unread_7\", message.unread_7, 5)",
              "\"unread_7\", message.unread_7, 6)",
            ),
          )
        False -> file
      }
    })
  assert narrowed != files
    as "the planted edit changes a field's width in the generated text"
  assert message_generator.mismatches(files, narrowed) == [Edited(target.path)]
    as "a one-digit edit to a width is seen"
}

pub fn a_generated_file_that_is_not_committed_is_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let target = file_named(files, "realm_list.gleam")
  let without = list.filter(files, fn(file) { file != target })
  assert message_generator.mismatches(files, without) == [Missing(target.path)]
    as "a file the schema generates and the repository lacks is named"
}

pub fn a_committed_generated_file_the_schema_no_longer_generates_is_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let old =
    GeneratedFile(
      path: "src/genesis_prime/message/removed_message.gleam",
      text: message_generator.generated_marker <> " from an older schema\n",
    )
  assert message_generator.mismatches(files, [old, ..files])
    == [Stale(old.path)]
    as "a generated file with no message or record in the schema is named"
}

pub fn a_hand_written_module_beside_the_generated_ones_is_not_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let hand_written =
    GeneratedFile(
      path: "src/genesis_prime/message/bit_stream.gleam",
      text: "//// How a message body is written and read.\n",
    )
  assert message_generator.mismatches(files, [hand_written, ..files]) == []
    as "only files that carry the generated marker are compared"
}

pub fn a_generated_encoder_states_the_width_of_every_field_test() -> Nil {
  use <- owned_test.run(10_000)
  let text = file_named(generated(), "server_hello.gleam").text
  assert string.contains(
    text,
    "bit_stream.write_unsigned(\"build\", message.build, 32)",
  )
    as "ReadMessage0003Body 0x1400a9140: the build is 32 bits, written in the code"
  assert string.contains(
    text,
    "bit_stream.write_unsigned(\"unread_5\", message.unread_5, 64)",
  )
    as "ReadMessage0003Body 0x1400a9140: the fifth value is 64 bits"
  assert string.contains(
    text,
    "bit_stream.write_unsigned(\"unread_7\", message.unread_7, 5)",
  )
    as "ReadMessage0003Body 0x1400a9140: the seventh value is 5 bits"
  assert string.contains(text, "bit_stream.read_unsigned(reader, 5)")
    as "the reader states the same width"
}

/// `opcode.0xca`: the client's reader (0x14008de20) takes the item's guid as a 64-bit value
/// and then 32 bits for the charges, so the body is those 96 bits, low byte first, and
/// nothing else. No recording holds the message.
pub fn item_charges_changed_reads_in_the_client_order_test() -> Nil {
  use <- owned_test.run(5000)
  let body = <<0x0123_4567_89AB_CDEF:64-little, 99:32-little>>
  assert item_charges_changed.decode(body)
    == Ok(ItemChargesChanged(item_guid: 0x0123_4567_89AB_CDEF, charges: 99))
    as "the guid is the first 64 bits and the charges the next 32"
  assert item_charges_changed.encode(ItemChargesChanged(
      item_guid: 0x0123_4567_89AB_CDEF,
      charges: 99,
    ))
    == Ok(body)
    as "the message writes the same bits"
  assert result.is_error(
    item_charges_changed.decode(<<
      0x0123_4567_89AB_CDEF:64-little,
      99:31-little,
    >>),
  )
    as "a body one bit short is refused"
}

/// `opcode.0x567.reader`: the client's reader (0x1400a48d0) takes the item's guid as a
/// 64-bit value and then 8 bits for the flags, so the body is those 72 bits, low byte first,
/// and nothing else. No recording holds the message.
pub fn item_flags_changed_reads_in_the_client_order_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([0x09, 0xFF], fn(flags) {
    let body = <<0x0123_4567_89AB_CDEF:64-little, flags:8>>
    assert item_flags_changed.decode(body)
      == Ok(ItemFlagsChanged(
        item_guid: 0x0123_4567_89AB_CDEF,
        item_flags: flags,
      ))
      as "the guid is the first 64 bits and the flags the next 8"
    assert item_flags_changed.encode(ItemFlagsChanged(
        item_guid: 0x0123_4567_89AB_CDEF,
        item_flags: flags,
      ))
      == Ok(body)
      as "the message writes the same bits"
  })
  assert result.is_error(
    item_flags_changed.decode(<<0x0123_4567_89AB_CDEF:64-little, 9:7>>),
  )
    as "a body one bit short is refused"
}

/// `table_rows -- Spell4CastResult 25`: the result 25 is ItemCharges; the values around it
/// that the schema names keep their numbers (22 ItemBad, 26 ItemTooHighLevel).
pub fn cast_result_25_is_item_charges_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_result.from_value(25) == cast_result.ItemCharges
    as "the value 25 names ItemCharges"
  assert cast_result.to_value(cast_result.ItemCharges) == 25
  assert cast_result.from_value(22) == cast_result.ItemBad
    && cast_result.from_value(26) == cast_result.ItemTooHighLevel
    as "the named neighbours are unchanged"
}

/// `opcode.0x169`: the client's reader (0x14007a040) takes two 32-bit values, the points to
/// spend and then the total, low byte first, and nothing else. No recording holds the
/// message, so the bodies are written by hand from the reader's layout, with fields that
/// differ so a swap fails.
pub fn the_ability_points_are_the_points_to_spend_then_the_total_in_32_bits_each_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "both zero",
        <<0:32-little, 0:32-little>>,
        AbilityPoints(ability_points: 0, total_ability_points: 0),
      ),
      #(
        "3 to spend of 41",
        <<3, 0, 0, 0, 41, 0, 0, 0>>,
        AbilityPoints(ability_points: 3, total_ability_points: 41),
      ),
      #(
        "the total fills its 32 bits",
        <<1, 0, 0, 0, 4, 3, 2, 1>>,
        AbilityPoints(ability_points: 1, total_ability_points: 0x01020304),
      ),
    ],
    fn(case_) {
      let #(name, body, value) = case_
      message_support.assert_codec(
        name:,
        body:,
        value:,
        encode: ability_points.encode,
        decode: ability_points.decode,
      )
    },
  )
}

/// `opcode.0x7a5`: the client's writer (`WriteUint32Body 0x14007d010`) writes one 32-bit
/// level, low byte first, and the client has no reader, so no body is received. The writer's
/// emulator vector is the one `vector.opcode.0x7df.body` holds, since the same writer
/// serves 0x07DF.
pub fn the_replay_level_up_is_one_32_bit_level_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("level 4", <<4, 0, 0, 0>>, 4),
      #("level 50, the highest the unlocks window lists", <<0x32, 0, 0, 0>>, 50),
      #("byte order: the low byte comes first", <<4, 3, 2, 1>>, 0x01020304),
      #("the largest of 32 bits", <<0xFF, 0xFF, 0xFF, 0xFF>>, 0xFFFFFFFF),
    ],
    fn(case_) {
      let #(name, body, level) = case_
      message_support.assert_codec(
        name:,
        body:,
        value: ReplayLevelUp(level:),
        encode: replay_level_up.encode,
        decode: replay_level_up.decode,
      )
    },
  )
  assert replay_level_up.decode(<<>>) == Error(bit_stream.EndOfData)
    as "an empty body ends inside the level"
  assert replay_level_up.decode(<<4, 0, 0>>) == Error(bit_stream.EndOfData)
    as "three bytes end inside the 32-bit level"
  assert replay_level_up.decode(<<4, 0, 0, 0, 0>>)
    == Error(bit_stream.TrailingBytes(count: 1))
    as "the client's writer adds 32 bits, so a body of five bytes is longer than any the client writes"
}

/// The `gaps()` of each generated module the schema gives gaps, by the module's name.
fn generated_gaps() -> List(#(String, List(gap.Entry))) {
  [
    #("movement_kind_4", movement_kind_4.gaps()),
    #("movement_path", movement_path.gaps()),
    #("movement_timed_path", movement_timed_path.gaps()),
    #("quest_log", quest_log.gaps()),
    #("reward_property_integer", reward_property_integer.gaps()),
    #("shared_item", shared_item.gaps()),
    #("spell_damage_description", spell_damage_description.gaps()),
    #("spell_missed", spell_missed.gaps()),
    #("spell_started", spell_started.gaps()),
    #("vendor_items", vendor_items.gaps()),
  ]
}

pub fn the_committed_message_modules_equal_the_generator_output_and_hold_each_schema_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  assert message_generator.mismatches(generated(), committed()) == []
    as "regeneration of the real schema reproduces every committed module"
  let assert Ok(text) = simplifile.read(message_generator.schema_path)
    as "the schema file reads"
  let assert Ok(schema) = message_schema.parse(text)
    as "the schema file is a schema"
  let schema_gaps =
    list.append(
      list.map(schema.messages, fn(message) { #(message.name, message.gaps) }),
      list.map(schema.records, fn(record) { #(record.name, record.gaps) }),
    )
    |> list.filter(fn(named) { named.1 != [] })
  assert list.sort(list.map(schema_gaps, fn(named) { named.0 }), string.compare)
    == list.sort(
      list.map(generated_gaps(), fn(named) { named.0 }),
      string.compare,
    )
    as "the modules this test checks are the messages and records the schema lists gaps for"
  list.each(schema_gaps, fn(named) {
    let #(name, schema_entries) = named
    let assert Ok(#(_, module_entries)) =
      list.find(generated_gaps(), fn(found) { found.0 == name })
      as { "the test lists the gaps of " <> name }
    assert module_entries
      == list.map(schema_entries, fn(entry) {
        gap.Entry(area: entry.area, missing: entry.missing)
      })
      as { name <> "'s gaps() holds the schema's entries, in order" }
  })
}
