--https://dune.xyz/queries/576204/1077547
-- ETHMAXY NAV
-- 0x0FE20E0Fa9C78278702B05c333Cc000034bb69E2

with

components as (
select * from (values
    ('\x1982b2F5814301d4e9a8b0201555376e62F82428'::bytea, 'aSTETH', 18, 'borrow'),
    ('\xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf'::bytea, 'variableDebtWETH', 18, 'debt')
) as t (token_address, symbol, decimals, asset_type)
)

, transfers as (
select
    date_trunc('minute', a.evt_block_time) as minute,
    b.token_address,
    a.value / (10^b.decimals) as amount
from        erc20."ERC20_evt_Transfer" a
inner join  components b on a.contract_address = b.token_address
where       a."to" = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2' --ETHMAXY Contract

union

select
    date_trunc('minute', a.evt_block_time) as minute,
    b.token_address,
    -a.value / (10^b.decimals) as amount
from        erc20."ERC20_evt_Transfer" a
inner join  components b on a.contract_address = b.token_address
where       a."from" = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2' --ETHMAXY Contract
)

, minutes as (select generate_series(min(minute), date_trunc('minute', now()), '1 minute') as minute from transfers),

temp as (
select
    minute,
    token_address,
    sum(amount) as amount
from        transfers
group by    minute, token_address
)


, composition_summary as (
select
    a.minute,
    coalesce(sum(tb.amount) over (order by a.minute asc rows between unbounded preceding and current row),0) as borrow_balance,
    coalesce(sum(td.amount) over (order by a.minute asc rows between unbounded preceding and current row),0) as debt_balance
from        minutes a
left join   temp tb on a.minute = tb.minute and tb.token_address = '\x1982b2F5814301d4e9a8b0201555376e62F82428' -- borrow token
left join   temp td on a.minute = td.minute and td.token_address = '\xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf' -- debt token
)


, unit_supply as (
select
    a.minute,
    coalesce(sum(b.amount) over (order by a.minute asc rows between unbounded preceding and current row),0) as unit_supply
from        minutes a
left join   (select
                date_trunc('minute', evt_block_time) as minute,
                case
                    when evt_type = 'Issue' then amount
                    else -amount
                end as amount
            from        dune_user_generated."galleon_issuance_events"
            where       symbol = 'ETHMAXY'
            ) b on a.minute = b.minute
)

, final as (
select
    a.minute,
    a.borrow_balance, -- aSTETH
    a.debt_balance, -- variableDebtWETH
    b.unit_supply,
    (a.borrow_balance - a.debt_balance) as aum_eth,
    (a.borrow_balance - a.debt_balance) * c.price as aum_usd,
    ((a.borrow_balance - a.debt_balance) / b.unit_supply) as nav_eth,
    ((a.borrow_balance - a.debt_balance) / b.unit_supply) * c.price as "NAV"
from        composition_summary a
left join   unit_supply b on a.minute = b.minute
inner join  prices.usd c on a.minute = c.minute and c.symbol = 'stETH'
)

select *, usd_price as "Market Price",
(usd_price - "NAV") / "NAV" as premium_discount_percentage
from final a
inner join dune_user_generated.galleon_ethmaxy_pricefeed b on a.minute = b.hour
where a.minute >= now() - interval '30 days'
and a.minute >= '2022-03-09 19:00'