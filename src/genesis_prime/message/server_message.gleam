//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Every message the server sends, by its number, for reading back what a
//// server wrote: a variant for each message of the schema that travels server
//// to client or either way, `decode` to read a body by its message's number
//// and `name` to give its name in the schema. A number several messages share
//// is read by each in turn, the messages that fix a field of their own before
//// those that fix none and each kind in the schema's order, and the first that
//// reads the body is the message. A number no such message has is reported as
//// unknown.

import genesis_prime/message/ability_tiers.{type AbilityTiers}
import genesis_prime/message/account_entitlements.{type AccountEntitlements}
import genesis_prime/message/action_set.{type ActionSet}
import genesis_prime/message/bit_stream.{type DecodeError}
import genesis_prime/message/camp_countdown.{type CampCountdown}
import genesis_prime/message/character_list.{type CharacterList}
import genesis_prime/message/chat_channel_joined.{type ChatChannelJoined}
import genesis_prime/message/chat_line.{type ChatLine}
import genesis_prime/message/chat_line_accepted.{type ChatLineAccepted}
import genesis_prime/message/chat_result.{type ChatResult}
import genesis_prime/message/chat_zone_named.{type ChatZoneNamed}
import genesis_prime/message/client_control_granted.{type ClientControlGranted}
import genesis_prime/message/combat_log.{type CombatLog}
import genesis_prime/message/create_character_result.{type CreateCharacterResult}
import genesis_prime/message/delete_character_result.{type DeleteCharacterResult}
import genesis_prime/message/disconnect_notice.{type DisconnectNotice}
import genesis_prime/message/enter_world.{type EnterWorld}
import genesis_prime/message/game_server_handoff.{type GameServerHandoff}
import genesis_prime/message/innate_index_set.{type InnateIndexSet}
import genesis_prime/message/item_added.{type ItemAdded}
import genesis_prime/message/leave_world.{type LeaveWorld}
import genesis_prime/message/login_accepted.{type LoginAccepted}
import genesis_prime/message/login_refused.{type LoginRefused}
import genesis_prime/message/max_character_level.{type MaxCharacterLevel}
import genesis_prime/message/movement_send_interval.{type MovementSendInterval}
import genesis_prime/message/play_character_refused.{type PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{type PlayerEnteredWorld}
import genesis_prime/message/player_health.{type PlayerHealth}
import genesis_prime/message/player_path.{type PlayerPath}
import genesis_prime/message/pong.{type Pong}
import genesis_prime/message/premium_tier.{type PremiumTier}
import genesis_prime/message/realm_handoff.{type RealmHandoff}
import genesis_prime/message/realm_list.{type RealmList}
import genesis_prime/message/rename_character_result.{type RenameCharacterResult}
import genesis_prime/message/resurrection_window.{type ResurrectionWindow}
import genesis_prime/message/server_hello.{type ServerHello}
import genesis_prime/message/spell_cast_confirmed.{type SpellCastConfirmed}
import genesis_prime/message/spell_cast_refused.{type SpellCastRefused}
import genesis_prime/message/spell_finished.{type SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_missed.{type SpellMissed}
import genesis_prime/message/spell_stack_removed.{type SpellStackRemoved}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/message/spell_targets_removed.{type SpellTargetsRemoved}
import genesis_prime/message/spell_threshold_closed.{type SpellThresholdClosed}
import genesis_prime/message/spell_threshold_ended.{type SpellThresholdEnded}
import genesis_prime/message/spell_threshold_index.{type SpellThresholdIndex}
import genesis_prime/message/spell_threshold_opened.{type SpellThresholdOpened}
import genesis_prime/message/unit_cc_state_applied.{type UnitCcStateApplied}
import genesis_prime/message/unit_cc_state_ended.{type UnitCcStateEnded}
import genesis_prime/message/unit_combat_state.{type UnitCombatState}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_create_ghost.{type UnitCreateGhost}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_create_static.{type UnitCreateStatic}
import genesis_prime/message/unit_death_state.{type UnitDeathState}
import genesis_prime/message/unit_destroyed.{type UnitDestroyed}
import genesis_prime/message/unit_float_stat_changed.{type UnitFloatStatChanged}
import genesis_prime/message/unit_health.{type UnitHealth}
import genesis_prime/message/unit_is_player.{type UnitIsPlayer}
import genesis_prime/message/unit_movement.{type UnitMovement}
import genesis_prime/message/unit_properties_changed.{type UnitPropertiesChanged}
import genesis_prime/message/unit_stat_changed.{type UnitStatChanged}
import genesis_prime/message/unit_stealth.{type UnitStealth}
import genesis_prime/message/unit_target.{type UnitTarget}
import genesis_prime/message/unit_threat.{type UnitThreat}
import genesis_prime/message/whisper_failed.{type WhisperFailed}
import gleam/result

/// A message the server sends, decoded: one variant for each message.
pub type ServerMessage {
  ServerHello(message: ServerHello)
  Pong(message: Pong)
  LoginAccepted(message: LoginAccepted)
  LoginRefused(message: LoginRefused)
  GameServerHandoff(message: GameServerHandoff)
  EnterWorld(message: EnterWorld)
  RealmList(message: RealmList)
  RealmHandoff(message: RealmHandoff)
  MovementSendInterval(message: MovementSendInterval)
  CharacterList(message: CharacterList)
  PremiumTier(message: PremiumTier)
  AccountEntitlements(message: AccountEntitlements)
  CreateCharacterResult(message: CreateCharacterResult)
  PlayCharacterRefused(message: PlayCharacterRefused)
  DeleteCharacterResult(message: DeleteCharacterResult)
  RenameCharacterResult(message: RenameCharacterResult)
  MaxCharacterLevel(message: MaxCharacterLevel)
  DisconnectNotice(message: DisconnectNotice)
  UnitCreatePlayer(message: UnitCreatePlayer)
  UnitIsPlayer(message: UnitIsPlayer)
  PlayerPath(message: PlayerPath)
  ClientControlGranted(message: ClientControlGranted)
  UnitMovement(message: UnitMovement)
  PlayerEnteredWorld(message: PlayerEnteredWorld)
  UnitDestroyed(message: UnitDestroyed)
  CampCountdown(message: CampCountdown)
  LeaveWorld(message: LeaveWorld)
  ChatLineAccepted(message: ChatLineAccepted)
  ChatLine(message: ChatLine)
  ChatResult(message: ChatResult)
  WhisperFailed(message: WhisperFailed)
  ChatChannelJoined(message: ChatChannelJoined)
  ChatZoneNamed(message: ChatZoneNamed)
  ItemAdded(message: ItemAdded)
  AbilityTiers(message: AbilityTiers)
  ActionSet(message: ActionSet)
  InnateIndexSet(message: InnateIndexSet)
  UnitCreateCreature(message: UnitCreateCreature)
  UnitCreateStatic(message: UnitCreateStatic)
  UnitCreateGhost(message: UnitCreateGhost)
  SpellCastRefused(message: SpellCastRefused)
  SpellCastConfirmed(message: SpellCastConfirmed)
  SpellStarted(message: SpellStarted)
  SpellGo(message: SpellGo)
  SpellMissed(message: SpellMissed)
  SpellFinished(message: SpellFinished)
  SpellTargetsRemoved(message: SpellTargetsRemoved)
  SpellStackRemoved(message: SpellStackRemoved)
  UnitCcStateApplied(message: UnitCcStateApplied)
  UnitCcStateEnded(message: UnitCcStateEnded)
  SpellThresholdClosed(message: SpellThresholdClosed)
  SpellThresholdEnded(message: SpellThresholdEnded)
  SpellThresholdOpened(message: SpellThresholdOpened)
  SpellThresholdIndex(message: SpellThresholdIndex)
  UnitHealth(message: UnitHealth)
  PlayerHealth(message: PlayerHealth)
  UnitStatChanged(message: UnitStatChanged)
  UnitFloatStatChanged(message: UnitFloatStatChanged)
  UnitPropertiesChanged(message: UnitPropertiesChanged)
  UnitDeathState(message: UnitDeathState)
  UnitTarget(message: UnitTarget)
  UnitThreat(message: UnitThreat)
  UnitCombatState(message: UnitCombatState)
  UnitStealth(message: UnitStealth)
  ResurrectionWindow(message: ResurrectionWindow)
  CombatLog(message: CombatLog)
}

/// Why a body is not a message the server sends.
pub type ServerMessageError {
  /// No message the server sends has this number.
  UnknownMessage(message_id: Int)
  /// The body is not the message its number names.
  Malformed(message_id: Int, error: DecodeError)
}

/// The message a body holds, read by the decoder of the message its number
/// names.
pub fn decode(
  message_id message_id: Int,
  body body: BitArray,
) -> Result(ServerMessage, ServerMessageError) {
  case message_id {
    0x0003 -> decoded(body, message_id, server_hello.decode, ServerHello)
    0x0001 -> decoded(body, message_id, pong.decode, Pong)
    0x0591 -> decoded(body, message_id, login_accepted.decode, LoginAccepted)
    0x063D -> decoded(body, message_id, login_refused.decode, LoginRefused)
    0x03DB ->
      decoded(body, message_id, game_server_handoff.decode, GameServerHandoff)
    0x00AD -> decoded(body, message_id, enter_world.decode, EnterWorld)
    0x0761 -> decoded(body, message_id, realm_list.decode, RealmList)
    0x07A1 -> decoded(body, message_id, realm_handoff.decode, RealmHandoff)
    0x00F1 ->
      decoded(
        body,
        message_id,
        movement_send_interval.decode,
        MovementSendInterval,
      )
    0x0117 -> decoded(body, message_id, character_list.decode, CharacterList)
    0x097F -> decoded(body, message_id, premium_tier.decode, PremiumTier)
    0x0968 ->
      decoded(
        body,
        message_id,
        account_entitlements.decode,
        AccountEntitlements,
      )
    0x00DC ->
      decoded(
        body,
        message_id,
        create_character_result.decode,
        CreateCharacterResult,
      )
    0x0162 ->
      decoded(
        body,
        message_id,
        play_character_refused.decode,
        PlayCharacterRefused,
      )
    0x00E6 ->
      decoded(
        body,
        message_id,
        delete_character_result.decode,
        DeleteCharacterResult,
      )
    0x014B ->
      decoded(
        body,
        message_id,
        rename_character_result.decode,
        RenameCharacterResult,
      )
    0x0036 ->
      decoded(body, message_id, max_character_level.decode, MaxCharacterLevel)
    0x036A ->
      decoded(body, message_id, disconnect_notice.decode, DisconnectNotice)
    0x0262 ->
      decoded(body, message_id, unit_create_player.decode, UnitCreatePlayer)
      |> result.lazy_or(fn() {
        decoded(
          body,
          message_id,
          unit_create_creature.decode,
          UnitCreateCreature,
        )
      })
      |> result.lazy_or(fn() {
        decoded(body, message_id, unit_create_ghost.decode, UnitCreateGhost)
      })
      |> result.lazy_or(fn() {
        decoded(body, message_id, unit_create_static.decode, UnitCreateStatic)
      })
    0x019B -> decoded(body, message_id, unit_is_player.decode, UnitIsPlayer)
    0x06BC -> decoded(body, message_id, player_path.decode, PlayerPath)
    0x0636 ->
      decoded(
        body,
        message_id,
        client_control_granted.decode,
        ClientControlGranted,
      )
    0x0638 -> decoded(body, message_id, unit_movement.decode, UnitMovement)
    0x0061 ->
      decoded(body, message_id, player_entered_world.decode, PlayerEnteredWorld)
    0x0355 -> decoded(body, message_id, unit_destroyed.decode, UnitDestroyed)
    0x0092 -> decoded(body, message_id, camp_countdown.decode, CampCountdown)
    0x0594 -> decoded(body, message_id, leave_world.decode, LeaveWorld)
    0x01C2 ->
      decoded(body, message_id, chat_line_accepted.decode, ChatLineAccepted)
    0x01C8 -> decoded(body, message_id, chat_line.decode, ChatLine)
    0x01D3 -> decoded(body, message_id, chat_result.decode, ChatResult)
    0x01D9 -> decoded(body, message_id, whisper_failed.decode, WhisperFailed)
    0x01BC ->
      decoded(body, message_id, chat_channel_joined.decode, ChatChannelJoined)
    0x01DA -> decoded(body, message_id, chat_zone_named.decode, ChatZoneNamed)
    0x0111 -> decoded(body, message_id, item_added.decode, ItemAdded)
    0x01A0 -> decoded(body, message_id, ability_tiers.decode, AbilityTiers)
    0x019D -> decoded(body, message_id, action_set.decode, ActionSet)
    0x019F -> decoded(body, message_id, innate_index_set.decode, InnateIndexSet)
    0x07FC ->
      decoded(body, message_id, spell_cast_refused.decode, SpellCastRefused)
    0x07FD ->
      decoded(body, message_id, spell_cast_confirmed.decode, SpellCastConfirmed)
    0x07FF -> decoded(body, message_id, spell_started.decode, SpellStarted)
    0x07F4 -> decoded(body, message_id, spell_go.decode, SpellGo)
    0x07FB -> decoded(body, message_id, spell_missed.decode, SpellMissed)
    0x07FE -> decoded(body, message_id, spell_finished.decode, SpellFinished)
    0x0811 ->
      decoded(
        body,
        message_id,
        spell_targets_removed.decode,
        SpellTargetsRemoved,
      )
    0x0813 ->
      decoded(body, message_id, spell_stack_removed.decode, SpellStackRemoved)
    0x087F ->
      decoded(
        body,
        message_id,
        unit_cc_state_applied.decode,
        UnitCcStateApplied,
      )
    0x0880 ->
      decoded(body, message_id, unit_cc_state_ended.decode, UnitCcStateEnded)
    0x0814 ->
      decoded(
        body,
        message_id,
        spell_threshold_closed.decode,
        SpellThresholdClosed,
      )
    0x0815 ->
      decoded(
        body,
        message_id,
        spell_threshold_ended.decode,
        SpellThresholdEnded,
      )
    0x0816 ->
      decoded(
        body,
        message_id,
        spell_threshold_opened.decode,
        SpellThresholdOpened,
      )
    0x0817 ->
      decoded(
        body,
        message_id,
        spell_threshold_index.decode,
        SpellThresholdIndex,
      )
    0x0937 -> decoded(body, message_id, unit_health.decode, UnitHealth)
    0x092F -> decoded(body, message_id, player_health.decode, PlayerHealth)
    0x0938 ->
      decoded(body, message_id, unit_stat_changed.decode, UnitStatChanged)
    0x0935 ->
      decoded(
        body,
        message_id,
        unit_float_stat_changed.decode,
        UnitFloatStatChanged,
      )
    0x093A ->
      decoded(
        body,
        message_id,
        unit_properties_changed.decode,
        UnitPropertiesChanged,
      )
    0x088C -> decoded(body, message_id, unit_death_state.decode, UnitDeathState)
    0x0908 -> decoded(body, message_id, unit_target.decode, UnitTarget)
    0x090A -> decoded(body, message_id, unit_threat.decode, UnitThreat)
    0x089A ->
      decoded(body, message_id, unit_combat_state.decode, UnitCombatState)
    0x08F5 -> decoded(body, message_id, unit_stealth.decode, UnitStealth)
    0x01B3 ->
      decoded(body, message_id, resurrection_window.decode, ResurrectionWindow)
    0x0247 -> decoded(body, message_id, combat_log.decode, CombatLog)
    _ -> Error(UnknownMessage(message_id:))
  }
}

/// The name of a message in the schema.
pub fn name(message: ServerMessage) -> String {
  case message {
    ServerHello(..) -> "server_hello"
    Pong(..) -> "pong"
    LoginAccepted(..) -> "login_accepted"
    LoginRefused(..) -> "login_refused"
    GameServerHandoff(..) -> "game_server_handoff"
    EnterWorld(..) -> "enter_world"
    RealmList(..) -> "realm_list"
    RealmHandoff(..) -> "realm_handoff"
    MovementSendInterval(..) -> "movement_send_interval"
    CharacterList(..) -> "character_list"
    PremiumTier(..) -> "premium_tier"
    AccountEntitlements(..) -> "account_entitlements"
    CreateCharacterResult(..) -> "create_character_result"
    PlayCharacterRefused(..) -> "play_character_refused"
    DeleteCharacterResult(..) -> "delete_character_result"
    RenameCharacterResult(..) -> "rename_character_result"
    MaxCharacterLevel(..) -> "max_character_level"
    DisconnectNotice(..) -> "disconnect_notice"
    UnitCreatePlayer(..) -> "unit_create_player"
    UnitIsPlayer(..) -> "unit_is_player"
    PlayerPath(..) -> "player_path"
    ClientControlGranted(..) -> "client_control_granted"
    UnitMovement(..) -> "unit_movement"
    PlayerEnteredWorld(..) -> "player_entered_world"
    UnitDestroyed(..) -> "unit_destroyed"
    CampCountdown(..) -> "camp_countdown"
    LeaveWorld(..) -> "leave_world"
    ChatLineAccepted(..) -> "chat_line_accepted"
    ChatLine(..) -> "chat_line"
    ChatResult(..) -> "chat_result"
    WhisperFailed(..) -> "whisper_failed"
    ChatChannelJoined(..) -> "chat_channel_joined"
    ChatZoneNamed(..) -> "chat_zone_named"
    ItemAdded(..) -> "item_added"
    AbilityTiers(..) -> "ability_tiers"
    ActionSet(..) -> "action_set"
    InnateIndexSet(..) -> "innate_index_set"
    UnitCreateCreature(..) -> "unit_create_creature"
    UnitCreateStatic(..) -> "unit_create_static"
    UnitCreateGhost(..) -> "unit_create_ghost"
    SpellCastRefused(..) -> "spell_cast_refused"
    SpellCastConfirmed(..) -> "spell_cast_confirmed"
    SpellStarted(..) -> "spell_started"
    SpellGo(..) -> "spell_go"
    SpellMissed(..) -> "spell_missed"
    SpellFinished(..) -> "spell_finished"
    SpellTargetsRemoved(..) -> "spell_targets_removed"
    SpellStackRemoved(..) -> "spell_stack_removed"
    UnitCcStateApplied(..) -> "unit_cc_state_applied"
    UnitCcStateEnded(..) -> "unit_cc_state_ended"
    SpellThresholdClosed(..) -> "spell_threshold_closed"
    SpellThresholdEnded(..) -> "spell_threshold_ended"
    SpellThresholdOpened(..) -> "spell_threshold_opened"
    SpellThresholdIndex(..) -> "spell_threshold_index"
    UnitHealth(..) -> "unit_health"
    PlayerHealth(..) -> "player_health"
    UnitStatChanged(..) -> "unit_stat_changed"
    UnitFloatStatChanged(..) -> "unit_float_stat_changed"
    UnitPropertiesChanged(..) -> "unit_properties_changed"
    UnitDeathState(..) -> "unit_death_state"
    UnitTarget(..) -> "unit_target"
    UnitThreat(..) -> "unit_threat"
    UnitCombatState(..) -> "unit_combat_state"
    UnitStealth(..) -> "unit_stealth"
    ResurrectionWindow(..) -> "resurrection_window"
    CombatLog(..) -> "combat_log"
  }
}

fn decoded(
  body: BitArray,
  message_id: Int,
  decode: fn(BitArray) -> Result(message, DecodeError),
  variant: fn(message) -> ServerMessage,
) -> Result(ServerMessage, ServerMessageError) {
  case decode(body) {
    Ok(message) -> Ok(variant(message))
    Error(error) -> Error(Malformed(message_id:, error:))
  }
}
