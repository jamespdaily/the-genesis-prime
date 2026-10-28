//// The folder of the client's extracted game tables, for the tools that read
//// them: `GENESIS_TABLE_DIR`, else `tables` under `GENESIS_HOME`, else under
//// `~/.genesis-prime`.

import envoy

/// The folder of the client's extracted game tables.
pub fn path() -> String {
  case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      case envoy.get("GENESIS_HOME"), envoy.get("HOME") {
        Ok(home), _ -> home <> "/tables"
        Error(Nil), Ok(home) -> home <> "/.genesis-prime/tables"
        Error(Nil), Error(Nil) -> "tables"
      }
  }
}
