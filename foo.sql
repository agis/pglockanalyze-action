-- hi
ALTER TABLE users ADD COLUMN last_seen timestamptz;

-- hi yo
-- there
ALTER TABLE users
  ADD COLUMN foo
  int;
