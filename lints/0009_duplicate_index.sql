create view lint."0009_duplicate_index" as

select
    'duplicate_index' as name,
    'WARN' as level,
    'EXTERNAL' as facing,
    'Detects cases where two ore more identical indexes exist.' as description,
    format(
        'Table \`%s.%s\` has identical indexes %s. Drop all except one of them',
        n.nspname,
        c.relname,
        array_agg(pi.indexname order by pi.indexname)
    ) as detail,
    'https://supabase.github.io/splinter/0009_duplicate_index' as remediation,
    jsonb_build_object(
        'schema', n.nspname,
        'name', c.relname,
        'type', case
            when c.relkind = 'r' then 'table'
            when c.relkind = 'm' then 'materialized view'
            else 'ERROR'
        end,
        'indexes', array_agg(pi.indexname order by pi.indexname)
    ) as metadata,
    format(
        'duplicate_index_%s_%s_%s',
        n.nspname,
        c.relname,
        array_agg(pi.indexname order by pi.indexname)
    ) as cache_key
from
    pg_indexes pi
    join pg_catalog.pg_namespace n
        on n.nspname  = pi.schemaname
    join pg_catalog.pg_class c
        on pi.tablename = c.relname
        and n.oid = c.relnamespace
    left join pg_catalog.pg_policy p
        on p.polrelid = c.oid
where
    c.relkind in ('r', 'm') -- tables and materialized views
    and n.nspname not in (
        'pg_catalog', 'information_schema', 'auth', 'storage', 'vault', 'pgsodium'
    )
group by
    n.nspname,
    c.relkind,
    c.relname,
    replace(pi.indexdef, pi.indexname, '')
having
    count(*) > 1;
