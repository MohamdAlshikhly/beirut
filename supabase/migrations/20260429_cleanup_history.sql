-- =============================================================
-- Stock History Cleanup (v1.2.16)
-- =============================================================
-- Run AFTER 20260429_stock_idempotency.sql has been applied and AFTER
-- all desktop terminals have been upgraded to v1.2.16 client.
--
-- This file is divided into stages. Run each stage separately and
-- inspect the results before moving on. Sections marked WRITE actually
-- modify data — read them carefully first.
-- =============================================================


-- =============================================================
-- STAGE 1 (READ-ONLY): Reconciliation report — current state
-- =============================================================
-- Shows the difference between products.quantity and the audit-trail
-- sum for every product. Use this to know what the cleanup will affect.

WITH sums AS (
  SELECT product_id, SUM(change)::numeric AS audit_sum
  FROM stock_movements
  WHERE product_id IS NOT NULL
  GROUP BY product_id
)
SELECT
  p.id,
  p.name,
  p.quantity            AS current_qty,
  COALESCE(s.audit_sum,0) AS audit_qty,
  p.quantity - COALESCE(s.audit_sum,0) AS diff
FROM products p
LEFT JOIN sums s ON s.product_id = p.id
WHERE p.quantity != COALESCE(s.audit_sum,0)
ORDER BY ABS(p.quantity - COALESCE(s.audit_sum,0)) DESC;


-- =============================================================
-- STAGE 2 (WRITE): Delete corrupted 10^276 entries on product 26
-- =============================================================
-- These two rows mathematically cancel each other (one offline sale
-- with insane bytes, one manual "fix" of equal magnitude) but their
-- IEEE-754 sum leaks ~10^261 of phantom error. Removing both is safe
-- because they were always equal and opposite.

DELETE FROM stock_movements
 WHERE product_id = 26
   AND ABS(change) > 1e10;


-- =============================================================
-- STAGE 3 (WRITE): Deduplicate return movements
-- =============================================================
-- The pre-v1.2.16 syncUp re-inserted the same stock_movement on every
-- retry, applying the change as many times as the retry succeeded
-- (sale 5560's return ran 2x, returning 58 products twice → +1 unit
-- ghost-credit per item). Keep the oldest, drop the rest.

DELETE FROM stock_movements
 WHERE id IN (
   SELECT id FROM (
     SELECT id, ROW_NUMBER() OVER (
       PARTITION BY product_id, change, reason
       ORDER BY created_at, id
     ) AS rn
     FROM stock_movements
     WHERE reason LIKE 'إرجاع فاتورة #%'
   ) sub
   WHERE rn > 1
 );


-- =============================================================
-- STAGE 4 (READ-ONLY): Re-run the reconciliation report
-- =============================================================
-- Confirms stages 2-3 fixed the obvious cases. The remaining diffs
-- come from sales that lost their stock_movements entirely (see the
-- 4,286-row mismatch we audited).

WITH sums AS (
  SELECT product_id, SUM(change)::numeric AS audit_sum
  FROM stock_movements
  WHERE product_id IS NOT NULL
  GROUP BY product_id
)
SELECT
  p.id,
  p.name,
  p.quantity            AS current_qty,
  COALESCE(s.audit_sum,0) AS audit_qty,
  p.quantity - COALESCE(s.audit_sum,0) AS diff
FROM products p
LEFT JOIN sums s ON s.product_id = p.id
WHERE p.quantity != COALESCE(s.audit_sum,0)
ORDER BY ABS(p.quantity - COALESCE(s.audit_sum,0)) DESC;


-- =============================================================
-- STAGE 5 (WRITE — OPTIONAL): Reconcile audit trail to current qty
-- =============================================================
-- Strategy: trust products.quantity (which the cashier has been
-- reading) as ground truth, and INSERT one compensating movement
-- per mismatched product so the audit-trail sum agrees. Each new
-- row gets a fresh client_id so v1.2.16+ syncs treat it normally.
--
-- Only run this if you have NOT done a physical stock count. If
-- you have, skip this and instead update products.quantity to the
-- true counted value, then re-run the reconciliation to confirm.

INSERT INTO stock_movements (product_id, change, reason, client_id, created_at)
SELECT
  p.id,
  p.quantity - COALESCE(s.audit_sum, 0),
  'تصحيح تلقائي: محاذاة السجل مع الكمية الحالية',
  gen_random_uuid(),
  NOW()
FROM products p
LEFT JOIN (
  SELECT product_id, SUM(change)::numeric AS audit_sum
  FROM stock_movements
  WHERE product_id IS NOT NULL
  GROUP BY product_id
) s ON s.product_id = p.id
WHERE p.quantity != COALESCE(s.audit_sum, 0)
  AND ABS(p.quantity - COALESCE(s.audit_sum, 0)) < 1e9;  -- skip nonsense magnitudes


-- =============================================================
-- STAGE 6 (READ-ONLY): Final verification
-- =============================================================
-- Should return zero rows after stage 5 (or after a manual stocktake
-- correction).

WITH sums AS (
  SELECT product_id, SUM(change)::numeric AS audit_sum
  FROM stock_movements
  WHERE product_id IS NOT NULL
  GROUP BY product_id
)
SELECT
  p.id,
  p.name,
  p.quantity            AS current_qty,
  COALESCE(s.audit_sum,0) AS audit_qty
FROM products p
LEFT JOIN sums s ON s.product_id = p.id
WHERE p.quantity != COALESCE(s.audit_sum,0);


-- =============================================================
-- STAGE 7 (READ-ONLY): Sanity check — duplicate movements remaining
-- =============================================================
SELECT product_id, change, reason, COUNT(*) AS cnt
FROM stock_movements
GROUP BY product_id, change, reason
HAVING COUNT(*) > 5  -- only flag clearly duplicated patterns
ORDER BY cnt DESC
LIMIT 20;
