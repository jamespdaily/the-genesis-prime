-- The content tables hold no `reason` column. A row of a content table states its origin in
-- `source` (and `source_row` for a world-database row); the text a row carried beside it
-- is dropped with the column, and so are the two checks each table had on it
-- (`<table>_other_source_states_its_reason` and `<table>_reason_says_something`, or
-- `<table>_reason_not_null` for `creature_special` and `creature_auto_attack`), since a
-- table constraint on a dropped column goes with it.

alter table arrival_objective drop column reason;
alter table class_resource drop column reason;
alter table click_objective drop column reason;
alter table creature_auto_attack drop column reason;
alter table creature_faction drop column reason;
alter table creature_kind drop column reason;
alter table creature_special drop column reason;
alter table game_number drop column reason;
alter table held_objective drop column reason;
alter table kill_objective drop column reason;
alter table projector_landing drop column reason;
alter table server_proxy drop column reason;
alter table spawn drop column reason;
alter table tutorial_quest drop column reason;
alter table vendor drop column reason;
alter table vendor_item drop column reason;
alter table zone_welcome drop column reason;
