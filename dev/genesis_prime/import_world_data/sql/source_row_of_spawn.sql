-- The row id in the file of a spawn, by the spawn's own id: a refused stat names
-- its spawn by that id, and the importer reports the row of the file.
select source_row
from spawn
where id = $1;
