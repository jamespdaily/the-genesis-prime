-- Takes every action bar slot, spent ability tier and held AMP saved for the character with
-- this id ($1), of the account with this login name ($2), so it shows its new class's bar,
-- enters with no points spent and holds no AMP of the class it had.
with guarded as (
  select character_id
  from character
  join account using (account_id)
  where character.character_id = $1
    and account.login_name = $2
),
gone_slots as (
  delete from character_action_slot
  where character_id in (select character_id from guarded)
),
gone_tiers as (
  delete from character_ability_tier
  where character_id in (select character_id from guarded)
)
delete from character_action_amp
where character_id in (select character_id from guarded);
