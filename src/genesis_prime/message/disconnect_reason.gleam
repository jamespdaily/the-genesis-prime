//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of DisconnectReason that `schema.toml` names, each with the
//// evidence for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type DisconnectReason {
  /// The value 6, the fact file's `0x1400168a0`.
  LoggedOutByGm
  /// The value 7, the fact file's `0x1400168a0`.
  Inactivity
  /// The value 8, the fact file's `0x1400168a0`.
  LostUserServer
  /// The value 12, the fact file's `0x1400168a0`.
  LostGatewayServer
  /// The value 15, the fact file's `0x1400168a0`.
  LostWorldServer
  /// The value 16, the fact file's `0x1400168a0`.
  OutOfGameTime
  /// The value 19, the fact file's `0x1400168a0`.
  AccountDisconnected
  /// The value 20, the fact file's `0x1400168a0`.
  CriticalTransactionFailure
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: DisconnectReason) -> Int {
  case value {
    LoggedOutByGm -> 6
    Inactivity -> 7
    LostUserServer -> 8
    LostGatewayServer -> 12
    LostWorldServer -> 15
    OutOfGameTime -> 16
    AccountDisconnected -> 19
    CriticalTransactionFailure -> 20
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> DisconnectReason {
  case number {
    6 -> LoggedOutByGm
    7 -> Inactivity
    8 -> LostUserServer
    12 -> LostGatewayServer
    15 -> LostWorldServer
    16 -> OutOfGameTime
    19 -> AccountDisconnected
    20 -> CriticalTransactionFailure
    other -> Other(other)
  }
}
