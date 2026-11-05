-- Every row of the class_resource table in class and name order: the one query the
-- load makes of the table at start (genesis_prime/content/class_resource). The
-- checks run on these rows, not in SQL.
select
  class_id,
  name,
  value,
  unit
from class_resource
order by class_id, name;
