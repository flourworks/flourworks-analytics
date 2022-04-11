-- https://dune.xyz/queries/588864
with

reserves as (
select * from (values
    ('\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'::bytea, 'ETH'),
    ('\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'::bytea, 'ETH') -- WETH
    ) as t (token_address, symbol)
),

hours as (select generate_series('2022-03-06 00:00', date_trunc('hour', now()), '1 hour') as hour), -- 

temp_aave_borrow_rates as (
select 
    date_trunc('hour', a."evt_block_time") as hour,
    avg(a."borrowRate"/1e27) as rate
from        aave_v2."LendingPool_evt_Borrow" a
left join   aave_v2."ProtocolDataProvider_call_getReserveData" b on a."evt_tx_hash" = b."call_tx_hash"
where       a.reserve = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
and         a."borrowRateMode" = '2'
and         a."evt_block_time" >= '2022-03-06'
group by    1
)

, aave_borrow_rates as (
select
    hour,
    (select rate from temp_aave_borrow_rates t where t.hour <= h.hour order by t.hour desc limit 1) as rate
from    hours h
)


, temp_lido_apy as (
select 
    date_trunc('day', evt_block_time) as day,
    (("postTotalPooledEther" / "totalShares" / (lag("postTotalPooledEther" / "totalShares", 1) over (order by evt_block_time)))^365 - 1) AS apy
from    lido."LidoOracle_evt_PostTotalShares"
)


, lido_apy as (
select
    hour,
    (select apy from temp_lido_apy t where t.day <= h.hour order by t.day desc limit 1) as apy
from    (select generate_series('2021-05-01 12:00', date_trunc('hour', now()), '1 hour') as hour) h
)

, rates as (
select 
    h.hour,
    a.rate as eth_borrow_rate,
    l.apy as steth_yield
from        hours h
left join   aave_borrow_rates a on h.hour = a.hour
left join   lido_apy l on h.hour = l.hour
)


, ethmaxy_leverage_ratio as (
select
    h.hour,
    (t0.amount_raw/1e18) as steth,
    (t1.amount_raw/1e18) as weth,
    (t0.amount_raw/1e18)/((t0.amount_raw/1e18)- (t1.amount_raw/1e18)) as leverage_ratio
from        (select generate_series('2022-03-06 00:00', date_trunc('hour', now()), '1 hour') as hour) h
inner join  erc20."view_token_balances_hourly" t0 
            on  h.hour = t0.hour 
            and t0."wallet_address" = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
            and t0.token_address = '\x1982b2F5814301d4e9a8b0201555376e62F82428'
inner join  erc20."view_token_balances_hourly" t1
            on  h.hour = t1.hour 
            and t1."wallet_address" = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
            and t1.token_address = '\xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf'
)

select
    r.hour, i.steth, i.weth,
    r.eth_borrow_rate * 100 as aave_eth_borrow_rate_percent,
    r.eth_borrow_rate,
    r.steth_yield * 100 as steth_yield_percent,
    r.steth_yield,
    i.leverage_ratio,
    ((i.leverage_ratio - 1) * (r.steth_yield - r.eth_borrow_rate) + r.steth_yield) * 100 as ethmaxy_yield_gross_pct,
    (i.leverage_ratio - 1) * (r.steth_yield - r.eth_borrow_rate) * 100 as real_gross_yield_pct,
    ((i.leverage_ratio - 1) * (r.steth_yield - r.eth_borrow_rate) + r.steth_yield) as ethmaxy_yield_gross,
    (i.leverage_ratio - 1) * (r.steth_yield - r.eth_borrow_rate) as real_gross_yield
from        rates r
inner join  ethmaxy_leverage_ratio i on r.hour = i.hour
where       r.hour >= '2022-03-06'
order by    1 desc
