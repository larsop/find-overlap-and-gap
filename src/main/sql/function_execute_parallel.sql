/**
 * From Joe Conway <mail@joeconway.com>
 * https://www.postgresql-archive.org/How-to-run-in-parallel-in-Postgres-td6114510.html
 * 
 */
CREATE OR REPLACE FUNCTION
 execute_parallel(stmts text[])
RETURNS text AS
$$
declare
  i int;
  retv text;
  conn text;
  connstr text;
  rv int;
  db text := current_database();
begin
  for i in 1..array_length(stmts,1) loop
    conn := 'conn' || i::text;
    connstr := 'dbname=' || db;
    perform dblink_connect(conn, connstr);
    rv := dblink_send_query(conn, stmts[i]);
  end loop;
  for i in 1..array_length(stmts,1) loop
    conn := 'conn' || i::text;
    select val into retv
    from dblink_get_result(conn) as d(val text);
  end loop;
  for i in 1..array_length(stmts,1) loop
    conn := 'conn' || i::text;
    perform dblink_disconnect(conn);
  end loop;
  return 'OK';
  end;
$$ language plpgsql;

GRANT EXECUTE on FUNCTION execute_parallel(stmts text[]) TO public;
