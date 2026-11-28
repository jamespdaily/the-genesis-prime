//// The real rows of the order cover: one row for the listed variants of a told type, with
//// the cover that names the test or the reason. `told` lists the types whose every variant
//// has a row (`rows`), `families` the other inputs of the relation table, which are read
//// from their types or, for the connection's timers, from the arms that tell them apart
//// (`family_rows`).
////
//// - `Order` names a test that sends the variant itself, written as the type's constructor
////   in the test or the test support it reaches (`order_coverage.breaches_of`), in the orders
////   it can arrive in.
//// - `Owner` names the test of the decision the variant's owner makes on it, among them the
////   variants the code under test sends and the test only drives, by a client's bytes or a
////   timer, and sees the effect of.
//// - `Independent` gives why the relation does not read the variant: the map relays a news
////   unread (it reads only `Appeared`, the first of a snapshot), and the creature's own
////   decisions on facts the stream delivered meet it in the creature's mailbox, each
////   stream input complete when delivered.

import code_rule/order_coverage.{type Row, Independent, Order, Owner, Row}
import code_rule/source.{type SourceFile}
import gleam/list
import gleam/string

const connection = "genesis_prime/client_connection"

const news = "genesis_prime/shared/unit_news"

const map_message = "genesis_prime/map/message"

const creature = "genesis_prime/world_map/creature"

const fight = "genesis_prime/world_map/creature_fight"

const guard = "genesis_prime/world_map/creature_guard"

const the_connection = "genesis_prime/game/connection"

/// The types whose every variant has a row in `rows`: `#(module, type name)`.
pub fn told() -> List(#(String, String)) {
  [
    #(connection, "StaySent"),
    #(news, "News"),
    #(map_message, "Notice"),
    #(map_message, "Delivered"),
    #(map_message, "Payload"),
    #(map_message, "Inbound"),
    #(map_message, "Landing"),
    #(creature, "Message"),
    #(map_message, "Message"),
  ]
}

const unread_news =
  "the map relays it unread, in the order its owner sent it, on the one broadcast path of every news but Appeared"

const only_the_map =
  "only the map sends it, from its own handlers, for static objects no owner process streams, so no other sender's fact orders against it"

const lifecycle_input =
  "the creature's shell turns the creature message of the same meaning into it, and that message has its row"

const own_decision =
  "the creature's own decision on facts the stream delivered, taken in the creature's mailbox where each stream input is complete when delivered"

const not_a_relation_fact =
  "it does not meet a relation fact and the map does not touch it, and it is held while an ask is out"

const fenced_ask =
  "a fenced lifecycle ask: its answer is taken as the ask's outcome and the map does not order it against a stream"

/// The rows for the types the map and the processes tell each other.
pub fn rows() -> List(Row) {
  list.flatten([
    stay_sent(),
    news_rows(),
    notice_rows(),
    delivered_rows(),
    payload_rows(),
    inbound_rows(),
    landing_rows(),
    creature_message_rows(),
    map_message_rows(),
  ])
}

fn stay_sent() -> List(Row) {
  [
    Row(
      module: connection,
      type_name: "StaySent",
      variants: ["SentByPlayer"],
      cover: Order(
        "player_streams_test.a_heal_the_map_accepted_before_its_caster_left_sight_is_applied_and_one_for_a_stay_the_player_left_after_the_map_accepted_it_is_dropped_at_the_connection_test",
      ),
    ),
    Row(
      module: connection,
      type_name: "StaySent",
      variants: ["SentByKill"],
      cover: Owner(
        "game_connection_held_map_test.a_held_message_for_another_stay_is_dropped_when_taken_test",
      ),
    ),
    Row(
      module: connection,
      type_name: "StaySent",
      variants: ["SentByLine"],
      cover: Owner(
        "game_connection_chat_test.a_line_queued_across_a_same_run_re_entry_is_dropped_by_the_stay_fence_test",
      ),
    ),
    Row(
      module: connection,
      type_name: "StaySent",
      variants: ["SentByPeer", "SentByMove"],
      cover: Owner(
        "game_connection_viewers_test.news_for_another_stay_is_dropped_for_each_kind_and_this_stays_is_written_test",
      ),
    ),
    Row(
      module: connection,
      type_name: "StaySent",
      variants: ["SentByMap"],
      cover: Owner(
        "game_connection_viewers_test.an_object_notice_for_another_stay_is_dropped_test",
      ),
    ),
    Row(
      module: connection,
      type_name: "StaySent",
      variants: ["SentByFoe", "SentByTarget"],
      cover: Owner(
        "map_relay_test.a_relay_from_an_address_that_ended_is_not_admitted_by_the_map_test",
      ),
    ),
  ]
}

