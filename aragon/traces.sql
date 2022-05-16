select table_type, table_schema
    , split_part(table_name,'_',1) as contract_name
    , split_part(table_name,'_',2) as trace_type
    , split_part(table_name,'_',3) as trace_name
    , table_name
from information_schema.tables
where table_schema in ('aragon') 
;