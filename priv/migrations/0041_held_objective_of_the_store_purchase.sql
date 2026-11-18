-- A visible scripted objective whose text asks for a purchase in the In-Game Store stays
-- open as a held_objective row does (0034): the server has no store, so nothing completes
-- it, and the stand-in rule would otherwise complete it with its quest. `store_purchase` is
-- the label for the later step that gives the server a store and deletes the rows of its kind.

alter table held_objective drop constraint held_objective_kind_is_known;
alter table held_objective add constraint held_objective_kind_is_known
  check (kind in ('instance_run', 'pvp_match', 'store_purchase'));

insert into held_objective (objective_id, kind, source, reason) values
  (21267, 'store_purchase', 'server_choice',
   'Quest2 10510 "Learning to Shop", objective text "Purchase ''Title: Smart Shopper'' with your OmniBit from the Beginner Basics section of the In-Game Store and redeem it to your character inventory"; the objective is a purchase in the In-Game Store, which the server has no store for yet, so it stays open (no column marks it, the text alone does)');
