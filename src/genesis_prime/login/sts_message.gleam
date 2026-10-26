//// The messages of the STS login in typed values: what the client sends,
//// decoded from a request, and what the server answers, encoded to the bytes
//// the client's parser accepts. The requests are in the order the client sends
//// them: Connect, LoginStart, KeyData, LoginFinish, ListMyAccounts and
//// RequestGameToken (records StsConnLib64.MT.dll!0x18002f410, 0x180006fb0,
//// 0x18000a350, 0x1800043d0, 0x180004950, 0x180004ac0).

import genesis_prime/login/sts_wire
import genesis_prime/login/sts_xml.{type Element, Parent, Tag, Text}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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
  let command = request.command
  case request.protocol, command {
    "Sts", "Ping" -> Ok(Ping)
    "Sts", "Connect" -> {
      use root <- result.try(root_of(request))
      use connect <- result.map(read_connect(root))
      ConnectionOpened(connect)
    }
    "Auth", "LoginStart" ->
      transaction(request, fn(root) {
        use login_name <- result.try(text_of(
          root:,
          command:,
          child: "LoginName",
        ))
        use net_address <- result.map(text_of(
          root:,
          command:,
          child: "NetAddress",
        ))
        LoginStart(login_name:, net_address:)
      })
    "Auth", "KeyData" ->
      transaction(request, fn(root) {
        use encoded <- result.try(text_of(root:, command:, child: "KeyData"))
        bit_array.base64_decode(encoded)
        |> result.map(KeyData)
        |> result.replace_error(NotBase64(command:))
      })
    "Auth", "LoginFinish" -> transaction(request, fn(_) { Ok(LoginFinish) })
    "GameAccount", "ListMyAccounts" ->
      transaction(request, fn(root) {
        use user_id <- result.try(text_of(root:, command:, child: "UserId"))
        use game_code <- result.map(text_of(root:, command:, child: "GameCode"))
        ListMyAccounts(user_id:, game_code:)
      })
    "Auth", "RequestGameToken" ->
      transaction(request, fn(root) {
        use user_id <- result.try(text_of(root:, command:, child: "UserId"))
        use game_code <- result.try(text_of(root:, command:, child: "GameCode"))
        use account_alias <- result.map(text_of(
          root:,
          command:,
          child: "AccountAlias",
        ))
        RequestGameToken(user_id:, game_code:, account_alias:)
      })
    protocol, command -> Error(UnknownCommand(protocol:, command:))
  }
}

/// A request that expects a reply: its sequence and what its body holds.
fn transaction(
  request: sts_wire.Request,
  read: fn(Element) -> Result(Transaction, MessageError),
) -> Result(Incoming, MessageError) {
  case request.sequence {
    None -> Error(MissingSequence(command: request.command))
    Some(sequence) -> {
      use root <- result.try(root_of(request))
      use read_request <- result.map(read(root))
      Transaction(sequence:, request: read_request)
    }
  }
}

fn root_of(request: sts_wire.Request) -> Result(Element, MessageError) {
  sts_xml.parse(request.body)
  |> result.replace_error(BodyNotXml(command: request.command))
}

fn text_of(
  root root: Element,
  command command: String,
  child child: String,
) -> Result(String, MessageError) {
  sts_xml.child(root, child)
  |> result.map(fn(found) { found.text })
  |> result.replace_error(MissingChild(command:, child:))
}

/// The children of Connect: a number the library leaves out is 0
/// (StsConnLib64.MT.dll!0x18002f410).
fn read_connect(root: Element) -> Result(Connect, MessageError) {
  let number = fn(child) { number_of(root:, command: "Connect", child:) }
  use connection_type <- result.try(number("ConnType"))
  use connection_product_type <- result.try(number("ConnProductType"))
  use connection_app_index <- result.try(number("ConnAppIndex"))
  use connection_deployment <- result.try(number("ConnDeployment"))
  use connection_epoch <- result.try(number("ConnEpoch"))
  use product_type <- result.try(number("ProductType"))
  use app_index <- result.try(number("AppIndex"))
  use deployment <- result.try(number("Deployment"))
  use epoch <- result.try(number("Epoch"))
  use program <- result.try(number("Program"))
  use build <- result.try(number("Build"))
  use process <- result.try(number("Process"))
  use notify_flags <- result.try(number("NotifyFlags"))
  use version_flags <- result.map(number("VersionFlags"))
  Connect(
    connection_type:,
    connection_product_type:,
    connection_app_index:,
    connection_deployment:,
    connection_epoch:,
    address: sts_xml.child(root, "Address")
      |> result.map(fn(found) { found.text })
      |> option.from_result,
    product_type:,
    app_index:,
    deployment:,
    epoch:,
    program:,
    build:,
    process:,
    notify_flags:,
    version_flags:,
  )
}

fn number_of(
  root root: Element,
  command command: String,
  child child: String,
) -> Result(Int, MessageError) {
  case sts_xml.child(root, child) {
    Error(Nil) -> Ok(0)
    Ok(found) ->
      int.parse(found.text)
      |> result.replace_error(NotANumber(command:, child:))
  }
}

/// The bytes of an answer.
pub fn encode(answer answer: Answer) -> BitArray {
  case answer {
    KeyDataAnswer(sequence:, key_data:) ->
      success(sequence, [
        Text("KeyData", bit_array.base64_encode(key_data, True)),
      ])
    LoginFinished(sequence:, user_id:, user_name:) ->
      success(sequence, [
        Text("AuthType", "0"),
        Text("UserId", user_id),
        Text("UserName", user_name),
      ])
    GameAccounts(sequence:, accounts:) ->
      success(
        sequence,
        list.map(accounts, fn(account) {
          Parent("GameAccount", [
            Text("Alias", account.alias),
            Text("Created", account.created),
            Text("GameAccountId", account.game_account_id),
          ])
        }),
      )
    GameToken(sequence:, token:) -> success(sequence, [Text("Token", token)])
    Refused(sequence:, code:) ->
      sts_wire.encode(sts_wire.Failure(
        sequence:,
        body: sts_xml.render(
          Tag("Error", [
            #("code", int.to_string(code)),
            #("server", "0"),
            #("module", "0"),
            #("line", "0"),
            #("text", ""),
          ]),
        ),
      ))
  }
}

fn success(sequence: Int, children: List(sts_xml.Node)) -> BitArray {
  sts_wire.encode(sts_wire.Success(
    sequence:,
    body: sts_xml.render(Parent("Reply", children)),
  ))
}

/// A sentence that says why a request is not a message, for the log.
pub fn describe(error error: MessageError) -> String {
  case error {
    UnknownCommand(protocol:, command:) ->
      "the request /"
      <> protocol
      <> "/"
      <> command
      <> " is not one of the login's"
    MissingSequence(command:) -> command <> " has no sequence"
    BodyNotXml(command:) -> "the body of " <> command <> " is not XML"
    MissingChild(command:, child:) ->
      "the body of " <> command <> " has no " <> child
    NotANumber(command:, child:) ->
      "the " <> child <> " of " <> command <> " is not a number"
    NotBase64(command:) -> "the KeyData of " <> command <> " is not base64"
  }
}