fn news_rows() -> List(Row) {
  [
    Row(
      module: news,
      type_name: "News",
      variants: ["Appeared"],
      cover: Owner(
        "player_streams_test.a_pair_is_shown_by_the_owners_snapshot_and_one_that_leaves_and_returns_is_two_generations_and_needs_a_new_snapshot_in_every_legal_order_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CreatureAppeared", "Health"],
      cover: Owner(
        "legal_order_test.a_viewer_that_arrives_or_leaves_as_the_creature_expires_is_shown_one_picture_in_every_legal_order_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["Removed"],
      cover: Owner(
        "legal_order_test.a_viewer_that_arrives_or_leaves_as_the_creature_expires_is_shown_one_picture_in_every_legal_order_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CastStarted", "CastWent", "HeldCastStarted"],
      cover: Owner(
        "player_streams_test.an_ally_start_is_taken_after_its_casters_start_at_every_viewer_in_every_legal_order_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CastFinished"],
      cover: Owner(
        "player_streams_test.a_cast_finished_at_a_viewer_before_the_allys_start_through_the_maps_relays_is_written_the_finish_and_no_start_in_both_orders_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["HeldCastEnded"],
      cover: Owner(
        "game_connection_viewers_test.a_cast_an_ally_listed_is_ended_for_the_viewer_by_the_ally_only_when_its_caster_did_not_tell_the_viewer_the_cast_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CastTicked", "CastTargetsRemoved"],
      cover: Owner(
        "game_connection_viewers_test.a_cast_the_viewer_holds_as_written_gets_its_casters_frames_a_cast_it_never_got_the_start_of_gets_none_and_a_borrowed_one_none_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CastStackRemoved"],
      cover: Owner(
        "game_connection_lasting_test.a_viewer_writes_0x811_and_0x813_only_for_a_cast_whose_start_it_wrote_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CasterRestrictionApplied", "CasterRestrictionEnded"],
      cover: Owner(
        "game_connection_viewers_test.a_casters_own_restriction_news_is_written_only_for_a_cast_held_as_written_and_its_end_only_for_an_instance_the_picture_holds_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CrowdControlApplied", "CrowdControlEnded"],
      cover: Owner(
        "game_connection_viewers_test.a_shown_units_crowd_control_news_is_written_as_0x87f_and_0x880_and_none_for_a_unit_not_shown_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["InterruptArmor"],
      cover: Owner(
        "game_connection_viewers_test.a_shown_units_interrupt_armor_news_is_written_as_0x938_of_stat_21_and_none_for_a_unit_not_shown_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["LookChanged"],
      cover: Owner(
        "game_connection_look_test.a_viewer_that_shows_the_unit_writes_its_0x933_and_one_that_does_not_writes_nothing_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["Died", "CameBack", "DeathLogged", "CameBackLogged"],
      cover: Owner(
        "game_connection_death_test.a_viewer_writes_a_players_death_and_coming_back_as_the_clients_frames_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CreatureFaces"],
      cover: Owner(
        "game_connection_fight_test.a_viewer_writes_a_creatures_facing_as_0x638_only_when_the_unit_is_shown_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: ["CombatState"],
      cover: Owner(
        "shown_test.combat_news_marks_only_a_shown_creature_in_combat_test",
      ),
    ),
    Row(
      module: news,
      type_name: "News",
      variants: [
        "CastMissed",
        "CastInterrupted",
        "CreatureMoved",
        "CreaturePlaced",
        "Targeting",
        "Threat",
        "Shield",
        "Absorption",
        "Level",
        "UnitStateHeld",
        "UnitStateEnded",
        "PropertiesChanged",
        "Stealth",
      ],
      cover: Independent(unread_news),
    ),
  ]
}

fn notice_rows() -> List(Row) {
  [
    Row(
      module: map_message,
      type_name: "Notice",
      variants: ["SeenBy"],
      cover: Owner(
        "player_streams_test.the_other_player_that_shows_a_player_who_joins_again_is_written_its_0x355_then_its_new_0x262_and_its_heals_reach_the_new_stay_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Notice",
      variants: ["UnseenBy"],
      cover: Owner(
        "player_streams_test.a_move_that_takes_a_viewer_out_of_sight_is_written_before_its_0x355_or_not_at_all_and_never_after_it_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Notice",
      variants: ["PlayerUnseen"],
      cover: Owner(
        "player_streams_test.a_viewer_that_leaves_the_casters_sight_between_its_go_and_the_allys_start_borrows_the_cast_on_the_ally_in_both_orders_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Notice",
      variants: ["UnitUnseen"],
      cover: Owner(
        "legal_order_test.an_unseen_and_the_creatures_news_write_nothing_after_the_unit_is_removed_in_every_legal_order_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Notice",
      variants: ["Gone"],
      cover: Owner(
        "map_relay_test.a_snapshot_in_the_maps_mailbox_when_its_creature_ends_is_relayed_and_gone_follows_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Notice",
      variants: ["ObjectsSeen", "ObjectsUnseen"],
      cover: Independent(only_the_map),
    ),
  ]
}

fn delivered_rows() -> List(Row) {
  [
    Row(
      module: map_message,
      type_name: "Delivered",
      variants: ["News"],
      cover: Owner(
        "world_relay_test.a_viewer_writes_the_creatures_snapshot_and_then_its_news_in_the_order_the_map_relayed_them_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Delivered",
      variants: ["Tell"],
      cover: Owner(
        "map_relay_test.a_relay_from_an_address_that_ended_is_not_admitted_by_the_map_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Delivered",
      variants: ["Landed"],
      cover: Owner(
        "map_player_relation_test.each_player_to_player_effect_is_delivered_by_its_kinds_checks_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Delivered",
      variants: ["Said"],
      cover: Owner(
        "player_streams_test.a_players_line_is_relayed_to_its_relaying_viewers_with_their_stay_and_before_the_snapshot_a_viewer_is_told_nothing_test",
      ),
    ),
  ]
}

fn payload_rows() -> List(Row) {
  [
    Row(
      module: map_message,
      type_name: "Payload",
      variants: ["Struck", "KillCredit"],
      cover: Owner(
        "world_relay_test.the_caster_is_told_the_answer_the_credit_and_the_health_news_in_that_order_while_the_maps_sends_are_held_back_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Payload",
      variants: ["Fight"],
      cover: Owner(
        "map_relay_test.a_relay_from_an_address_that_ended_is_not_admitted_by_the_map_test",
      ),
    ),
  ]
}

fn inbound_rows() -> List(Row) {
  [
    Row(
      module: map_message,
      type_name: "Inbound",
      variants: ["Strike"],
      cover: Order(
        "legal_order_test.a_strike_and_the_senders_move_out_of_sight_are_taken_in_the_order_the_sender_told_them_and_each_order_has_its_own_result_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Inbound",
      variants: ["StrikeAnswered"],
      cover: Order(
        "map_ring_test.the_map_relays_a_players_killing_answer_its_death_and_its_wake_to_a_creature_in_the_order_the_connection_told_them_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Inbound",
      variants: [
        "TargetMoved",
        "ModifierStarts",
        "ModifierEnds",
        "Thrown",
        "Despawn",
        "UnitStates",
        "CastViewSet",
        "CastViewEnds",
        "ControlsEnd",
      ],
      cover: Owner(
        "map_relay_test.a_players_tell_is_delivered_to_a_running_creature_unchanged_and_dropped_for_an_ended_one_or_an_earlier_life_test",
      ),
    ),
  ]
}

fn landing_rows() -> List(Row) {
  [
    Row(
      module: map_message,
      type_name: "Landing",
      variants: ["HealStrike"],
      cover: Owner(
        "player_streams_test.a_heal_the_map_accepted_before_its_caster_left_sight_is_applied_and_one_for_a_stay_the_player_left_after_the_map_accepted_it_is_dropped_at_the_connection_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Landing",
      variants: ["ChangeStart"],
      cover: Order(
        "player_streams_test.a_change_told_to_a_player_before_it_took_the_notice_of_its_caster_is_applied_in_every_order_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Landing",
      variants: ["HealAnswer", "ChangeEnd", "CastWent", "AllyEvent"],
      cover: Owner(
        "map_player_relation_test.each_player_to_player_effect_is_delivered_by_its_kinds_checks_test",
      ),
    ),
  ]
}

fn creature_message_rows() -> List(Row) {
  [
    Row(
      module: creature,
      type_name: "Message",
      variants: ["Seen"],
      cover: Owner(
        "legal_order_test.news_before_a_snapshot_and_a_snapshot_of_an_earlier_generation_are_dropped_in_every_legal_order_test",
      ),
    ),
    Row(
      module: creature,
      type_name: "Message",
      variants: ["Unseen"],
      cover: Owner(
        "legal_order_test.an_unseen_and_the_creatures_news_write_nothing_after_the_unit_is_removed_in_every_legal_order_test",
      ),
    ),
    Row(
      module: creature,
      type_name: "Message",
      variants: ["Strike"],
      cover: Order(
        "legal_order_test.a_strike_and_the_senders_move_out_of_sight_are_taken_in_the_order_the_sender_told_them_and_each_order_has_its_own_result_test",
      ),
    ),
    Row(
      module: creature,
      type_name: "Message",
      variants: ["Retire"],
      cover: Owner(
        "creature_test.a_creature_told_to_retire_stops_with_nothing_to_send_test",
      ),
    ),
    Row(
      module: creature,
      type_name: "Message",
      variants: [
        "Approached",
        "Withdrew",
        "PlayerDied",
        "TargetMoved",
        "StrikeAnswered",
        "ModifierStarts",
        "ModifierEnds",
        "Thrown",
        "Despawn",
        "UnitStates",
        "CastViewSet",
        "CastViewEnds",
        "ControlsEnd",
        "CasterGone",
      ],
      cover: Owner(
        "world_tell_fence_test.a_tell_to_the_life_that_ended_is_dropped_and_the_same_tell_to_the_life_that_replaced_it_is_taken_for_every_kind_of_tell_test",
      ),
    ),
  ]
}

fn map_message_rows() -> List(Row) {
  [
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["PlayerSnapshot"],
      cover: Owner(
        "player_streams_test.a_pair_is_shown_by_the_owners_snapshot_and_one_that_leaves_and_returns_is_two_generations_and_needs_a_new_snapshot_in_every_legal_order_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Join"],
      cover: Independent(fenced_ask),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Leave"],
      cover: Independent(fenced_ask),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Moved"],
      cover: Owner(
        "player_streams_test.a_move_that_takes_a_viewer_out_of_sight_is_written_before_its_0x355_or_not_at_all_and_never_after_it_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["TellCreature"],
      cover: Order(
        "legal_order_test.a_strike_and_the_senders_move_out_of_sight_are_taken_in_the_order_the_sender_told_them_and_each_order_has_its_own_result_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Relay"],
      cover: Owner(
        "legal_order_test.a_strike_and_the_senders_move_out_of_sight_are_taken_in_the_order_the_sender_told_them_and_each_order_has_its_own_result_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Released"],
      cover: Owner(
        "map_release_test.a_released_creature_is_gone_for_every_viewer_and_starts_again_after_the_release_time_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Snapshot", "Broadcast", "Expired"],
      cover: Owner(
        "legal_order_test.a_viewer_that_arrives_or_leaves_as_the_creature_expires_is_shown_one_picture_in_every_legal_order_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["PlayerBroadcast"],
      cover: Order(
        "map_player_relation_test.the_news_a_connection_sent_before_it_ended_is_relayed_before_its_removal_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["TellLanding"],
      cover: Order(
        "player_streams_test.at_the_ally_a_change_start_then_the_casters_unseen_ends_or_keeps_it_by_its_flag_and_the_unseen_first_refuses_the_start_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Say"],
      cover: Owner(
        "player_streams_test.a_players_line_is_relayed_to_its_relaying_viewers_with_their_stay_and_before_the_snapshot_a_viewer_is_told_nothing_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["LifeChanged"],
      cover: Order(
        "map_ring_test.the_map_relays_a_players_killing_answer_its_death_and_its_wake_to_a_creature_in_the_order_the_connection_told_them_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Ready"],
      cover: Owner(
        "map_ring_test.a_player_that_wakes_before_its_ready_is_only_marked_and_ready_sends_approached_to_each_ring_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["StealthChanged"],
      cover: Owner(
        "map_stealth_property_test.over_random_moves_readies_stealth_and_life_changes_and_creature_starts_the_ring_sends_alternate_and_the_last_is_approached_exactly_for_a_ready_unstealthed_living_player_in_the_ring_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["VisibilityChanged"],
      cover: Owner(
        "map_visibility_test.visibility_changed_shows_and_hides_the_units_in_sight_test",
      ),
    ),
    Row(
      module: map_message,
      type_name: "Message",
      variants: ["Summon"],
      cover: Owner(
        "map_summon_test.a_summon_starts_the_creature_at_the_players_place_and_facing_for_the_players_who_see_that_place_test",
      ),
    ),
  ]
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
    order_coverage.variants_in(sources:, module:, type_name:)
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
  let timers = case order_coverage.file_of(sources:, module: the_connection) {
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
  [
    Row(
      module: connection,
      type_name: "Message",
      variants: ["SentBySessions"],
      cover: Independent(
        "it comes from the account sessions, not from the map, and meets no relation fact",
      ),
    ),
    Row(
      module: connection,
      type_name: "Message",
      variants: ["ForUnit"],
      cover: Owner(
        "game_connection_held_map_test.a_held_message_for_another_stay_is_dropped_when_taken_test",
      ),
    ),
    Row(
      module: connection,
      type_name: "Message",
      variants: ["SentByChat"],
      cover: Independent(
        "a whisper's reply or a watch's end between characters, resolved by the reply or the watch end and outside the map",
      ),
    ),
    Row(
      module: connection,
      type_name: "Request",
      variants: [
        "AskStore",
        "AskHandOff",
        "AskSessions",
        "AskMap",
        "AskMapRun",
      ],
      cover: Independent(fenced_ask),
    ),
    Row(
      module: fight,
      type_name: "Input",
      variants: [
        "Approached",
        "Withdrew",
        "PlayerDied",
        "TargetMoved",
        "StruckBy",
        "Unseen",
        "StrikeAnswered",
        "Thrown",
      ],
      cover: Independent(lifecycle_input),
    ),
    Row(
      module: fight,
      type_name: "Input",
      variants: [
        "TimerFired",
        "Killed",
        "Despawned",
        "Controlled",
        "ControlEnded",
        "SpeedChanged",
        "Reconsidered",
      ],
      cover: Independent(own_decision),
    ),
    Row(
      module: fight,
      type_name: "Input",
      variants: ["RingAtStart"],
      cover: Owner(
        "world_respawn_test.two_ring_players_are_both_aggroed_by_the_life_that_replaces_their_killed_creature_test",
      ),
    ),
    Row(
      module: fight,
      type_name: "Timer",
      variants: ["StrikeDeadline"],
      cover: Owner(
        "world_creature_test.an_answer_that_reaches_the_creature_after_its_round_closed_changes_nothing_test",
      ),
    ),
    Row(
      module: fight,
      type_name: "Timer",
      variants: [
        "AttackTick",
        "HomeArrival",
        "CastEnds",
        "FlightEnds",
        "ChaseArrival",
      ],
      cover: Independent(own_decision),
    ),
    Row(
      module: guard,
      type_name: "Input",
      variants: ["Interrupted", "TimerFired", "Killed", "Despawned"],
      cover: Independent(own_decision),
    ),
    Row(
      module: guard,
      type_name: "Timer",
      variants: ["OpeningEnds"],
      cover: Independent(own_decision),
    ),
    Row(
      module: the_connection,
      type_name: "timer_due",
      variants: ["strike"],
      cover: Owner(
        "world_relay_test.the_map_delivers_a_relay_held_past_the_strike_deadline_unchanged_and_the_round_decides_that_it_is_late_test",
      ),
    ),
    Row(
      module: the_connection,
      type_name: "timer_due",
      variants: [
        "save_timer",
        "quest_reset_timer",
        "quest_deadline_timer",
        "item_expiry_timer",
        "cast_state",
        "class_resource",
        "player_life",
        "departures",
        "claim_wait_over",
      ],
      cover: Independent(not_a_relation_fact),
    ),
  ]
}
