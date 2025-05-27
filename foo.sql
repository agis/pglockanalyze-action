-- hi
ALTER TABLE users ADD COLUMN last_seen timestamptz;
 
-- there
ALTER TABLE users
  ADD COLUMN foo
  int;