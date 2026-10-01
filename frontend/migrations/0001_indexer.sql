CREATE TABLE chain_cursor (
  stream TEXT PRIMARY KEY,
  block_number INTEGER NOT NULL
);

CREATE TABLE trades (
  event_id TEXT PRIMARY KEY,
  transaction_hash TEXT NOT NULL,
  log_index INTEGER NOT NULL,
  block_number INTEGER NOT NULL,
  block_timestamp INTEGER NOT NULL,
  wallet TEXT NOT NULL,
  zero_for_one INTEGER NOT NULL,
  amount_specified TEXT NOT NULL,
  nav_fee INTEGER NOT NULL,
  inventory_fee INTEGER NOT NULL,
  volatility_fee INTEGER NOT NULL,
  total_fee INTEGER NOT NULL,
  epoch_gross_flow TEXT NOT NULL,
  epoch_net_asset_flow TEXT NOT NULL,
  nav_updated_at INTEGER NOT NULL,
  asset_amount TEXT,
  epoch_start INTEGER
);

CREATE INDEX trades_wallet_time ON trades(wallet, block_timestamp DESC);
CREATE INDEX trades_hash ON trades(transaction_hash);

CREATE TABLE nav_events (
  event_id TEXT PRIMARY KEY,
  transaction_hash TEXT NOT NULL,
  block_number INTEGER NOT NULL,
  block_timestamp INTEGER NOT NULL,
  kind TEXT NOT NULL,
  nav TEXT,
  effective_at INTEGER
);

CREATE INDEX nav_events_time ON nav_events(block_timestamp DESC);
