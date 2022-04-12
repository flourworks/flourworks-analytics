--https://dune.xyz/queries/593383

-- This query attributes ETHMAXY in the Uni V3 contract as incentivized or nonincentivized
-- depending on the total G-UNI tokens minted vs. in the staking contract.
-- This attribution holds as long as G-UNI comprises the vast majority of the Uni V3 liquidity.

                    -- [START] total number of G-UNI ETHMAXY/WETH LP Token over time
with
guni_lp_mint as (
select
date_trunc('day',evt_block_time) as day,
sum(value/1e18) as balance
from erc20."ERC20_evt_Transfer"
where contract_address = '\x18D53f4953AD14236602DA05eFAfc0Df4f5d064D' ------ minted token Gelato Uniswap ETHMAXY/WETH LP contract
and "from" = '\x0000000000000000000000000000000000000000'
group by 1
)

, guni_lp_burn as (
select
date_trunc('day',evt_block_time) as day,
sum(-value/1e18) as balance
from erc20."ERC20_evt_Transfer"
where contract_address = '\x18D53f4953AD14236602DA05eFAfc0Df4f5d064D' ------ burned token Gelato Uniswap ETHMAXY/WETH LP contract
and "to" = '\x0000000000000000000000000000000000000000'
group by 1
)

, guni_net_total as (

select day , sum(balance) as balance
from (
            select * from guni_lp_mint lm
            union all
            select * from guni_lp_burn lb
      ) t
      group by 1
                    ) 
                    -- [END] total number of G-UNI ETHMAXY/WETH LP Token over time
                    
                    
                     -- [START] total number of INCENTIVISED G-UNI ETHMAXY/WETH LP Token over time
, lm_guni_lp_mint as (
select
date_trunc('day',evt_block_time) as day,
sum(-value/1e18) as balance
from erc20."ERC20_evt_Transfer"
where contract_address = '\x18D53f4953AD14236602DA05eFAfc0Df4f5d064D' ------ minted token Gelato Uniswap ETHMAXY/WETH LP contract
and "from" = '\xdc5bbb7f25a05259b2bd559936771f8fc0e2c4cb'
group by 1
)

, lm_guni_lp_burn as (
select
date_trunc('day',evt_block_time) as day,
sum(value/1e18) as balance
from erc20."ERC20_evt_Transfer"
where contract_address = '\x18D53f4953AD14236602DA05eFAfc0Df4f5d064D' ------ burned token Gelato Uniswap ETHMAXY/WETH LP contract
and "to" = '\xdc5bbb7f25a05259b2bd559936771f8fc0e2c4cb'
group by 1
)                    

, lm_guni_net_total as (
select day , sum(balance) as balance
       --sum(balance) over (order by day asc rows between unbounded preceding and current row) as running_balance
from (
            select * from lm_guni_lp_mint lm
            union all
            select * from lm_guni_lp_burn lb
      ) t
   group by 1
                    )
                     -- [END] total number of INCENTIVIZED G-UNI ETHMAXY/WETH LP Token over time  
                     
                      -- [START] Total number of G-UNI ETHMAXY/WETH LP Token  vs Total number of INCENTIVIZED G-UNI ETHMAXY/WETH LP Token 

, net_incentivized_guni_gap_days as (                  
select 
g.day, 
coalesce(g.balance,0)        as gunilp, 
coalesce(l.balance,0)        as inc_gunilp
from guni_net_total g 
left join lm_guni_net_total l on g.day = l.day
)


, generate_days as (
select generate_series(min(day), date_trunc('day',now()), '1 day') as day
from net_incentivized_guni_gap_days
)

, ethmaxy_balance_univ3 as (
    select day
        , amount as ethmaxy_amount
    from erc20.view_token_balances_daily
    where wallet_address = '\xfECeCEbf44D38858A0C478C2c4afA2601F5352Fb' -- UNI v3 contract
    and token_address = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2' -- ETHMAXY
)

select g.day
, coalesce(gunilp,0)      as gunilp
, coalesce(inc_gunilp,0)  as inc_gunilp
, sum(coalesce(gunilp,0)) over (order by g.day) as running_gunilp
, sum(coalesce(inc_gunilp,0)) over (order by g.day) as running_inc_gunilp
, sum(coalesce(gunilp,0)) over (order by g.day) - sum(coalesce(inc_gunilp,0)) over (order by g.day) running_non_inc_gunilp
, sum(coalesce(inc_gunilp,0)) over (order by g.day) / sum(coalesce(gunilp,0)) over (order by g.day) as pct_guni_inc
, coalesce(b.ethmaxy_amount, 0) as ethmaxy_in_univ3
, sum(coalesce(inc_gunilp,0)) over (order by g.day) * coalesce(b.ethmaxy_amount, 0)/ sum(coalesce(gunilp,0)) over (order by g.day) 
    as ethmaxy_incent_v3
, (1 - sum(coalesce(inc_gunilp,0)) over (order by g.day) / sum(coalesce(gunilp,0)) over (order by g.day) ) * coalesce(b.ethmaxy_amount, 0)
    as ethmaxy_nonincent_v3

from generate_days g
left join net_incentivized_guni_gap_days ni on g.day = ni.day
left join ethmaxy_balance_univ3 b on g.day = b.day
