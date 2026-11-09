-- Takes the character's row lock until the transaction ends, so the saves of
-- one character run one after another and the save that follows reads the quest
-- rows the one before it committed (save_place.sql). The statement after it in
-- the transaction takes its snapshot once the lock is held. No row means no such
-- character for the account.
select character_id
from character
where character_id = $1 and account_id = $2
for update;
