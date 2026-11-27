-- Stub: retires nothing.
update creature_special set retired_by_import = $1 where false and $2::int[] is null and $3::int[] is null and $4::smallint[] is null and $5::int[] is null;
