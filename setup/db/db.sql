CREATE TABLE files (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    pub_name        TEXT NOT NULL,
    meta_data_json  JSONB NOT NULL,
    is_deleated     BOOLEAN NOT NULL DEFAULT FALSE,
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

