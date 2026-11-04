-- Records that a file of the world database was imported: its name, the SHA-256
-- of its bytes and its row count, and when. An import of the same file again
-- replaces the record.
insert into content_import (file, sha256, rows, imported_at)
values ($1, $2, $3, now())
on conflict (file) do update set
  sha256 = excluded.sha256,
  rows = excluded.rows,
  imported_at = excluded.imported_at;
