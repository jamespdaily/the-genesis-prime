//// The chat channel types the server decides on. A channel's type on the wire
//// is the id of its ChatChannel row (ChatChannel.flags); every other row is
//// `Other`, whose flags the rule reads from the table (genesis_prime/game/chat).

/// A chat channel type, as the ChatChannel table numbers it. The client makes
/// Say, Yell, Emote, Whisper and AccountWhisper itself, each with id 0, and
/// joins Zone only when the server sends 0x1bc (`ChatChannel.flags`,
/// `0x140404ee0`).
pub type ChannelType {
  /// Row 4: said to the players who see the speaker.
  Say
  /// Row 5: as Say, on its own channel.
  Yell
  /// Row 6: a line to one character by name.
  Whisper
  /// Row 7: the client holds it; no group exists to say it to.
  Party
  /// Row 8: as Say, on its own channel.
  Emote
  /// Row 9: said to the players of the same map run under the same top zone.
  Zone
  /// Row 19: the client holds it and may send on it; the server builds none.
  Support
  /// Row 32: the client holds it and may send on it; the server builds none.
  Instance
  /// Row 34: a whisper to an account friend, which the client sends as 0x1d4
  /// with its account bit set.
  AccountWhisper
  /// Any other row, by its id.
  Other(id: Int)
}

/// The channel type of a ChatChannel row id.
pub fn from_id(id id: Int) -> ChannelType {
  case id {
    4 -> Say
    5 -> Yell
    6 -> Whisper
    7 -> Party
    8 -> Emote
    9 -> Zone
    19 -> Support
    32 -> Instance
    34 -> AccountWhisper
    other -> Other(id: other)
  }
}

/// The ChatChannel row id of a channel type, which is its type on the wire.
pub fn id(channel_type channel_type: ChannelType) -> Int {
  case channel_type {
    Say -> 4
    Yell -> 5
    Whisper -> 6
    Party -> 7
    Emote -> 8
    Zone -> 9
    Support -> 19
    Instance -> 32
    AccountWhisper -> 34
    Other(id:) -> id
  }
}
