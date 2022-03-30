-- https://dune.xyz/queries/552428
select 
    day
    , count(wallet_address) as num_holders
    , avg(amount_raw / 1e18) as avg_amount_held
FROM erc20.view_token_balances_daily
where token_address = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2' --ETHMAXY
and wallet_address <> '\x0000000000000000000000000000000000000000'
and amount_raw > 0
group by 1
order by 1 desc;