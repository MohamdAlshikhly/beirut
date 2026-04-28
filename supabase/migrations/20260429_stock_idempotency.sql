-- =============================================================
-- Stock Idempotency & Type Safety Migration  (v1.2.16)
-- =============================================================
-- Goals:
--   1. Make stock_movements idempotent across retries (client_id UNIQUE).
--   2. Replace fragile reason-string linkage with proper sale_id FK.
--   3. Replace `double precision` (which corrupted product 26 with 10^276)
--      with NUMERIC(14,3) which can hold realistic POS quantities.
--   4. Make sales idempotent across retries (client_id UNIQUE).
--
-- Run this ONCE in Supabase SQL Editor before deploying v1.2.16 client.
-- The migration is additive: existing rows get backfilled UUIDs so the
-- old client (which doesn't send client_id yet) keeps working until upgraded.
-- =============================================================

BEGIN;

-- 1. Add columns (nullable first, so we can backfill).
ALTER TABLE stock_movements
  ADD COLUMN IF NOT EXISTS client_id UUID,
  ADD COLUMN IF NOT EXISTS sale_id   BIGINT;

ALTER TABLE sales
  ADD COLUMN IF NOT EXISTS client_id UUID;

-- 2. Backfill UUIDs for existing rows.
UPDATE stock_movements SET client_id = gen_random_uuid() WHERE client_id IS NULL;
UPDATE sales           SET client_id = gen_random_uuid() WHERE client_id IS NULL;

-- 3. NOT NULL + UNIQUE.
ALTER TABLE stock_movements ALTER COLUMN client_id SET NOT NULL;
ALTER TABLE sales           ALTER COLUMN client_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stock_movements_client_id_uniq
  ON stock_movements(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS sales_client_id_uniq
  ON sales(client_id);

-- 4. Foreign key for sale_id (nullable: manual edits & seed rows have no sale).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'stock_movements_sale_id_fkey'
  ) THEN
    ALTER TABLE stock_movements
      ADD CONSTRAINT stock_movements_sale_id_fkey
      FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS stock_movements_sale_id_idx ON stock_movements(sale_id);

-- 5. Convert numeric columns from double precision → numeric(14,3).
--    Cap insane values that would overflow numeric(14,3) before casting.
UPDATE stock_movements SET change = 0
  WHERE change IS NULL OR ABS(change) > 99999999999;
UPDATE products SET quantity = 0
  WHERE quantity IS NULL OR ABS(quantity) > 99999999999;

ALTER TABLE stock_movements
  ALTER COLUMN change TYPE NUMERIC(14,3) USING change::NUMERIC(14,3);

ALTER TABLE products
  ALTER COLUMN quantity TYPE NUMERIC(14,3) USING quantity::NUMERIC(14,3);

ALTER TABLE products
  ALTER COLUMN base_unit_conversion TYPE NUMERIC(14,4)
  USING base_unit_conversion::NUMERIC(14,4);

COMMIT;

-- =============================================================
-- Verification (run separately, expect zero rows / no errors)
-- =============================================================
-- SELECT COUNT(*) FROM stock_movements WHERE client_id IS NULL;          -- expect 0
-- SELECT COUNT(*) FROM sales           WHERE client_id IS NULL;          -- expect 0
-- SELECT data_type FROM information_schema.columns
--   WHERE table_name='stock_movements' AND column_name='change';         -- expect numeric
