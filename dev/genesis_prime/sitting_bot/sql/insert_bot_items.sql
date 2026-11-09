-- Gives the bot's character, the one of the account with this login name ($1)
-- named $2 (found as the name's unique index finds it: any case, under the ICU
-- root collation, migration 0005), the Novice set of CharacterCreation row 466,
-- the row its race, sex, class and faction come from: the five armor pieces at
-- bag indexes 0, 1, 3, 4 and 5, the shield at 15 and the weapon at 16, all at
-- location 0 (equipped) as a stack of 1 (Item2.novice_set,
-- CharacterCreation.itemId0 to itemId06). A character that already holds an
-- item is left as it is, so a run beside another gives the set once.
insert into character_item (character_id, item2_id, location, bag_index, stack_count)
select character.character_id, set.item2_id, 0, set.bag_index, 1
from character
join account using (account_id)
cross join (
  values
    (81359, 0), (81344, 1), (81381, 3), (81345, 4), (81380, 5), (8534, 15),
    (81346, 16)
) as set (item2_id, bag_index)
where account.login_name = $1
  and lower(character.name collate "und-x-icu") = lower($2::text collate "und-x-icu")
  and not exists (
    select 1
    from character_item
    where character_item.character_id = character.character_id
  );
