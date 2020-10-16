
-- example of how to use
-- select ST_Area(cbg_get_table_extent(ARRAY['org_esri_union.table_1 geo_1', 'org_esri_union.table_2 geo_2']));
-- select ST_Area(cbg_get_table_extent(ARRAY['org_ar5.ar5_flate geo']));

-- Return the bounding box for given list of arrayes with table name and geo column name 
-- The table name must contain both schema and tablename 
-- The geo column name must follow with one single space after the table name.
-- Does not handle tables with different srid

CREATE OR REPLACE FUNCTION cbg_get_table_extent (schema_table_name_column_name_array VARCHAR[]) RETURNS geometry  AS
$body$
DECLARE
	grid_geom geometry;
	grid_geom_tmp geometry;	
	grid_geom_estimated box2d;	
	line VARCHAR;
	line_values VARCHAR[];
	line_schema_table VARCHAR[];
	geo_column_name VARCHAR;
	schema_table_name VARCHAR;
	source_srid int;
	schema_name VARCHAR := 'org_ar5';
	table_name VARCHAR := 'ar5_flate';
	sql VARCHAR;

BEGIN

	
	FOR i IN ARRAY_LOWER(schema_table_name_column_name_array,1)..ARRAY_UPPER(schema_table_name_column_name_array,1) LOOP
		line := schema_table_name_column_name_array[i];
