   -- https://dune.xyz/queries/586916/1096784
    WITH ethmaxy_user_base AS (
    
        WITH transfers AS (
    
          SELECT
            tr."from" AS address,
            -tr.value / 1e18 AS amount,
            date_trunc('minute', evt_block_time) AS evt_block_minute,
            'transfer' AS type,
            evt_tx_hash
          FROM erc20."ERC20_evt_Transfer" tr
          WHERE contract_address in (select "token_address" from dune_user_generated."galleon_tokens" where symbol = 'ETHMAXY')
        
          UNION ALL
        
          SELECT
            tr."to" AS address,
            tr.value / 1e18 AS amount,
            date_trunc('minute', evt_block_time) AS evt_block_minute,
            'transfer' AS type,
            evt_tx_hash
          FROM erc20."ERC20_evt_Transfer" tr
          WHERE contract_address in (select "token_address" from dune_user_generated."galleon_tokens" where symbol = 'ETHMAXY')
        
        ),
        
        
uniswapv3_add as (

SELECT
  "from" as address,
  amount0 / 1e18 as amount,
  date_trunc('minute', block_time) AS evt_block_minute,
  'uniswapv3_add' as type,
  hash as evt_tx_hash
  
  FROM uniswap_v3."Pair_evt_Mint" m
  LEFT JOIN ethereum."transactions" tx ON m.evt_tx_hash = tx.hash
  WHERE tx.block_time > '5/4/21'
  and contract_address = '\xfececebf44d38858a0c478c2c4afa2601f5352fb'
  
),

uniswapv3_remove as (

SELECT
  "from" as address,
  -amount0 / 1e18 as amount,
  date_trunc('minute', block_time) AS evt_block_minute,
  'uniswapv3_add' as type,
  hash as evt_tx_hash
  
  FROM uniswap_v3."Pair_evt_Burn" m
  LEFT JOIN ethereum."transactions" tx ON m.evt_tx_hash = tx.hash
  WHERE tx.block_time > '5/4/21'
  and contract_address = '\xfececebf44d38858a0c478c2c4afa2601f5352fb'
  
),
        
        lp AS (
              
        SELECT * FROM uniswapv3_add
        
        UNION ALL
        
        SELECT * FROM uniswapv3_remove
        
        ),
        
        contracts AS (
        
          SELECT
            address,
            "type"
          FROM labels.labels
          WHERE "type" = 'contract_name'
        
        ),
        
        liquidity_providing AS (
        
          SELECT
            l.*,
            CASE c.type
              WHEN 'contract_name' THEN 'contract'
              ELSE 'non-contract'
            END AS contract
          FROM lp l
          LEFT JOIN contracts c ON l.address = c.address
        
        ),
        
        moves AS (
        
          SELECT
            *
          FROM transfers
        
          UNION ALL
        
          SELECT
            address,
            amount,
            evt_block_minute,
            type,
            evt_tx_hash
          FROM liquidity_providing
          WHERE contract = 'non-contract'
        
        ),
        
        actions AS (
        
            SELECT
              m.address,
              m.evt_block_minute,
              m.amount,
              m.type,
              m.evt_tx_hash
            FROM moves m
            LEFT JOIN contracts c ON m.address = c.address
            WHERE c.type IS NULL
            AND m.type IN ('mint', 'burn', 'transfer', 'uniswapv3_add', 'uniswapv3_remove')
        
        )
        
        SELECT
          *
        FROM actions
        WHERE address != '\x0000000000000000000000000000000000000000'
        
    ),
    
    contract_bots AS (
    
        WITH contract_bots_temp AS (
        
            SELECT
                address,
                date_trunc('day', evt_block_minute),
                SUM(amount) AS amount,
                COUNT(DISTINCT evt_tx_hash) AS n_tx_hash,
                COUNT(*) AS n_movements
            FROM ethmaxy_user_base
            GROUP BY 1, 2
        
        )
        
        SELECT
            DISTINCT
            address
        FROM contract_bots_temp
        WHERE amount <= 1e-14 AND n_movements >= 2
    
    ),
    
    good_addresses AS (
    
        SELECT
            DISTINCT
            address
        FROM ethmaxy_user_base
        WHERE address NOT IN (SELECT address FROM contract_bots)
    
    ),
    
    temp AS (
    
        SELECT
            address,
            evt_block_minute AS dt,
            amount,
            type,
            evt_tx_hash,
            SUM(amount) OVER (PARTITION BY address ORDER BY evt_block_minute) AS running_exposure
        FROM ethmaxy_user_base
        WHERE address NOT IN (SELECT address FROM contract_bots)
        ORDER BY 1, 2
    
    ),
    
    cohorts AS (
    
        SELECT
            address,
            date_trunc('day', MIN(dt)) AS start_dt,
            to_char(MIN(dt), 'Mon') || ' ' || date_part('year', MIN(dt)) AS cohort,
            CASE 
                WHEN MAX(running_exposure) >= 250 THEN '250+'
                WHEN MAX(running_exposure) >= 50 THEN '50-249'
                WHEN MAX(running_exposure) >= 10 THEN '10-49'
                ELSE '<10'
            END AS exposure
        FROM temp
        GROUP BY 1
    
    ),
    
    cohorts_raw AS (
        
        SELECT
            dt,
            to_char(dt, 'Mon') || ' ' || date_part('year', dt) AS cohort
        FROM temp
        ORDER BY dt
    
    ),
    
    cohort_levels AS (
    
        SELECT
            DISTINCT cohort
        FROM cohorts_raw
    
    ),
    
    current_cohort AS (
    
        SELECT
            to_char(MIN(CURRENT_DATE), 'Mon') || ' ' || date_part('year', MIN(CURRENT_DATE)) AS cohort
            
    ),
    
    completed_cohorts AS (
    
        SELECT
            *
        FROM cohort_levels
        WHERE cohort NOT IN (SELECT cohort FROM current_cohort)
    
    ),
    
    full_address_dates AS (
    
        SELECT
            address,
            dt
        FROM good_addresses
        CROSS JOIN generate_series('2022-03-05'::date, date_trunc('day', NOW()), '1 day') AS dt -- date of the 1st DEX trade in UNIv3
        
    ),
    
    address_dates AS (
    
        SELECT
            t.*
        FROM full_address_dates t
        LEFT JOIN cohorts c ON t.address = c.address
        WHERE t.dt >= c.start_dt
        
    ),
    
    address_date_amount AS (
    
        SELECT
            a.*,
            COALESCE(t.amount, 0) AS amount
        FROM address_dates a
        LEFT JOIN (
            SELECT
                address,
                date_trunc('day', dt) AS dt,
                SUM(amount) AS amount
            FROM temp
            GROUP BY 1, 2
        ) t ON a.address = t.address AND a.dt = t.dt
    
    ),
    
    address_daily_balance AS (
    
        SELECT
            *,
            SUM(amount) OVER (PARTITION BY address ORDER BY dt) AS running_amount,
            ROW_NUMBER() OVER (PARTITION BY address ORDER BY dt) AS day
        FROM address_date_amount
    
    ),
    
    fin AS (
    
        SELECT
            a.*,
            CASE
                WHEN a.running_amount > 0.01 THEN 1
                ELSE 0
            END AS retained,
            c.cohort,
            c.exposure
        FROM address_daily_balance a
        LEFT JOIN cohorts c ON a.address = c.address
    
    ),
    
    include_days AS (
    
        SELECT 
            cohort,
            ROUND(MAX(day) * .85) AS include_days
        FROM fin
        GROUP BY 1
    
    ),
    
    final AS (
    
        SELECT
            a.*
        FROM fin a
        LEFT JOIN include_days b ON a.cohort = b.cohort
        WHERE b.include_days >= a.day
    
    )

, t AS (

SELECT 
   *,
   running_amount - LAG(running_amount, 1) OVER (PARTITION BY address ORDER BY dt) AS net_new
FROM final

),

t2 AS (

SELECT
    address,
    dt,
    CASE
        WHEN net_new IS NULL THEN 1
        WHEN net_new > 0 THEN 1
        ELSE 0
    END AS buys
FROM t

),

t3 AS (

SELECT
    address,
    dt,
    SUM(buys) OVER (PARTITION BY address ORDER BY dt ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS buys
FROM t2

),

t4 AS (

SELECT
    address,
    dt,
    CASE
        WHEN buys < 5 THEN CAST(buys AS varchar(255))
        ELSE '5+'
    END AS buys
FROM t3

)

SELECT
    dt,
    buys,
    COUNT(*)
FROM t4
GROUP BY 1, 2
ORDER BY 1, 2
