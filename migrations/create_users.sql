-- +migrate Up
CREATE TABLE users (zxc VARCHAR);

-- +migrate Down
DROP TABLE users;
