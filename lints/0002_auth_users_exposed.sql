create view lint."0002_auth_users_exposed" as

select
    'auth_users_exposed' as name,
    'WARN' as level,
    'EXTERNAL' as facing,
    'Detects if auth.users is exposed to anon or authenticated roles via a view or materialized view in the public schema, potentially compromising user data security.' as description,
    format(
        'View/Materialized View "%s" in the public schema may expose \`auth.users\` data to anon or authenticated roles.',
        c.relname
    ) as detail,
    'https://supabase.github.io/splinter/0002_auth_users_exposed' as remediation,
    jsonb_build_object(
        'schema', 'public',
        'name', c.relname,
        'type', 'view',
        'exposed_to', array_remove(array_agg(DISTINCT case when pg_catalog.has_table_privilege('anon', c.oid, 'SELECT') then 'anon' when pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT') then 'authenticated' end), null)
    ) as metadata,
    format('auth_users_exposed_%s_%s', 'public', c.relname) as cache_key
from
    pg_depend d
    join pg_rewrite r
        on r.oid = d.objid
    join pg_class c
        on c.oid = r.ev_class
    join pg_namespace n
        on n.oid = c.relnamespace
    join pg_class pg_class_auth_users
        on d.refobjid = pg_class_auth_users.oid
where
    d.refobjid = 'auth.users'::regclass
    and d.deptype = 'n'
    and n.nspname = 'public'
    and (
      pg_catalog.has_table_privilege('anon', c.oid, 'SELECT')
      or pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT')
    )
    -- Exclude self
    and c.relname <> '0002_auth_users_exposed'
    -- There are 3 insecure configurations
    and
    (
        -- Materialized views don't support RLS so this is insecure by default
        (c.relkind in ('m')) -- m for materialized view
        or
        -- Standard View, accessible to anon or authenticated that is security_definer
        (
            c.relkind = 'v' -- v for view
            -- Exclude security invoker views 
            and not (
                lower(coalesce(c.reloptions::text,'{}'))::text[]
                && array[
                    'security_invoker=1',
                    'security_invoker=true',
                    'security_invoker=yes',
                    'security_invoker=on'
                ]
            )
        )
        or
        -- Standard View, security invoker, but no RLS enabled on auth.users
        (
            c.relkind in ('v') -- v for view
            -- is security invoker 
            and (
                lower(coalesce(c.reloptions::text,'{}'))::text[]
                && array[
                    'security_invoker=1',
                    'security_invoker=true',
                    'security_invoker=yes',
                    'security_invoker=on'
                ]
            )
            and not pg_class_auth_users.relrowsecurity 
        )
    )
group by
    c.relname, c.oid;
