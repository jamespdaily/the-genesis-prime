//// The messages of the STS login in typed values: what the client sends,
//// decoded from a request, and what the server answers, encoded to the bytes
//// the client's parser accepts. The requests are in the order the client sends
//// them: Connect, LoginStart, KeyData, LoginFinish, ListMyAccounts and
//// RequestGameToken (records StsConnLib64.MT.dll!0x18002f410, 0x180006fb0,
//// 0x18000a350, 0x1800043d0, 0x180004950, 0x180004ac0).

import genesis_prime/login/sts_wire
import gleam/option.{type Option}

/// The game code the client names in ListMyAccounts and RequestGameToken: the
/// ncAppGroupCode of its RealmDataCenter row (GetNcAppGroupCode 0x140018aa0).
pub const game_code = "wildstar"

/// The values of the Connect message the library sends when its TCP
/// connection is up. Each number the library leaves out when it is 0 is 0
/// here (StsConnLib64.MT.dll!0x18002f410).
pub type Connect {
  Connect(
    connection_type: Int,
    connection_product_type: Int,
    connection_app_index: Int,
    connection_deployment: Int,
    connection_epoch: Int,
    address: Option(String),
    product_type: Int,
    app_index: Int,
    deployment: Int,
    epoch: Int,
    program: Int,
    build: Int,
    process: Int,
    notify_flags: Int,
    version_flags: Int,
  )
}

/// A request that expects a reply, with the sequence to answer it by.
pub type Transaction {
  /// The account name in lower case and the client's own address
  /// (StsConnLib64.MT.dll!0x180006fb0).
  LoginStart(login_name: String, net_address: String)
  /// The bytes of the SRP client's key data (StsConnLib64.MT.dll!0x18000a350).
  KeyData(bytes: BitArray)
  /// The request after SRP; the client sets none of its optional children
  /// (StsConnLib64.MT.dll!0x1800043d0).
  LoginFinish
  /// The login's UserId and the game code (StsConnLib64.MT.dll!0x180004950).
  ListMyAccounts(user_id: String, game_code: String)
  /// The UserId, the game code and the game account's alias
  /// (StsConnLib64.MT.dll!0x180004ac0).
  RequestGameToken(user_id: String, game_code: String, account_alias: String)
}

/// What a request is, decoded.
pub type Incoming {
  /// The one-way Connect, with no sequence.
  ConnectionOpened(connect: Connect)
  /// The one-way keep-alive Ping, with no body and no sequence
  /// (StsConnLib64.MT.dll!0x18002f370).
  Ping
  /// A request with its sequence.
  Transaction(sequence: Int, request: Transaction)
}

/// Why a request does not decode to a message.
pub type MessageError {
  /// The protocol and command name no message of the login.
  UnknownCommand(protocol: String, command: String)
  /// A request that expects a reply has no sequence.
  MissingSequence(command: String)
  /// The body is not a root element (`sts_xml.XmlError`).
  BodyNotXml(command: String)
  /// A child the message needs is not in the body.
  MissingChild(command: String, child: String)
  /// A child that must be a decimal number is not.
  NotANumber(command: String, child: String)
  /// KeyData is not base64.
  NotBase64(command: String)
}

/// A game account the login lists for its UserId.
pub type GameAccount {
  GameAccount(alias: String, created: String, game_account_id: String)
}

/// What the server answers, each to a sequence.
pub type Answer {
  /// The reply to LoginStart and to KeyData: the SRP key data
  /// (StsConnLib64.MT.dll!0x18000a350).
  KeyDataAnswer(sequence: Int, key_data: BitArray)
  /// The reply to LoginFinish: AuthType 0, the UserId and the UserName
  /// (StsConnLib64.MT.dll!0x1800043d0).
  LoginFinished(sequence: Int, user_id: String, user_name: String)
  /// The reply to ListMyAccounts (StsConnLib64.MT.dll!0x180004950).
  GameAccounts(sequence: Int, accounts: List(GameAccount))
  /// The reply to RequestGameToken (StsConnLib64.MT.dll!0x180004ac0).
  GameToken(sequence: Int, token: String)
  /// An error reply with the code the client's handlers act on
  /// (StsConnLib64.MT.dll!0x18002de60).
  Refused(sequence: Int, code: Int)
}

/// The message a request holds.
pub fn decode(
  request request: sts_wire.Request,
) -> Result(Incoming, MessageError) {
  todo as "decode a request"
}

/// The bytes of an answer.
pub fn encode(answer answer: Answer) -> BitArray {
  todo as "encode an answer"
}

/// A sentence that says why a request is not a message, for the log.
pub fn describe(error error: MessageError) -> String {
  todo as "the error in words"
}
