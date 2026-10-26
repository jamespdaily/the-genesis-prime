//// STUB of the generated module for the client table LocalizedText: the types and signatures only.

import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file

pub type LocalizedText {
  LocalizedText(
    id: Int,
    sound_event_id: Int,
    sound_event_id_female: Int,
    version: Int,
    unit_voice_type_id: Int,
    string_context_enum: Int,
    sound_availability_flag_female: Int,
  )
}

pub const schema =
  tbl_file.Schema(
    table: "LocalizedText",
    file: "LocalizedText",
    record_size: 28,
    columns: [
      tbl_file.Column(name: "ID", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "soundEventId", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "soundEventIdFemale",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "version", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "unitVoiceTypeId", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "stringContextEnum",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "soundAvailabilityFlagFemale",
        column_type: tbl_file.Integer32,
      ),
    ],
  )

pub fn entry() -> store.Entry {
  todo
}

pub fn get(tables: store.Tables, id: Int) -> Result(LocalizedText, Nil) {
  todo
}

pub fn all(tables: store.Tables) -> List(LocalizedText) {
  todo
}
