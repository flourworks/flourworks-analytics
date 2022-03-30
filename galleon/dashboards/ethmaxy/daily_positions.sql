-- https://dune.xyz/queries/552491

with positions as (
select * from dune_user_generated.set_protocol_daily_positions
where set_address = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
)
select asteth.day
    , asteth.real_units_per_set_token as steth
    , coalesce(weth.real_units_per_set_token,0) as weth
    , asteth.real_units_per_set_token/(asteth.real_units_per_set_token + coalesce(weth.real_units_per_set_token,0)) as lev_ratio
from positions asteth
left join positions weth on asteth.day = weth.day and weth.component_symbol = 'WETH'
where asteth.component_symbol = 'aSTETH'
order by 1 desc