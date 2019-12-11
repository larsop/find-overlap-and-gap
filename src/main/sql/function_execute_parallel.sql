DROP FUNCTION IF EXISTS execute_parallel(stmts text[]);

/**
 * From Joe Conway <mail@joeconway.com>
 * https://www.postgresql-archive.org/How-to-run-in-parallel-in-Postgres-td6114510.html
 * 
 */

DROP FUNCTION IF EXISTS execute_parallel(stmts text[], num_parallel_thread int);

CREATE OR REPLACE FUNCTION
 execute_parallel(stmts text[], num_parallel_thread int)
RETURNS text AS
$$
declare
  i int = 1;
  y int = 0;
  num_stmts_executed int = 1;
  stop_st_stmt_index int = 1;
  retv text;
  conn text;
  connstr text;
  rv int;
  db text := current_database();
begin
	
  	LOOP 
  	  stop_st_stmt_index = num_stmts_executed + num_parallel_thread-1;
  	  
  	  IF (stop_st_stmt_index > array_length(stmts,1)) THEN
  	  	stop_st_stmt_index = array_length(stmts,1);
  	  END IF;
  	  
 	  for i in num_stmts_executed..stop_st_stmt_index loop
	    conn := 'conn' || i::text;
	    connstr := 'dbname=' || db;
	    perform dblink_connect(conn, connstr);
	    rv := dblink_send_query(conn, stmts[i]);
	  end loop;
	  
	  for i in num_stmts_executed..stop_st_stmt_index loop
	    conn := 'conn' || i::text;
	    select val into retv
	    from dblink_get_result(conn) as d(val text);
	  end loop;

	  for i in num_stmts_executed..stop_st_stmt_index loop
	    y = y + 1;
	    conn := 'conn' || i::text;
	    perform dblink_disconnect(conn);
	  end loop;

	  
	  RAISE NOTICE 'Done with y=% , array_length= %', y, array_length(stmts,1);

	  num_stmts_executed = num_stmts_executed + num_parallel_thread;
	  EXIT WHEN stop_st_stmt_index = array_length(stmts,1) ; 

	END LOOP ;

  return 'OK';
  end;
$$ language plpgsql;

GRANT EXECUTE on FUNCTION execute_parallel(stmts text[], num_parallel_thread int) TO public;

 