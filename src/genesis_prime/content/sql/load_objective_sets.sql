-- Every row of the content tables whose rows each name a QuestObjective, in table and key
-- order: the one query the load makes of them at start (genesis_prime/content/objective_set).
-- The checks run on these rows, not in SQL. A table of this kind adds one line here.
select 'held_objective' as table_name, objective_id from held_objective
union all
select 'arrival_objective', objective_id from arrival_objective
union all
select 'kill_objective', objective_id from kill_objective
order by table_name, objective_id;
