//// The folders of the client's extracted game tables and other files, for the tools
//// that read them: `GENESIS_TABLE_DIR`, else `tables` under `GENESIS_HOME`, else under
//// `~/.genesis-prime`; and for the other files `GENESIS_CLIENT_FILES_DIR`, else
//// `client-files` under the same.

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

/// The folder of the client's other extracted files, among them `en-US.bin`.
pub fn client_files_path() -> String {
  case envoy.get("GENESIS_CLIENT_FILES_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      case envoy.get("GENESIS_HOME"), envoy.get("HOME") {
        Ok(home), _ -> home <> "/client-files"
        Error(Nil), Ok(home) -> home <> "/.genesis-prime/client-files"
        Error(Nil), Error(Nil) -> "client-files"
      }
  }
}
