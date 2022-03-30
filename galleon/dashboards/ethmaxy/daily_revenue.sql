-- https://dune.xyz/queries/549832/1032532
-- ETHMAXY token: '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
WITH 

ethmaxy_mint_burn AS (

        SELECT 
        date_trunc('day', evt_block_time) AS day, 
        SUM("_quantity"/1e18) AS amount 
        FROM setprotocol_v2."DebtIssuanceModuleV2_evt_SetTokenIssued"
        WHERE "_setToken" = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
        GROUP BY 1

    UNION ALL

    SELECT 
        date_trunc('day', evt_block_time) AS day, 
        -SUM("_quantity"/1e18) AS amount 
    FROM setprotocol_v2."DebtIssuanceModuleV2_evt_SetTokenRedeemed"
    WHERE "_setToken" = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
    GROUP BY 1
    
)

, ethmaxy_days AS (
    
    SELECT generate_series('2022-03-01'::timestamp, date_trunc('day', NOW()), '1 day') AS day -- Generate all days since the first contract
    
)

, ethmaxy_units AS (

    SELECT
        d.day,
        COALESCE(m.amount, 0) AS amount
    FROM ethmaxy_days d
    LEFT JOIN ethmaxy_mint_burn m ON d.day = m.day
    
)

, ethmaxy AS (

SELECT 
    day,
    'ETHMAXY' AS product,
    SUM(amount) OVER (ORDER BY day) AS units
FROM ethmaxy_units

)

, ethmaxy_swap AS (

--eth/ethmaxy univ3      https://info.uniswap.org/#/pools/0xfececebf44d38858a0c478c2c4afa2601f5352fb
    
    SELECT --*,
        date_trunc('hour', sw."evt_block_time") AS hour,
        ("amount0")/1e18 AS a0_amt, -- ETHMAXY
        ("amount1")/1e18 AS a1_amt -- WETH
    FROM uniswap_v3."Pair_evt_Swap" sw
    WHERE contract_address = '\xfECeCEbf44D38858A0C478C2c4afA2601F5352Fb' -- liq pair address I am searching the price for
        AND sw.evt_block_time >= '2022-03-05'

)


, ethmaxy_a1_prcs AS (

    SELECT 
        avg(price) as a1_prc, 
        date_trunc('hour', minute) AS hour
    FROM prices.usd
    WHERE minute >= '2022-03-01'
        AND contract_address ='\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' --weth as base asset
    GROUP BY 2
                
)

, ethmaxy_hours AS (
    
    SELECT generate_series('2022-03-01 00:00:00'::timestamp, date_trunc('hour', NOW()), '1 hour') AS hour -- Generate all days since the first contract
    
)

, ethmaxy_temp AS (

SELECT
    h.hour,
    COALESCE(AVG(abs(s.a1_amt)/abs(s.a0_amt)*a.a1_prc), NULL) AS usd_price, 
    COALESCE(AVG(abs(s.a1_amt)/abs(s.a0_amt)), NULL) as eth_price
    -- a1_prcs."minute" AS minute
FROM ethmaxy_hours h
LEFT JOIN ethmaxy_swap s ON s."hour" = h.hour 
LEFT JOIN ethmaxy_a1_prcs a ON h."hour" = a."hour"
GROUP BY 1
ORDER BY 1

)

, ethmaxy_feed AS (

SELECT
    hour,
    'ETHMAXY' AS product,
    (ARRAY_REMOVE(ARRAY_AGG(usd_price) OVER (ORDER BY hour), NULL))[COUNT(usd_price) OVER (ORDER BY hour)] AS usd_price,
    (ARRAY_REMOVE(ARRAY_AGG(eth_price) OVER (ORDER BY hour), NULL))[COUNT(eth_price) OVER (ORDER BY hour)] AS eth_price
FROM ethmaxy_temp


)

, ethmaxy_aum AS (

SELECT
    d.*,
    f.usd_price AS price,
    f.usd_price * d.units AS aum
FROM ethmaxy d
LEFT JOIN ethmaxy_feed f ON f.product = d.product AND d.day = f.hour

)


, ethmaxy_revenue AS (

    SELECT
        DISTINCT
        a.*,
        (a.aum * 0.0195/365) AS revenue -- Streaming Fee: 1.95%
    FROM ethmaxy_aum a
    ORDER BY 1
    
)

SELECT 
    *,
    AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS av
FROM ethmaxy_revenue
where day >= '2022-03-06' -- date of the 1st DEX trade 