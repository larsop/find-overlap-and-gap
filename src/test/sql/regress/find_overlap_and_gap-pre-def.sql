
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
 */

DROP FUNCTION IF EXISTS execute_parallel(stmts text[]);
DROP FUNCTION IF EXISTS execute_parallel(stmts text[], num_parallel_thread int);

-- TODO add test return value
-- TODO catch error on main loop to be sure connenctinos are closed

CREATE OR REPLACE FUNCTION execute_parallel(stmts text[], num_parallel_thread int DEFAULT 3)
RETURNS boolean AS
$$
declare
  i int = 1;
  current_stmt_index int = 1;
  current_stmt_sent int = 0;
  num_stmts_executed int = 1;
  num_stmts_failed int = 0;
  num_conn_opened int = 0;
  retv text;
  retvnull text;
  conn_status int;
  conn text;
  connstr text;
  rv int;
  new_stmts_started boolean; 
  all_stmts_done boolean; 

  db text := current_database();
begin
	
	-- Check if num parallel theads if bugger than num stmts
	IF (num_parallel_thread > array_length(stmts,1)) THEN
  	  	num_parallel_thread = array_length(stmts,1);
  	END IF;

  	
  	-- Open connections for num_parallel_thread
	-- and send off the first batch of jobs
	BEGIN
	  	for i in 1..num_parallel_thread loop
		    conn := 'conn' || i::text;
		    connstr := 'dbname=' || db;
		    perform dblink_connect(conn, connstr);
		    num_conn_opened = num_conn_opened + 1;
		end loop;
	EXCEPTION WHEN OTHERS THEN
	  	
	  	RAISE NOTICE 'Failed to open all requested onnections % , reduce to  %', num_parallel_thread, num_conn_opened;
	  	
		-- Check if num parallel theads if bugger than num stmts
		IF (num_conn_opened < num_parallel_thread) THEN
	  	  	num_parallel_thread = num_conn_opened;
	  	END IF;

	END;


	IF (num_conn_opened > 0) THEN
	  	-- Enter main loop
	  	LOOP 
	  	  new_stmts_started = false;
	  	  all_stmts_done = true;

		  for i in 1..num_parallel_thread loop
			conn := 'conn' || i::text;
		    select dblink_is_busy(conn) into conn_status;

		    if (conn_status = 0) THEN
		    	BEGIN
				    select val into retv from dblink_get_result(conn) as d(val text);
			  		--RAISE NOTICE 'current_stmt_index =% , val1 status= %', current_stmt_index, retv;
				    -- Two times to reuse connecton according to doc.
				    select val into retvnull from dblink_get_result(conn) as d(val text);
			  		--RAISE NOTICE 'current_stmt_index =% , val2 status= %', current_stmt_index, retv;
				EXCEPTION WHEN OTHERS THEN
					RAISE NOTICE 'Got an error for conn %  retv %', conn, retv;
					num_stmts_failed = num_stmts_failed + 1;
				END;
			    IF (current_stmt_index <= array_length(stmts,1)) THEN
			   		RAISE NOTICE 'Call stmt %  on connection  %', stmts[current_stmt_index], conn;
				    rv := dblink_send_query(conn, stmts[current_stmt_index]);
					current_stmt_index = current_stmt_index + 1;
					all_stmts_done = false;
					new_stmts_started = true;
				END IF;
			ELSE
				all_stmts_done = false;
		    END IF;

		    
		  end loop;
-- 		  RAISE NOTICE 'current_stmt_index =% , array_length= %', current_stmt_index, array_length(stmts,1);
		  EXIT WHEN (current_stmt_index - 1) = array_length(stmts,1) AND all_stmts_done = true AND new_stmts_started = false; 
		  
		  -- Do a slepp if nothings happens to reduce CPU load 
		  IF (new_stmts_started = false) THEN 
		  	RAISE NOTICE 'sleep at current_stmt_index =% , array_length= %', current_stmt_index, array_length(stmts,1);
		  	perform pg_sleep(1);
		  END IF;
		END LOOP ;
	
		-- cose connections for num_parallel_thread
	  	for i in 1..num_parallel_thread loop
		    conn := 'conn' || i::text;
		    perform dblink_disconnect(conn);
		end loop;
  END IF;


  IF num_stmts_failed = 0 AND (current_stmt_index -1)= array_length(stmts,1) THEN
  	return true;
  else
  	return false;
  END IF;
  
END;
$$ language plpgsql;

GRANT EXECUTE on FUNCTION execute_parallel(stmts text[], num_parallel_thread int) TO public;

