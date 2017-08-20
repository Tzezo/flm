CREATE TABLE files (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    orig_name       TEXT NOT NULL,
    pub_name        TEXT NOT NULL,
    meta_data_json  JSONB NOT NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

ALTER TABLE files ADD CONSTRAINT files_name_uniq UNIQUE (name);
CREATE UNIQUE INDEX files_pug_name_uniq ON files (pub_name) WHERE (is_deleted is false);
