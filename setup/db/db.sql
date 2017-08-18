CREATE TABLE files (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    pub_name        TEXT NOT NULL,
    meta_data_json  JSONB NOT NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

ALTER TABLE files ADD CONSTRAINT files_name_uniq UNIQUE (name);
ALTER TABLE files ADD CONSTRAINT files_pub_name_uniq UNIQUE (pub_name);