--		raise NOTICE 'line : %', line;

		SELECT string_to_array(line, ' ') INTO line_values; 
		schema_table_name := line_values[1];
		geo_column_name := line_values[2];
		

		select string_to_array(schema_table_name, '.') into line_schema_table;

		schema_name := line_schema_table[1];
		table_name := line_schema_table[2];
		raise NOTICE 'schema_table_name : %, geo_column_name : %', schema_table_name, geo_column_name;

		sql := 'SELECT Find_SRID('''|| 	schema_name || ''', ''' || table_name || ''', ''' || geo_column_name || ''')';
--		raise NOTICE 'execute sql: %',sql;
		EXECUTE sql INTO source_srid ;

--		BEGIN
--			sql := format('ANALYZE %s',schema_table_name);
--			raise NOTICE 'execute sql: %',sql;
--			EXECUTE sql;
--			sql := 'SELECT ST_EstimatedExtent('''|| 	schema_name || ''', ''' || table_name || ''', ''' || geo_column_name || ''')';
--			raise NOTICE 'execute sql: %',sql;
--			EXECUTE sql INTO grid_geom_estimated ;
--			raise NOTICE 'grid_geom_estimated: %',grid_geom_estimated;
--        EXCEPTION WHEN internal_error THEN
        -- ERROR:  XX000: stats for "edge_data.geom" do not exist
        -- Catch error and return a return null ant let application decide what to do
--        END;

  
		IF grid_geom_estimated IS null THEN
			sql :=  'SELECT ST_SetSRID(ST_Extent(' || geo_column_name ||'),' || source_srid || ') FROM ' || schema_table_name; 
	    	raise NOTICE 'execute sql: %',sql;
			EXECUTE sql INTO  grid_geom_tmp;
		ELSE
			grid_geom_tmp :=  ST_SetSRID(box2d(grid_geom_estimated)::geometry, source_srid);
			--SELECT ST_SetSRID(ST_Extent(grid_geom_tmp), source_srid) INTO grid_geom_tmp ;

		END IF;

		-- first time grid_geom is null
		IF grid_geom IS null THEN
			grid_geom := ST_SetSRID(ST_Extent(grid_geom_tmp), source_srid);
		ELSE
		-- second time take in account tables before
			grid_geom := ST_SetSRID(ST_Extent(ST_Union(grid_geom, grid_geom_tmp)), source_srid);
		END IF;
		
		raise NOTICE 'grid_geom: %',ST_AsText(grid_geom);
		
	END LOOP;

	
	RETURN grid_geom;

END;
$body$
LANGUAGE 'plpgsql';

-- Grant so all can use it
GRANT EXECUTE ON FUNCTION cbg_get_table_extent (schema_table_name_column_name_array VARCHAR[]) to PUBLIC;


--DROP FUNCTION cbg_content_based_balanced_grid(table_name_column_name_array VARCHAR[], 
--													grid_geom_in geometry,
--													min_distance integer,
--													max_rows integer);

-- Create a content balanced grid based on number of rows in given cell.

-- Parameter 1 :
-- table_name_column_name_array a list of tables and collums to involve  on the form 
-- The table name must contain both schema and tablename 
-- The geo column name must follow with one single space after the table name.
-- Does not handle tables with different srid
-- ARRAY['org_esri_union.table_1 geo_1', 'org_esri_union.table_2 geo_2']

-- Parameter 2 :
-- grid_geom_in if this is point it ises the boundry from the tables as a start

-- Parameter 3 :
-- min_distance this is the default min distance in meter (no box will be smaller that 5000 meter

-- Parameter 4 :
-- max_rows this is the max number rows that intersects with box before it's split into 4 new boxes 


CREATE OR REPLACE FUNCTION cbg_content_based_balanced_grid (	
													table_name_column_name_array VARCHAR[], 
													grid_geom_in geometry,
													min_distance integer,
													max_rows integer) RETURNS geometry  AS
$body$
DECLARE
	x_min float;
	x_max float;
	y_min float;
	y_max float;

	x_delta float;
	y_delta float;

	x_center float;
	y_center float;

	sectors geometry[];

	grid_geom_meter geometry;
	
	-- this may be adjusted to your case
	metric_srid integer = 3035;

	x_length_meter float;
	y_length_meter float;

	num_rows_table integer = 0;
	num_rows_table_tmp integer = 0;

	
	line VARCHAR;
	line_values VARCHAR[];
	geo_column_name VARCHAR;
	table_name VARCHAR;

	sql VARCHAR;
	
	source_srid int; 
	grid_geom geometry;


BEGIN

	-- if now extent is craeted for given table just do it.
	IF ST_Area(grid_geom_in) = 0 THEN 
		grid_geom := cbg_get_table_extent(table_name_column_name_array);
		--RAISE NOTICE 'Create new grid geom  %', ST_AsText(grid_geom);
	ELSE 
		grid_geom := grid_geom_in;
	END IF;
	
	source_srid = ST_Srid(grid_geom);

	x_min := ST_XMin(grid_geom);
	x_max := ST_XMax(grid_geom);
	y_min := ST_YMin(grid_geom); 
	y_max := ST_YMax(grid_geom);

	grid_geom_meter := ST_Transform(grid_geom, metric_srid); 
	x_length_meter := ST_XMax(grid_geom_meter) - ST_XMin(grid_geom_meter);
	y_length_meter := ST_YMax(grid_geom_meter) - ST_YMin(grid_geom_meter);

	FOR i IN ARRAY_LOWER(table_name_column_name_array,1)..ARRAY_UPPER(table_name_column_name_array,1) LOOP
		line := table_name_column_name_array[i];
		raise NOTICE '%',line;
		
		SELECT string_to_array(line, ' ') INTO line_values; 

		table_name := line_values[1];
		geo_column_name := line_values[2];
	
		-- Use the && operator 
		-- We could here use any gis operation we vould like
		
		sql := 'SELECT count(*) FROM ' || table_name || ' WHERE ' || geo_column_name || ' && ' 
		|| 'ST_MakeEnvelope(' || x_min || ',' || y_min || ',' || x_max || ',' || y_max || ',' || source_srid || ')';


		raise NOTICE 'execute sql: %',sql;
		EXECUTE sql INTO num_rows_table_tmp ;
		
		num_rows_table := num_rows_table +  num_rows_table_tmp;

	END LOOP;

	IF 	x_length_meter < min_distance OR 
		y_length_meter < min_distance OR 
		num_rows_table < max_rows
	THEN
		sectors[0] := grid_geom;
		RAISE NOTICE 'x_length_meter, y_length_meter   %, % ', x_length_meter, y_length_meter ; 
	ELSE 
		x_delta := (x_max - x_min)/2;
		y_delta := (y_max - y_min)/2;  
		x_center := x_min + x_delta;
		y_center := y_min + y_delta;


		-- sw
		sectors[0] := cbg_content_based_balanced_grid(table_name_column_name_array,ST_MakeEnvelope(x_min,y_min,x_center,y_center, ST_SRID(grid_geom)), min_distance, max_rows);

		-- se
		sectors[1] := cbg_content_based_balanced_grid(table_name_column_name_array,ST_MakeEnvelope(x_center,y_min,x_max,y_center, ST_SRID(grid_geom)), min_distance, max_rows);
	
		-- ne
		sectors[2] := cbg_content_based_balanced_grid(table_name_column_name_array,ST_MakeEnvelope(x_min,y_center,x_center,y_max, ST_SRID(grid_geom)), min_distance, max_rows);

		-- se
		sectors[3] := cbg_content_based_balanced_grid(table_name_column_name_array,ST_MakeEnvelope(x_center,y_center,x_max,y_max, ST_SRID(grid_geom)), min_distance, max_rows);

	END IF;

  RETURN ST_Collect(sectors);

END;
$body$
LANGUAGE 'plpgsql';

-- Grant so all can use it
GRANT EXECUTE ON FUNCTION cbg_content_based_balanced_grid (	
													table_name_column_name_array VARCHAR[], 
													grid_geom_in geometry,
													min_distance integer,
													max_rows integer) to public;


-- Function with default values called with 2 parameters
-- Parameter 1 : An array of tables names and the name of geometry columns.
-- The table name must contain both schema and table name, The geometry column name must follow with one single space after the table name.
-- Parameter 2 : max_rows this is the max number rows that intersects with box before it's split into 4 new boxes 


CREATE OR REPLACE FUNCTION cbg_content_based_balanced_grid (
													table_name_column_name_array VARCHAR[],
													max_rows integer) 
													RETURNS geometry  AS
$body$
DECLARE

-- sending in a point will cause the table to use table extent
grid_geom geometry := ST_GeomFromText('POINT(0 0)');
-- set default min distance to 1000 meter
min_distance integer := 1000;

BEGIN
	return cbg_content_based_balanced_grid(
		table_name_column_name_array,
		grid_geom, 
		min_distance,
		max_rows);
END;
$body$
LANGUAGE 'plpgsql';


-- Grant so all can use it
GRANT EXECUTE ON FUNCTION cbg_content_based_balanced_grid (table_name_column_name_array VARCHAR[],max_rows integer) to public;

/**
 * Based on code from Joe Conway <mail@joeconway.com>
 * https://www.postgresql-archive.org/How-to-run-in-parallel-in-Postgres-td6114510.html
 * 
 * Execute a set off stmts in parallel  
 * 
 */

DROP FUNCTION IF EXISTS execute_parallel(_stmts text[]);
DROP FUNCTION IF EXISTS execute_parallel(_stmts text[], _num_parallel_thread int);
DROP FUNCTION IF EXISTS execute_parallel(_stmts text[], _num_parallel_thread int,_user_connstr text);
DROP FUNCTION IF EXISTS execute_parallel(_stmts text[], _num_parallel_thread int,_close_open_conn boolean,_user_connstr text);
DROP FUNCTION IF EXISTS execute_parallel(_stmts text[], _num_parallel_thread int,_close_open_conn boolean,_user_connstr text, _contiune_after_stat_exception boolean);


CREATE OR REPLACE FUNCTION execute_parallel(
_stmts text[], -- The list of statements to run
_num_parallel_thread int DEFAULT 3, -- number threads/connections to use
_close_open_conn boolean DEFAULT false, -- always close connection before and open before sending next statement
_user_connstr text DEFAULT NULL, -- check https://www.postgresql.org/docs/11/contrib-dblink-connect.html
_contiune_after_stat_exception boolean DEFAULT true -- If true, will contiunue to run even if one the statements fails
)
RETURNS int AS
$$
declare
  i int = 1;
  current_stmt_index int = 1;
  current_stmt_sent int = 0;
  new_stmt text;
  old_stmt text;
  num_stmts_executed int = 0;
  num_stmts_failed int = 0;
  num_conn_opened int = 0;
  num_conn_notify int = 0;
  retv text;
  retvnull text;
  conn_status int;
  conntions_array text[];
  conn_stmts text[];
  connstr text;
  rv int;
  new_stmts_started boolean; 
  v_state text;
  v_msg text;
  v_detail text;
  v_hint text;
  v_context text;
  

  db text := current_database();
  db_port text;
  
  raise_error text;
  raise_error_temp text;

begin
	
	IF (Array_length(_stmts, 1) IS NULL OR _stmts IS NULL) THEN
       RAISE NOTICE 'No statements to execute';
       RETURN TRUE;
    ELSE
       RAISE NOTICE '% statements to execute in % threads', Array_length(_stmts, 1), _num_parallel_thread;
    END IF;
    
	-- Check if num parallel theads if bugger than num _stmts
	IF (_num_parallel_thread > array_length(_stmts,1)) THEN
  	  	_num_parallel_thread = array_length(_stmts,1);
  	END IF;

  	
    IF _user_connstr IS NULL THEN

      SELECT setting
        INTO db_port
        FROM pg_catalog.pg_settings
        WHERE name = 'port';

      IF db_port IS NOT NULL THEN
        connstr := 'dbname=' || db || ' port=' || db_port;
      ELSE 
        connstr := 'dbname=' || db;
      END IF;
    ELSE
      --connstr := 'dbname=' || db || ' port=5432';
      connstr := _user_connstr;
    END IF;
 	
    RAISE NOTICE '% statements to execute in % threads using %', Array_length(_stmts, 1), _num_parallel_thread, connstr;
	
  	
  -- Open connections for _num_parallel_thread
  BEGIN
    for i in 1.._num_parallel_thread loop
      conntions_array[i] := 'conn' || i::text;
      perform dblink_connect(conntions_array[i], connstr);
      num_conn_opened := num_conn_opened + 1;
      conn_stmts[i] := null;
    end loop;
  EXCEPTION WHEN OTHERS THEN

    GET STACKED DIAGNOSTICS
      v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT,
      v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT,
      v_context = PG_EXCEPTION_CONTEXT;

    IF num_conn_opened = 0 THEN
      RAISE EXCEPTION 'Failed to open any connection: % - detail: % - hint: % - context: %',
        v_msg, v_detail, v_hint, v_context;
    END IF;

    RAISE WARNING 'Failed to open all requested connections % , reduce to  % state  : %  message: % detail : % hint   : % context: %', 
      _num_parallel_thread, num_conn_opened, v_state, v_msg, v_detail, v_hint, v_context;

    -- Check if num parallel theads if bugger than num _stmts
    IF (num_conn_opened < _num_parallel_thread) THEN
      _num_parallel_thread = num_conn_opened;
    END IF;

  END;


	IF (num_conn_opened > 0) THEN
	  	-- Enter main loop
	  	LOOP 
	  	  new_stmts_started = false;
	  
		 -- check if connections are not used
		 raise_error_temp = null;
		 FOR i IN 1.._num_parallel_thread loop
		    IF (conn_stmts[i] is not null) THEN 
		      --select count(*) from dblink_get_notify(conntions_array[i]) into num_conn_notify;
		      --IF (num_conn_notify is not null and num_conn_notify > 0) THEN
		      SELECT dblink_is_busy(conntions_array[i]) into conn_status;
		      IF (conn_status = 0) THEN
		        old_stmt := conn_stmts[i];
			    conn_stmts[i] := null;
			    num_stmts_executed := num_stmts_executed + 1;
		    	BEGIN

			    	LOOP 
			    	  select val into retv from dblink_get_result(conntions_array[i]) as d(val text);
			    	  EXIT WHEN retv is null;
			    	END LOOP ;

				EXCEPTION WHEN OTHERS THEN
				    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT,
                    v_context = PG_EXCEPTION_CONTEXT;
                    RAISE NOTICE 'Failed get value for stmt: % , using conn %, state  : % message: % detail : % hint : % context: %', 
                    old_stmt, conntions_array[i], v_state, v_msg, v_detail, v_hint, v_context;
					num_stmts_failed := num_stmts_failed + 1;
		   	 	    perform dblink_disconnect(conntions_array[i]);
		            perform dblink_connect(conntions_array[i], connstr);
		            raise_error_temp = Format('Failed get value for stmt: %L , using conn %L, state  : %L message: %L detail : %L hint : %L context: %L', 
                    old_stmt, conntions_array[i], v_state, v_msg, v_detail, v_hint, v_context);
                    IF raise_error IS NULL THEN
                      raise_error = raise_error_temp;
                    ELSE
                      raise_error = raise_error||';;;;;'||raise_error_temp;
                    END IF;
				END;
		      END IF;
		    END IF;
	        IF conn_stmts[i] is null AND current_stmt_index <= array_length(_stmts,1) THEN
	            -- start next job
	            -- TODO remove duplicate job
		        new_stmt := _stmts[current_stmt_index];
		        conn_stmts[i] :=  new_stmt;
		   		RAISE NOTICE 'New stmt (%) on connection %', new_stmt, conntions_array[i];
		   		-- Handle null value in statement list
		   		IF new_stmt is not NULL THEN
	    	    BEGIN
		    	  IF _close_open_conn=true THEN
		   	 	    perform dblink_disconnect(conntions_array[i]);
		            perform dblink_connect(conntions_array[i], connstr);
		    	  END IF;
			      --rv := dblink_send_query(conntions_array[i],'BEGIN; '||new_stmt|| '; COMMIT;');
			      rv := dblink_send_query(conntions_array[i],new_stmt);
			      new_stmts_started = true;
			      EXCEPTION WHEN OTHERS THEN
			        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT,
                    v_context = PG_EXCEPTION_CONTEXT;
                    RAISE NOTICE 'Failed to send stmt: %s , using conn %, state  : % message: % detail : % hint : % context: %', conn_stmts[i], conntions_array[i], v_state, v_msg, v_detail, v_hint, v_context;
				    num_stmts_failed := num_stmts_failed + 1;
		   	 	    perform dblink_disconnect(conntions_array[i]);
		            perform dblink_connect(conntions_array[i], connstr);
			      END;
			    ELSE
			      num_stmts_executed := num_stmts_executed + 1;
			    END IF;
				current_stmt_index = current_stmt_index + 1;
			END IF;
		    
		  END loop;
		  
		  EXIT WHEN num_stmts_executed = Array_length(_stmts, 1) OR 
		  (_contiune_after_stat_exception = false AND raise_error_temp is not null); 
		  
		  
		  
		  -- Do a slepp if nothings happens to reduce CPU load 
		  IF (new_stmts_started = false) THEN 
		  	--RAISE NOTICE 'Do sleep at num_stmts_executed %s current_stmt_index =% , array_length= %, new_stmts_started = %', 
		  	--num_stmts_executed,current_stmt_index, array_length(_stmts,1), new_stmts_started;
			perform pg_sleep(0.0001);
		  END IF;
		END LOOP ;
	
		-- cose connections for _num_parallel_thread
	  	for i in 1.._num_parallel_thread loop
		    perform dblink_disconnect(conntions_array[i]);
		end loop;
  END IF;

  RAISE NOTICE '% statements to execute in % threads, done with % , failed num %', 
  Array_length(_stmts, 1), _num_parallel_thread, (current_stmt_index -1), num_stmts_failed;

  		            

  IF num_stmts_failed = 0 AND (current_stmt_index -1)= array_length(_stmts,1) THEN
  	return (current_stmt_index -1);
  else
  	IF raise_error is not null THEN
  	  RAISE EXCEPTION 'Num ok stats % raise_error %', (current_stmt_index -1)-num_stmts_failed, raise_error USING HINT = 'An error happend in one the statemnet, please chem them ';
  	END IF;  
  END IF;
  
END;
$$ language plpgsql;

GRANT EXECUTE on FUNCTION execute_parallel(_stmts text[], _num_parallel_thread int,_close_open_conn boolean,_user_connstr text, _contiune_after_stat_exception boolean) TO public;

