
-- this is internal helper function
-- this is a function that creates unlogged tables and the the grid neeed when later checking this table for overlap and gaps. 
 
DROP FUNCTION IF EXISTS find_overlap_gap_init(
table_to_analyze_ varchar, -- The schema.table name with polygons to analyze for gaps and intersects
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
max_rows_in_each_cell int, -- this is the max number rows that intersects with box before it's split into 4 new boxes 
overlapgap_overlap_ varchar, -- The schema.table name for the overlap/intersects found in each cell 
overlapgap_gap_ varchar, -- The schema.table name for the gaps/holes found in each cell 
overlapgap_grid_ varchar, -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
overlapgap_boundery_ varchar -- The schema.table name the outer boundery of the data found in each cell 
);

CREATE OR REPLACE FUNCTION find_overlap_gap_init(
table_to_analyze_ varchar, -- The schema.table name with polygons to analyze for gaps and intersects
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
max_rows_in_each_cell int, -- this is the max number rows that intersects with box before it's split into 4 new boxes 
overlapgap_overlap_ varchar, -- The schema.table name for the overlap/intersects found in each cell 
overlapgap_gap_ varchar, -- The schema.table name for the gaps/holes found in each cell 
overlapgap_grid_ varchar, -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
overlapgap_boundery_ varchar -- The schema.table name the outer boundery of the data found in each cell 
)
    RETURNS INTEGER
AS $$DECLARE

	-- used to run commands
	command_string text;
	
	-- the number of cells created in the grid
	num_cells int;
	
	-- drop result tables
	drop_result_tables_ boolean = true;
	

	-- test table geo columns name
	geo_collumn_on_test_table_ varchar;

	
BEGIN

	geo_collumn_on_test_table_ := geo_collumn_name_;
	
	IF (drop_result_tables_ = true) THEN
		EXECUTE FORMAT('DROP TABLE IF EXISTS %s',overlapgap_grid_);
	END IF;

	-- create a content based grid
	EXECUTE FORMAT('CREATE TABLE %s( id serial, %s geometry(Geometry,%s))',overlapgap_grid_,geo_collumn_name_,srid_);
	
	command_string := FORMAT('INSERT INTO %s(%s) 
	SELECT q_grid.cell::geometry(geometry,%s)  as %s 
	FROM (
	SELECT(ST_Dump(
	cbg_content_based_balanced_grid(ARRAY[ %s],%s))
	).geom AS cell) AS q_grid',
	overlapgap_grid_,
	geo_collumn_name_,
	srid_,
	geo_collumn_name_,
	quote_literal(table_to_analyze_ || ' ' || geo_collumn_on_test_table_)::text,
	max_rows_in_each_cell
	);
	-- display
	RAISE NOTICE 'command_string %.', command_string;
	-- execute the sql command
	EXECUTE command_string;

	-- Add more attributes to content based grid

	-- Number of rows in this in box
	EXECUTE FORMAT('ALTER table  %s add column num_rows_data int',overlapgap_grid_);

	-- Total number of overlaps that is line found in this box
	EXECUTE FORMAT('ALTER table  %s add column num_overlap int',overlapgap_grid_);

	-- Number of overlaps with surface found this box
	EXECUTE FORMAT('ALTER table  %s add column num_overlap_poly int',overlapgap_grid_);

	-- Total number of gaps that is a point found in this box
	EXECUTE FORMAT('ALTER table  %s add column num_gap int',overlapgap_grid_);

	-- Number of gaps with surface found this box
	EXECUTE FORMAT('ALTER table  %s add column num_gap_poly int',overlapgap_grid_);

	-- Just a check to see if the a exeception
	EXECUTE FORMAT('ALTER table  %s add column ok_exit boolean default false',overlapgap_grid_);
	
	
	
	command_string := FORMAT('CREATE INDEX ON %s USING GIST (%s)',overlapgap_grid_,geo_collumn_on_test_table_);
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string;

	
	-- count number of cells
	command_string := FORMAT('SELECT count(*) from %s',overlapgap_grid_);
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string  INTO num_cells;

	-- create a table to keep the boundery of the data found in the data table
	IF (drop_result_tables_ = true) THEN
		EXECUTE FORMAT('DROP TABLE IF EXISTS %s',overlapgap_boundery_);
	END IF;
	EXECUTE FORMAT('CREATE UNLOGGED TABLE %s( id serial, cell_id int, %s geometry(Geometry,%s))',overlapgap_boundery_,geo_collumn_name_,srid_);

	-- create table where intersected data from ar5 are stored
	IF (drop_result_tables_ = true) THEN
		EXECUTE FORMAT('DROP TABLE IF EXISTS %s',overlapgap_overlap_);
	END IF;
	EXECUTE FORMAT('CREATE UNLOGGED TABLE %s( id serial, cell_id int, %s geometry(Geometry,%s))',overlapgap_overlap_,geo_collumn_name_,srid_);

	-- create table where for to find gaps for ar5 
	IF (drop_result_tables_ = true) THEN
		EXECUTE FORMAT('DROP TABLE IF EXISTS %s',overlapgap_gap_);
	END IF;
	EXECUTE FORMAT('CREATE UNLOGGED TABLE %s( id serial, cell_id int, outside_data_boundery boolean default true, %s geometry(Geometry,%s))',overlapgap_gap_,geo_collumn_name_,srid_);

	return num_cells;

END;
$$
LANGUAGE plpgsql;

GRANT EXECUTE on FUNCTION  find_overlap_gap_init(
table_to_analyze_ varchar, -- The schema.table name with polygons to analyze for gaps and intersects
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
max_rows_in_each_cell int, -- this is the max number rows that intersects with box before it's split into 4 new boxes 
overlapgap_overlap_ varchar, -- The schema.table name for the overlap/intersects found in each cell 
overlapgap_gap_ varchar, -- The schema.table name for the gaps/holes found in each cell 
overlapgap_grid_ varchar, -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
overlapgap_boundery_ varchar -- The schema.table name the outer boundery of the data found in each cell 
) TO public;



DROP PROCEDURE IF EXISTS find_overlap_gap_run(
table_to_analyze_ varchar, -- The table to analyze 
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
table_name_result_prefix_ varchar, -- This is table name prefix including schema used for the result tables
max_rows_in_each_cell_ int -- this is the max number rows that intersects with box before it's split into 4 new boxes, default is 5000
);

DROP PROCEDURE IF EXISTS find_overlap_gap_run(
table_to_analyze_ varchar, -- The table to analyze 
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
table_name_result_prefix_ varchar, -- This is the prefix used for the result tables
max_parallel_jobs_ int, -- this is the max number of paralell jobs to run. There must be at least the same number of free connections
max_rows_in_each_cell_ int -- this is the max number rows that intersects with box before it's split into 4 new boxes, default is 5000
);

CREATE OR REPLACE PROCEDURE find_overlap_gap_run(
table_to_analyze_ varchar, -- The table to analyze 
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
table_name_result_prefix_ varchar, -- This is table name prefix including schema used for the result tables
-- || '_overlap'; -- The schema.table name for the overlap/intersects found in each cell 
-- || '_gap'; -- The schema.table name for the gaps/holes found in each cell 
-- || '_grid'; -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
-- || '_boundery'; -- The schema.table name the outer boundery of the data found in each cell 
-- NB. Any exting data will related to this table names will be deleted 

max_parallel_jobs_ int, -- this is the max number of paralell jobs to run. There must be at least the same number of free connections
max_rows_in_each_cell_ int DEFAULT 5000 -- this is the max number rows that intersects with box before it's split into 4 new boxes, default is 5000
) LANGUAGE plpgsql 
AS $$
DECLARE
	command_string text;
	num_rows int;

	part text;	
	id_list_tmp int[];
	this_list_id int;
	
	-- Holds the list of func_call to run
	stmts text[];

	-- Holds the sql for a functin to call
	func_call text;
	
	-- Holds the reseult from paralell calls
	call_result int;
	
	-- the number of cells created in the grid
	num_cells int;

	overlapgap_overlap varchar = table_name_result_prefix_ || '_overlap'; -- The schema.table name for the overlap/intersects found in each cell 
	overlapgap_gap varchar = table_name_result_prefix_ || '_gap'; -- The schema.table name for the gaps/holes found in each cell 
	overlapgap_grid varchar  = table_name_result_prefix_ || '_grid'; -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
	overlapgap_boundery varchar = table_name_result_prefix_ || '_boundery'; -- The schema.table name the outer boundery of the data found in each cell 


BEGIN

	
	--select * from geometry_columns;
	
	--Generate command to create grid
	command_string := FORMAT('SELECT find_overlap_gap_init(%s,%s,%s,%s,%s,%s,%s,%s)',
	quote_literal(table_to_analyze_),
	quote_literal(geo_collumn_name_),
	srid_,
	max_rows_in_each_cell_,
	quote_literal(overlapgap_overlap),
	quote_literal(overlapgap_gap),
	quote_literal(overlapgap_grid),
	quote_literal(overlapgap_boundery)
	);
		
	-- display the string
	RAISE NOTICE '%', command_string;
	-- execute the string
	EXECUTE command_string INTO num_cells;

	-- Get list id from grid and make id list
	command_string := FORMAT('SELECT array_agg(DISTINCT id) from %s',overlapgap_grid);
		-- display the string
	RAISE NOTICE '%', command_string;
	-- execute the string
	EXECUTE command_string INTO id_list_tmp;


	-- create a table to hold call stack
	DROP TABLE IF EXISTS return_call_list;
	CREATE TEMP TABLE return_call_list (func_call text);

	-- create call for each cell
	FOREACH this_list_id IN ARRAY id_list_tmp
	LOOP 
		func_call := FORMAT('SELECT find_overlap_gap_single_cell(%s,%s,%s,%s,%s,%s)',quote_literal(table_to_analyze_),quote_literal(geo_collumn_name_),srid_,
		quote_literal(table_name_result_prefix_),this_list_id,num_cells);
		INSERT INTO return_call_list(func_call) VALUES (func_call);
		stmts[this_list_id] = func_call;
	END loop;


	COMMIT;
	
	select execute_parallel(stmts,max_parallel_jobs_) into call_result;
	
	IF (call_result = 0) THEN 
		RAISE EXCEPTION 'Failed to run overlap and gap for % with the following statement list %', table_to_analyze_, stmts;
	END IF;
	

END $$;

GRANT EXECUTE on PROCEDURE find_overlap_gap_run( 
table_to_analyze_ varchar, -- The table to analyze 
geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
srid_ int, -- the srid for the given geo column on the table analyze
table_name_result_prefix_ varchar, -- This is table name prefix including schema used for the result tables
-- || '_overlap'; -- The schema.table name for the overlap/intersects found in each cell 
-- || '_gap'; -- The schema.table name for the gaps/holes found in each cell 
-- || '_grid'; -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
-- || '_boundery'; -- The schema.table name the outer boundery of the data found in each cell 
-- NB. Any exting data will related to this table names will be deleted 

max_parallel_jobs_ int, -- this is the max number of paralell jobs to run. There must be at least the same number of free connections
max_rows_in_each_cell_ int  -- this is the max number rows that intersects with box before it's split into 4 new boxes, default is 5000
) TO public;





DROP FUNCTION IF EXISTS find_overlap_gap_single_cell(
 	table_to_analyze_ varchar, -- The table to analyze 
 	geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
 	srid_ int, -- the srid for the given geo column on the table analyze
 	table_name_result_prefix_ varchar, -- This is the prefix used for the result tables
	this_list_id int, num_cells int
);

CREATE OR REPLACE FUNCTION find_overlap_gap_single_cell(
		table_to_analyze_ varchar, -- The table to analyze 
	geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
	srid_ int, -- the srid for the given geo column on the table analyze
	table_name_result_prefix_ varchar, -- This is the prefix used for the result tables
	this_list_id int, num_cells int)
    RETURNS text
AS $$DECLARE
	command_string text;
	
	num_rows_data int;

	num_rows_overlap int;
	num_rows_gap int;
	num_rows_overlap_area int;
	num_rows_gap_area int;
	
	
	id_list_tmp int[];
	
	overlapgap_overlap varchar = table_name_result_prefix_ || '_overlap'; -- The schema.table name for the overlap/intersects found in each cell 
	overlapgap_gap varchar = table_name_result_prefix_ || '_gap'; -- The schema.table name for the gaps/holes found in each cell 
	overlapgap_grid varchar  = table_name_result_prefix_ || '_grid'; -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
	overlapgap_boundery varchar = table_name_result_prefix_ || '_boundery'; -- The schema.table name the outer boundery of the data found in each cell 

BEGIN

	-- create table where intersected data from ar5 are stored
	EXECUTE FORMAT('DROP TABLE IF EXISTS overlapgap_cell_data');
	EXECUTE FORMAT('CREATE TEMP TABLE overlapgap_cell_data( id serial, %s geometry(Geometry,%s))',geo_collumn_name_,srid_);

	-- get data from ar5 and intersect with current box
	command_string := FORMAT(
	'INSERT INTO overlapgap_cell_data(%s)
	SELECT * FROM 
	( SELECT 
		(ST_Dump(ST_intersection(cc.%s,a1.%s))).geom as %s
		FROM 
		%s a1,
		%s cc
		WHERE 
		cc.id = %s AND
		cc.%s && a1.%s AND
		ST_Intersects(cc.%s,a1.%s)
	) AS r
	WHERE ST_area(r.%s) > 0',
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	table_to_analyze_,
	overlapgap_grid,
	this_list_id,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_
);

	execute command_string ;
	
	EXECUTE FORMAT('CREATE INDEX geoidx_overlapgap_cell_data_flate ON overlapgap_cell_data USING GIST (%s)',geo_collumn_name_); 

	-- count total number of rows
	command_string := FORMAT('SELECT count(*) FROM overlapgap_cell_data');
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string  INTO num_rows_data;
	RAISE NOTICE 'Total number of % rows for cell %(%)', num_rows_data, this_list_id,num_cells;


	command_string := FORMAT(
	'INSERT INTO %s(cell_id,%s) 
	SELECT  %L as cell_id, ST_union(r.%s) AS %s FROM 
	( SELECT 
		a1.%s
		FROM 
		overlapgap_cell_data a1
	) AS r',
	overlapgap_boundery,
	geo_collumn_name_,
	this_list_id,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_);

--	RAISE NOTICE '%', command_string;
	
	execute command_string;
	

	-- get data from overlapp objects
	command_string := FORMAT(
	'INSERT INTO %s(cell_id,%s)
	SELECT %L as cell_id, %s FROM 
	(
		SELECT DISTINCT ST_Intersection(a1.%s,a2.%s) AS %s
		FROM 
		overlapgap_cell_data a1,
		overlapgap_cell_data a2
		WHERE 
		a1.%s && a2.%s AND
		ST_Overlaps(a1.%s,a2.%s) AND
		NOT ST_Equals(a1.%s,a2.%s)
	) as r WHERE ST_area(%s) > 0',
	overlapgap_overlap,
	geo_collumn_name_,
	this_list_id,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_	
	);

	--RAISE NOTICE '%', command_string;
	execute command_string ;

	-- find gaps (where it no data)
	command_string := FORMAT(
	'INSERT INTO %s(cell_id,%s)
	SELECT %L as cell_id, r.%s FROM
	( SELECT %s FROM 
		(	
			SELECT DISTINCT (ST_Dump(ST_Difference(cc.%s,r.%s))).geom AS %s
			FROM 
			(
				SELECT %s FROM (
					SELECT ST_Union(r.%s) AS %s FROM
					( SELECT 
						(ST_Dump(ST_Union(a1.%s))).geom as %s
						FROM 
						overlapgap_cell_data a1
					) AS r
					WHERE ST_area(r.%s) > 0
				) AS r
			) AS r,
			%s cc
			WHERE cc.id = %s
		) AS r
	) AS r',
	overlapgap_gap,
	geo_collumn_name_,
	this_list_id,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	geo_collumn_name_,
	overlapgap_grid,
	this_list_id);

	--RAISE NOTICE '%', command_string;
	execute command_string ;

	-- count total number of overlaps
	command_string := FORMAT('SELECT  count(*) 
	FROM ( SELECT  (ST_dump(%s)).geom as geom from %s where cell_id = %s) as r',geo_collumn_name_,overlapgap_overlap,this_list_id);
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string  INTO num_rows_overlap;
	RAISE NOTICE 'Total overlaps is % for cell number %(%)', num_rows_overlap, this_list_id,num_cells;

	-- count number of overlaps with area
	command_string := FORMAT('SELECT  count(*) 
	FROM ( SELECT  (ST_dump(%s)).geom as geom from %s where cell_id = %s) as r 
	WHERE ST_Area(r.geom) > 0',geo_collumn_name_,overlapgap_overlap,this_list_id);
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string  INTO num_rows_overlap_area;
	RAISE NOTICE 'Total overlaps is % for cell number %(%)', num_rows_overlap, this_list_id,num_cells;

	-- count total number of gaps
	command_string := FORMAT('SELECT  count(*) 
	FROM ( SELECT  (ST_dump(%s)).geom as geom from %s where cell_id = %s) as r',geo_collumn_name_,overlapgap_gap,this_list_id);
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string  INTO num_rows_gap;
	RAISE NOTICE 'Total gaps is % for cell number %(%)', num_rows_gap, this_list_id,num_cells;

	-- count number of gaps with area
	command_string := FORMAT('SELECT  count(*) 
	FROM ( SELECT  (ST_dump(%s)).geom as geom from %s where cell_id = %s) as r 
	WHERE ST_Area(r.geom) > 0',geo_collumn_name_,overlapgap_gap,this_list_id);
	-- display
	RAISE NOTICE 'command_string % .', command_string;
	-- execute the sql command
	EXECUTE command_string  INTO num_rows_gap_area;
	RAISE NOTICE 'Total gaps is % for cell number %(%)', num_rows_gap, this_list_id,num_cells;
 
	command_string := FORMAT('UPDATE %s 
	set ok_exit=true,
	num_overlap=%s,
	num_overlap_poly=%s,
	num_gap=%s,
	num_gap_poly=%s, 
	num_rows_data=%s 
	WHERE id = %s',
	overlapgap_grid,
	num_rows_overlap,
	num_rows_overlap_area,
	num_rows_gap,
	num_rows_gap_area,
	num_rows_data,
	this_list_id);

	EXECUTE command_string;
	
	return 'num_rows_overlap:' || num_rows_overlap || ', num_rows_gap:' || num_rows_gap;


END;
$$
LANGUAGE plpgsql PARALLEL SAFE COST 1;

GRANT EXECUTE on FUNCTION find_overlap_gap_single_cell(
	table_to_analyze_ varchar, -- The table to analyze 
	geo_collumn_name_ varchar, 	-- the name of geometry column on the table to analyze	
	srid_ int, -- the srid for the given geo column on the table analyze
	table_name_result_prefix_ varchar, -- This is the prefix used for the result tables
	this_list_id int, num_cells int
) TO public;
 



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


CREATE SCHEMA test_data;
--- give puclic access
GRANT USAGE ON SCHEMA test_data TO public;
--
-- PostgreSQL database dump
--

-- Dumped from database version 11.3
-- Dumped by pg_dump version 11.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_with_oids = false;


CREATE TABLE test_data.overlap_gap_input_t1 (
    c1 integer,
    c2 character(16),
    c3 character(16),
    geom public.geometry(Polygon,4258)
);


--
-- Data for Name: overlap_gap_input_t1; Type: TABLE DATA; Schema: test_data; 
--

COPY test_data.overlap_gap_input_t1 (c1, c2, c3, geom) FROM stdin;
5017	Bjugn           	Trøndelag       	0103000020A2100000010000000800000031E1EDF6B764224044073C6502EE4F402A8FC02C773A23407BD23189C7045040EC3DDC824E9D2340EC1557A35BF54F4055A79CA1666E244035C256139AEA4F40992B4A2EDEA62340B8FA1F3AEFD94F40C8926C6F8A6D2240CB9BA72857DF4F40D98C1EA6514C22401FA0E1D606E34F4031E1EDF6B764224044073C6502EE4F40
713	Sande           	Vestfold        	0103000020A210000001000000050000008C16077E6B3E2440CD37E79DA9CB4D40E008CB682E132440D9B498FAFCD14D403A39140965992440EDC406F5A3D54D40636CE1A8C8CB244026EAFD36E5C34D408C16077E6B3E2440CD37E79DA9CB4D40
5011	Hemne           	Trøndelag       	0103000020A2100000010000000C0000000DC15053ECB921409E1BACF22EA94F40BFD8221C77D221406B1FB1D7A1AD4F4020AB9FC3467C21402213650F47B94F40CC27E93B20172240B27E080CA2BD4F40858BA86BF07A2240AF52E69F1CA84F40FA2E32CFD4D8224011C1B14DADA34F4067F9447E8C4922403F16F83D2A964F4053D039060B5F22404FCFA38267914F405758A4CE64B8214046968E09A28E4F40818596475B862140C48131484C984F409200B68F2BB92140540D3AED1E9C4F400DC15053ECB921409E1BACF22EA94F40
5024	Orkdal          	Trøndelag       	0103000020A210000001000000080000003E872CE3C31823404F91FDAA7AA84F404D479AD364762340A4EE1669ACB54F406029292DB51B2440621E67462FBA4F402575BDD353C82340D9FF0B85EEAA4F404D7136701CBF2340BDDF69186B924F40C901FDF091B92240348EE22BEA994F40097D6D289DAF2240B57075E2D1A14F403E872CE3C31823404F91FDAA7AA84F40
121	Rømskog         	Østfold         	0103000020A2100000010000000600000008C4130B9A6327404838F4CB10DB4D40BA5AD3CE9CDA2740622FB9E931E54D40C8AD05B35AE42740571C44B7A8D94D40DD97BA34D96F27400D5F202EDBCF4D4058B6B928204D27404544AD5413D64D4008C4130B9A6327404838F4CB10DB4D40
5029	Skaun           	Trøndelag       	0103000020A21000000100000007000000DE214B567CD123400FA0DBF815A44F402575BDD353C82340D9FF0B85EEAA4F40DF51D526CE0124400601B9F3BDAF4F40AA37050C4376244079637D104DA84F40FE2E44CEBC4B244050268405E99A4F40F82025DB67F0234084E616E66E954F40DE214B567CD123400FA0DBF815A44F40
1804	Bodø            	Nordland        	0103000020A210000001000000110000009CDD88F2DB9B2A40BABBCACC00E35040C833FA5EAA302B40EF4EAD8FC6EC504053141ACF2B452C40CB5B330E8CE550406A926B0FD5252E4054CEAD087CE7504020E9CF07335D2E40B1289FC59EE45040C415F06B92202E404B38E76FFDDE5040829AE87DE75B2E40C2DCF0683FD95040507A1A0335F02D40246850A64AD15040EEB0BE18D5BA2E403A9BC84FD1CB504011537D5FA0142E40ACBA0A5CEABA5040738BB8606F522D40B05D5EB826C8504029CFF4431A9D2C405209136CF0C95040484B60B9CB972C40670FB36174CE5040183EB3ADBB312B4031DA959A1ECF5040EE8DD9ABB1972A401C474F8DAACA5040039F5EBCBE752940F13B623AA0D150409CDD88F2DB9B2A40BABBCACC00E35040
1824	Vefsn           	Nordland        	0103000020A21000000100000013000000C771DAA358432940C8D93F6E927750400CDB44FEA068294040718C0AC07C5040E6E2EF51DA5D2A405E21025D0B805040B61ACFF6B3882A40D4F4AAF93C86504050F41D3F751D2B4078E0F4376D8B50406487283D97662B40B8654AB2F9885040AF7DAE446E782B407435797C23815040FED83853B75F2B40BC985A87287B5040ECF8E81DDD342B407E87C2BEE07B50406442B3E934882B40CC1FC8D49C74504099DC487A8E482B40FA72ABF6416F5040AC134FB73DD62A40C7F4AE0EA6705040B274C235FCAE2A40501CA7F0836A50402DCD1FEB33662A40E9808DEB516C5040E9C9113732952A40785CACD7966150408A96DA5E2E0B2A4075C95F02B45D504049739C38C5FA294006D7C58C356B5040649C2715642B29408B2A78478B725040C771DAA358432940C8D93F6E92775040
1235	Voss            	Hordaland       	0103000020A210000001000000130000001D3D7DB2138D1840AE925B462D624E40134027DEDA3E19405D0CCFA464684E40880576CC718C1940299F6EB6F9764E40E36D60CDE52C1A40D797623F28724E40FBE491F2CEA01A40A33FF896D27A4E40CABD4845544A1B407B18ED70B5744E402CDC3EF370EA1A40C2EC3A495C6B4E4002387B548DCB1B402DFBFAA5AB6B4E4020FCF32D597C1B40A582A1AA51624E40E3B54A6787F11B40280086DAD35E4E405614113CF3571B40259FC55051504E40CF65466A169B1A40A13EE17FEA514E40B763EBB33E711A40EFE7C38D50434E405CA657A1CEED1940B88A05341C3C4E402E999376A35A184089F1DF7847424E40FD23FD1ED04E1840C93B1DB9634B4E40AF15672BF75E17403981BAF1AD514E40C2B3E8A96EB3174018468918F25D4E401D3D7DB2138D1840AE925B462D624E40
1511	Vanylven        	Møre og Romsdal 	0103000020A210000001000000090000000FBB30790FBB15401A68080D100C4F40596A4F87FE6E15402826631ECF134F405131E9A60CCB15409767A1F7C5194F40EFDD1488DB67174085A8444FFE194F4041C9561C507117405C90C61FDA064F405F03574072D016400644654002FC4E406416B21281C515408ED1A0E1B2FC4E4092887E4F1D061640B6D9ADABFF064F400FBB30790FBB15401A68080D100C4F40
1911	Kvæfjord        	Troms           	0103000020A2100000010000000A0000009BC73A38AD952F404E0B7469D92C51405401D61AB30B304079C10F6B803051404571EE4D8FDC2F40817736BBD03451402E496287BD1C304096AB865BA23B5140E3E43349276C3040423DFB52F52A51409A612496B7EC2F400CC9F4184A275140FAA4B9947A3C2F40BC0CFB8CFE1C5140287774BED0592F4038C26854141F51406822B948772F2F404802B5BA782451409BC73A38AD952F404E0B7469D92C5140
5047	Overhalla       	Trøndelag       	0103000020A21000000100000009000000FF890643943E27404EDF91D3EA1F50400480FE781D0C284024AB07DB5F2B5040D3B23695DC3828405BA029D61A235040D65CED2DB9742840225654A5C62150400A5B3D7B4A24284082E061FB931E50402CB7B3A8CB402840799B4D5945155040C7B734AEBE842740126B3425251250403ADE71EA374F27400F544BD482145040FF890643943E27404EDF91D3EA1F5040
5044	Namsskogan      	Trøndelag       	0103000020A21000000100000010000000C4D86217020A2940908372E0883650405ED69838CC70294094491E005A385040F8D6AEB4216E29408B9C4786F73C5040C064B2D253DE29408E85B613043F504086DFD58FD7D02940557FEE15DC415040991924F9B82B2A402214B0B609475040919B74DA01422B407DFF3184BD4650409BC9A9E000DB2A4028E0C26EC2425040C7BCBB67D35C2A40AB6E0AE60430504042E6E4A834142A40DF0F2381233050402D9FA914293E2A402625F172322950404DF86413932E2A401585A0CD31205040CE9C232DA9942940CBE34D21622C504033C4874F4E082940B28696FE3A2E50400EDF3132E92B294093898D87DA345040C4D86217020A2940908372E088365040
928	Birkenes        	Aust-Agder      	0103000020A2100000010000000B000000BA555CB63127204029FB1933743A4D403C5CD346A0BB1F401A752ECB58474D400676E03BBE5A204016AB378590514D4046345B4B718420407F3D349611444D4076900BE3AEB62040E3816142D54B4D40C4918B7277E3204006332A752F4B4D4044CD1DC40A9E2040EA888DF884324D40438D6204FBBC2040065CD5172D2A4D409DABE236117C20401BCB2AF807204D40C91C84D367152040F3D5F95021244D40BA555CB63127204029FB1933743A4D40
221	Aurskog-Høland  	Akershus        	0103000020A2100000010000000900000064AE957C8A972640241F96E6B0EA4D406D500C880FB626406E414D9C65F94D40583876DDEA0A2740A6A4DFA5C3024E40093D098286A327404283A86D06034E409BC28E47119C2740D1A2919D05F34D40BA5AD3CE9CDA2740622FB9E931E54D4047B728E8F85B274015551D78F4DE4D4035F8AF3358FC264016F5759BFCCB4D4064AE957C8A972640241F96E6B0EA4D40
2011	Kautokeino      	Finnmark        	0103000020A21000000100000014000000DE094A977F4736407AFD99ECDD5E514088D5062BD5B836406A503AD68A6051401E44582771E5364071AA7149746C5140E098CDF4ED35384042E27F8ECD6A5140EB39A8A7316638402BA60B07FC635140D1A15267173438405E0A1A27BF5751407A4F29C9645D3840228FA05EDB4E5140BADE9ABBFC0F3940772A62AF1F39514062187B4CCF6639409C230AF1C4385140274FD56239283940D4CCFE6E31335140B03DB79CCB1D3940C401D400EF285140264023D135E738409092436C7E23514012163A0818DF3740620A99868935514092892CCF6BAC3740FDDE1642272D5140194DC1A9E62A3740C81FCDA639285140AB5BB5AAE05F364044AE14DDDD2D5140B36594663D57364009CBA343F13451406C58F171CEFB354030632330AA445140EA80E5E367873640969862E3554A5140DE094A977F4736407AFD99ECDD5E5140
2021	Karasjok        	Finnmark        	0103000020A21000000100000014000000D389B152646638404D789496036351408B65FF9EA9333840A6D26D6B516B5140F2736DFFDD373840D5C2607F9E735140857A72BC244039408CB83F9DC66E51401D5232E0147F3940488BF62EEA6F51408C7C795B72C4394045348050CD795140C056EC0BA9423A4086414D926B74514011EB19C838E4394011D4DE95976A5140FF6BE5CB00FA39401F8D75320E675140BAAED6086AD73940C9BD01C7436351405AA5BD8A04CB3940EE6AC327F05A514029E977CFBDD839403FFB6F9334595140FA85DA9787B33940806E96340050514071C3424706C73940A4AB1D7C2B41514087D05D27ED97394044A905DF8D3851408EF4DB19501539406BAFF8F8E4385140E793FD8480B738400E3B27B060415140C64CF5ED8BA738400C22EA71E4485140412973E43E343840D653F226A3575140D389B152646638404D78949603635140
2027	Nesseby         	Finnmark        	0103000020A210000001000000080000005BF579E013583C4002C0B86EF08C51409B358CB9C18C3C40008ADF8BC8955140086AFE23AE463D40F349C0EDDA975140A76EAFF76E263D4006254A788F8551400BEC23A829583D402A9E2CA21C84514061F1A77CFA533D40A6E2B749DA7D5140348A925099543C408059BB10597651405BF579E013583C4002C0B86EF08C5140
1004	Flekkefjord     	Vest-Agder      	0103000020A2100000010000000A00000064EF053DEF6B1A406D704B319A364D40BB0E513FE66E1A401821BA41E4474D40A71814A2EACF1A407D15C20151484D40F490A86A12B81A405A2A9D954C404D40A72822A66B791B4039D63F57CA3F4D408F2E66E790B41B40D8D017F5112C4D404FD0F59797231B402285F7FFEB2B4D40B59D85821BEC1A407DE12D53F21B4D4018FFC24B4C9918404BEB2D9B90034D4064EF053DEF6B1A406D704B319A364D40
712	Larvik          	Vestfold        	0103000020A2100000020000000C00000023F32C0A04C02340EAEC92A4A7994D4028DAE05BBB82234041B7E63A96A94D4092B0B65E5A842340C3FCF3DEA8BA4D409D47D012B41E24403307B6378CBC4D40DB53CC2531FC23406CB324B62FA24D402AB2D6040B7F2440FA532357B6874D400613818332922440A7903BE51F634D40838B78FC84F023401EE178DE375C4D40AD77676F219723405DDEE901F9724D409D2A132E9A87234020AE3F1A49814D409D4D0B184AAB23401992364FB87F4D4023F32C0A04C02340EAEC92A4A7994D4005000000C3FF20C5213D2440EEC19EE93F8D4D400D3B46A2C8472440B48227B37D8C4D4058E8A22C244A2440ADF28EDAF18C4D40744D407CEF4224400E9641DA4F8E4D40C3FF20C5213D2440EEC19EE93F8D4D40
1014	Vennesla        	Vest-Agder      	0103000020A2100000010000000700000066F584AC5DCA1E4036DB2D503E214D4082A080D3D0E61E400D499F2A3D2B4D40B97D18D0DE7E1E404EB12621D42C4D402AF501FC4ACD1E407DCBD83D433B4D405B761BD9B128204030E405E533274D4033B7B95D47E51F4030800FB8BA1B4D4066F584AC5DCA1E4036DB2D503E214D40
821	Bø              	Telemark        	0103000020A210000001000000060000008A663C8F38BA21406012652EBDB74D40E9063DFDC80222403ABF6E926BC44D409AA2A8B3D55E2240830E78EB45BB4D408422038991CE214075E83AC6F2AB4D40C9CCFF45B5A321400C63DD119AB24D408A663C8F38BA21406012652EBDB74D40
1420	Sogndal         	Sogn og Fjordane	0103000020A2100000010000000B0000009A55CFD4CAAC1B402F0BF5BC229E4E40DAF67E39EE8A1B4043D926D705A74E40B5923A533F6D1A4051AE440D29A54E4075A13504868C1A408F61E3116BB44E40F51F80DF343F1A403FDCB06CD2B64E40EC013215253C1B404C338BDAFDC84E40A356E745E67E1B40CE559DAAEAB44E4072EDDCCA1DB81D4099269A1260974E4016614D5AC8FE1B40C7BE8BF4BF8B4E40F8DF8DBC48821B40574C4FCC0D944E409A55CFD4CAAC1B402F0BF5BC229E4E40
434	Engerdal        	Hedmark         	0103000020A2100000010000000F00000067FE83FAF9352740873AD10108044F40BC61252A21052740BA5A6AF560124F40CEDB628F0AB52740CD62E5B13A124F4062B20BF879AC2740DD1F74FFEE2F4F400778397C63822840BAF355065F2A4F401DAB342347992840DCACBF4E3D224F40178182247C4628402C212D0EA6DC4E40366446BE1F8D2840D55C2A8BF3D14E40AD9C9197B6F72740D6D46E782ACD4E4086D7381160CC2740F69997697DD94E40DC7A501932B32740D468B879C4C94E40F8079D5D22832740A79117DD19CF4E40BF6B9F021F4527407E4237870DDD4E40F797348AF87727404E91A1EE90F14E4067FE83FAF9352740873AD10108044F40
612	Hole            	Buskerud        	0103000020A2100000010000000500000038ECA3BBC33F2440E10A5FEEA6054E40A516C30A379A24402695732F33104E404005D2AD9AF4244018E956941E044E40367421EF5FB024404FF777166DFA4D4038ECA3BBC33F2440E10A5FEEA6054E40
301	Oslo            	Oslo            	0103000020A21000000100000008000000EE8F795485262540B34FE9E152FE4D40319E8ADB73FA24409A404D9235024E40C58E78C04325254009FBEDCDF20E4E408DB076EE6E7E25406906DB53BF0F4E403C4656841CE72540A05955CB80F94D40833080318BDF254027A48B3675EA4D40726DA808098B25404B7EF3A568E94D40EE8F795485262540B34FE9E152FE4D40
219	Bærum           	Akershus        	0103000020A21000000100000005000000EA64B63621BD2440429B200045F74D404005D2AD9AF4244018E956941E044E401972FD2FF0502540A09CDB5C34F14D4096300EF94D20254017D7F2D7B1E94D40EA64B63621BD2440429B200045F74D40
624	Øvre Eiker      	Buskerud        	0103000020A210000001000000080000001B3B91E0316D2340AC62024C6BE14D4087E6DD3EAA562340DE96322B4BF34D40EEBD3ED8BD1F2440AB3325D467EE4D40D933EF55FEE32340FDDF6A4113E14D40B7D9CA1F1C01244091F169443CD64D404AC17C9538E22340B439752520CB4D403545436513552340D0D63D4DADD84D401B3B91E0316D2340AC62024C6BE14D40
715	Holmestrand     	Vestfold        	0103000020A21000000100000006000000D8F01F84890B24400EBC25E5BCC14D40DD26D109A6D42340418AC9D68ECA4D4007B689E22BFF234021DA24CCF9D44D40BA3E909542B1244036190CF125BF4D40DB1EFC7F84342440A25DA0294AB94D40D8F01F84890B24400EBC25E5BCC14D40
216	Nesodden        	Akershus        	0103000020A210000001000000060000001972FD2FF0502540A09CDB5C34F14D40F3469080467625403C33256347F04D401B63FD8520722540130EDBCFBCE34D40DAC042903D2925405AE8455588DD4D4096300EF94D20254017D7F2D7B1E94D401972FD2FF0502540A09CDB5C34F14D40
1853	Evenes          	Nordland        	0103000020A21000000100000006000000E82108561FB530407673F4F89E205140EB2F601B74563140CEAA7847FF2351402263CD085D3F31400B455570131F514007FD3D4D965C314049A973A7D31D5140E69A6DA0B28E3040C6189A8D9E1C5140E82108561FB530407673F4F89E205140
5030	Klæbu           	Trøndelag       	0103000020A21000000100000006000000D334993A84C12440BEC05E94B8A04F40D28DC61248E324407555BC3577AB4F40B24D053E4D732540210E2BCD44A74F40E591BAE6B13D254089562D0E53A44F40C28BC9BBC76325403C14278E77944F40D334993A84C12440BEC05E94B8A04F40
105	Sarpsborg       	Østfold         	0103000020A21000000100000009000000522D2CF63C0B2640990637461BA34D4025BF4A8C40E52540DEC17A3314A94D40023E4C35FCF22540959FE98591B24D408B8B408E3B3E2640FF5FE12869B54D406D7780A732B22640769E002182A34D4039B079E9AD552640DB7BE4E8DA8B4D40D6C1063C2A242640EC350E773D9A4D40A53DD07AED4226400A45FCCDCE9F4D40522D2CF63C0B2640990637461BA34D40
1822	Leirfjord       	Nordland        	0103000020A2100000010000000900000097FDF6FC61672940C6D7314E168850400DADD699E9A52A4067BB084F6C8F5040FA146B67F6FA2A40380061C80D8E50407EFC7F28F15F2A406818C41E24805040DAFF2971C9CD294049805902C57D504039C288A8425F2940DF451626667D5040786BC0F5CA8C29400951029E66805040D2725E5BEC3B2940E34C60B28482504097FDF6FC61672940C6D7314E16885040
5039	Verran          	Trøndelag       	0103000020A2100000010000000A0000008E7F3356F78125409D1A44C613FD4F405071BA2B0BA925400E7DE000BF055040DD51A75C4F202640F3D5A2625309504005C3B5ED00AF2640F3A1A676AC065040F4E55D8FA07526401E1BA3CB96045040B024EB7E588726407C23948F05005040B1658A06F6632640BD3175BBEAFB4F40427AB7EF1DE324401B82BFA0B6DE4F408C399413A8D424400583BBDB40E44F408E7F3356F78125409D1A44C613FD4F40
519	Sør-Fron        	Oppland         	0103000020A2100000010000000E000000E879C51D4B6923403F61F8302CBF4E40A0833382E8C123406F82476617CF4E405D1E1A3BFE0524409AB2E30C52F44E40322606956354244065EF95ECE2F04E407B03AB1A00EC2340FBE39F3490D94E40411535B730202440DC0AA6971AC74E408078773787F8234079D0F0A3DDB34E40FFA39D1FFE1B2340FCAAFDEAE3B54E40D23FA7AD0B9A22404180B20570A54E40735B8E33E65F2240421B3C4D57AE4E40DD9D6027D3C722408880634E52B14E4064382D17C0AD2240B2482FC178B84E40BA70EAE839C82240FCDBBD5181BD4E40E879C51D4B6923403F61F8302CBF4E40
432	Rendalen        	Hedmark         	0103000020A2100000010000000D000000FDC7F3FFE353254016721E7A64EA4E408CE666E99FE524400F161A5A61FB4E40042C3B0866CC25406C65EE499CF84E401C599EA908FC2540ABAAD90325114F405E51F2F85E6F26404F87DDD1A3194F40B8A06EDDA2F12640A482C92C02154F408EFF9E72EA772740486DF3F99AF14E40BF6B9F021F4527407E4237870DDD4E404DCA28CFC0AF274036C480F605C94E40B16F503834902640E822BF0DE8B44E40AB5AF8B849F52540782B45B882E14E405FBDCC73FDA22540765260D796DE4E40FDC7F3FFE353254016721E7A64EA4E40
1444	Hornindal       	Sogn og Fjordane	0103000020A21000000100000006000000A8B9C8044ADA1940450B43DB88014F40C3747EF55AA11A40D3E71C8132094F401E57612E0B2D1B4018FB683227FC4E4097F035AA5E011A40B6B2684733F64E40F64D98EAAC9E1940331761B229FE4E40A8B9C8044ADA1940450B43DB88014F40
5028	Melhus          	Trøndelag       	0103000020A21000000100000006000000CEA3D053C5CA2340875CBFEFC5934F40FE2E44CEBC4B244050268405E99A4F406F7AAD97696E244067668EE91CAC4F409A8B9DFFAC6E254046376D1A61924F40416975A56B062440531F880F85824F40CEA3D053C5CA2340875CBFEFC5934F40
1121	Time            	Rogaland        	0103000020A21000000100000005000000D0FCC2705081164080482AEA6F5A4D408E2C3389F50017401F930A17A3664D40AEC0825BA1B817403B10D29169574D403B7FEB235C381740636280426F4E4D40D0FCC2705081164080482AEA6F5A4D40
1211	Etne            	Hordaland       	0103000020A210000001000000090000007FA48BD9900E17400984D81790D94D407ED5E7FFDCB51740F2983CD303E44D4087B8F3BF365818406744961BF2DF4D4076ADE4974D541940C593FAE853024E40779C9292001A1A40FB40757FF9EB4D40F3FB7FEDB0351940CB98922F3BE24D4068EC52596FBB18404C43C73104CB4D40CA2A7CF9ADE01740EFDCC99B1BCA4D407FA48BD9900E17400984D81790D94D40
536	Søndre Land     	Oppland         	0103000020A2100000010000000B000000744635BB0F1524400F69300445504E40200E45896CF423404AF77D0C515E4E4090FFA26B1A672440E485193DB7644E4038F68CE9433C244076D32BA495674E40D48EE74C998B24408FF591F17B704E409B0CD41B9AC4244045B45E793E6C4E40541450966FBC2440EEE2AC1A3C644E40E71FA1ACDF192540DE19C8ED27504E40FCFA0440C1A32440FCD632BB6A434E4002A01B98E63F2440E3A4EB308C444E40744635BB0F1524400F69300445504E40
226	Sørum           	Akershus        	0103000020A21000000100000006000000DF928154733F26409CBF1AB152FF4D40A4CCD1E5362526402A7BC813CA064E40448C9B708B8026403C75053BE3094E405983D5F506E126401064C29985FE4D40D5199C307FA42640DB0C1CCF76F04D40DF928154733F26409CBF1AB152FF4D40
417	Stange          	Hedmark         	0103000020A210000001000000070000006751065D6A232640233827C257554E40667305D0380E26408D4506F930634E400482137024A32640B4FE42E0B2644E407C56C4F1D63B2740306293AE72564E40EB9B536A074F2740E9A40FCE5A484E40351110CE07A42640B1359D09163B4E406751065D6A232640233827C257554E40
426	Våler           	Hedmark         	0103000020A2100000010000000E000000B928FB68063B27407DF21CAD375B4E4077E64234D2FF2740D22968E6A26B4E4041DF2BB5AAFF2740FF175091217A4E40D31AF5ED13442840B0AC360B2A764E40B472440BFB3228408FF907A0F0844E4052FAC03E7A522840691B9773DF874E407AFCE98163AA2840DCA02329F1714E4092C3EF5D104C2840A2486797B1704E4070B0F24F7B6728406614F2ABD36B4E40750CB76ACACE27408B4492CA31594E407138FFEA94DE2740C905C0C05C514E4039E63103A2B1274087111F883F4A4E40080F74A0B749274085D11C38604A4E40B928FB68063B27407DF21CAD375B4E40
425	Åsnes           	Hedmark         	0103000020A2100000010000000A0000003397A662C2C827402EFF52C4EF4C4E40A1E7FF3B60CD274034C3F204E3584E4070B0F24F7B6728406614F2ABD36B4E4068E4A2E7F55628401D362AD106724E4085F1E9971CAD284072D482AD086C4E40F1CF06AB52322940A960ED7C4F434E40721D27B3B021284082F6D1645B464E4008C8390757872740D53684425D3C4E4051874F6D5E4827403C8CD7E8A5494E403397A662C2C827402EFF52C4EF4C4E40
1433	Naustdal        	Sogn og Fjordane	0103000020A210000001000000060000007E2B77DCE7991640FB7EB64115C64E40BEF4E32E95E2174058002EBC10D24E40F4F985484C16194051B0D401E2CF4E4092A8C0780A27164047F5D330CBB84E4045AC919A58081540C1315D73A8BE4E407E2B77DCE7991640FB7EB64115C64E40
1412	Solund          	Sogn og Fjordane	0103000020A2100000010000000700000073FBA5F5706910400E8C2E086F9D4E4079A75DC5FD4813406340AED24EA04E40843635AC689F14407DA8E99F158F4E40E861F6F64E7112405EF2976690714E40FF6A798834BD10409B09EB4BAB6A4E401C6A3831245D10401C21FAE877814E4073FBA5F5706910400E8C2E086F9D4E40
5041	Snåsa           	Trøndelag       	0103000020A21000000100000008000000D93309A86A0328403F4690F0910D50404A667BA128E927403E9EEBDE32135040C3D0832C95232A405AAD701CC41B50400116A2E0FD7E2A40B69C6D6C3010504091BCF790166C2A409910767D1A065040D7F9E31D83C1284011883C737CFA4F40F7698FD4631F2840AA38BF82C4065040D93309A86A0328403F4690F0910D5040
1841	Fauske          	Nordland        	0103000020A2100000010000000C0000007B0FE5F97A772E40D6C91DE28ACE5040507A1A0335F02D40246850A64AD15040E2CC421266692E4009F11BAD22DC5040E977696D62C12E40BD1EBF22E9DC504045D0B8F3722D2F406B520BBB8DD550406CB8CFC7D0282F40C1F7A1B974D0504013764EE643932F40C18B010122D45040EBAFF31573673040AAFDA9481ECD50409488203144633040A8DE8DD6E8C25040F455CD79112B304082F6F8B409C15040E775C159922D2F404FC8292CB0CC50407B0FE5F97A772E40D6C91DE28ACE5040
1124	Sola            	Rogaland        	0103000020A21000000100000006000000D5398705D9071440FE3757AFAC754D406B5940B8CCC715409CA9B424B57D4D40AF26469FDCCF16407419B62C82774D401166B52505631640AB9B9A680C684D403AE834DE9E49144091EE6D9B1D644D40D5398705D9071440FE3757AFAC754D40
1120	Klepp           	Rogaland        	0103000020A210000001000000060000003AE834DE9E49144091EE6D9B1D644D4042B81ABCD5151640F6F9A1D6BB6B4D407F90FD1866F41640BFF6EAE80F654D40DA5B93A9F08016402357183FF2594D40AB1C196528A71440C9FEE703D34F4D403AE834DE9E49144091EE6D9B1D644D40
904	Grimstad        	Aust-Agder      	0103000020A21000000100000007000000FDC9D0912BC5204076BB162FE5294D4044CD1DC40A9E2040EA888DF884324D409E2E606F0EFC20400DB52654F23E4D4040E59DE6EC1D2140E7B004F306344D409FA1DA1A712222406FCEC9E408204D40BC6A5022F5812140783D004F6A0A4D40FDC9D0912BC5204076BB162FE5294D40
234	Gjerdrum        	Akershus        	0103000020A21000000100000005000000E880FB1D2BDD2540F863F3179B0A4E40168BD6C19CD42540DBEE846775104E40BD2A665C733B26407D04629F100E4E40E4D82B29CB1C2640DFD3C874CB034E40E880FB1D2BDD2540F863F3179B0A4E40
101	Halden          	Østfold         	0103000020A21000000100000008000000AAE2AB5C984E2640A9CC3416258A4D405CFF7DA891AF26406161C94B10A14D406B89FEF0AA1D2740DA95FBFA3AA14D4075F765CAC96B27400DE4DA9D4F844D4010CD5D56D34D2740AABE3674FF734D40A8396E7F800D2740CE31AC173E704D4043A0EDF208AE264068751CA4B78E4D40AAE2AB5C984E2640A9CC3416258A4D40
906	Arendal         	Aust-Agder      	0103000020A21000000100000007000000C94E96A26F0F2140E21978F8D8364D40D28A20B0DA00214002AF6344E03F4D406C31CB16E6382140FEEE6786F4394D40008EC63530A2214086243867404D4D40FCA716AD69BA2240B66AD72F7C364D409FA1DA1A712222406FCEC9E408204D40C94E96A26F0F2140E21978F8D8364D40
1903	Harstad         	Troms           	0103000020A2100000010000000A000000D2D35969183930408F9DD1D3953551402CE80970640D30407F7FA1628D4051409EF376A7B86E30407B420A9A0154514026C898E3CFBD3040B70DB81C274E5140F99ABCC713B63040864ABD4E484151403CF29EDC20F23040107B9AB6EC3C5140C6966E80357B30402E87A5BD5E235140B49FF4F1D2443040D48FFA9137285140E3E43349276C3040423DFB52F52A5140D2D35969183930408F9DD1D395355140
1017	Songdalen       	Vest-Agder      	0103000020A21000000100000007000000197630BB9E311E405F37C5E23F234D40E58564051B471E40D547F00F492E4D4082A080D3D0E61E400D499F2A3D2B4D40FFB8200EDFC31E40B294FF4371214D409638094602701F40A53C78B0A11E4D40D3BE21A383991F40EE0C2D2F7E0E4D40197630BB9E311E405F37C5E23F234D40
1018	Søgne           	Vest-Agder      	0103000020A21000000100000006000000CF92CF00778B1E40660998D7CF084D409348B397054D1E4030FA37C869114D40B5F1E983468B1F40BE173C6E780E4D40F8D927A2A42C20400C90F0A590EC4C407266198658841F40A5A51A11A9E64C40CF92CF00778B1E40660998D7CF084D40
5023	Meldal          	Trøndelag       	0103000020A2100000010000000A00000028AEE7E5E3F3224022AC6E2AE0844F405BA274FC3FE522409EA23EC8DD944F40348276BBC20B234036F32EC6C0974F40672F9F494DC62340CAF6D7DA6C924F407ECB5082170724404942752E3F844F4029110546D0F92340CE2643087F7B4F4096295EA188E622409B3A6DA7F9714F4040312D1721DC2240F5A24C57217A4F4029F1C2A3C72A2340867A259230814F4028AEE7E5E3F3224022AC6E2AE0844F40
5022	Rennebu         	Trøndelag       	0103000020A210000001000000090000006E3D43EBBD202340F617A95715644F40517C5488D7D72240CB8F925274684F4022540BBA30E62240EC66A1A7F4714F40055B236C3AE623402123F074717C4F409C32A07470A62440CDACB372FF584F40ED68127DCC4924408331656600584F404E50C0221D032440FE699D3C74474F40380485CC44D1234028E06F65DC5B4F406E3D43EBBD202340F617A95715644F40
5033	Tydal           	Trøndelag       	0103000020A21000000100000009000000E0293220F6CB26405DB5E75C127E4F4048A6E8E3358B26406D1480FF7D804F40773577CF08BE26409ACE76DB108E4F405330450B33DD27402C8B4964DC984F4019A8A3C7E71A28403507F0F577974F40574FEE3ABC6F2840B836BBF50A804F40545855A23D262840409417A386734F40E1391A32D4452840F45911BEBB5F4F40E0293220F6CB26405DB5E75C127E4F40
532	Jevnaker        	Oppland         	0103000020A2100000010000000700000044095F44BF8E24404801D41EB7254E4051F81BB677632440F063E4573D334E4016966ED3E7C624407571566207304E40970A948388BB244017BE15B815294E40C316FB0383112540EEB36684EC234E4079C3EE4A21272540CF9589EB02174E4044095F44BF8E24404801D41EB7254E40
2015	Hasvik          	Finnmark        	0103000020A2100000010000000A000000E09C79BC696235403488D7B099A65140931E9F82092D3540AFCCDBA68FB25140152DEDE35F4C364056CFA62736BF5140A5A4793A3FDE364085C8192A43AD5140D2FF80B252D5364017294C6CD5A85140B04DF36643E63640AD65B7C4D0A65140EEB8C175A5B43640F35DA67FFFA251407CA3E011DFAF36404A5E51791D965140354365E1C2913640D68E9AB9EE915140E09C79BC696235403488D7B099A65140
1021	Marnardal       	Vest-Agder      	0103000020A21000000100000009000000D4EF69F0C8B81D4063F698C98F1B4D40E609B9EB248B1D40C9BB7FDAD8244D40C482E89C41E11D408B2D7BF12E3A4D40CA6C4A4849C31E40550CBDCD8D384D4049F45628F41B1E4089225E364D264D4088CC672F4BF01E403D79DDD5C61A4D4065A3DB393AD31E40C06529683C124D403540EA71DBE61D409BA2609F0A134D40D4EF69F0C8B81D4063F698C98F1B4D40
632	Rollag          	Buskerud        	0103000020A210000001000000060000008CD02A3C1FFA2140D9A071A20E024E40F0AD686BFAF02140C4D826C30C0A4E403B3BD0A9896F2240DCFF096383134E403D80EC0E9EEE22401BB2F9F551FE4D4003E01400B85E2240B1464B2590F04D408CD02A3C1FFA2140D9A071A20E024E40
621	Sigdal          	Buskerud        	0103000020A21000000100000007000000B53D7CD4D56F2240B6FBB5F06B134E40E22A87D0434C22402E15F0CB952E4E406342849FF9EA224017E77CECF8254E40CF5F1FD004FC2240A71883B5FF144E40EBE8D7A299B72340E17C255C7AFB4D40346251215A732340A6C474D1EDF24D40B53D7CD4D56F2240B6FBB5F06B134E40
512	Lesja           	Oppland         	0103000020A2100000010000000700000013C3887137EF1F40F49C36F8B6164F40148FD59055C7204005406644932E4F404DFB4A90C61F224027A0E7A1B12F4F40C4F2F8F772A32240C8D0141C6A204F4009ACC9B49DD52140E42BE9B85D004F40901287BD966F2040F53CD2F251004F4013C3887137EF1F40F49C36F8B6164F40
5001	Trondheim       	Trøndelag       	0103000020A2100000010000000500000062F0252D180A244074F71D69C2B44F40BEDC9B7C27FA2440C73144C81FC24F40B24D053E4D732540210E2BCD44A74F40DB7740527E9B24404E45C3CF07A74F4062F0252D180A244074F71D69C2B44F40
5031	Malvik          	Trøndelag       	0103000020A21000000100000007000000EE0E7AAE5C3925409B26408294B34F4069EBE036C719254086134CCA65BF4F40BB777A082AAD2540E9CDF8712EBA4F40768F060D8EB525406D6CFA650EAC4F403C902147DFED2540E6B2647F2AAA4F40F98B725EE07D2540FE28718004A64F40EE0E7AAE5C3925409B26408294B34F40
941	Bykle           	Aust-Agder      	0103000020A2100000010000000B00000016CA7DEC6D171C40FABD8CFF97BD4D400121DC7EA5F71B4001F911726BCC4D40DEE98C97D1DB1C400CEF769A1AD64D40F8A53396EFC41D4037ED336950D44D403460BBEDA5801E406B46B5B81BBB4D4053C6B7BB80A91D408237AB1F90A44D400787C1B7EB631B40A8704FC861974D40ED8D699888531B40B98759479EA84D402AC939978ABA1B40660581053CB34D4082A8B14905881B4026DA9937F3B64D4016CA7DEC6D171C40FABD8CFF97BD4D40
1576	Aure            	Møre og Romsdal 	0103000020A210000001000000070000003FAF611695AF20404143EF4201AE4F4020AB9FC3467C21402213650F47B94F40BFD8221C77D221406B1FB1D7A1AD4F40A31FC95059A3214086706B51EE984F409CFECCAB94B91F408C1EDCCDC68E4F40B157028086F91E4077901FF352954F403FAF611695AF20404143EF4201AE4F40
5038	Verdal          	Trøndelag       	0103000020A2100000010000000700000042EFF22C28C626409605279451E64F40686FC48EF1A9264004C6606BDDE64F404B58BA99947D274030C10963B7F34F40ADF3EAA3FC5D29401BFC8E50B3FC4F40B44588BEAE4C2840DE53C96306CC4F40489A21CED27427402AAE9C1FF5CB4F4042EFF22C28C626409605279451E64F40
5032	Selbu           	Trøndelag       	0103000020A21000000100000008000000A1F43B90685C2540DB5C575C26994F4045C0DDE870532540762C73AA34A74F40CA2CED44D76026400408B0CB87AC4F40A5B7E14EBCE8264042A59F06C2A94F406DA67390774327405FF3DCAA81924F4048B80109DEBD264057D94E420D8E4F4048A6E8E3358B26406D1480FF7D804F40A1F43B90685C2540DB5C575C26994F40
1046	Sirdal          	Vest-Agder      	0103000020A210000001000000100000001876B6726F341A4039E271F7C84F4D401DFA0AFD88BE1940EC64792D1D534D40EF27B2A9487D1A40DDC23ED72C594D409861B8DF87121A40E86534963A624D402E8614AD286F1A40F0D9143AA6704D407593A55A4C3E1A40B0F1994A79744D4032967D61E9C31B40247511700F984D40D3CC74DDC6D11C400C79310A51924D4024547B09A8B71C40E0885E2A5F814D40A4FDB2BC9F6D1C406639557E757F4D40DD30B813329F1C40C76EAC4722744D40BAD9101C14AC1B40A2F5D72447654D40B228686D3F4F1B40F0014625C7414D40F490A86A12B81A405A2A9D954C404D40A71814A2EACF1A407D15C20151484D401876B6726F341A4039E271F7C84F4D40
2003	Vadsø           	Finnmark        	0103000020A2100000010000000B0000009C9F51540E463D400D7E30A50B935140086AFE23AE463D40F349C0EDDA9751404582BE7823FB3C40120122B1049A514047DE6102D9393D4065AAE9F0939E51408710EB2100AB3D40C6A7BC0D4597514038A625B361983D40EF91BF51B8955140D34BB2E5D0753E40DCA31762608D5140430D563FC4EE3E40EA132C21D1815140CB795947F20D3E4003A02DD5667E5140A76EAFF76E263D4006254A788F8551409C9F51540E463D400D7E30A50B935140
5049	Flatanger       	Trøndelag       	0103000020A2100000010000000B000000B121A8A7A41724406D0F940A1B26504077CAB1C04D662340E7A349E99E2E5040B43FE3E38A9B2340F23C873ECD3150404684806A8CDC2440F09B82C7AE255040E5463703F6792540D098D5483B2A50400E072AF40CFE25408B94C1329B275040FC94B0607D3726406CECE11D8F2450404DE656F324072640B8EFD3EF8C1F50404EF3869853332640C9C31D2063175040211C773806A12540D28A9033D6125040B121A8A7A41724406D0F940A1B265040
5025	Røros           	Trøndelag       	0103000020A2100000010000000A000000499D17A42E6426400F7FD18F4F4B4F40D1402D1E0A452640AF8CE44FE9564F40E21030E87D9C26404A31D65B4A5F4F402B7D8044A09D27401A74ECC3216A4F4060CC1E5724232840422DA30A45624F40E1391A32D4452840F45911BEBB5F4F402EE12FE8BE1C2840167BC75D534E4F400778397C63822840BAF355065F2A4F40DD74B816BA1C2740E494811F902F4F40499D17A42E6426400F7FD18F4F4B4F40
1563	Sunndal         	Møre og Romsdal 	0103000020A2100000010000000B00000033587D03C7B920409DDB0B3522434F40B4203955806F2040D802CCB9E1494F404817211D0A95204074C584FD93564F4055F61A518A692040185CB2557B5E4F40B341D5269CE1204001A0EAD009644F40D9344300CDBE2040CC4E5A467B784F40E7C60845D67C2240A6672F0414474F40BC7DC22C045E224022B44C539C364F40F1CEA84B38F12140ABF23C964C2D4F40004F8977BA2C214084401B5D44344F4033587D03C7B920409DDB0B3522434F40
5054	Indre Fosen     	Trøndelag       	0103000020A2100000010000000A00000016BA60D050902340F0A1564BFAD14F40A05538A1597C23407583B2EBFED54F40D2637DE588AD2440FF032F9ECEEE4F40427AB7EF1DE324401B82BFA0B6DE4F4044B960B4E55525406925DC3FC5E54F400388B5D93EC02540F978475C8DD94F40BEDC9B7C27FA2440C73144C81FC24F406029292DB51B2440621E67462FBA4F4081EAE3FF38C92340680200F8BABF4F4016BA60D050902340F0A1564BFAD14F40
5021	Oppdal          	Trøndelag       	0103000020A210000001000000090000000877C97D5677224030D5DA3C52484F400FF0EF4205D721402CD1A34E1B5B4F40517C5488D7D72240CB8F925274684F40C17BAD0698C823408834EA56A25C4F403EDEC468F63124403C584867C2364F40B0F29FFC2E342340FB2940A7BB204F404DFB4A90C61F224027A0E7A1B12F4F40BC7DC22C045E224022B44C539C364F400877C97D5677224030D5DA3C52484F40
5027	Midtre Gauldal  	Trøndelag       	0103000020A2100000010000000900000005EDFAAA9520244080F59EE8A2734F40416975A56B062440531F880F85824F40917CF7CA93482440B380B00864874F409A8B9DFFAC6E254046376D1A61924F40610CC6C32AFF2540C893D94BFC874F4002C70545AFE32540329460A6ED644F40A5D246840E7B2540EB58FBA69E524F409C32A07470A62440CDACB372FF584F4005EDFAAA9520244080F59EE8A2734F40
5026	Holtålen        	Trøndelag       	0103000020A2100000010000000A0000001D25E314CCE225409221683C117A4F40CD504D8F1FFF254089AA6EC0FB874F4054A3A14B144B26409B565CE12C884F401BB828D565292740D5B80318A4704F4033754B7DE18F27401D6DD2F28B724F402B7D8044A09D27401A74ECC3216A4F40C42A3BC1313F2640720782B8AB544F40E4B5236BB0952540108B803EEC564F4002C70545AFE32540329460A6ED644F401D25E314CCE225409221683C117A4F40
5018	Åfjord          	Trøndelag       	0103000020A210000001000000090000008378C13D4E972340E9F209EFA9F74F402A8FC02C773A23407BD23189C7045040A5E935870765234052AD8B77EF0C50408E7E4FE7F36A244013AA616E4C035040D2E688A01CFD244006024AC3070850408EDC1C1CC2C225409D46CFAF43065040EECFEC450DE724407AFD790DB8E24F40D2637DE588AD2440FF032F9ECEEE4F408378C13D4E972340E9F209EFA9F74F40
402	Kongsvinger     	Hedmark         	0103000020A2100000010000000B000000212D98BDA7CF2740D1672439711A4E40528EF60FBEDF2740F5C1CFB0D6214E40044BA133D6AB2740B0DF3022F72D4E4003E38F5E2E7A2840AA82CB3358274E407F91D25AB09F28409A05EE4EF6324E4001D784342DDB2840E8E84890E52F4E40892E34BB741529400E330B96C0184E409241AD31A5B728408F206594A8FD4D404A8AB618FD7B2840FD2278B896114E40609ABEBC0ED42740BF6D58E2500B4E40212D98BDA7CF2740D1672439711A4E40
1920	Lavangen        	Troms           	0103000020A2100000010000000700000050CDF79DB3703140DFCC193A963251403EB4541EEFD7314095BB86B9313551403274805AFA0C32401655243ECD2A5140EA70581BF6053240953118ECF0265140A8D591B32FCC31408A55CCA863265140FD2E6726C8D731403BE008C74F2C514050CDF79DB3703140DFCC193A96325140
1939	Storfjord       	Troms           	0103000020A2100000010000000C000000D809033CEEE33340613CBBCFB159514061B83172BA78344033B20FBF805C514040F9373F428234407265011FA056514008CBD48234083540702EFDEAFE4E514094073CBAD1FC344041FB0E8A484C5140DFA33721D21B3540D13C71C6A6465140ADD21233BB0E35402C51DE915242514011A7E16EA2B73440168D1AA9AA475140715F9F256EF93340441BAEFF344451403411628E76EB334027B25BC8294D51409414B55368A43340A91BB9BE0D525140D809033CEEE33340613CBBCFB1595140
1849	Hamarøy         	Nordland        	0103000020A21000000100000010000000EF62FB59C5782F40626524B50EFE5040AC7973A29EBC2E400E75718737FC50400ADA31A4061F2E40CA09B873C3075140BF448C18D2962F401FCA05BDE20F5140555337DD1B02304006D910C18B0D514095B2425A450730402A3058F13B07514025DE221A1FCC2F408FD6832B9A0451408E24BFEA641B3040A300FA13F6FD50400EDFD960E00D30407B3B1D02ECF75040CF10C6B1688E3040453E1A9B6BE9504040C20F5D566830404116997B2DE25040AD0DD82022513040B6183AFA20E45040A7D2CBA0A81B3040B97283EFA1EE5040407F1CC22DFC2F4067D1C0E99DED50403D1B8047E97B2F40483208FE3DF65040EF62FB59C5782F40626524B50EFE5040
123	Spydeberg       	Østfold         	0103000020A210000001000000050000001D9376F6740926408880F04376CE4D40E8631D4C4E2426402E457E6096D94D4021306413A57B26408F7A2F43E1D44D40DF4A0FFB55F42540A18B9BA16DC04D401D9376F6740926408880F04376CE4D40
901	Risør           	Aust-Agder      	0103000020A21000000100000006000000A9685F7D10262240F4430F134D594D40DBE85E4074EE214003AB4AA0745A4D40392D9858DE612240DE3EA094396A4D40AB68E0FC765623408D941A4A394D4D4008C920B134102340F9FE1D7E06434D40A9685F7D10262240F4430F134D594D40
2004	Hammerfest      	Finnmark        	0103000020A2100000010000000E000000691AAFE770A436408DFC7031B2B45140152DEDE35F4C364056CFA62736BF514067E1B1CD593F37403A179328EBCB51403024A80C59D1374005A77F5B30BB51402D85BEA4142C3840510C4365CBAA5140AF20C982DCA33740F3982FBC8FA45140EDCAD10A106A3740855C8488B69C5140B1AD85B659DF36406F84AA0B3A995140D8EFECCEF1B036407116D160AC9C5140DE78F4DFD1B4364006B535CA08A35140B04DF36643E63640AD65B7C4D0A65140D2FF80B252D5364017294C6CD5A85140A5A4793A3FDE364085C8192A43AD5140691AAFE770A436408DFC7031B2B45140
2014	Loppa           	Finnmark        	0103000020A2100000010000000D000000FE85F0E691B134400A9929C31EA15140573320C0CF7A34403A58D70C08AD5140931E9F82092D3540AFCCDBA68FB25140E09C79BC696235403488D7B099A65140302CE5C05B7C3640B81379B928935140D08E383E346736409EBD17F6238F5140C48939978B9A36402C2323FB54865140A207BAD382373640D1D14AFE798251400E06FF31871E3640777E7A07E98A51407651E78846D43540EC78107973865140197C1780EAA0354077860753208C5140AE392A09B201354074B2DB47338F5140FE85F0E691B134400A9929C31EA15140
616	Nes             	Buskerud        	0103000020A21000000100000006000000D6A1F3E92463214075516A9B22414E40880B0F3B46EA21400E828A0FD8554E40FA708EFCD4A22240D54D88A978594E40CE11EA3CCBDE2240EA0E2E86BE4C4E403F88B32DE03B2240DAB7D8F196324E40D6A1F3E92463214075516A9B22414E40
1833	Rana            	Nordland        	0103000020A21000000100000014000000DCC1F5C338912A40E144C3C152935040F0C6B6D607622A40656720A181935040C94C97AFA3812A40387769D5A59950400CDF003560A02B40DE6C4EFBF39D504062FFA6176F8C2B4058DEE272C1A250408353117CABBE2B401D10B5EF02A85040A7E1A88C186E2C40574D60B1EEA75040A706087F1B5E2D4023F8C3252DB050401B4FE84F358F2D40F4B41AF656A95040B757F6F82FFC2D403A856F3E9BAB5040F49CC4433AF62D405CD8869387B15040ACB7952DE2502E40F2B2A60FF4B15040D493B58117722E40AD3CD5600DA550401827FB3C15112F405F5A50F1B3A35040CC107DE123C12E402DD2B0DBFE9E504063E365D52EF82E4069E86DCF1392504019BFB640BE0E2D40333E8DA51D8650406672CAD39FB82B408BD30DE4259050404F9B72AC66C42A40E8F0A40F9D8E5040DCC1F5C338912A40E144C3C152935040
1219	Bømlo           	Hordaland       	0103000020A21000000100000007000000EF8DABAE046D1240D823742CEEF44D40CB28DB0959501440068E6C9124F84D402F3094595BE31540C6E885EF79DD4D406080322EE9BF14402D2CF52DFBC14D4076838C502D6A1240F6A0D3E371C74D40E4591A0134B01240F1B4D2551DD54D40EF8DABAE046D1240D823742CEEF44D40
1106	Haugesund       	Rogaland        	0103000020A2100000010000000600000001108E3727C413403209DBA788B84D40D5B3F03C924612400D707B4576C04D4076838C502D6A1240F6A0D3E371C74D40FF5F730ACB961540D55992F6DABD4D40968CA2418E2C15401B95301F0AB14D4001108E3727C413403209DBA788B84D40
1551	Eide            	Møre og Romsdal 	0103000020A2100000010000000800000080C27E6D550B1D40E3F569CFAE764F40FED490F3D1DD1C40489E5AEB36874F401D1EF533DB311B40FE63BBF2899F4F402E01E70758DD1C408B6CB469B5934F40AC5CCB2A6C581D400146DEC2507D4F40B8DCD06719761E4023CB88675F734F40A1F278321C4D1D4087B94CC6F66C4F4080C27E6D550B1D40E3F569CFAE764F40
1259	Øygarden        	Hordaland       	0103000020A210000001000000050000002D1723F785101140FD30C0800A584E4031BD7F5F561B13406D60EDC9F15D4E4074ED6936FBFC1340BF3B6967E33C4E404FCE278AC4AB11409EE8AC7DCF344E402D1723F785101140FD30C0800A584E40
1151	Utsira          	Rogaland        	0103000020A210000001000000060000003F04AD7AFC1F1240BF22BDC0DEB84D4050040337E69C134027067916F0B04D408BE678888D1F14400F6141531CA64D409BF20D5393DE1240CD8DD68112894D402C5DDE63C5E11140ECBA76444C9C4D403F04AD7AFC1F1240BF22BDC0DEB84D40
1101	Eigersund       	Rogaland        	0103000020A21000000100000008000000A32AF26D20671740E3A27117AF3E4D40878630D32C4B19402CC3B83574504D404010A07870FD19404F706AE7114E4D40C6905286930E1940AE96E55B97474D40075B2BA5D91C194045AEF7095B3C4D402B591CEBAA7C17401884302F44144D407D1B6CD7021416404FFB65A18F2A4D40A32AF26D20671740E3A27117AF3E4D40
1234	Granvin         	Hordaland       	0103000020A21000000100000006000000AC3B9AD4CC7E1A406F4ACF8D79464E40CF65466A169B1A40A13EE17FEA514E40022D211DA75D1B4029A2A7EA874F4E4029F3FE9A12401B4026BCE32CDC414E40F5140E6870F7194057E4C8567B394E40AC3B9AD4CC7E1A406F4ACF8D79464E40
1411	Gulen           	Sogn og Fjordane	0103000020A21000000100000009000000986B3BE45B251340D84E0BC867804E40843635AC689F14407DA8E99F158F4E401AF3A39177AC1540A05AD43600864E40ED5ABBC14A5316409F9258B8F28B4E40D535BC72D37F1640A3ADA36CF97E4E40580A095424E814407EB26C2583764E40C636BEA985701440D98FED421B674E40E861F6F64E7112405EF2976690714E40986B3BE45B251340D84E0BC867804E40
1252	Modalen         	Hordaland       	0103000020A21000000100000005000000A3AEFC88F27517402320036BD5794E400335771CAD111840B904E3AA82844E40D09B101869D718405BE49165F5744E404BAF3D5F24A716404722CD16A55E4E40A3AEFC88F27517402320036BD5794E40
420	Eidskog         	Hedmark         	0103000020A2100000010000000700000042186FFB109F2740D1D60FC087FE4D40FE88247209A92740FAF1DA2672084E405CA0E3691C4B284082F52B581F124E4060909E86748028401B0B3C1241114E409241AD31A5B728408F206594A8FD4D401A315215EFAD2740EA196BD49EEB4D4042186FFB109F2740D1D60FC087FE4D40
1525	Stranda         	Møre og Romsdal 	0103000020A2100000010000000C000000C49E4286DFD21A406730C1AE0D0B4F40E4E80C24F2221B4034EF19219C174F400265C170A0D11A40453D66D3461C4F40BF30A78762691B402E54A1FDA22F4F405D789E25BAAB1C4020A4BC0D99284F4008CB7F9807241C402FACC56B8A254F40E4519C8DA7181C40D424050BA31B4F408745771886AD1D4089C326B8550A4F40B6DE0CE77C651D40E669ABB7FB004F40A17AD9F50B5D1B400FB90D7F55FB4E40C3747EF55AA11A40D3E71C8132094F40C49E4286DFD21A406730C1AE0D0B4F40
1531	Sula            	Møre og Romsdal 	0103000020A2100000010000000500000013CCEAC73B0C184076F550CADE384F408719AFB877E918402ED9DA318A3A4F4061967297FA80194003C0BFB16A364F4005E0259CA7AA1840848689A2EF2E4F4013CCEAC73B0C184076F550CADE384F40
1417	Vik             	Sogn og Fjordane	0103000020A21000000100000009000000344AEB41C7A318408226A4CD4B844E4091DADE7177C618402F327C6AB6914E40D69127D4A8EF194002D5332AA38C4E4090FA030B239E1A40E79F5D5769984E401D4580D7CD1E1C40E7C58068B4874E4085310A3935001B403C3CCF2691774E408313D104973719408D1971EABB704E40248736054D8B1840AC855B691E784E40344AEB41C7A318408226A4CD4B844E40
441	Os              	Hedmark         	0103000020A2100000010000000800000046F630B4FE3D2640CFBFD87E54394F40D5A229CB4D7A2540E99ADD5C3D4B4F40A5D246840E7B2540EB58FBA69E524F40C25D0D40BC3E2640755C10C4B5544F40DD74B816BA1C2740E494811F902F4F4062B20BF879AC2740DD1F74FFEE2F4F40E1826BA231B52740CC2AF3AA4B124F4046F630B4FE3D2640CFBFD87E54394F40
521	Øyer            	Oppland         	0103000020A210000001000000060000005A55D379A3692440B297C844B5AA4E40B8F9290D6F5C254025692A285DBC4E40F3E5134AB7B22540B26553CA0CA24E40126D9BD771D6244009E084866C974E4009F9113847DF2440C906141A179E4E405A55D379A3692440B297C844B5AA4E40
533	Lunner          	Oppland         	0103000020A21000000100000006000000B1FF131F1F1025405774DFD73F1F4E40670482711EEA24404466157399284E4056C33618BFBA2540609E23B12E284E4081FAFC65558A254000F6020256134E404111C49A913325407AB22D97D8104E40B1FF131F1F1025405774DFD73F1F4E40
427	Elverum         	Hedmark         	0103000020A2100000010000000B0000008776650BE3AE2640FFCF21BCE27E4E407DCDE96A6D79274023C03D86259A4E40B260CA3D90E62740E660235904874E4052FAC03E7A522840691B9773DF874E40B472440BFB3228408FF907A0F0844E40D31AF5ED13442840B0AC360B2A764E4041DF2BB5AAFF2740FF175091217A4E40BD63CAE8EFFF274052FFAB4DA86B4E40FCB687142D7E2740B08B0698495F4E40ABDE44FBFA07274037A660DF07644E408776650BE3AE2640FFCF21BCE27E4E40
428	Trysil          	Hedmark         	0103000020A2100000010000000E000000E66CFAAF65AE27405039A9C34EB24E40E54E2F6B9F8A27403BF13EC3EBC04E4086D7381160CC2740F69997697DD94E40AD9C9197B6F72740D6D46E782ACD4E40366446BE1F8D2840D55C2A8BF3D14E4063F9C0987D2329409F6F23B0CCC84E406983C8DCDFBD2940ABF229ACA1AD4E40465462C2E05C2940F96100E29E874E4091D18005AF722840DBECE289AC814E4089BF79CFC930284057E5CC19628B4E40B260CA3D90E62740E660235904874E407DCDE96A6D79274023C03D86259A4E40EEAD392709D5274083BAE0D16DA24E40E66CFAAF65AE27405039A9C34EB24E40
1426	Luster          	Sogn og Fjordane	0103000020A2100000010000000D000000EC013215253C1B404C338BDAFDC84E40C4CF464167A61D401C7CBADDC2ED4E40FC16AACD270E1E4067B4CB461ADD4E402CC9983F03A21F40782482FB5FDC4E40258DF6460CCA1F40E7F1A24F41C74E408C85BC7650862040D0EC177159C44E40E1341E21E4A4204061E9F1735ABA4E40EFA0590B53941E409123ED1083B84E4085F83CF7E77A1E40DFE1D12D31A94E405A467A8FA5071E40F935C98A16AA4E408F9FB0EAD8741D404D0EDE6D43974E40A356E745E67E1B40CE559DAAEAB44E40EC013215253C1B404C338BDAFDC84E40
515	Vågå            	Oppland         	0103000020A21000000100000011000000C1466179DA102140311F40F937C94E40A631073CE5FB2140AB80ACB474DE4E4056E65C5D1BBD2140779BCA6A9FE94E4055E7DFEA57BE2140A83BDC9324014F4091547B41AF0722409B216EAE41024F401B9C5F949EDC2240AA4BFAE962E84E406799B0A7313D2240A27575B7C5E04E40A4E4592EE13A22400FAA4138C3CB4E4013A18552C37022406F8D892255C74E40EBFFD3589ECC21407C9DF82A40BE4E4055B7F918B2492240B917ABE302BC4E4080014156DA232240616F5A957FB14E406A4A7BF0A88F214075F712F1B2B94E404DDDC160F10521402E1047FF8EB34E40122FB3B04CFA204055E19F8BC8B94E40800C652200452140F7718577DABE4E40C1466179DA102140311F40F937C94E40
514	Lom             	Oppland         	0103000020A2100000010000000E000000CB411F3B60622040D1A6316C9BE34E402289E5A04E862140786AF3A3F6034F4055E7DFEA57BE2140A83BDC9324014F4056E65C5D1BBD2140779BCA6A9FE94E40D4130FDB1DFC21405E4E237D95DE4E40BB69BDFCDD8421405252BFFE36CD4E4017B7B40D28112140BA20FDD2C6CA4E40800C652200452140F7718577DABE4E403C9D53D4A9EE20409ABDACF5E8B24E4036697154E69A2040BD13F2EE09B94E408C85BC7650862040D0EC177159C44E40258DF6460CCA1F40E7F1A24F41C74E40F3329512209E1F4065085EF6EDD64E40CB411F3B60622040D1A6316C9BE34E40
1241	Fusa            	Hordaland       	0103000020A210000001000000060000003BAA68303F591640974A1FEB371F4E40FF7E6D524DF516400B7BB846432D4E403D61C0D133D6174067F62CD1A6254E40F60F820DD2231740F2C2AE906F044E40F14A7A670F141640E4F32A6EEC0F4E403BAA68303F591640974A1FEB371F4E40
1418	Balestrand      	Sogn og Fjordane	0103000020A21000000100000008000000AF9227ABC4571940BAF4ED2010A64E400575ABED9D791A40B28E0C7856B64E40E389ADC4DE781A4062F478A715A14E406C9A472D4DCD1A409B649B62E6A04E40D69127D4A8EF194002D5332AA38C4E40DAEC57753987184040E523E94B914E40B0E72767C6A419403071EEEFBBA04E40AF9227ABC4571940BAF4ED2010A64E40
1419	Leikanger       	Sogn og Fjordane	0103000020A21000000100000006000000104E5643888D1A40BAD00A3E609E4E401BC53BD003071B40E09D442441A84E4024CEA9EF30CA1B40DC52274769A04E40F8DF8DBC48821B40574C4FCC0D944E40867DD210D04E1A402B71DDE294994E40104E5643888D1A40BAD00A3E609E4E40
1247	Askøy           	Hordaland       	0103000020A2100000010000000600000074ED6936FBFC1340BF3B6967E33C4E404A0C5A3D6D97134071F1BED8E1504E4042989B80EEF21440E8A90DB7683F4E40609D0924FC1E1540BD7CEABB5C344E4036BD988F35AE144074D3A1F9DD304E4074ED6936FBFC1340BF3B6967E33C4E40
5012	Snillfjord      	Trøndelag       	0103000020A21000000100000007000000C41434EECD3F224037AF61EBAAB74F40CC27E93B20172240B27E080CA2BD4F401DACBA75A3E822409BF863E44ECB4F404D479AD364762340A4EE1669ACB54F40FA2E32CFD4D8224011C1B14DADA34F40858BA86BF07A2240AF52E69F1CA84F40C41434EECD3F224037AF61EBAAB74F40
805	Porsgrunn       	Telemark        	0103000020A2100000010000000600000088AC69F290362340EA14F46CF88D4D402BDA9671FC9623400286BA1AC89A4D4080932F2CE1CA23404A880678C6964D404843836B48A62340FFB0938A2C944D409D4D0B184AAB23401992364FB87F4D4088AC69F290362340EA14F46CF88D4D40
238	Nannestad       	Akershus        	0103000020A210000001000000070000002B12221E4D9725403E91054D771E4E40F56E897E28DE2540B6A33667602C4E408FC847183B2E264013C55D264A2A4E4044B44D4126422640316D865D971F4E40856051D8691426405F7D47A8AA0D4E40D7B78C80728C25403A39ECFE10184E402B12221E4D9725403E91054D771E4E40
1242	Samnanger       	Hordaland       	0103000020A210000001000000060000007D43B1C9869B16403D62E7A8E3344E40BFB4C85363AA1740416992D166434E40C7D19A42DBF617405838536667404E40DC32E1874AA2174035E40FC7A7294E406E565AD5314816409C090C9A02254E407D43B1C9869B16403D62E7A8E3344E40
1232	Eidfjord        	Hordaland       	0103000020A2100000010000000B0000004FFB2C537D0D1C4083B1334B69354E404D6DFD210A691B403D6328F5A33D4E402C52B0A49B201D400EE0AD96C74B4E400339927BAFED1E40A49CB928AF424E402C4323CAE0B11E4090FBD3C2AC254E409729AAE6FAF31D40A9CF5FB6A90C4E408BAA293C61E41C403770ED181F114E40DC974A546BA91C402D26594933214E40298F1ADDA1F91C405345BDBA53224E40A9B96FF1F9ED1B40C7956A3A962C4E404FFB2C537D0D1C4083B1334B69354E40
1528	Sykkylven       	Møre og Romsdal 	0103000020A2100000010000000500000082FD53784C821940466D1637CC2D4F40EDC6522C4DC41A40E02894191E3B4F40F0EEAD05E08E1B4062630F7999374F400265C170A0D11A40453D66D3461C4F4082FD53784C821940466D1637CC2D4F40
233	Nittedal        	Akershus        	0103000020A2100000010000000600000020DFF101998725402646999F350C4E40C3D63FAD845A2540BC327218E1124E409E048271EEB92540AD82C0C7BB174E4062B9CADB7EFB254023E4005801FE4D401730B983E5AC2540F956BCA0BFFF4D4020DFF101998725402646999F350C4E40
1026	Åseral          	Vest-Agder      	0103000020A210000001000000090000001E29B766E9A41C40B938DE8462564D40DAB15E2EEBA51C40551C7BE4116B4D405AF5A86B46D61D40AA2CC0AF7D704D405E4A2A0E02AB1E4092EDAE8A68614D40B2E6445C1B311E403C37D3B47F574D4023F254C88E711E408110D4E7834A4D40F4DDF8628EC21D40F1181F6CA23E4D409499C696052B1D403BDF38841F434D401E29B766E9A41C40B938DE8462564D40
217	Oppegård        	Akershus        	0103000020A210000001000000050000005158D19FF16F25409189F8E99BE54D4011D95E25F07C2540E353CAA16DEB4D40C63934F210AE2540F83892E61AE64D40A87C4971458B254075890D203FE14D405158D19FF16F25409189F8E99BE54D40
419	Sør-Odal        	Hedmark         	0103000020A2100000010000000B000000C16CB60400272740EB7AEDE23E194E4095A1C98F2B342740F832B37836224E40D6A189BB690A27403247D49FD0254E40208AF5E1C53F2740992BB8AFA3274E4034F5D2F997382740A429D4EC7D2F4E401EECCC71869A27404F9E7DD0E32E4E40E81C75B7BFDF27409FA84E90D5214E408925DBB835C327400566E99C74194E40E0C48A9010D8274036D34B6B570A4E40BA7EC78BFFA427408B9CC6AFAC064E40C16CB60400272740EB7AEDE23E194E40
1145	Bokn            	Rogaland        	0103000020A210000001000000050000001B4C84F0D4641540D05D1286399A4D407AAF46C80FE115406CC459DD5BA34D40ED77F3421D94164060C0DC70C29A4D406C8515B7F07B154059E26AE94C8E4D401B4C84F0D4641540D05D1286399A4D40
1129	Forsand         	Rogaland        	0103000020A2100000010000000700000015733B6CB7D21840F32025AAC3824D40E9A53C5397A21A40B2C27E9EB3974D4057A22F71B6C11B400D84A40149974D40E19A0CA374CF1A40F3C21D38417F4D40B6E5E7BB78D718406F42BAC4616C4D403127F9EE02E317406DB762B1887A4D4015733B6CB7D21840F32025AAC3824D40
1813	Brønnøy         	Nordland        	0103000020A2100000010000000F00000010B0BC9F172D26406860A6FEB15D5040EF91B645A54825402935676267625040FF5903AD8EB927402AE24245365F50405E113D78521629403E493AF9E767504032D3F6722B6429409853A5E00F6650408A0246570C6C294013CC6C3F226150405CDF4758AF122A40E066760F8362504094C4320DBDDD2940076FFDA370595040307E735CE4132A40D8CEAD9094595040D0E7DED467552A409C62DE562A5150408886278C41732940EA488AF80C4D5040A18CEEFDB2E0284068D0384F705350407FECB41D5AB2284016789551165C504065CFB370C2652740C97029202455504010B0BC9F172D26406860A6FEB15D5040
418	Nord-Odal       	Hedmark         	0103000020A210000001000000060000008732776830B3264039A714AFBD394E4049520975A7B326403809B53056424E407634C3061B3B2740C5E10C8AC54A4E4048F58550ACAC274066DD35F31E354E40D6A189BB690A27403247D49FD0254E408732776830B3264039A714AFBD394E40
2028	Båtsfjord       	Finnmark        	0103000020A210000001000000080000001DCBA5C02D853D40DF2278DC00A851408F85AA01540D3E40A33E9A042BBC514079AF8472F7383F402228EC203DA951404F5D18AD06133E4017BE4C6CF892514038A625B361983D40EF91BF51B89551408710EB2100AB3D40C6A7BC0D4597514047DE6102D9393D4065AAE9F0939E51401DCBA5C02D853D40DF2278DC00A85140
1160	Vindafjord      	Rogaland        	0103000020A2100000010000000A000000E3C00B121E56164083C9F92727BF4D4019EAAB2AA212164098E41E9E18B84D40DA6AD0DEF7D61540644852AFF8C14D40C0484C6D2D34164015E0FDA761C84D406FFFF6A0A9521640BA8A21BF74E04D40CA2A7CF9ADE01740EFDCC99B1BCA4D40D2F018298DA91840317ACED3F0CA4D40D177F45039BC184072D4A6837EBF4D40326A6EFBF5D41640DBB12C9408B44D40E3C00B121E56164083C9F92727BF4D40
1103	Stavanger       	Rogaland        	0103000020A21000000100000006000000FC564E669BA61640596AC946E37C4D40A4BCCB35EBF21640A2585F87AA874D40C80DAD4B2574174048A7AFC3497E4D40C014811C4908174085C926E343714D40B2FE924735431640FBE93D721C7C4D40FC564E669BA61640596AC946E37C4D40
1114	Bjerkreim       	Rogaland        	0103000020A2100000010000000800000073FE8578E5921740EB72523F64514D40DEDC64687EAE1840251C087BBE654D4032186687103A19408A491B86C05D4D40684F78CFDA471A40667E625507624D407FD78B85BF7D1A40EEA356311E5A4D408C29E545B5161840AE3E921AD0414D40B3A8C35F667D1740CDDF43B5E7474D4073FE8578E5921740EB72523F64514D40
1940	Gáivuotna       	Troms           	0103000020A2100000010000000E0000005F1A241E5B563440F231A5A6AF6351405E6484ED386E344008CD2E02636C5140B593174685623440E83339FD647051406B1C21435B9B344062BD1792516F5140780BD99763FA344019BA6A0EA1615140D4CCDF6FB4EC3440EC40416454605140D0CD554584253540AA16BA81E86051404FB919B23806354045B77E47355B5140C23AA6D1604735404C1FC9E8F553514008CBD48234083540702EFDEAFE4E5140B28B3B744B8D344020E858CCB55551403696B8D127793440304DBACE785C51402B7C6FFC4046344092A537C7B65D51405F1A241E5B563440F231A5A6AF635140
1037	Kvinesdal       	Vest-Agder      	0103000020A2100000010000000B0000008556FC2471801B40C989F19C283B4D4062B792B7B7371B4079B17A3BBC494D40BAD9101C14AC1B40A2F5D72447654D405AC43C4994A51C40A52EC97C00694D408CC19B46A1BB1C408E6B7638EA5B4D40DBA78AF8B3451C403563F16D8B444D408F4E7E22268E1C4017241BA724244D401B20E02DA9E51A4052DDAAC1781C4D40076807F2E3161B40824F3B880B2B4D408F2E66E790B41B40D8D017F5112C4D408556FC2471801B40C989F19C283B4D40
501	Lillehammer     	Oppland         	0103000020A21000000100000008000000841C5349EF752440DE3D3EF843924E405E90C04CCB67244005FCF0E14D984E4084789446C0BB2440867E003DBA9F4E40126D9BD771D6244009E084866C974E40AC70544AC27C2540E4F1F3BD429E4E407A37C52B7CE32440E68A95190A834E4093BB1A7E54132440792680A5E48B4E40841C5349EF752440DE3D3EF843924E40
412	Ringsaker       	Hedmark         	0103000020A21000000100000009000000D7C2198EA6EE2440DF33FD9704844E408EA4DCF66DCB2540EBAA8121D4A54E40D1F269F8653B26404BA0747632834E40CEDA7781D539264021BA8FA5C66E4E408DF5EAF242F62540D22E2A3AB7684E40C6AB119CC31B26403B5DE594D2574E40E3750F88E17925401CD10A31AB634E402240216C4E4D2540216831D4577A4E40D7C2198EA6EE2440DF33FD9704844E40
403	Hamar           	Hedmark         	0103000020A21000000100000009000000E4207645492B26404244E1C8AC754E40D1F269F8653B26404BA0747632834E408325166CA2F725407BDA6AB6369E4E400126371ED0792640210337B812874E407FE764F8D48C26401CD3406AF66A4E40667305D0380E26408D4506F930634E408DF5EAF242F62540D22E2A3AB7684E40FD33A2BE9B2B2640218C1BDC706A4E40E4207645492B26404244E1C8AC754E40
529	Vestre Toten    	Oppland         	0103000020A21000000100000008000000E71FA1ACDF192540DE19C8ED27504E403A5E6E833DF8244060BCDFF622564E401FFD10CC8F1B25401B8BE3A47C5E4E40BBF24011CA852540A3F868CCA35A4E4038ED70660B5F2540E6FE2A65F3534E404D60F30EEA5B2540CE3E39EA62404E40A73681F86E042540CA7BCFBB4B484E40E71FA1ACDF192540DE19C8ED27504E40
528	Østre Toten     	Oppland         	0103000020A2100000010000000500000081733C282D5D25404CD9C912D8494E40C012FEC6517D2540D541D64431634E40C2A7DD40D74E2640E4BB447B754D4E405B653DBB5AD825408EEDEF053C3C4E4081733C282D5D25404CD9C912D8494E40
237	Eidsvoll        	Akershus        	0103000020A21000000100000007000000EC26A99D304326404F8B241595314E40C93375B1E9242640834E159557424E40C2A7DD40D74E2640E4BB447B754D4E40B2FFD5A807D82640AB95C9ED1C2D4E405C9921D7F4762640FC7E69AAED1C4E40FB2443EEFB3726400372CCFE25224E40EC26A99D304326404F8B241595314E40
236	Nes             	Akershus        	0103000020A210000001000000070000006EAF01E151A626400F24DB919F124E40356F7297B5822640609FBDAB59204E40B2FFD5A807D82640AB95C9ED1C2D4E40038394EAF9A427407B2A94C9D3034E4082A7EC4403E02640987F645094FE4D407068DB787293264030816822D4074E406EAF01E151A626400F24DB919F124E40
1870	Sortland        	Nordland        	0103000020A2100000010000000D00000095397D4DD5DB2D407B9E7D61D32E514061D2E6AA80C42E40D396F34AD93851404F203855057F2F40A47A620FBB305140C4B28691F9B82F408AB94AC9FC385140942C225B1B972F4023B334B1F83E51402CE80970640D30407F7FA1628D4051402E496287BD1C304096AB865BA23B51404571EE4D8FDC2F40817736BBD03451405401D61AB30B304079C10F6B803051403ACA693B6F912F402EC412CC642D5140B94980721E302F402CCA1FF734225140E39AC04C6C932D40275BA032AE2B514095397D4DD5DB2D407B9E7D61D32E5140
1942	Nordreisa       	Troms           	0103000020A21000000100000015000000A061B1BD9AD534406A5D6CB9816851407F1E019368623440B967A2A11071514094F46C8F2E7534408D85EA7C0678514087331A4F63BC3440F9C163C73C745140086863CFD7BA3440B712321D70785140963497F6AF04354070BBD2EC0B7E5140548AD30AF36D354080074298CE7D51403A83A2500A9A35405B36D20E6B785140FA121E6B3E9035400FCC02F7D2755140A58FD00F95C33540606A8795ED7351400EB04C64159935403D9EC8AFAF695140417EF96915A33540D5B850B5F9645140A547FA7F6C373640BF58AC5436635140EA80E5E367873640969862E3554A51406C58F171CEFB354030632330AA445140E8F4E1BC88A0354066892B9FB35151404FB919B23806354045B77E47355B5140BE592760172C35406157F533645E5140D4CCDF6FB4EC3440EC40416454605140780BD99763FA344019BA6A0EA1615140A061B1BD9AD534406A5D6CB981685140
2002	Vardø           	Finnmark        	0103000020A21000000100000008000000336D30DF225E3E40D2070CF8AE98514079AF8472F7383F402228EC203DA951401AD9F2DF2AA53F40954293347BA05140DED21315F1C23F40CE0D7081D898514053BDF5FBE2953F40C5DA169432895140E69FD788C0323F4099458F54D08051404F5D18AD06133E4017BE4C6CF8925140336D30DF225E3E40D2070CF8AE985140
1566	Surnadal        	Møre og Romsdal 	0103000020A2100000010000000B000000B274EC5D6AD12040C3F4803C95764F408659EB0BC77C20404FBC52F98B814F4040DB5D669EF021405913994124914F405BFE49E8F45A2240B4E4FEE61A7F4F405C43D716BE3E2240104F1D35AC774F406F765F449F9D22404DFA5795DF734F404F93E730CBBA2240DCEB7449A5654F400FF0EF4205D721402CD1A34E1B5B4F400A25E5B4F23C2140E1D2245D9D634F4051E72E59F135214038AA798F166F4F40B274EC5D6AD12040C3F4803C95764F40
819	Nome            	Telemark        	0103000020A21000000100000005000000B2D2419D918A2240DB64FCC0EF954D40C4FFAFBD6D942240AD478D614D934D40DF067CF7647F2240B6B9D2239C934D40CFCC27E7B7802240E106D6C0E2934D40B2D2419D918A2240DB64FCC0EF954D40
541	Etnedal         	Oppland         	0103000020A2100000010000000700000097927041431423407D7E9923007D4E40A3D18CC45AC122406CBD4D7A2E874E409DBCF9A2C35B234061BA6FC861904E401453DF2C519423401BFB1875D8894E40B92DEE447DA12340651257F44D664E40F9AA1643741C2340176DCD04F66C4E4097927041431423407D7E9923007D4E40
1529	Skodje          	Møre og Romsdal 	0103000020A2100000010000000500000093BB520F01BB19409C31897FE13E4F4063493AEC2EC21A40347971C313474F4091043F45CF6F1B402CC22F189B454F40BF560170FE481A405061715365374F4093BB520F01BB19409C31897FE13E4F40
2019	Nordkapp        	Finnmark        	0103000020A21000000100000008000000770C5070118039408265D3373EBC5140033D4670E32A394004C5C4F2F1BE5140F2C91FBB77EB3840731217B87BD55140D655B2DC890F3B4067F5759E83D651406C17A1F26C953A40C3D3AE0D84B751403D825714E83A3A404D30DDB161AB5140E086C6495F5039406AAB69F252B05140770C5070118039408265D3373EBC5140
138	Hobøl           	Østfold         	0103000020A210000001000000060000000D0BAFF399B02540F26E753F2DC94D40444CC08FA9F025403DF94A4A39DA4D40E8631D4C4E2426402E457E6096D94D40B61F8EF07DF92540096EB0122DC54D40D11D0FAEDC8E2540C02121A5A7C24D400D0BAFF399B02540F26E753F2DC94D40
1812	Sømna           	Nordland        	0103000020A21000000100000009000000DCA1B802F49227408537FDF7835250405A613B40F8542740B56EA8EF4051504063E695C5BF372540E5E5B6622C60504065CFB370C2652740C9702920245550407FECB41D5AB2284016789551165C50405C3B83D4E3ED28405C93592DFF5550403CB41C57AA1B284079EB6EC9BA4B50405F6AAA7E4F952740EAA54484084E5040DCA1B802F49227408537FDF783525040
834	Vinje           	Telemark        	0103000020A2100000010000000F000000F8D44787D1711C40DA0D28F7F3E04D403B15673480EE1C40215050383AFB4D40DE04603081951E404B4B54AF3C104E4015EB651EE2322040FEF8306014054E40E1E724E4BD602040BB31600049F74D40C320E42668522040E9F5354E41ED4D40E9772F0F4BA62040F916C6FA0FEA4D409D10CD75B9692040590802A568DA4D40295A00967786204010945A4552C94D406231F3D8A00020400630E69718C84D4056B71D3767DD1F40962BA6485EBE4D40793D9A39FE611F400E34ED663ACC4D401AFB3D18CB341E4050330A8416CB4D407F6807E5B8701C40BCA9EB5EADD94D40F8D44787D1711C40DA0D28F7F3E04D40
1102	Sandnes         	Rogaland        	0103000020A21000000100000005000000E47D01D9D6741640758460F0B8694D40C80DAD4B2574174048A7AFC3497E4D401D7BD29E9C741840672F3609436F4D401F31E6956A471740DDB40F656E634D40E47D01D9D6741640758460F0B8694D40
1003	Farsund         	Vest-Agder      	0103000020A210000001000000080000003C97BE59BB9719404A228AC3740E4D40E41B05B21A081B40644D453F831D4D40F425707722AD1B400FC034C5E61A4D40705853C4B7781B406B93FDBC83124D4085BFFC2B73011C40287D5442930B4D40BB6EC4BB03171B4033F8057BD1E84C404D2EB98275A8184072820660AB024D403C97BE59BB9719404A228AC3740E4D40
2025	Tana            	Finnmark        	0103000020A210000001000000150000008F9C951158613B408F1B86DCA19651407A041306A1623C40669134F5BDB051401C6F031970CB3C400929C1A058A0514047DE6102D9393D4065AAE9F0939E5140294953A145CE3C40722A9540909551409B358CB9C18C3C40008ADF8BC8955140CE123F7DBB5E3C4049284986348E5140FF8F756BED4D3C405DF3449CAE855140ECB402CC62583C40336E4A715F78514016E6B92293043C40DF1B7DE6B17F514091A3D06BA0F43B40987B9C0CE885514004EC9EB72D0A3B40836DFF8E467A5140E500DC81907D3A406A49A5337B7C5140C056EC0BA9423A4086414D926B7451408C7C795B72C4394045348050CD795140CBC48C85ED433A401AE45A58DE7F514005F913BA9D3E3A402192F4FA0185514057259F11F1023B4083936C07028A51401ED7DDF07B023B40D756662EB58D5140FFB32E45215E3B405F6EFEE9B59251408F9C951158613B408F1B86DCA1965140
1850	Tysfjord        	Nordland        	0103000020A2100000010000000E00000048B74769D208304087DAD145CC00514025DE221A1FCC2F408FD6832B9A04514095B2425A450730402A3058F13B075140555337DD1B02304006D910C18B0D5140B0E448F711A12F4087C0A74D66125140A02325D967823040BFCFA5FD13105140173C2F6E80AD30402544F8ACC1085140B58D26BF352E3140917A1DBA3A035140F9E66171F5BC30402C4C716C82FA5040CF10C6B1688E3040453E1A9B6BE950404566C774F833304085C1FEAC95F050400EDFD960E00D30407B3B1D02ECF750408E24BFEA641B3040A300FA13F6FD504048B74769D208304087DAD145CC005140
701	Horten          	Vestfold        	0103000020A21000000100000005000000251F3A1A14C62440CAD18DCA5CB04D40FA9F2CD239C72440372B9D1A65B04D4008A8BD6749C724404D9280905DB04D40C53A19964EC624404CCB286856B04D40251F3A1A14C62440CAD18DCA5CB04D40
1430	Gaular          	Sogn og Fjordane	0103000020A21000000100000006000000500AB96FA4991640C6C9B75DB3A54E402B17AE848EA41540F9666907ECB34E40BF18B4C42D1A194033BF4A67A4B34E404E44EB18C0A81940F50BEC0A5CAB4E401863AFB0C931174000CB8E520A9E4E40500AB96FA4991640C6C9B75DB3A54E40
1416	Høyanger        	Sogn og Fjordane	0103000020A2100000010000000E00000078D39C8F03BA1540BBB0A8EFD48D4E409136EEED59C81540C9F1EF5A819A4E4015C2061B6F76164041E47D5840974E405E8412DF82AC174001651DF48DA44E40B0E72767C6A419403071EEEFBBA04E409CDDF10838881840B3AD67DB77954E4091DADE7177C618402F327C6AB6914E4096592DB6EA981840EAB48CABEB7D4E400335771CAD111840B904E3AA82844E406CBB38E66AD31640D4ED9BD46C7A4E40D805F7F9B26016402092C7734E7F4E40ED5ABBC14A5316409F9258B8F28B4E406E583431D57E154018655711B6864E4078D39C8F03BA1540BBB0A8EFD48D4E40
938	Bygland         	Aust-Agder      	0103000020A21000000100000009000000FD51D92F36061E40A22C20D2E16E4D40FEB9FD9F5E211C400153418126694D4094471B9932471D40EAC08DFAB17F4D40BF9CEE89B6481F405206EAB68F8C4D402D1870D4D404204040CBCD407B7B4D4044F055B008F21F40D2DB9FF2885A4D4037E7D26B2A8E1F4003230778DD534D40B72242A949D01E40AF0CFCD91D594D40FD51D92F36061E40A22C20D2E16E4D40
710	Sandefjord      	Vestfold        	0103000020A21000000100000008000000D4810B8C1634244035127FFA34994D40DB53CC2531FC23406CB324B62FA24D40FC72ABCDD31524409CB328DFDEB04D40CC14EE6918C32440D868FF1E459F4D40E21A4C95FFB7244065281637B9624D400613818332922440A7903BE51F634D406973E17B129A244057FB905D297B4D40D4810B8C1634244035127FFA34994D40
135	Råde            	Østfold         	0103000020A2100000010000000800000017C2FA797A6D25405E39D89FFEA84D400083919F3BA425402169FC43B7B24D403BD1B991A6F425405D1840B8E9B14D408776E50170D025404B8EE28D53A74D4083EDA74F9ADB2540E949E03D4BA54D4045F6EA8505D6254009E2E3444BA44D40F43D09F13F2E2540C0C6B4A85DA24D4017C2FA797A6D25405E39D89FFEA84D40
716	Re              	Vestfold        	0103000020A2100000020000000800000098737A4A394E244015E5B78C15B14D40FC72ABCDD31524409CB328DFDEB04D405E4BD6BB042024402333CF352DBA4D4076838A6E60E92440553D29D16CBD4D4025D7362EC0AA2440E152E534ECB64D40794918FBDCCA2440B6FCB95B19B04D40E599BB5F34B22440317621C1EEA84D4098737A4A394E244015E5B78C15B14D4005000000E7486FE586C62440FA35B70760B04D40251F3A1A14C62440CAD18DCA5CB04D4008A8BD6749C724404D9280905DB04D40FA9F2CD239C72440372B9D1A65B04D40E7486FE586C62440FA35B70760B04D40
622	Krødsherad      	Buskerud        	0103000020A210000001000000060000005927B7BBFC032340E73590B57F194E406342849FF9EA224017E77CECF8254E4072878D1ED269234069C644D423284E402D5303D56EC3234080C025574D104E40B3AF6522288423409A2FC9B614094E405927B7BBFC032340E73590B57F194E40
623	Modum           	Buskerud        	0103000020A21000000100000008000000D348B0A192B723409EC4DBF5A7FB4D40B3AF6522288423409A2FC9B614094E40E5B51276A7D12340634ACC64DD154E406E05D0606FEE2340E7D65C06B7074E4054A442368C9624402479A874BEFC4D40E1942A660C1424405B4F771ADEED4D40177853CF026D2340E713189E2EF74D40D348B0A192B723409EC4DBF5A7FB4D40
1811	Bindal          	Nordland        	0103000020A2100000010000000D00000008B5202AA2D62740B0BDD1485B4550402EE280F7B8D427405A0C62BB444A5040CB9B6A85F72725402AC5E258175E5040DCA1B802F49227408537FDF7835250406520C56D3BBA27405F776669054D50403CB41C57AA1B284079EB6EC9BA4B5040224FA17507DC28402165231F915350408886278C41732940EA488AF80C4D504062768AEB941A2A4022ED3A81D94F5040EA3273DE3C502A40D6996AA085495040E79CF5CE618929402A8965A8353C504003387C71BB8D2840C237EC246D3D504008B5202AA2D62740B0BDD1485B455040
1253	Osterøy         	Hordaland       	0103000020A21000000100000009000000CD9DFA49A0861540D7E89CDB8A414E40CE71460B0D451540645305AE9E444E40DB7824E1CB6C164055CCFF4C28594E40AB7161CF3CB11640BC6BD7686D594E401D6E1710ABB21640890A4ECCA54C4E405BBDFCB0EF581640A1CAB0F8F1494E40D19137FC25E216400885C040623B4E409AF1D815B01A1640A473BCF273364E40CD9DFA49A0861540D7E89CDB8A414E40
415	Løten           	Hedmark         	0103000020A210000001000000050000003423CD10E28826407DACA9F535714E400126371ED0792640210337B812874E407842D0CC3449274047CB2010BC584E4038CA16ADBC7B2640FBB23AC5D0644E403423CD10E28826407DACA9F535714E40
831	Fyresdal        	Telemark        	0103000020A2100000010000000B000000A2881FA790F41E40C2F3B2A93B934D40F335965F391F1F40B3C52F643F9C4D40DC307CEBDDC81E403952B6E0D2A94D404B1BFF5D4C482040F85B6AAF2AAD4D4081C2C7E5F2B42040215B1F3963A14D401CB794C3AC922040DF341049B89D4D406FE8F14B2F9B2040AA2B5417208F4D40720CB659EBCF2040BE2A5CD60C834D40F78385222F9C2040327C975FDD764D404FD97786F9F01F40B50033D4167B4D40A2881FA790F41E40C2F3B2A93B934D40
211	Vestby          	Akershus        	0103000020A210000001000000050000008E4AD6F01D442540A14531C971C94D40A4C71329705E254003B6AC78E8D24D406542B13F59B825405ACB5FE194CB4D4020D3CD69AB732540868DE7A166BC4D408E4AD6F01D442540A14531C971C94D40
1238	Kvam            	Hordaland       	0103000020A2100000010000000500000012E5903B97B6174066DD4E43252B4E40DF63906B353218400872FB69DA424E40846E7E5E371A1A401E1FF861BC3B4E409E49E370697D17401FF0D6E6C50C4E4012E5903B97B6174066DD4E43252B4E40
935	Iveland         	Aust-Agder      	0103000020A210000001000000060000006BC92B920C2F1F40C0AFAA0BAB354D408703572B09211F40AA28CCD99C3F4D403C5CD346A0BB1F401A752ECB58474D407F3E04FD41382040FC2E950244384D408CDAF7317FDD1F4090E3D23C80274D406BC92B920C2F1F40C0AFAA0BAB354D40
828	Seljord         	Telemark        	0103000020A2100000010000000B000000CBB8E96DBFBF2040D5A2900F86C44D4078CF46017E7B20408C50A8FA8AC84D409D10CD75B9692040590802A568DA4D4038AD5F4FE8BD2040226A3DCDC4E54D40E6A88F464A2A21401011E64CD4CA4D406CA56B12CED52140A83C83D7D1BC4D4019C5115106A7214035EE3854E7B64D40FACC7DED74C32140F26D924C00AD4D40334076DA1B45214070B9744EBEAF4D40EEC1CEC16F3A2140B86EF34508BA4D40CBB8E96DBFBF2040D5A2900F86C44D40
1422	Lærdal          	Sogn og Fjordane	0103000020A210000001000000080000005320EAF2A5561D405605A09965844E4016614D5AC8FE1B40C7BE8BF4BF8B4E40BA8EA2558BE61D4078617F7F87984E40661FB0D345401F409FD566B7678F4E406EDA5B0D71032040CD2F0A25139E4E4095773000B990204014118A2D44844E409C5F0BCA62001F4067D3EC11BD6B4E405320EAF2A5561D405605A09965844E40
137	Våler           	Østfold         	0103000020A210000001000000050000007644EF3734912540E06B449C6ABE4D404FC7443CDEF72540F099849C53C54D4001BA410A9D4626403F20167B2AB54D4020EF8F96F4B125401BFA2DED8EB14D407644EF3734912540E06B449C6ABE4D40
124	Askim           	Østfold         	0103000020A2100000010000000500000008A0F01C81312640CEF81B62DCCC4D40F921E1B8255F2640577B94D3F6D34D400D647EBE9F852640E9C85BCEC7CB4D404476FAD8DD542640966C3A3FDFC44D4008A0F01C81312640CEF81B62DCCC4D40
701	Horten          	Vestfold        	0103000020A21000000100000005000000181F07905CAC2440F261656D72B54D4076838A6E60E92440553D29D16CBD4D40AA098C79593025401837DF8E97AD4D40B9EFBCF1F1C724404156FD27D5AC4D40181F07905CAC2440F261656D72B54D40
815	Kragerø         	Telemark        	0103000020A2100000010000000700000082E6919C7C5822403C632DD7C06F4D40F485D1BABE9A22404DA4350B1E804D40D7DB3CED88262340C8BFA289E6744D40225F233BF6902340B5A66E07C8774D40838B78FC84F023401EE178DE375C4D40AB68E0FC765623408D941A4A394D4D4082E6919C7C5822403C632DD7C06F4D40
1927	Tranøy          	Troms           	0103000020A2100000010000000B000000C7B238442A353140E50EDDA6B44C5140978B0264094531409AA433F9385251406A4B50CD75913140822640CA615651400B726E0B90AC3140205DD72B124F5140520B3818E9D931405714BE91E64C5140FF016E87EDD43140C7729AD73149514053CF8DFE23543140F139C59683455140F9055DD2473E3140F6E1D9194B3E5140F99ABCC713B63040864ABD4E4841514057DAC037A6BA30401DD592C5234C5140C7B238442A353140E50EDDA6B44C5140
5048	Fosnes          	Trøndelag       	0103000020A210000001000000080000000E7D48FB3FB62640BA281334ED2D5040FF089898E63B284010413A37713550405AD5B187076F284097BFA71D1E325040BBE493BBA2C32740E3A8C3DEA8285040EC0F10889C1D27403F2A178A0A295040A75392F8E7EB264020ABCF8DBD245040AC23B9456DD6254015CB563CB72D50400E7D48FB3FB62640BA281334ED2D5040
5005	Namsos          	Trøndelag       	0103000020A2100000010000000D0000000126E474815426400E4D73245A205040E5463703F6792540D098D5483B2A5040AC23B9456DD6254015CB563CB72D50404F6BF952839A264011BB2DCD8B25504088D0122D8F4C2740BB6AE0533D29504082DA7E376CD327405B4DD96E912550403A0FB5B19B35274009E1B917512050403ADE71EA374F27400F544BD482145040C7B734AEBE842740126B34252512504071735711831527404AE6A749EF0E50409F3EB08BCC7926409E843971C6195040BBC3BCF235B52640D5DAF3AB931D50400126E474815426400E4D73245A205040
502	Gjøvik          	Oppland         	0103000020A210000001000000080000005F5DA1E489722440718888CA79714E40AC625FCDD75524407C04A09AA9784E405FC261324B772440CA6F9BFEF1824E40D7C2198EA6EE2440DF33FD9704844E402240216C4E4D2540216831D4577A4E40C012FEC6517D2540D541D64431634E40F3012C3F73062540193962628E5A4E405F5DA1E489722440718888CA79714E40
522	Gausdal         	Oppland         	0103000020A2100000010000000A000000B697426B50BB224018900206CEA24E40D23FA7AD0B9A22404180B20570A54E40FFA39D1FFE1B2340FCAAFDEAE3B54E40C3EDAEE9E99D2340BD5191BF74B54E40AD44613FA25B24408F4CA9C396AF4E4033DE092D3DBC2440AB1D6B5ABF9F4E405E90C04CCB67244005FCF0E14D984E4077C36396DF6424406F0ED6EACB8E4E40EFF2BE3AC6FF23400D0DFB501A8E4E40B697426B50BB224018900206CEA24E40
619	Ål              	Buskerud        	0103000020A2100000010000000A00000032C6F452CB822040E21B422AEF584E405B09EA56C7191F4017F312C3EB6E4E400CFA45C021841F408933433147764E406BAF2DE246AB2040D32105A1FC6E4E40F4D5BA23526F21408EF2B68633624E40A8C88653F0AF2140FE4DAA8B15514E40E3F804A7E65C2140A124C18F8B414E409B4CEFFE6FC520401D2B2052393C4E40E51737BFA3D520402A8C4CB99E4E4E4032C6F452CB822040E21B422AEF584E40
615	Flå             	Buskerud        	0103000020A21000000100000005000000BBBAA3A517472240A57755A2522F4E40DB43ECFB9BC822408D6F6BBFFC484E40A2E8DEFE84B12340DA259D87DB374E40F0A95C214977234027AC418F57284E40BBBAA3A517472240A57755A2522F4E40
711	Svelvik         	Vestfold        	0103000020A2100000010000000500000023A6440108AC2440500A737DD0CF4D4084ED3EA495A5244098E5E61AD9D94D40B085E6A81CD22440C846FC6662D54D40636CE1A8C8CB244026EAFD36E5C34D4023A6440108AC2440500A737DD0CF4D40
811	Siljan          	Telemark        	0103000020A2100000010000000600000041BD2386D84023402E2EBD6ECBA44D40814A7BCD66362340BCDE265CB7B44D4010544E79618E23409C12217CBCB44D4028DAE05BBB82234041B7E63A96A94D4023F32C0A04C02340EAEC92A4A7994D4041BD2386D84023402E2EBD6ECBA44D40
704	Tønsberg        	Vestfold        	0103000020A21000000100000005000000EFA0F081569224406C950F12ABA54D40EDA820A5B0FF2440CD7778D975AD4D40F43D09F13F2E2540C0C6B4A85DA24D405591B77462F42440D0992675219D4D40EFA0F081569224406C950F12ABA54D40
633	Nore og Uvdal   	Buskerud        	0103000020A2100000010000000D00000098AC74D562701E4088B1407D3E1F4E40A46D9A93B4C41E40B514770ED1344E40F89C56C61D642040FA47320A452C4E40FEA208CC5E25214076F5BB08B2334E40264F34CAB73E2140CA4F112C9F384E40B266508ABBF02040610F50E4283E4E40E3F804A7E65C2140A124C18F8B414E40E22A87D0434C22402E15F0CB952E4E403B3BD0A9896F2240DCFF096383134E4016539D35FA1A22405342565216094E40FF540A2D1B72214062D4160C70174E409729AAE6FAF31D40A9CF5FB6A90C4E4098AC74D562701E4088B1407D3E1F4E40
618	Hemsedal        	Buskerud        	0103000020A2100000010000000A000000B5EA53353D4E2040321288015B7D4E4087DD57903B722040A0F16C55EA7B4E4095773000B990204014118A2D44844E40284B6D3DCA6D2040701B1F8AE6864E4030FC19F54F9E20406BE10D7FBD8B4E4040FEBFFD85D62140BBAD1A1B836E4E4085EFE62ADF7221409D52D406CC614E406B181AA168EF20409EFC459663644E40BE8B9D37ED142040E523D3DD54724E40B5EA53353D4E2040321288015B7D4E40
822	Sauherad        	Telemark        	0103000020A2100000010000000700000070D4C2226A41224098125B18A4B64D40C3B7C881A86322403B47CA0FFEBF4D40E17D859FD0072340556AB5F1E0C44D40F3F73AEB00CF22401DF62E4E03BB4D407089E67E62D02240ABAE564B78AD4D406FAD4FA65E6022406929F73FDFA94D4070D4C2226A41224098125B18A4B64D40
5036	Frosta          	Trøndelag       	0103000020A21000000100000005000000C61B4EAFD26E25400C94B858E2D34F40CBDAA6B5C5E4254035B2F30790D14F4080FFD1BFCF4E25402F34A729CABE4F40BEDC9B7C27FA2440C73144C81FC24F40C61B4EAFD26E25400C94B858E2D34F40
1816	Vevelstad       	Nordland        	0103000020A2100000010000000A0000006666649DDE7A28405B2741D5796C5040741E42DC535029401E54ACD0F771504049739C38C5FA294006D7C58C356B50405CDF4758AF122A40E066760F836250408A0246570C6C294013CC6C3F2261504032D3F6722B6429409853A5E00F6650405E113D78521629403E493AF9E76750407F986CAAA0BB284045508F2DAC62504082257BC32F74284081368B0D796650406666649DDE7A28405B2741D5796C5040
912	Vegårshei       	Aust-Agder      	0103000020A2100000010000000600000055BDFCCDA44F2140CA769F05A3634D4074763E2751A321406A75311B886F4D4061925DA8BE08224000D7A71C0E604D407F085B284F9C2140695557A3DA514D40888C271F504D2140493F23F9B0594D4055BDFCCDA44F2140CA769F05A3634D40
1523	Ørskog          	Møre og Romsdal 	0103000020A2100000010000000500000089947963ABBC1A403A2BF0EA033D4F4094C6D5749F9C1B40B45C463BAF454F406AAA00AF597B1C401005D820A3384F409AD16E43E63F1C402498E5D0E5344F4089947963ABBC1A403A2BF0EA033D4F40
1539	Rauma           	Møre og Romsdal 	0103000020A2100000010000000E000000B2103676DCEE1C40C46B72C2FD3D4F40274541D861311D40EFCC3C461B454F40AC164D662DE51C40564FE53F5A514F40C3082162CCED1E409AD31EAA8A5C4F40B1E9B822324D1F404DEB5CF8D04F4F40C8A9F54E202920409B096A4B954A4F403737403B270D2040A939D29ED5394F400DA9A97365692040047AC797762A4F4013C3887137EF1F40F49C36F8B6164F406C7159CF39F01E4058C4E80EA2174F40489D8992B2881E4054CC4CF20B224F403129A00F962F1F40E325420074324F401C29F002A7811D4067AB850EA3314F40B2103676DCEE1C40C46B72C2FD3D4F40
1443	Eid             	Sogn og Fjordane	0103000020A210000001000000060000004DC0A24966221640C5C0FA0339F54E40BC69EDBC73E31540A9834AE203F74E40C2B4FE9D32BA1840BD384D175D014F400FCB0A35C7E81940EE1A5281A1F74E4039ACFFC3A78818406A61E4664CEB4E404DC0A24966221640C5C0FA0339F54E40
1560	Tingvoll        	Møre og Romsdal 	0103000020A2100000010000000800000028731E57F3162040AD4881F22F7C4F4081312E2295581F40A8ECD814FF814F409CFECCAB94B91F408C1EDCCDC68E4F407DFD8A7490342040AA3778658F904F40C83BCEB376B120408A4EB0C01B7C4F40B341D5269CE1204001A0EAD009644F40BC60660714552040C7472EAEA0694F4028731E57F3162040AD4881F22F7C4F40
1266	Masfjorden      	Hordaland       	0103000020A2100000010000000500000019C758FF048B14403EB282654C6A4E40E03E8ED5E42A1540FAFC5B62D2784E40A3AEFC88F27517402320036BD5794E40C91D431247CC1540BC00CE8B9E5A4E4019C758FF048B14403EB282654C6A4E40
830	Nissedal        	Telemark        	0103000020A21000000100000008000000DDE908FC72C02040DD0475EBFC874D401CB794C3AC922040DF341049B89D4D409B2F7464D2322140E605DF86C99E4D40F0616E8356A921409D8C6E37CF744D40A17CAABFC87C2140391A8A416B6A4D4039D330E3A12621405CDA226439774D4082764A47B09E2040483406C1B0754D40DDE908FC72C02040DD0475EBFC874D40
106	Fredrikstad     	Østfold         	0103000020A2100000010000000800000033B84AD5953B254003D10D1D559E4D4020D5DBC5F8EB2540BB3A827777A94D40A53DD07AED4226400A45FCCDCE9F4D40D6C1063C2A242640EC350E773D9A4D405554234F2C40264074C771F457914D40F2383B2D21AD2540F5F5562DD1914D40E8BAEB329C59254050C2C7FECB854D4033B84AD5953B254003D10D1D559E4D40
2018	Måsøy           	Finnmark        	0103000020A2100000010000000B00000035FB603BA49237401FE88C3E1AC1514067E1B1CD593F37403A179328EBCB5140E1F82A392ECD3740A34662257AD25140F2C91FBB77EB3840731217B87BD55140033D4670E32A394004C5C4F2F1BE5140770C5070118039408265D3373EBC5140D0088D3D9A473940AF858A0C9BAE51405B01DD432AFA3840BC8182CE91A75140371855B2C7EF3740EBF374A814B251403024A80C59D1374005A77F5B30BB514035FB603BA49237401FE88C3E1AC15140
1828	Nesna           	Nordland        	0103000020A2100000010000000600000080D4390F10412940BED7928CA69050400EC5D5D5BA9F29400635990C38955040DCC1F5C338912A40E144C3C1529350400DADD699E9A52A4067BB084F6C8F5040BEC509540FAB2940240D78197989504080D4390F10412940BED7928CA6905040
1233	Ulvik           	Hordaland       	0103000020A21000000100000008000000FAC34586B35E1B400BE17FE45A4C4E409B83F14DE6591B40A5D272C354564E40E3B54A6787F11B40280086DAD35E4E40C56982771C8B1E40CDBCE41703514E400339927BAFED1E40A49CB928AF424E402C52B0A49B201D400EE0AD96C74B4E40FB6B85351D011B403A31AB391F3E4E40FAC34586B35E1B400BE17FE45A4C4E40
439	Folldal         	Hedmark         	0103000020A210000001000000080000002F1CEE0B823323406AC8930376164F4043880D0BB9AD2340095F12E8582E4F403EDEC468F63124403C584867C2364F4082B7EED87EC824407657C37E2E194F4058017A12F0072440F394908035F14E40111EEFDE4CB22340A8950F0EB0F34E400CD36AC10FD323403B8913A7C5084F402F1CEE0B823323406AC8930376164F40
814	Bamble          	Telemark        	0103000020A21000000100000005000000ED0D44D08E9F224044BEE14AAF804D40719BA83ADF1A234060C249D3C38F4D40225F233BF6902340B5A66E07C8774D40C27C79C37AD62240D0794B3DA7774D40ED0D44D08E9F224044BEE14AAF804D40
1524	Norddal         	Møre og Romsdal 	0103000020A21000000100000009000000F74C5065D8121C40E295AB53EC224F40E6A0EAC406571D4001B9D07F6E354F40E7FC7F68CD7E1E406C51AE3BEB374F40600D724077501F40BD39748F732E4F40489D8992B2881E4054CC4CF20B224F406C7159CF39F01E4058C4E80EA2174F4092D2DF9BC9551E40E49ECE115D084F4078F48D1C35561C40A3C300CDB3154F40F74C5065D8121C40E295AB53EC224F40
1926	Dyrøy           	Troms           	0103000020A21000000100000009000000EE607315D4503140E515AFA047435140ED45594177E0314005E3CF8B8C49514018D4E5E6B0F03140341B0BF024475140703A87E009E731400D2C5E805543514044CE992E600D324075EA44E4BE3E5140F75B22974AAF3140BEDD570EAE405140BF92556EDB6D314022F89E0AC1395140F9055DD2473E3140F6E1D9194B3E5140EE607315D4503140E515AFA047435140
516	Nord-Fron       	Oppland         	0103000020A2100000010000000A0000006B4AA2971DB922402BB66A0C1AD04E40F4A35651267E2340DFF52B9F95E94E408435D86DBB06244031B14531FCEB4E400F96062E5D7C23401B39379C54C24E40BA70EAE839C82240FCDBBD5181BD4E40F67722AFE3A62240FCFAD463D1AC4E4080014156DA232240616F5A957FB14E409C1D9C968C472240F6C2BC4B46BC4E404CB87CF9E9CD214054B8C52229BA4E406B4AA2971DB922402BB66A0C1AD04E40
1917	Ibestad         	Troms           	0103000020A21000000100000007000000F440E65120DF304010E9968CF53751403CF29EDC20F23040107B9AB6EC3C5140F9055DD2473E3140F6E1D9194B3E5140A661D5D3318831409C5D8484C7385140629A279B712931400274363B2A2F51404E79A75167B73040E4C64C03E12C5140F440E65120DF304010E9968CF5375140
1839	Beiarn          	Nordland        	0103000020A2100000010000000E000000AD1953EC7CA62C401FB9FB5164BF50409FF0DF2C9CD22C40DB84099D82C35040A7046053B3AC2C4016586DB134C65040946FCAF7DCC32C400A384351D5C85040748B287558D32D400705704E25C2504009AF9FFFDC0B2E409B629CD54ABB50401844D8A360FE2D4078E1EB042CAC50404D875507B87C2D405AE83266AEA95040F86E48B220672D40233475FD4BB05040833BE6D789BE2C40A0881591E0AB504082B7887D00D62C408550D55CD7AE5040D90FF4C492A82C409E1D10F92EB05040DFCA31EF6BCB2C40D150436F82B15040AD1953EC7CA62C401FB9FB5164BF5040
1834	Lurøy           	Nordland        	0103000020A2100000010000000A0000008635528BA6752840F5CC415EC79C5040305D8EA3F0DE28404A7ECCF1969D5040BB8454B640BB284053A4AD7167A5504044367974EE162940FA5054C1AFA85040E6AEE3502B9629400A31B3CCADA150404923F53B2D4A2A403A16A0CA79A150401E47270877852A40B5BCE0CDFF955040BCFECDF2BADA284033B9D1D4E08E50404900593A35FD274052980534639550408635528BA6752840F5CC415EC79C5040
5031	Malvik          	Trøndelag       	0103000020A21000000100000005000000531A6C9FA5BB254057A2C8F882AC4F408DD1645A63BD254014D06866FDAC4F40EBFD14987EC525402AD0E29C9EAC4F40F5FA987EC6C12540BD209338E0AB4F40531A6C9FA5BB254057A2C8F882AC4F40
5016	Agdenes         	Trøndelag       	0103000020A21000000100000006000000F9A1F508EA152340F7E2144795C54F40C46512D0287F22402F3E7856F5C84F40A05538A1597C23407583B2EBFED54F401958DD679BF52340E091D274A7BB4F4036A1F0995C7B234035E349536DB14F40F9A1F508EA152340F7E2144795C54F40
1837	Meløy           	Nordland        	0103000020A21000000100000011000000A149018917C42940C07273629EB950406DA3C18932B02840DCA565DBFAC75040039F5EBCBE752940F13B623AA0D15040EE8DD9ABB1972A401C474F8DAACA504063B2548288C12A404C42D29403C3504088500488EE3D2B40FE26B5D56FBC5040908BB15FF4DB2B40EE2A09953FBB5040D60105B995562C40DFFF638080B15040863DBB8D1DC62C405F7CBDB063B25040D90FF4C492A82C409E1D10F92EB05040FEC273087CD62C40FC90B75BC2AD5040A7E1A88C186E2C40574D60B1EEA750402C9093E2FCA12B40907310E264A850406A30BB7F917A2A40FC4C1A89BFB1504025CD1A2044142A40E0DB0EAFB6AF5040E94A4AF108BD294042568D9FA0B35040A149018917C42940C07273629EB95040
1526	Stordal         	Møre og Romsdal 	0103000020A210000001000000050000009A58260AFE621B4013E8502847344F40B2103676DCEE1C40C46B72C2FD3D4F400E499CE2DF561D4022B1D361EA394F408CE48D179BCF1C407A9B2F9BF9284F409A58260AFE621B4013E8502847344F40
1936	Karlsøy         	Troms           	0103000020A2100000010000000D000000573320C0CF7A34403A58D70C08AD5140BB045B76639F3440528CA5D319A55140203E59E14C7234400E9627D19291514059DE311076D73340DF40BE794D7551405D04A116AD5A33407B31F24A1873514081D4A9D4CE0333406BA21DAD277A51402D3E0704560C3340F060578AAC7D5140733348A826C432400865B2085F7F51401E5BF7BFD7C832402CD8C98C50835140CBF7A6BB07493240A95A0A097D835140F541AAC624CE3140C7BBB556C78A5140071DC8F268563240C2D5DDDB47995140573320C0CF7A34403A58D70C08AD5140
1902	Tromsø          	Troms           	0103000020A210000001000000140000005DFC09CFF82831404F0F8054F0735140F541AAC624CE3140C7BBB556C78A5140CBF7A6BB07493240A95A0A097D8351401E5BF7BFD7C832402CD8C98C50835140733348A826C432400865B2085F7F51402D3E0704560C3340F060578AAC7D514081D4A9D4CE0333406BA21DAD277A51405D04A116AD5A33407B31F24A1873514059DE311076D73340DF40BE794D755140E6FBE19D3CB73340ED3A3A1B346B51406F3FBBE72B0B34407DAA107468655140690EAFEB69DE334052B6F334695851409414B55368A43340A91BB9BE0D52514048A34C805854334096C511B12C5A5140CFD011D1D35C3340C4E9A987265D51405330D439B42B33406A30EAFBCB5951409AD576C525033340545F36CE9D5F5140E8E6FA9CCA2532400969CD97BB5F514007B0886B0AAA31404116B5C3CA6D51405DFC09CFF82831404F0F8054F0735140
1931	Lenvik          	Troms           	0103000020A2100000010000000C0000000C827CE5FDA73140C7EA823FE95C514063F8C260D7C531400BB43E8B725E51405E7A0F33360E3140107B14C9AE6F51405DFC09CFF82831404F0F8054F073514007B0886B0AAA31404116B5C3CA6D51400B6C700B7E8C3240A3645CD12358514029F7B5AF218532402962641EE3525140FF016E87EDD43140C7729AD731495140D54E127B95D93140DAD2DEC40C4D51400B726E0B90AC3140205DD72B124F51406A4B50CD75913140822640CA615651400C827CE5FDA73140C7EA823FE95C5140
1871	Andøy           	Nordland        	0103000020A2100000010000000B00000067A1C4CABAB42E403B517CFBA949514044D538864E0B2E402820AAE338545140DD3C4F221D413040CEA5B05730665140A9773647848430402C0D23C0975A51406CCF03FD075030403BDB75799E4A51402CE80970640D30407F7FA1628D405140942C225B1B972F4023B334B1F83E5140C4B28691F9B82F408AB94AC9FC38514092C1C1772D7F2F40B5C93F01BC30514061D2E6AA80C42E40D396F34AD938514067A1C4CABAB42E403B517CFBA9495140
1438	Bremanger       	Sogn og Fjordane	0103000020A21000000100000007000000CA15820BEEE710403FB03F8B48E44E40C28E6C06C7C311409D4B4F9516044F40FB6B24B64FB814406E6EB16D1DF04E402D4DAD5034D41640EFA2929EB5F24E4083F3C75D3D8217401C2CF99853E84E406107D45A3DDF1440AB7012C5C1D44E40CA15820BEEE710403FB03F8B48E44E40
1244	Austevoll       	Hordaland       	0103000020A21000000100000006000000C0F0FA972E301240BB94507C510D4E4034E8526A1ED71440E68167702A184E40DEE0B3A5C9531540A59DC385B80D4E40D19EB438884F15407D21E871E0FF4D40EF8DABAE046D1240D823742CEEF44D40C0F0FA972E301240BB94507C510D4E40
1848	Steigen         	Nordland        	0103000020A2100000010000000C000000EEDFF3A652402C409C8481F96BFC50400ADA31A4061F2E40CA09B873C3075140AC7973A29EBC2E400E75718737FC50407012BC6FF1782F4027506CC5E1FE50403D1B8047E97B2F40483208FE3DF650401150530378D22F407EAB051B85F35040EE55914E3E3B2F407424714EC2F05040224372E050722F40E31B9AFAB4EA50406A926B0FD5252E4054CEAD087CE7504053141ACF2B452C40CB5B330E8CE55040C833FA5EAA302B40EF4EAD8FC6EC5040EEDFF3A652402C409C8481F96BFC5040
1845	Sørfold         	Nordland        	0103000020A210000001000000100000006A926B0FD5252E4054CEAD087CE75040224372E050722F40E31B9AFAB4EA5040EE55914E3E3B2F407424714EC2F05040E4E65644FB942F404100789D1EF250408DB5856F641B3040DFF49422AAEE504040C20F5D566830404116997B2DE25040840F70D072283040C3C4F6E139E15040B09CCA16FF16304071DB9C99DBDB504093E0568C795430402A88876CC5D05040CAC21CBAA6902F407FFB695A25D4504073513022FF302F402D2208EE5AD05040CD11F1D3A5E62E4011DE73E1F8DB5040040AE567202D2E40E3932D2514DB5040028C04C176212E4040BF0E4C3BDF5040D2A240091B602E40E1E945850AE350406A926B0FD5252E4054CEAD087CE75040
1260	Radøy           	Hordaland       	0103000020A2100000010000000500000031BD7F5F561B13406D60EDC9F15D4E40E188E1E19327144072D049F68E5D4E40FA570DA985D61440446CAA5F9A4C4E404A0C5A3D6D97134071F1BED8E1504E4031BD7F5F561B13406D60EDC9F15D4E40
229	Enebakk         	Akershus        	0103000020A21000000100000007000000B2753BE4CAF22540D43E8DD029E24D409C020BDD5EDD2540AA2B41DD5FEB4D4031DBFEE2E65826402A915A1793ED4D40692A8194C17C2640F18C6C5F10DF4D40DB4CD848E775264032DDC10E64D74D4024BB025C6F132640C64A22DD81D84D40B2753BE4CAF22540D43E8DD029E24D40
911	Gjerstad        	Aust-Agder      	0103000020A210000001000000060000002715083632982140B6646CE90B714D403D15A54024862140BE7AAF2568794D40A213826461FD2140BDA24511227F4D40392D9858DE612240DE3EA094396A4D40E2E0A010840B22409815D11DC9614D402715083632982140B6646CE90B714D40
5037	Levanger        	Trøndelag       	0103000020A210000001000000060000006DF50DCB2EDF25406C8D2DB2A1D24F402A2F6A0083B62540A5E0F74DBDD84F403BA7A2AE368026404F9C5BB501EB4F40D5F7EACDFF742740C85188CFFDCB4F405BFF6130309725406BA4B9EF58C74F406DF50DCB2EDF25406C8D2DB2A1D24F40
127	Skiptvet        	Østfold         	0103000020A210000001000000050000006A70EBAAF82526405AFBACA122BD4D4080D697984E42264049DCF7DA4DC64D4063305CE2577B264022AD047CFBBE4D40579925381A5026405D9CA46E49B24D406A70EBAAF82526405AFBACA122BD4D40
122	Trøgstad        	Østfold         	0103000020A210000001000000050000002244581D316E2640CE32CA03F0D04D4036A5652292822640589F301398E24D4076CD62CD27022740A37C84360AD04D408BC05F03B39D2640C493B90E1AC94D402244581D316E2640CE32CA03F0D04D40
1149	Karmøy          	Rogaland        	0103000020A2100000010000000B0000008BE678888D1F14400F6141531CA64D4050040337E69C134027067916F0B04D403F04AD7AFC1F1240BF22BDC0DEB84D40D5B3F03C924612400D707B4576C04D40D4AF7C7747771540A0B9778444B54D409DFB2BBA64B8154061BA769B87A24D409ACC420B0866154005FE4EDC4B9D4D406C8515B7F07B154059E26AE94C8E4D400C5E05EC22D61340BDADACCF5C7A4D409BF20D5393DE1240CD8DD68112894D408BE678888D1F14400F6141531CA64D40
423	Grue            	Hedmark         	0103000020A210000001000000080000009440B4478E9D274067181AF374384E40F6983DC54820284047D61F5155464E401543575DB9362940BC7B0888A1414E40A9BF2CEF100329400A62DC1A6F234E407F91D25AB09F28409A05EE4EF6324E4003E38F5E2E7A2840AA82CB3358274E40479CA8BF39A027408AC603C4D42D4E409440B4478E9D274067181AF374384E40
1251	Vaksdal         	Hordaland       	0103000020A2100000010000000D00000028680D88D1A11640C58D456B70574E40ACAE4FC027711740836DA776ED674E408313D104973719408D1971EABB704E40789037F674E8184077C956BD14624E40C2B3E8A96EB3174018468918F25D4E4030E43DF382631740FA5D00A3BB534E40FD23FD1ED04E1840C93B1DB9634B4E40E8DA5889C85018408732AE852C434E401428683B367B164052F5EF0C0F384E40D19137FC25E216400885C040623B4E40346399B635591640DF355590CA494E401D6E1710ABB21640890A4ECCA54C4E4028680D88D1A11640C58D456B70574E40
1429	Fjaler          	Sogn og Fjordane	0103000020A21000000100000006000000F4EA37510512154071E83D7C85A34E4079A75DC5FD4813406340AED24EA04E407058D31F4DAB1540F08234F3C1B04E409E3E33405AED1640CAA2BC6E31A04E408324D8F5F25A16408E79B85E0C974E40F4EA37510512154071E83D7C85A34E40
5053	Inderøy         	Trøndelag       	0103000020A21000000100000009000000640480FF089E2540C9861EB166EE4F40B024EB7E588726407C23948F050050407A67EA2552CF26400F9B6848F3FF4F40BC4A930B15AF26402517A95726F14F40FFA388508A0C27403E16541F33EE4F40698FF188A71426401E8A880EE1E74F400388B5D93EC02540F978475C8DD94F40E08CA87BE64525407076483B75E84F40640480FF089E2540C9861EB166EE4F40
1865	Vågan           	Nordland        	0103000020A2100000010000000B000000FFF0A52F12612C4039BA3FA4A90F514032D545E4A5B52B40CA00DC5A1C1C5140AAA6B001A9C62A4097AF857C9F2251401098C1A7CDFB2A40EBF1545BBD26514098C736CC1D412D40DE2CEED2E11651405176C8DB438B2E40F6344B59441651403A853AC77E402E400ADEF462931251409CB91419506F2E40D23FFD00330B5140EEDFF3A652402C409C8481F96BFC5040BCBA1A1D770C2C40CAEE67C504065140FFF0A52F12612C4039BA3FA4A90F5140
1857	Værøy           	Nordland        	0103000020A2100000010000000500000074984FE3B6F9274059E8445B09F25040970A67134D5528409D9EDC5AAFF75040B881D2646B032B40B839EDFB23EB5040A8DC6C9C2FA72940505455865BD7504074984FE3B6F9274059E8445B09F25040
1505	Kristiansund    	Møre og Romsdal 	0103000020A210000001000000080000008F8DC3DB0A781D4018ECC064129B4F40CBEC8DCB9AE21B40E8EFF2B3D6AB4F402DF5458450711C40F15FFD17E7B64F4066A0FCFBBF1A1F4007670DFAE8994F4041F210899CB91F4075ACC79425894F4097D1F05575061F40722DA1F2AE804F407D32BABFE7AD1E404F6964BF29904F408F8DC3DB0A781D4018ECC064129B4F40
1547	Aukra           	Møre og Romsdal 	0103000020A21000000100000007000000D343B38D00FC1A402AA3DFEA3E694F40ACE3EFDB3AD41A4031C219ADE6714F4015CFD47D2F5A1940CBE4F4BFB08B4F40650E087F49FF1940522A1DF1AE924F40DFA36F498A301C40BD09F68263604F406AB332D9E6C91A40FD6939713F624F40D343B38D00FC1A402AA3DFEA3E694F40
1441	Selje           	Sogn og Fjordane	0103000020A210000001000000090000005DC2F76F20BC13405B58FE355C0D4F403CBF3E40D050124009FCCCE525174F40EA4228503344134098518050F2304F406AD2E9ED1BDF1440505535FB6E214F407025351A71031640C12D01C227014F402A3CE1C2DF221540F52FF93A1EF74E40C9A3893319CF14408B308D53BEFA4E403AD52C793FE414409B1345ADC1054F405DC2F76F20BC13405B58FE355C0D4F40
1265	Fedje           	Hordaland       	0103000020A21000000100000005000000FF6A798834BD10409B09EB4BAB6A4E40E861F6F64E7112405EF2976690714E400A426ED82A2A1340014C4549BB614E402D1723F785101140FD30C0800A584E40FF6A798834BD10409B09EB4BAB6A4E40
1122	Gjesdal         	Rogaland        	0103000020A2100000010000000800000017C350253AF9174028D1F8BFCE694D40B6E5E7BB78D718406F42BAC4616C4D4051696B917FA91A40CF690DBF207E4D4079D626D653B61940B0CC011C195F4D40DEDC64687EAE1840251C087BBE654D402D30A63A72D117405AB47EFD13564D40D357ECBA283217401BAF41AA54604D4017C350253AF9174028D1F8BFCE694D40
628	Hurum           	Buskerud        	0103000020A21000000100000005000000380399FE68CE2440B9FDDCC7FAD54D405AF80C4C513B2540FCFEAC9059D44D408B52A5EA0B16254047307CB089BA4D40EFA8B7E191C92440A82C6157E1C14D40380399FE68CE2440B9FDDCC7FAD54D40
1424	Årdal           	Sogn og Fjordane	0103000020A210000001000000090000005A467A8FA5071E40F935C98A16AA4E4085F83CF7E77A1E40DFE1D12D31A94E40EFA0590B53941E409123ED1083B84E40A6CC022FB77C1F4092CE0A8C08BB4E40D0F56E0CFC4C204023DB16769FB64E404F3D0A93BD802040497B0B30EBAA4E403EA186FF10A01E408B9AAF29318E4E4058E90FD726831D40445D6E7884994E405A467A8FA5071E40F935C98A16AA4E40
1516	Ulstein         	Møre og Romsdal 	0103000020A21000000100000007000000A918A0F8F7E4164070A0C6184E334F40AA7C40C4B5BC1640C1B08122C1414F409BE093EB5FD217400D4706A8C7384F400221B1E63F9A1740963CF894C32D4F401F1BEC5A3EDE17406608F77138234F400BA864783C63174076077FEBAA1B4F40A918A0F8F7E4164070A0C6184E334F40
5013	Hitra           	Trøndelag       	0103000020A21000000100000006000000BD58A29815462040B675E0C6C3C74F40D98C1EA6514C22401FA0E1D606E34F402E06A6BDEE98224055617A52DECD4F40CC27E93B20172240B27E080CA2BD4F403FAF611695AF20404143EF4201AE4F40BD58A29815462040B675E0C6C3C74F40
1034	Hægebostad      	Vest-Agder      	0103000020A210000001000000070000008FD5A4A6856A1C404A231285293D4D409F62E96CD6511C408D2CD8DD6B524D400F03B6383BA31C400F01F676DA554D40876E81CBFF831D4093ED8C72D5414D4003B8DDB854321D40A752B760E9274D408F4E7E22268E1C4017241BA724244D408FD5A4A6856A1C404A231285293D4D40
1852	Tjeldsund       	Nordland        	0103000020A210000001000000070000006D558DC41D2830400D79971C3221514099A297094CFE2F40899A5BC090235140C4CC029FA4443040F0FBB73064285140B945AC36439A30403DD487A0E5225140A7CBA7A152913040C3AD5AF0CA1B5140F672EA57A40730406DD78CA51D1851406D558DC41D2830400D79971C32215140
1545	Midsund         	Møre og Romsdal 	0103000020A2100000010000000500000038C5332280101A408D39C19693594F40B620C056C7431B4040A47B101E624F40A95FA167E8011C40F195764256584F40FC8DE231BBC91940D7CB923853534F4038C5332280101A408D39C19693594F40
937	Evje og Hornnes 	Aust-Agder      	0103000020A210000001000000070000005F1BB877FA711E40320F34C6434B4D40B2E6445C1B311E403C37D3B47F574D4012547FFC2C951E4097EE8B639A5D4D40629CC95A69392040C171F059874B4D4095AE238288481E40762E48E80C394D40CD4C97C98D0D1E40348050DE7B434D405F1BB877FA711E40320F34C6434B4D40
1504	Ålesund         	Møre og Romsdal 	0103000020A210000001000000050000009C064CFDC13B18400C51C2FEAE3A4F407EAAC76DC0D919402E6A33D035434F40EC2B9F1BD7C7194042F562D9893C4F40BF560170FE481A405061715365374F409C064CFDC13B18400C51C2FEAE3A4F40
1223	Tysnes          	Hordaland       	0103000020A21000000100000006000000D19EB438884F15407D21E871E0FF4D40DEE0B3A5C9531540A59DC385B80D4E4081A247C1839C1640BC1A11919A0E4E40EB87080235141740B7DA052654FA4D400200AEB8B4981640DFBFC070DAED4D40D19EB438884F15407D21E871E0FF4D40
215	Frogn           	Akershus        	0103000020A2100000010000000500000097A34A1C965A2540073CB4AC3DD54D40F658E483F15D2540F9CEE9C688D54D40C85098425B612540EB400A6C13D54D40685A7A59D15C2540FBA5F2E49CD44D4097A34A1C965A2540073CB4AC3DD54D40
1827	Dønna           	Nordland        	0103000020A210000001000000070000001B959480D3172840D2445FFAFB8D50409D836C790EAE274017987C100494504080D4390F10412940BED7928CA6905040BEC509540FAB2940240D781979895040BE9F9C72F7F628407E88823CC07F504097021BDE009E28408958136C948050401B959480D3172840D2445FFAFB8D5040
5031	Malvik          	Trøndelag       	0103000020A2100000010000000500000063AE307EFAB52540D01B345057AC4F408FF97DA9A1B72540B7EDD8F0D5AC4F4050D76063A7BD2540446DC55F2EAC4F403F7E138E17B82540AB2A2D80FFAB4F4063AE307EFAB52540D01B345057AC4F40
235	Ullensaker      	Akershus        	0103000020A21000000100000007000000D5597FBFB3272640709A23C3CC124E40BB198038D71526409AFC4F2401194E408DE15512865E2640D930395CD7204E403C8B17C0B1A026403990C3A58D1A4E4057E2290AE4AB2640503AEE325F0E4E40AA4FF84DC9302640CB52B63F15074E40D5597FBFB3272640709A23C3CC124E40
513	Skjåk           	Oppland         	0103000020A210000001000000100000007AEF11D7CB911D40000C2B5973F94E40F4BCFD4DC05E1D40C46369E188044F40289EA117ACA81D4079368B84C90B4F4092D2DF9BC9551E40E49ECE115D084F40AF6E21BF48511E40057906569A0F4F409C32F5C1324F1F40F59249A847184F4013C3887137EF1F40F49C36F8B6164F40901287BD966F2040F53CD2F251004F4071A04A60C72E2140475EA77203014F4040E871431ADF2040C67F525EECF74E40A492E213F60C2140C7596D209AF24E40187EB30FAFEF2040AF8EC9DD15ED4E40F3329512209E1F4065085EF6EDD64E40D03B3D3C94021F404BACF89C9DE04E40FC16AACD270E1E4067B4CB461ADD4E407AEF11D7CB911D40000C2B5973F94E40
1256	Meland          	Hordaland       	0103000020A21000000100000005000000B996FDB03DED13401F393FA9C3474E40AF3F006401B813407B97444935504E40622DC18C8B261540FAEAAD2836444E4042989B80EEF21440E8A90DB7683F4E40B996FDB03DED13401F393FA9C3474E40
213	Ski             	Akershus        	0103000020A2100000010000000600000045FDE6ED1E9B2540ABDE4FA657DE4D4099FA658B80DF254039FB142774EA4D40F237F1F0C2F72540043D30DC35D44D408F71C825F5EB2540271E61DE58D14D40906BDD3258C22540C716A73234CF4D4045FDE6ED1E9B2540ABDE4FA657DE4D40
511	Dovre           	Oppland         	0103000020A2100000010000000D00000091547B41AF0722409B216EAE41024F40902B2C732093224079857ABE23194F40C4F2F8F772A32240C8D0141C6A204F40FC568DA4EB6C22402CD55199EB2B4F40B0F29FFC2E342340FB2940A7BB204F40031D6AA6BC95234092B7E7F4DA244F40396E2F58EB2A2340620592A8A1174F40E7F4EE033DDB2340676FDB931F064F407BEA93CD78AD234037B8DBEDB6014F40111EEFDE4CB22340A8950F0EB0F34E40714E2871A1272340C0C6141A8CFA4E406AB452C7E0BC2240CDE4EC3A72F14E4091547B41AF0722409B216EAE41024F40
5042	Lierne          	Trøndelag       	0103000020A2100000010000000A0000009850091913282A406095D1E7961D50405561324FDBC02A4039CD76297E2E504026C70DF5CEDC2B405A8D95AF9D345040B8551D1EFB4E2B409E3F794E24255040382D7F614D3A2C4028AC4F51991D5040FA31E6BB70502C40E5D0CBC97B0C5040ED3E8DA95FEF2B4071B940968200504091BCF790166C2A409910767D1A0650400116A2E0FD7E2A40B69C6D6C301050409850091913282A406095D1E7961D5040
1820	Alstahaug       	Nordland        	0103000020A2100000010000000A000000F91975357F24284044B7694375775040AB908931BD74284040E5CB6545775040FD8B28DF966F2840C503DCFE9E7A5040D2725E5BEC3B2940E34C60B284825040786BC0F5CA8C29400951029E668050403D7242FEB03529401A2CF1D5C47950402AC7DCE71823294000B60873AA7150404EF2E420F9A32840B2C48D29176D5040E9794B90445D284048EB8205E76C5040F91975357F24284044B7694375775040
1928	Torsken         	Troms           	0103000020A2100000010000000A000000A9773647848430402C0D23C0975A5140DD3C4F221D413040CEA5B05730665140FC69AB9505923040EADB5D2090695140E9EBBD8DF2D3304083318FE11A5E5140FB37751550683140368AE7601E535140407D119F7132314082E3E31E9B4F514053D6508D59423140AE2F56F6484D5140C3FDAD4B8FD53040DDFFAE7E1C4B51409EF376A7B86E30407B420A9A01545140A9773647848430402C0D23C0975A5140
1548	Fræna           	Møre og Romsdal 	0103000020A2100000010000000A000000118EA8175B151B40120B6285F5764F40650E087F49FF1940522A1DF1AE924F401D1EF533DB311B40FE63BBF2899F4F40FED490F3D1DD1C40489E5AEB36874F407AF98AAC50201D40952FB9F38E724F40DBDC471BF8B71D40095C3E89FF694F40DFA36F498A301C40BD09F68263604F4062B0AE1818CD1B4087F5B94A0C654F40AA6590D632F21B40F0B900CC636D4F40118EA8175B151B40120B6285F5764F40
5015	Ørland          	Trøndelag       	0103000020A21000000100000005000000C8926C6F8A6D2240CB9BA72857DF4F40234DA7B2595E2340DA3E4ABB21E04F40992B4A2EDEA62340B8FA1F3AEFD94F402E06A6BDEE98224055617A52DECD4F40C8926C6F8A6D2240CB9BA72857DF4F40
538	Nordre Land     	Oppland         	0103000020A2100000010000000A000000F26F2D1C4B8E23406D26CAAD4F7C4E401453DF2C519423401BFB1875D8894E40F558E95E99432340B9D0B4C417944E40E2EE9E2EDC162440B4DFE43F1D8F4E40342970BA5B7724400C04B3A7ED824E40D216C780D9552440214E528AA1784E4009984333F38124404167B383926F4E40B3F64A6730222440353577C1D05E4E400A8B78D36CAB2340CF62EF8EAB5D4E40F26F2D1C4B8E23406D26CAAD4F7C4E40
1413	Hyllestad       	Sogn og Fjordane	0103000020A21000000100000007000000BC6C27FEC50E1440A3A2914BD8964E405E04ADD736AB1340CAB7EDA83D9E4E408672955D5B0F1540910510F01EA44E409136EEED59C81540C9F1EF5A819A4E402FEA0CF859CD154068DF2565488F4E406E583431D57E154018655711B6864E40BC6C27FEC50E1440A3A2914BD8964E40
829	Kviteseid       	Telemark        	0103000020A210000001000000070000002A8CFD43255A204031FCBB8D20AB4D40BB794AADF2A820408ED0E100B1B44D405FC38AA8398920404FC3CEF19EBC4D4056ED4DD98AA32040E75252287DC94D4000C7433CFDC32140E3DD9CF9B6A64D4058B39E26262F214097F5E4BF139F4D402A8CFD43255A204031FCBB8D20AB4D40
807	Notodden        	Telemark        	0103000020A2100000010000000D0000005DCB6F1A70052240BA2B626799D04D40034D3AB13DC1214025847A492CD54D400330C223F6D2214037F4DD7C27DD4D40EF2D3610C49D2140A43EEF1FA8EC4D40E5BDD15AE2D22140A29FD112FBF24D4023C59696470F22400F06CEB1D0E14D40BB345AFE465F2240D68609B9DAE94D401031145D4ABC224072B016E902E44D40FB6D212FA5AA2240DAD88BE3ACD84D400F3BDEFCFFF0224006BFF1FE96C74D4041A9B1F05D5B224045CC719C2DBE4D40D8744E5F2B8F21403B78618C65C24D405DCB6F1A70052240BA2B626799D04D40
817	Drangedal       	Telemark        	0103000020A2100000010000000800000020F6F459BB522140184A3726598B4D407118EE376E79214084743186038F4D40232C8FFCD22B2140C5BFB26A14A54D40857168413349224099895A28099C4D40C7386A18205622408990447138924D40ADEB64EC22CC224023E179D790864D40544C00253152224067BBA15E46714D4020F6F459BB522140184A3726598B4D40
1222	Fitjar          	Hordaland       	0103000020A210000001000000060000003C53E481C07914402518402617F44D40CB28DB0959501440068E6C9124F84D40D19EB438884F15407D21E871E0FF4D40156710FE41FF1540B9E7223037F64D400F94D2D850481540F14982A362E74D403C53E481C07914402518402617F44D40
2024	Berlevåg        	Finnmark        	0103000020A210000001000000080000001B65B429E4CC3C40F03643BC6ABD5140187A06C028293D406BBCEB66B9C751408F85AA01540D3E40A33E9A042BBC514062E39D95CE353D40F4FE59D2839E51401C6F031970CB3C400929C1A058A051401EAD06B0D16A3C406FE6192F76AC51407A041306A1623C40669134F5BDB051401B65B429E4CC3C40F03643BC6ABD5140
1221	Stord           	Hordaland       	0103000020A21000000100000005000000D73C30DA0567154059C210D525EA4D40156710FE41FF1540B9E7223037F64D408EC1A5EE6F9A1640691B5A5C3FEB4D40D876C8B17C9D154038C099209CDC4D40D73C30DA0567154059C210D525EA4D40
1924	Målselv         	Troms           	0103000020A2100000010000001500000003FD877FE6943240D3F9B64C253E5140719793459195324082F7A853C5425140E1FEE48DF58032407841B1738841514034E0DCA57B60324038CFA686FC4251400DB46D82D3733240264B3457CB42514048723EC628723240C12CE88B5C485140C8FBC5ACA32D3240BF466DDA914B5140926A7068A9573240D81EC545124C51403DCEF3B6C942324047B0E859C64F514029F7B5AF218532402962641EE35251400B6C700B7E8C3240A3645CD12358514061F94F2E0F50334019F09B57444251400DCADA405F0F34406CAC27B2ED42514000A511A77C4E344038875392463B5140D7AAC7C6FB553440E053B31E5933514063DC080E600D3440F7DC1919D4255140D108830A9FBA3340D4BF013CF1235140AA7C1C0D0F353340FCF632B46631514092097C4512D93240D7F24758783351409765416A72983240B578D43C9739514003FD877FE6943240D3F9B64C253E5140
1922	Bardu           	Troms           	0103000020A2100000010000000F000000EA70581BF6053240953118ECF02651407914226F280D3240CB3FA0695E2D51406EA88F9E1BFC3140F45BB4BD7830514006D38523CC223240BA3EA2106B355140E02DC8945D123240C0D93C4762375140BAAF1E2CE12D32404B3A8326863851406D934E0E193A3240FC276E22B53F51405EDAF8369B8A32408AE2CF02424351409765416A72983240B578D43C9739514092097C4512D93240D7F2475878335140F22F5EC6FE3934404502BE80691F51408F9003AEE0EB3340A7F41CEEC81651404620E940DB673240150F2F7B3D255140629A0B873C2032409FC6C94156225140EA70581BF6053240953118ECF0265140
1805	Narvik          	Nordland        	0103000020A2100000010000000C000000ADA52B20BA1531406D7CB85BA3165140FE9FFC8A54F93040A2062BB5B61A514007FD3D4D965C314049A973A7D31D51402263CD085D3F31400B455570131F5140EB2F601B74563140CEAA7847FF235140EA70581BF6053240953118ECF0265140629A0B873C2032409FC6C941562251404B3BC531BF2632408C08FEF6B80C5140BCD094D856E63140D1400C2A0AFE5040EA0911A4D33731406F6E8CD15F095140F3FE3D6EB73D3140FFB76B8318105140ADA52B20BA1531406D7CB85BA3165140
1832	Hemnes          	Nordland        	0103000020A2100000010000000D00000048C0074EAB6D2B40A9979891787F5040EED843AD67582B408254D713D58A50404374F2B2E7AA2A40723FC1B61E875040296D52CAAC042B406D1C7F39EF8F504005807E4863632C403CFA8E4F8C8C50407F004B3BFB8B2C403D3F5ECC6F87504019BFB640BE0E2D40333E8DA51D865040567FA0FC61342D40236FD9132F7750401C2AFA2CDD9C2C40C9788D4F10795040186210AEF9262C40D72A98C526725040DACD73EA85832B408746A3E879715040ECF8E81DDD342B407E87C2BEE07B504048C0074EAB6D2B40A9979891787F5040
1421	Aurland         	Sogn og Fjordane	0103000020A2100000010000000C0000000742B6A9FC001B40A4E9C7E7836F4E40247CDA824A4E1B40F030DBC3BD724E404E012A5670FB1A405FB7939527764E4075A1BBE6F9311B40EAE53BC5EE7F4E40BAFAD590CEB31C403F7DF0C575884E409C5F0BCA62001F4067D3EC11BD6B4E4021C01C6350D11E4091BE21809B5E4E40C9CEF258E9E01D4020D7175878564E40C57FC3D703FB1B404E3E5B79AB5B4E4020FCF32D597C1B40A582A1AA51624E4002387B548DCB1B402DFBFAA5AB6B4E400742B6A9FC001B40A4E9C7E7836F4E40
620	Hol             	Buskerud        	0103000020A2100000010000000D000000B36B49EFACB31E40FEE5746DB4444E40C56982771C8B1E40CDBCE41703514E406DFDF0E95FC11D40198DB22A7C544E4021C01C6350D11E4091BE21809B5E4E405B09EA56C7191F4017F312C3EB6E4E4088DF983229D42040018D6E20034F4E409B4CEFFE6FC520401D2B2052393C4E40264F34CAB73E2140CA4F112C9F384E4072D9C1885D472040E35A7BE4A62B4E401E075C9FB3271F40ECA1131A8E2F4E40AD55752C41C81E403A44A6B03E324E400339927BAFED1E40A49CB928AF424E40B36B49EFACB31E40FEE5746DB4444E40
534	Gran            	Oppland         	0103000020A210000001000000090000009C44031BE45C24407AF91D1D3C384E402741765C3B4C2440FA785EF63B464E40775E0FC32A1A254055E901142B484E40B63178EC766C2540064609C60D424E404A03F5740D5825404C351EA188374E40F56E897E28DE2540B6A33667602C4E400393CC51DAC52440D75F033F86284E4016966ED3E7C624407571566207304E409C44031BE45C24407AF91D1D3C384E40
2012	Alta            	Finnmark        	0103000020A210000001000000110000004371B67C1E443640950E0AC20A855140C48939978B9A36402C2323FB548651400110DE245E6736400A45DC2E01905140C44C0D5F3BA83640C8ADFC23EF925140D8EFECCEF1B036407116D160AC9C51400393EABD3F6C3740A9B0C8E057995140E70BC8B890BA374028E438680D955140AB0340D106F6374035A6346C2D8651403175C13E4FE937408275037149805140C051060A831D3840817395E33F7F5140E098CDF4ED35384042E27F8ECD6A5140DC0E7F12F47C374080F29D17A16D514079C417004EC136401CFCC7104F6951403BB99EA293733640E6CCEFDE9A7251403D601CDBD8863640732761A7AA795140AC8501A99A2F36405534C6C1B58051404371B67C1E443640950E0AC20A855140
1923	Salangen        	Troms           	0103000020A21000000100000008000000BF92556EDB6D314022F89E0AC1395140F75B22974AAF3140BEDD570EAE4051406D934E0E193A3240FC276E22B53F5140D35CCD18C0023240426CBD3D4D2F51403EB4541EEFD7314095BB86B9313551409866528F4F6F3140D3B05BFF3B355140A661D5D3318831409C5D8484C7385140BF92556EDB6D314022F89E0AC1395140
1838	Gildeskål       	Nordland        	0103000020A2100000010000000D0000004AA289959CCD2A4015447F57ACC25040EE8DD9ABB1972A401C474F8DAACA5040183EB3ADBB312B4031DA959A1ECF5040484B60B9CB972C40670FB36174CE50408D50EE2246CA2C40CF0CF53220C95040A7046053B3AC2C4016586DB134C650409FF0DF2C9CD22C40DB84099D82C350409C5053F1DB9D2C402472196E08BE50408AA562AF62C62C40A2F6A7C84EB45040D60105B995562C40DFFF638080B15040908BB15FF4DB2B40EE2A09953FBB504050C400FD585E2B40A3EA9B265DBB50404AA289959CCD2A4015447F57ACC25040
1925	Sørreisa        	Troms           	0103000020A2100000010000000A000000A69AE71E94ED31400C289F86C6475140ED45594177E0314005E3CF8B8C4951408D4F538BD44D324004462FBD204E5140926A7068A9573240D81EC545124C5140C8FBC5ACA32D3240BF466DDA914B514048723EC628723240C12CE88B5C485140027B5DDEF87532403FB7D931BF43514044CE992E600D324075EA44E4BE3E5140703A87E009E731400D2C5E8055435140A69AE71E94ED31400C289F86C6475140
729	Færder          	Vestfold        	0103000020A21000000100000007000000DAB21FCCBEAA244023922CBA0A904D405A774093EAC42440E9894E54A5A24D40F43D09F13F2E2540C0C6B4A85DA24D409850BFBB624F25405885FE1092984D405054272BAA2F2540DA25612667614D40E21A4C95FFB7244065281637B9624D40DAB21FCCBEAA244023922CBA0A904D40
2017	Kvalsund        	Finnmark        	0103000020A2100000010000000A000000D4E2B581D3953740C46D5B7710A05140AF20C982DCA33740F3982FBC8FA451402D85BEA4142C3840510C4365CBAA51404AD2B60D1B2B3840EE698CD87EAE51405B01DD432AFA3840BC8182CE91A7514058F4A32F572D3840F498BB7534875140AB0340D106F6374035A6346C2D865140E70BC8B890BA374028E438680D9551401E12F4964E443740B1DDBDEB3B9B5140D4E2B581D3953740C46D5B7710A05140
1439	Vågsøy          	Sogn og Fjordane	0103000020A21000000100000009000000B8016BE533CF1240F4CE20B596FD4E40C28E6C06C7C311409D4B4F9516044F403CBF3E40D050124009FCCCE525174F403AD52C793FE414409B1345ADC1054F40C9A3893319CF14408B308D53BEFA4E402A3CE1C2DF221540F52FF93A1EF74E40BA10BE1930291640D344865BBEFB4E40FB6B24B64FB814406E6EB16D1DF04E40B8016BE533CF1240F4CE20B596FD4E40
1002	Mandal          	Vest-Agder      	0103000020A210000001000000060000009AA543534B581D4053F7883313064D4086B2D9B39C391E406267EE2FA1134D407266198658841F40A5A51A11A9E64C40DE4E7D19FF071D408EBF0DC97EE14C4070A0E1FC890E1D4036977C89CBFF4C409AA543534B581D4053F7883313064D40
1546	Sandøy          	Møre og Romsdal 	0103000020A210000001000000060000004D64202B928C1840E45A9AFD3D684F40E0D06B58218D174025ED97A0AA764F4015CFD47D2F5A1940CBE4F4BFB08B4F40D343B38D00FC1A402AA3DFEA3E694F4038C5332280101A408D39C19693594F404D64202B928C1840E45A9AFD3D684F40
1554	Averøy          	Møre og Romsdal 	0103000020A210000001000000080000002E01E70758DD1C408B6CB469B5934F40EC8BB5BC27711B40C75CBDFEFBA24F40CBEC8DCB9AE21B40E8EFF2B3D6AB4F407D32BABFE7AD1E404F6964BF29904F4019E7F4A017021F40296F0EF4AA7E4F40AB4D1EECCDF41D407B30352F02764F40AC5CCB2A6C581D400146DEC2507D4F402E01E70758DD1C408B6CB469B5934F40
118	Aremark         	Østfold         	0103000020A210000001000000050000000E6CE2A90E2C2740B15C1DA22F9A4D40A0EA3A210A2827409D1C75DF29A94D4098F044B982A42740AA6923A22AA64D4075F765CAC96B27400DE4DA9D4F844D400E6CE2A90E2C2740B15C1DA22F9A4D40
5050	Vikna           	Trøndelag       	0103000020A2100000010000000700000093201B545DBB2440D1023823F95050405598FF2A104D26403B934C710748504077D3B6D833C326407ACF146F6A3B50404684806A8CDC2440F09B82C7AE255040B43FE3E38A9B2340F23C873ECD315040F1C8961371FE23406D09580CAB37504093201B545DBB2440D1023823F9505040
1532	Giske           	Møre og Romsdal 	0103000020A21000000100000007000000A24351648834164001DDC0C097494F40040A7687745D15404595A9DA3D554F402E2722DBA390164048089B24EF674F40933A24F25CB918405CDFFB24C64A4F401701E4C299C31840D60505AA2E414F40CB1F4F695F8B174066CDF4AE28394F40A24351648834164001DDC0C097494F40
545	Vang            	Oppland         	0103000020A2100000010000000D0000006EDA5B0D71032040CD2F0A25139E4E4051C9F5E7D57C2040DDE5070223A94E40D0F56E0CFC4C204023DB16769FB64E4036697154E69A2040BD13F2EE09B94E408FA2649E64712140C01FFF5009B34E404A5DA57477A721402756462710AB4E40DF20D479397B21401D428C3DF0A24E40711F55B03FC72140F5228254D59A4E409BA528C7065C214038997B9219874E40FC1225A8F67921404940ED8895804E40A9D1D529805021403124796136784E4045E4287D8B4420406B5E34B4098E4E406EDA5B0D71032040CD2F0A25139E4E40
119	Marker          	Østfold         	0103000020A21000000100000006000000524C006C390B274072C59666CAC14D40BCFAE19368102740A9D475BAC6D14D4051929CB82B72274062C3AB0F8DD44D4098F044B982A42740AA6923A22AA64D404757CADFF42C2740FC3084D022A84D40524C006C390B274072C59666CAC14D40
5045	Grong           	Trøndelag       	0103000020A2100000010000000A0000009174AE48D8402840280E7E9F0E1D50400A5B3D7B4A24284082E061FB931E5040D3863C3539012940F0BE669C7C285040CFF7386C1C2629401FB325F1A62D504033C4874F4E082940B28696FE3A2E5040CE9C232DA9942940CBE34D21622C50404DF86413932E2A401585A0CD31205040C3D0832C95232A405AAD701CC41B50402CB7B3A8CB402840799B4D59451550409174AE48D8402840280E7E9F0E1D5040
5019	Roan            	Trøndelag       	0103000020A21000000100000006000000A5E935870765234052AD8B77EF0C50402DD7DAB07A662340FD0F2CC556195040B103CFDE7AB92440D1C649F91C135040C82ED38C6F9225404179347D510750408E7E4FE7F36A244013AA616E4C035040A5E935870765234052AD8B77EF0C5040
1874	Moskenes        	Nordland        	0103000020A21000000100000006000000970A67134D5528409D9EDC5AAFF750407E1FF24DB1F028402A8748C7C10951409E8108D4AB002A402B8992CDEB0251403C37ADC4D3632B404796D3F433F25040B881D2646B032B40B839EDFB23EB5040970A67134D5528409D9EDC5AAFF75040
1933	Balsfjord       	Troms           	0103000020A2100000010000000A00000044B24367969C32401943E4BB9C54514072052160295C32405737FCCD0F6051409AD576C525033340545F36CE9D5F51405330D439B42B33406A30EAFBCB595140CFD011D1D35C3340C4E9A987265D514048A34C805854334096C511B12C5A51403411628E76EB334027B25BC8294D514038FF887ECEFD33408A25C063DB45514061F94F2E0F50334019F09B574442514044B24367969C32401943E4BB9C545140
125	Eidsberg        	Østfold         	0103000020A210000001000000060000008C7185831C622640B9D861AA50C44D401A5790EE397F26408C7820B7E8CC4D40D837F8257FF726406983B937A7CC4D40199E58559D1927405064A18609BC4D40E9F48EA3EC9E264040D001579EB94D408C7185831C622640B9D861AA50C44D40
540	Sør-Aurdal      	Oppland         	0103000020A2100000010000000B00000094E58C3EBFA42240D3D92AE22B574E401BA4A72AFC83224013E1E3753C624E408371EF68F4EF22401EC21CB188704E40536EB36B3ADD2340EC47F6DCE6604E406709381571122440B4B863E61A514E40783C33B067CE2340B57F040930514E40EB05847F8FE72340992644D1314E4E404D3C3F4F23AA234015470E76344A4E4035F36E140F9A234095A3294D243A4E40E7ED642AA7D5224046A6BAAD19464E4094E58C3EBFA42240D3D92AE22B574E40
128	Rakkestad       	Østfold         	0103000020A2100000010000000800000073FD12ADE5812640B688A0A254AF4D40941DA6AB696026404226D9FAE6B34D40905ACC9DEB752640D232A9EB9ABC4D40199E58559D1927405064A18609BC4D409D99147EE0312740AF21B6567FB34D406B89FEF0AA1D2740DA95FBFA3AA14D4003FDFCF2B8E32640FA3C54E97D9E4D4073FD12ADE5812640B688A0A254AF4D40
5040	Namdalseid      	Trøndelag       	0103000020A2100000010000000B0000007BE63460CADA254011487DB3EF1150404EF3869853332640C9C31D20631750404DE656F324072640B8EFD3EF8C1F50400C48DBE7CC35264035C203473523504091F11BF835622640E8311722BA1C5040BBC3BCF235B52640D5DAF3AB931D50409F3EB08BCC7926409E843971C619504071735711831527404AE6A749EF0E5040C82ED38C6F9225404179347D51075040E71F026D497B25405C5007F5540B50407BE63460CADA254011487DB3EF115040
1938	Lyngen          	Troms           	0103000020A2100000010000000B00000059DE311076D73340DF40BE794D755140C721520BFF383440E113EBD7B1835140DAC2E03725803440ABB4F6650E7C51407F1E019368623440B967A2A110715140CFECEBAD30683440B360B45C37675140B149E0CE42323440113D6BFD885A5140D809033CEEE33340613CBBCFB1595140D7453DD60DE133401DD3F5420E5E51406F3FBBE72B0B34407DAA107468655140E6FBE19D3CB73340ED3A3A1B346B514059DE311076D73340DF40BE794D755140
1856	Røst            	Nordland        	0103000020A2100000010000000800000074984FE3B6F9274059E8445B09F25040AC22EC964E2229406D6A1AC0D2DE5040A8DC6C9C2FA72940505455865BD750406DA3C18932B02840DCA565DBFAC75040AD4DCF95C6552740A503E888FFC05040813EDC06C89E26408A32AC8EB5DD504082450BBFC6E82640B494E0DBFEE6504074984FE3B6F9274059E8445B09F25040
1835	Træna           	Nordland        	0103000020A210000001000000070000005A3E832EB9B72740D505DD0B2FB4504079A22C7942CD28403D203A56CDAA5040305D8EA3F0DE28404A7ECCF1969D50409D836C790EAE274017987C100494504062D7B6A0759826403561891FE39950403026ECE87F2B2740DABE753DC6AB50405A3E832EB9B72740D505DD0B2FB45040
1141	Finnøy          	Rogaland        	0103000020A21000000100000005000000ED77F3421D94164060C0DC70C29A4D40E7E7118DE1111740BC2BBD46E4A64D401D8225B68258184097A1B7B70FA64D40B8FAADAE74721740911A7037658A4D40ED77F3421D94164060C0DC70C29A4D40
1818	Herøy           	Nordland        	0103000020A2100000010000000A00000062D7B6A0759826403561891FE39950409D836C790EAE274017987C1004945040CEFA80D9DE872840F85B6A7F5E8650405E59D9107A9628403611E882CC805040BE9F9C72F7F628407E88823CC07F50401C38AB753E102840B0EAB6388676504008086DDDB6C02740A58E9E8FE6795040F9416BC172222840C0267F229D7E504032ADD8CA63E82540215CB0B42B7E504062D7B6A0759826403561891FE3995040
1815	Vega            	Nordland        	0103000020A2100000010000000800000032ADD8CA63E82540215CB0B42B7E5040F9416BC172222840C0267F229D7E504008086DDDB6C02740A58E9E8FE6795040CEF9E593B9452840925C55BBF775504082257BC32F74284081368B0D79665040FF5903AD8EB927402AE24245365F50408765FF1296592540355EE142A264504032ADD8CA63E82540215CB0B42B7E5040
1146	Tysvær          	Rogaland        	0103000020A2100000010000000A000000FEA95084C5811540B09309EA43B04D40AB101A5DC58E1540D3F704F3DEBE4D4019EAAB2AA212164098E41E9E18B84D40E3C00B121E56164083C9F92727BF4D40326A6EFBF5D41640DBB12C9408B44D40EFA4F943577F1740C7055327ADB94D4035B3ED8119B01740105D8F484EAC4D40ED77F3421D94164060C0DC70C29A4D409DFB2BBA64B8154061BA769B87A24D40FEA95084C5811540B09309EA43B04D40
1216	Sveio           	Hordaland       	0103000020A2100000010000000600000043661FBB5CC4144080841DFD1DC74D40BD7A5C67FA261540CA342BA978D24D406FFFF6A0A9521640BA8A21BF74E04D4086F623A01E0B1640A743EF2AE1C24D4035C7F96D3F42154044F69291DABC4D4043661FBB5CC4144080841DFD1DC74D40
5014	Frøya           	Trøndelag       	0103000020A2100000010000000B000000352DA956E2F71E40C3C2F5EB62DE4F402925C7EFA5971E409BA8695153E24F407260DA5E9B342040EAF212DA7002504062AD03E385A622402983FDDD062350404D61193BB67623405BD718F63B1550402A8FC02C773A23407BD23189C7045040FF842708497822408BB13125C5F64F40D98C1EA6514C22401FA0E1D606E34F405A40C93473DE2140B4C5D79FCFD84F400E453E2EA13720407680EE1790CC4F40352DA956E2F71E40C3C2F5EB62DE4F40
1127	Randaberg       	Rogaland        	0103000020A21000000100000005000000669156BC160216406A706F062B874D40502355C27E2E1640513A06DD45894D407401C71BE5BB164009C18CC2DA814D406B5940B8CCC715409CA9B424B57D4D40669156BC160216406A706F062B874D40
1142	Rennesøy        	Rogaland        	0103000020A210000001000000050000002FABD1A602FF154015ABCB526B904D400C46A526A9641640839046965F984D40B8FAADAE74721740911A7037658A4D407401C71BE5BB164009C18CC2DA814D402FABD1A602FF154015ABCB526B904D40
1111	Sokndal         	Rogaland        	0103000020A21000000100000008000000A323A876324A1840B6341D39612A4D40DE51CFB63103194068D238F2093D4D4097166A854F3619401289D1FD5C354D402C93002292DE19406753D9D5E73A4D401B02E98B2C171A40F7CF622317314D4018FFC24B4C9918404BEB2D9B90034D402B591CEBAA7C17401884302F44144D40A323A876324A1840B6341D39612A4D40
1144	Kvitsøy         	Rogaland        	0103000020A210000001000000060000004E6010A4A6FA1440B98819A33A884D402FABD1A602FF154015ABCB526B904D40502355C27E2E1640513A06DD45894D401F7F7CE8F78815408D1BD5246E7B4D400C5E05EC22D61340BDADACCF5C7A4D404E6010A4A6FA1440B98819A33A884D40
1112	Lund            	Rogaland        	0103000020A2100000010000000A000000839422F9D3211940C356FE160B3E4D40C6905286930E1940AE96E55B97474D40821C408A79751A4083AF41D502504D40CC3EEDC1B6861A400B2A9C6958394D40BFFF088F6F2C1A40EFBD6263E5284D401715C5DADEE11940EAECAD4956264D401B02E98B2C171A40F7CF622317314D403F5019BF85DF19406B8A4D3ADB3A4D4097166A854F3619401289D1FD5C354D40839422F9D3211940C356FE160B3E4D40
1135	Sauda           	Rogaland        	0103000020A21000000100000008000000F3887200FEE41840FC63F6C81AD84D40CD74DAF5F8261A4080007C64E2EB4D40A3E66DCC27C61A4058FE349156E94D40E2EA5BE8FCC01A40368518930DD94D400046DF6125341A4020E7B6F142CF4D405EAD7DEDF20A19402BCF7576A1C84D4068EC52596FBB18404C43C73104CB4D40F3887200FEE41840FC63F6C81AD84D40
1134	Suldal          	Rogaland        	0103000020A2100000010000000C000000A2F34E42B9991840DFDCA5CF3DC44D400AC2DB3CACE81B406D35C83AD3E24D4033572B2F99621C40D6D1EC0632E44D407F6807E5B8701C40BCA9EB5EADD94D40DEE98C97D1DB1C400CEF769A1AD64D400121DC7EA5F71B4001F911726BCC4D4016CA7DEC6D171C40FABD8CFF97BD4D40F38C52E3E7751B40AEA993DC27AF4D405C0CB513F09B17408D67486396A74D40EFA4F943577F1740C7055327ADB94D406F87C86E28B0184035A67D6D48BD4D40A2F34E42B9991840DFDCA5CF3DC44D40
1851	Lødingen        	Nordland        	0103000020A2100000010000000E000000AD4C303BA97F2E40236AE2D6AD1651405C7987AC25432E400FB6771A9C1751404C1B37865CE22E40AA84E1F72B1D514001248CB3BFD12E408AB33CDDF121514099DAA6625A3E2F40E6D27A05AE225140287774BED0592F4038C26854141F5140F52B7248EA3A2F403A2DE919631D5140EF416DF1264C2F4027A7B1B55F1C51409A612496B7EC2F400CC9F4184A275140AE75FA702B2930409621CEAD69215140BF448C18D2962F401FCA05BDE20F51409CB91419506F2E40D23FFD00330B51403A853AC77E402E400ADEF46293125140AD4C303BA97F2E40236AE2D6AD165140
1840	Saltdal         	Nordland        	0103000020A210000001000000090000009D08FFD83F152E40773F05EC12BB50407008C9E714B92E40A305228501CD50408EB7900A704E304071B32FD533C150401827FB3C15112F405F5A50F1B3A350404DC5E2AB1C6A2E406A03B0BAB0A550400F8524D3A94C2E40E4301534CBAC50403E9115E84D662E401C1752E81AB05040F49CC4433AF62D405CD8869387B150409D08FFD83F152E40773F05EC12BB5040
1445	Gloppen         	Sogn og Fjordane	0103000020A210000001000000090000009145E209FFA416405EEE101976DB4E401326A37F425417408D55F4ECFEE04E404B3BFE1F934D1740B027266B28ED4E40364F738630A017402F4AC89144EF4E4066A3F1FE56081B407CE553FDC3E34E402D5C1D3A97A51A40E2CCAB6A08D54E40F4EEB5C942801940D0D5F7821ECD4E4032CEE7C277AA1640330101BF67CB4E409145E209FFA416405EEE101976DB4E40
1431	Jølster         	Sogn og Fjordane	0103000020A21000000100000008000000390B6927AE0F1840B8D06F114DBF4E4061C25E007F1F1940DD3F2430B3D24E40F4EEB5C942801940D0D5F7821ECD4E403D14B45163E01A402FD6E7EBD0D94E40AFD51F69CF6A1B4041D2C49103CE4E40A6B1C2EE81911A40C708BA78F0BA4E40561C51E66CE11740FCE750731EBA4E40390B6927AE0F1840B8D06F114DBF4E40
1432	Førde           	Sogn og Fjordane	0103000020A21000000100000007000000968DE7A2775217408E80A2F4D9B34E4067D4E16D740D1640F7EB266578B84E402EFD3CC863C718403AF35D7DDECA4E40561C51E66CE11740FCE750731EBA4E4060DB92C83B961A40F2401736EDBD4E40E95C97FBF6A61940BF23404182AB4E40968DE7A2775217408E80A2F4D9B34E40
1201	Bergen          	Hordaland       	0103000020A210000001000000070000001299B49C58AD1440315CAF16EB2E4E40609D0924FC1E1540BD7CEABB5C344E40622DC18C8B261540FAEAAD2836444E40B89470B6EBBE16401E37CDD1C6374E40C5118C324D0315405F89D0218A164E406BAD01750C94144044ADCEE9C5214E401299B49C58AD1440315CAF16EB2E4E40
1243	Os              	Hordaland       	0103000020A21000000100000005000000C5118C324D0315405F89D0218A164E40145ADF414D3A164050C61395B5294E40C19C843951821640CD5FAB4199244E4066950547F9F0154033C787353E0E4E40C5118C324D0315405F89D0218A164E40
1573	Smøla           	Møre og Romsdal 	0103000020A2100000010000000700000078EC386B0ABF1D405FECD19FDFA84F402DF5458450711C40F15FFD17E7B64F402925C7EFA5971E409BA8695153E24F400E453E2EA13720407680EE1790CC4F403FAF611695AF20404143EF4201AE4F4066A0FCFBBF1A1F4007670DFAE8994F4078EC386B0ABF1D405FECD19FDFA84F40
1264	Austrheim       	Hordaland       	0103000020A210000001000000050000000E07A39E4FF3124085A92110A5664E403869C60A64BF12408766BD1FDA6D4E40A7E2FBAABECE134071FA9020816B4E4059861267722E1440278B6C03D0604E400E07A39E4FF3124085A92110A5664E40
5046	Høylandet       	Trøndelag       	0103000020A2100000010000000A0000000BE8E41D5C6E2840400856580E325040D6786DE571A828409D2F83F99F3B50401367C91F6A292940D9DE98D82B3F50408F22B8216777294093B237CFAA3B5040C4D86217020A2940908372E0883650400EDF3132E92B294093898D87DA345040D3863C3539012940F0BE669C7C285040E27678F9A2662840BC006089A62150400480FE781D0C284024AB07DB5F2B50400BE8E41D5C6E2840400856580E325040
1227	Jondal          	Hordaland       	0103000020A21000000100000009000000282991B277DE18406FAADA5123244E406237A41D628819402820F62C00324E40C99AD5585D1E1A40EDA01B267E2C4E403471441F4EAA19401C5D3157EB254E40403DA10534E51940B3C51C47BC1A4E402D2E7493F11D1940F85D939AA11A4E40BDF499F4CBC418402B8F95E17F0F4E4037C32C09411B18406089763FCF184E40282991B277DE18406FAADA5123244E40
1224	Kvinnherad      	Hordaland       	0103000020A2100000010000000E00000092481951C0D816403C82D2C042FB4D404B6DBB9796D41640AA141F37F4044E4037C32C09411B18406089763FCF184E40AC67F333F9A4184027240ECAF30E4E402D2E7493F11D1940F85D939AA11A4E40403DA10534E51940B3C51C47BC1A4E403F21531BBFDE1940D024AE057A0E4E40A985778C9385184039471E9E99EE4D402B04ED8570A618402FA03F1577E54D4087B8F3BF365818406744961BF2DF4D4038FB9FD21F8A1640E0655B13A4D94D40D70B5A7D1247164056C264FC74E54D40A9E5C10807071740C452711611F64D4092481951C0D816403C82D2C042FB4D40
1133	Hjelmeland      	Rogaland        	0103000020A210000001000000060000009C1B7A94FCD21740679E16210A9B4D4081506CF889851940F8D36B3A71AF4D40F38C52E3E7751B40AEA993DC27AF4D40F493BAE4AE461B40AD701EFA35974D408E56A03AA9E31840B52841B7B3844D409C1B7A94FCD21740679E16210A9B4D40
940	Valle           	Aust-Agder      	0103000020A2100000010000000B00000098C982462AB51C4066D37DEAA0944D40D5D8AB354CFC1B40DF7F44DE44984D40845B3D5C36BD1C40D7DAFF709AA54D4053C6B7BB80A91D408237AB1F90A44D40EC874EDCEA281E402FB04B7E0CB34D40DC307CEBDDC81E403952B6E0D2A94D40BF9CEE89B6481F405206EAB68F8C4D40EE581D4199B31C4068751ED23C784D40A4FDB2BC9F6D1C406639557E757F4D4024547B09A8B71C40E0885E2A5F814D4098C982462AB51C4066D37DEAA0944D40
1032	Lyngdal         	Vest-Agder      	0103000020A21000000100000009000000A8002A8FE88B1B40CE38807DF4144D40655DB99218461C403B49BB47E3234D40FEDF484F57211D40BC56170C4D224D4066C4494FE0EF1C402B586E5DE3114D40177B1BC1F7211C40922D07294F044D402B34E8BB4FBD1B4070E8E1E6D4E44C40BB6EC4BB03171B4033F8057BD1E84C4085BFFC2B73011C40287D5442930B4D40A8002A8FE88B1B40CE38807DF4144D40
826	Tinn            	Telemark        	0103000020A2100000010000000D000000C1F942C36B58204044EDA25E2EF94D40E9301A1DD8691F40A6A3C087CD0E4E40FF540A2D1B72214062D4160C70174E40CD6528E56DEA214062F36F408D0C4E40079739A04FFC21401F5550EA89FD4D40AB48B1BB9B6222404E4A47275AF54D4057D28DC5866022405F0B18FB56EB4D4023C59696470F22400F06CEB1D0E14D40E5BDD15AE2D22140A29FD112FBF24D4046256133089A20401EAE4404C6E34D40F0EEE89BEDA52040C37AB3791EEA4D40C320E42668522040E9F5354E41ED4D40C1F942C36B58204044EDA25E2EF94D40
827	Hjartdal        	Telemark        	0103000020A2100000010000000800000090787B4D96FC204034D5E63A54D54D4097B10BEF4EBE2040E018315BE6E54D40EF2D3610C49D2140A43EEF1FA8EC4D400330C223F6D2214037F4DD7C27DD4D4082E6876DD3BF2140A84BE65C91D54D40E3C5B9A5810B2240074E07BB70CC4D40D2B6D2F0FD8E21405038BB8EB3C34D4090787B4D96FC204034D5E63A54D54D40
544	Øystre Slidre   	Oppland         	0103000020A21000000100000008000000856E267ADE7E2140A52886FD21A24E40BFCB8BDC8FA62140CF73B49004A54E408FA2649E64712140C01FFF5009B34E406A4A7BF0A88F214075F712F1B2B94E40C747190998EE2240ADC7B327CF9E4E4064F73B6A06C92240DB131355888D4E402F37513A365722408FFEC87E84864E40856E267ADE7E2140A52886FD21A24E40
542	Nord-Aurdal     	Oppland         	0103000020A2100000010000000B0000005EE92EC8FAC72140C71A187CC4724E4086167B78D30E224083232C5867814E40871998D98CC422400C82DBC9D28C4E40C747190998EE2240ADC7B327CF9E4E4081ED2D25696123409B7701AC5E904E40ED1830A55AC22240909CD94A86874E40D04F795B67112340D53DE234A47E4E40C1CCEA7E341E23406331A2538E6E4E40BFD1092F49CB224012DB5711186F4E401BA4A72AFC83224013E1E3753C624E405EE92EC8FAC72140C71A187CC4724E40
1517	Hareid          	Møre og Romsdal 	0103000020A21000000100000005000000C592DC5C319B1740376FE7495A2E4F409BE093EB5FD217400D4706A8C7384F4005E0259CA7AA1840848689A2EF2E4F401F1BEC5A3EDE17406608F77138234F40C592DC5C319B1740376FE7495A2E4F40
1228	Odda            	Hordaland       	0103000020A2100000010000000B00000076ADE4974D541940C593FAE853024E403F21531BBFDE1940D024AE057A0E4E404D445FA35CDB19407331DB7774194E40C04070AD83811D40BDA70A7800004E403B15673480EE1C40215050383AFB4D4033572B2F99621C40D6D1EC0632E44D40FA0C8CF68FD61A4011356EC4CED84D40327B2CE2859B1A40E0FF1DAE0FDB4D40D28B9C20C5BD1A408A65C71864EA4D40E2AFC00BFB191A40ABE218593CEB4D4076ADE4974D541940C593FAE853024E40
111	Hvaler          	Østfold         	0103000020A21000000100000007000000E8BAEB329C59254050C2C7FECB854D40F2383B2D21AD2540F5F5562DD1914D4039B079E9AD552640DB7BE4E8DA8B4D40EFF1A37701222640E106A5421B7D4D407C25920321472540B375CF1736724D405054272BAA2F2540DA25612667614D40E8BAEB329C59254050C2C7FECB854D40
2030	Sør-Varanger    	Finnmark        	0103000020A210000001000000150000005990805E9D983C40B91D51F2AA79514061F1A77CFA533D40A6E2B749DA7D51400BEC23A829583D402A9E2CA21C845140CB795947F20D3E4003A02DD5667E5140E69FD788C0323F4099458F54D08051400A75A36F4DD13E40C7A9115BDE725140FB5A1547DFF13E402D943682BB6B51401A8F195955F03E40AB0852A5E2635140AEDA91D713843E40F25547F095625140F22C595FD5153E40B74F06171E6A51400472EDE639303E40AEF3114D61645140270DFE9F231D3E40AAA103BAEF5D5140787939E4D7493D405E768B70F452514000AC1469033E3D403ABC723A3C4751409010225B9F0A3D404DF95942B1405140BE6DAA992FCE3C40E7B5B9081D475140E96519A9DED43C40EC6CF1CB5B4E514002989F0E23563D401ED73DA59C5E5140B080B38D46223D40C8E74E49806C5140348A925099543C408059BB10597651405990805E9D983C40B91D51F2AA795140
1854	Ballangen       	Nordland        	0103000020A2100000010000000A000000F672EA57A40730406DD78CA51D185140FE9FFC8A54F93040A2062BB5B61A5140DEB9DFC52E3D314069FAEE9E3E105140EA0911A4D33731406F6E8CD15F09514056A749BEDD493140A54FBF9D5C085140B58D26BF352E3140917A1DBA3A035140173C2F6E80AD30402544F8ACC1085140A02325D967823040BFCFA5FD131051408568240E88CD2F402491007E29145140F672EA57A40730406DD78CA51D185140
1826	Hattfjelldal    	Nordland        	0103000020A210000001000000110000002896F0AC5FA52B407D7DDE86D55C5040EC6EC7A6C2BE2B40A23F7C3BDE5F5040BD677D72666D2B40D80F0FFC7A61504044DCBD7AB9892B40582C1A667E63504085A1E61E48402B40DA4F912F556E5040FFC572B622552B40CDD9B97FB6705040186210AEF9262C40D72A98C526725040AC12E974E99B2C4064A2FD150D795040567FA0FC61342D40236FD9132F775040EE37EF6C7F032D404780D797D2535040663D3AD3F1C12C40C8293F00D94F5040D47D9D9DE7A62C40D2044B4E9C475040BF9634D578522B40BF6B5B4CEE4650401C92BB8AD9BE2B402735D2067A5050401A51F69F1A852B404FE21684355450402959D61F42BA2B40303A70E98B5A50402896F0AC5FA52B407D7DDE86D55C5040
1943	Kvænangen       	Troms           	0103000020A210000001000000120000009CC63E529257354084FA9868227E5140F931B7FE6D2135402B9516D9907E5140E78E6FF34D703540C0B360049D8351405FD8F9364F1C3540A1AA04F6AF865140AE392A09B201354074B2DB47338F5140197C1780EAA0354077860753208C51407651E78846D43540EC781079738651400E06FF31871E3640777E7A07E98A5140586720D0443E36405D2A4C307F7D51403D601CDBD8863640732761A7AA7951403BB99EA293733640E6CCEFDE9A72514081776FB906923640CA15517F9B6C51401F8B87B7FBE43640E109D3DD6E69514088D5062BD5B836406A503AD68A6051407ECB21120DBE3540B35A6BDE9C6251400EB04C64159935403D9EC8AFAF695140A58FD00F95C33540606A8795ED7351409CC63E529257354084FA9868227E5140
1868	Øksnes          	Nordland        	0103000020A21000000100000008000000C408F107B8602C402F4378CB1040514044D538864E0B2E402820AAE33854514067A1C4CABAB42E403B517CFBA949514061D2E6AA80C42E40D396F34AD93851407E75A0E957B92D4037919093602E514069CDA796DA692D4050E49FE762315140179CB5EB845C2D4085E2E9C32C375140C408F107B8602C402F4378CB10405140
104	Moss            	Østfold         	0103000020A210000001000000060000008B52A5EA0B16254047307CB089BA4D40423C72D19D3B25408CD600256DC44D40225D4D7D5792254008153A8A3ABE4D402AE7718B427F2540AE0191AF2BB44D4025245643172B2540992B58EA4FB24D408B52A5EA0B16254047307CB089BA4D40
231	Skedsmo         	Akershus        	0103000020A210000001000000050000000F70BE71C2FB25403EFB75F99DFE4D40B034594F2FF2254049CA74AD88054E40FDEE2F435C5B264023F7869B7EFE4D4016B91099E4E12540D99F973E30FA4D400F70BE71C2FB25403EFB75F99DFE4D40
1534	Haram           	Møre og Romsdal 	0103000020A2100000010000000A00000090D313EC2E6C184058FF9FC8AA4E4F402E2722DBA390164048089B24EF674F40E0D06B58218D174025ED97A0AA764F4038C5332280101A408D39C19693594F40FC8DE231BBC91940D7CB923853534F40353894A3C3FB19402933B7D746504F40359E458ED0B41A40A19C446AF9524F40B056C1DF915C1B400A137AC8C6474F401701E4C299C31840D60505AA2E414F4090D313EC2E6C184058FF9FC8AA4E4F40
1027	Audnedal        	Vest-Agder      	0103000020A210000001000000060000002EB7505A554F1D405852A1B567314D40876E81CBFF831D4093ED8C72D5414D40B1EAB81B4B141E4022FE2F87E9414D4057D752E4BC991D409A8F3AC3351D4D4038834F72DA051D404CCDC17B7E1E4D402EB7505A554F1D405852A1B567314D40
1231	Ullensvang      	Hordaland       	0103000020A2100000010000000F000000C99AD5585D1E1A40EDA01B267E2C4E406237A41D628819402820F62C00324E404D6DFD210A691B403D6328F5A33D4E406EB7D2C967261C405C6F49B667344E40A9B96FF1F9ED1B40C7956A3A962C4E40298F1ADDA1F91C405345BDBA53224E40DC974A546BA91C402D26594933214E408BAA293C61E41C403770ED181F114E409729AAE6FAF31D40A9CF5FB6A90C4E40309F9334E7BE1D400A69EE0C76024E40C8CE2584A6EB1C40F80A32F72D004E404CA80D36F5F11A4052A3D77314174E409D84025D093F1A409E703265D7144E403471441F4EAA19401C5D3157EB254E40C99AD5585D1E1A40EDA01B267E2C4E40
543	Vestre Slidre   	Oppland         	0103000020A210000001000000070000000728F6AB48612140932E5E0F46884E40711F55B03FC72140F5228254D59A4E408B4730697E5B224093D8A1E226844E402FF90AFF04A1214045947C6346734E4082A7FEEEDF4E2140DDFA3C18CD774E40FC1225A8F67921404940ED8895804E400728F6AB48612140932E5E0F46884E40
1130	Strand          	Rogaland        	0103000020A2100000010000000600000005C32F7E082A1740651846F1E1854D402D22ECF9DD91184092B865DC43924D4043EA623903731840164B3866EB8A4D408E56A03AA9E31840B52841B7B3844D403127F9EE02E317406DB762B1887A4D4005C32F7E082A1740651846F1E1854D40
2023	Gamvik          	Finnmark        	0103000020A2100000010000000A0000002AB6E7B684A53B4023DC8806AEC1514097EC518438C63B404B03F2F618D551400678629F9A773C40F33BC37BDFD15140187A06C028293D406BBCEB66B9C751403795F6C2273D3C40211DDE097FAA51401877AEDD896D3B404D6EAF1991995140FF927537FC593B40EB523C729EA3514097BD3BC542653B40E56BF6A63FA851401AA958F20ABA3B40650D6F3D97B251402AB6E7B684A53B4023DC8806AEC15140
1941	Skjervøy        	Troms           	0103000020A21000000100000007000000203E59E14C7234400E9627D192915140BB045B76639F3440528CA5D319A551405FD8F9364F1C3540A1AA04F6AF865140E78E6FF34D703540C0B360049D8351401A37B9E927A13440EEEC447F4D745140C721520BFF383440E113EBD7B1835140203E59E14C7234400E9627D192915140
1867	Bø              	Nordland        	0103000020A21000000100000008000000C408F107B8602C402F4378CB10405140179CB5EB845C2D4085E2E9C32C37514069CDA796DA692D4050E49FE7623151407E75A0E957B92D4037919093602E514065DD89DC06642D40BB3E39B0F1265140B6B35542AC452C404E0113F7B31E51401098C1A7CDFB2A40EBF1545BBD265140C408F107B8602C402F4378CB10405140
1860	Vestvågøy       	Nordland        	0103000020A2100000010000000B0000003CE8B05617A52A4084347D31E20E5140B5C343FEE3012A40973E4FD629195140AAA6B001A9C62A4097AF857C9F22514032D545E4A5B52B40CA00DC5A1C1C5140FFF0A52F12612C4039BA3FA4A90F5140BCBA1A1D770C2C40CAEE67C504065140EEDFF3A652402C409C8481F96BFC50403C37ADC4D3632B404796D3F433F250400C7039DB73E42A4080D77B0AF6FD5040985360B020EF2A40697807709F0A51403CE8B05617A52A4084347D31E20E5140
605	Ringerike       	Buskerud        	0103000020A2100000010000000F0000001498A444E4AA2340DF0E61B9AF184E40DAD75E57B5682340F58DE8D7B4264E40583C872D77AB234057F3C447382F4E400F2196F0D67B2340D3533F70A12D4E40A2E8DEFE84B12340DA259D87DB374E4042308758F79E2340128262E22D474E4006E9E7C116122440298EA92DE7504E40ED0DA46AB99E24401CF120DF631F4E40DF3C71902E3125402245B5F1A6124E40D06895D5D13125407220EC4FE4094E40319E8ADB73FA24409A404D9235024E40A516C30A379A24402695732F33104E409288F81C2304244049F2B16C2B054E400D00B0DCC2EC23404F4D40B876144E401498A444E4AA2340DF0E61B9AF184E40
220	Asker           	Akershus        	0103000020A21000000100000005000000FDCD4E2B39B424400704D400F6E94D40905CE4DDCCB92440846C56CAF5F34D40D99435927B222540113F47E9D2EC4D401EBF898F86D92440E8C15A83BEE24D40FDCD4E2B39B424400704D400F6E94D40
626	Lier            	Buskerud        	0103000020A21000000100000005000000359AF387622A2440AB9DD443CDEB4D40AF272247773424403322741C75F84D409C4F6C5F72C0244051B4EA3613F64D40FA7B173F64A02440A4CEDADA74DC4D40359AF387622A2440AB9DD443CDEB4D40
625	Nedre Eiker     	Buskerud        	0103000020A21000000100000005000000E3B594E780EB234066417E2E9EE24D40EEBD3ED8BD1F2440AB3325D467EE4D40FF1637E02442244096A683E7D5DF4D408E7934D80FFF234002016329F8D44D40E3B594E780EB234066417E2E9EE24D40
602	Drammen         	Buskerud        	0103000020A210000001000000060000003AAD3E26D72A244023CF39459FDB4D40BD2910CAC43624405864EA9173E84D403074EB4045A52440F9499F5C40D84D40E72B6C6B852D244023EC49B03FD24D400C040251CA022440E0CC6BB204D54D403AAD3E26D72A244023CF39459FDB4D40
215	Frogn           	Akershus        	0103000020A210000001000000070000001D8B5319611825407DBEA2AFD1D94D4035D5D2348E152540253F765312E34D406BCCC3D4CE3D25404A4487696EDC4D401B63FD8520722540130EDBCFBCE34D406BDADE1198802540A86399928ADA4D40CC09C4BD4E512540A4A0D0A26BCE4D401D8B5319611825407DBEA2AFD1D94D40
5004	Steinkjer       	Trøndelag       	0103000020A2100000010000000B000000B024EB7E588726407C23948F05005040F4E55D8FA07526401E1BA3CB9604504005C3B5ED00AF2640F3A1A676AC06504062DF79638D542640102A7767AE0850402EF5B45124DE27400F48947923155040F3F3AA8579162840AAEFA2EBAA075040D7F9E31D83C1284011883C737CFA4F40FFA388508A0C27403E16541F33EE4F40BC4A930B15AF26402517A95726F14F407A67EA2552CF26400F9B6848F3FF4F40B024EB7E588726407C23948F05005040
1557	Gjemnes         	Møre og Romsdal 	0103000020A21000000100000006000000BC5F86E49D001E4047C4AD76A16E4F4081312E2295581F40A8ECD814FF814F4015904DD996422040ED9B70F8FB764F4030969EB5174720406AF0B6EDF86C4F40F262BB821A8A1D40E3776BE09A6B4F40BC5F86E49D001E4047C4AD76A16E4F40
1543	Nesset          	Møre og Romsdal 	0103000020A2100000010000000D000000084171C957951F40552F8C559D4F4F4028C38DBE47A81E4063AE20845E5E4F40E706B67F954F1F40862021F4536A4F4030969EB5174720406AF0B6EDF86C4F40E6653F241FA62040E768EE41D7644F4055F61A518A692040185CB2557B5E4F404817211D0A95204074C584FD93564F40B4203955806F2040D802CCB9E1494F40D5CBB96D9A7621404B8DC2583D304F400DA9A97365692040047AC797762A4F403737403B270D2040A939D29ED5394F40C8A9F54E202920409B096A4B954A4F40084171C957951F40552F8C559D4F4F40
1449	Stryn           	Sogn og Fjordane	0103000020A21000000100000009000000595D6D01542C1940E5136AA19CE74E401558F0B9930B194072BDBF3756F34E4052222ED0AEEF1C406051C6235D044F402598FB72CD8C1D4001763E7BCDFF4E409C4A43232BA81D401410AA271DF24E40AFD51F69CF6A1B4041D2C49103CE4E40BDD5D499EFF11A402D59597B59D54E40AD96A38DF5F41A40251DFE32EEE54E40595D6D01542C1940E5136AA19CE74E40
627	Røyken          	Buskerud        	0103000020A21000000100000005000000BBCE1FDD5DA12440A60C7B82A4DC4D401349159DA6A92440C9F6913806E64D40117522BE1D17254073EE3427E8E44D400BB05A5DA21C2540B959812C73D74D40BBCE1FDD5DA12440A60C7B82A4DC4D40
1859	Flakstad        	Nordland        	0103000020A210000001000000060000007E1FF24DB1F028402A8748C7C1095140B5C343FEE3012A40973E4FD629195140985360B020EF2A40697807709F0A51400BA601849AD82A400312C753FA0151404AFBFD8ACF282B40038B401045F650407E1FF24DB1F028402A8748C7C1095140
5052	Leka            	Trøndelag       	0103000020A210000001000000060000005598FF2A104D26403B934C710748504093201B545DBB2440D1023823F9505040CB9B6A85F72725402AC5E258175E50405311C74BA0EB2740BB48DD047A475040CD3AF076F3C12640465797A1C13F50405598FF2A104D26403B934C7107485040
1515	Herøy           	Møre og Romsdal 	0103000020A210000001000000070000007BD25ABECA821440DAF12DEC302E4F40896919AEB28C1340C0B84A4D74374F40040A7687745D15404595A9DA3D554F40AA7C40C4B5BC1640C1B08122C1414F401134AD3DDE6D1740478CFBB9C11E4F409A94AFA8EBE7164080FC1989A41A4F407BD25ABECA821440DAF12DEC302E4F40
1514	Sande           	Møre og Romsdal 	0103000020A21000000100000006000000E4238F2E88E614407EB4CBE3D1204F40EA4228503344134098518050F2304F40896919AEB28C1340C0B84A4D74374F4004CCFDDA622C1740646E6553591A4F40596A4F87FE6E15402826631ECF134F40E4238F2E88E614407EB4CBE3D1204F40
1401	Flora           	Sogn og Fjordane	0103000020A2100000010000000900000063833303EEE71040FD2DA58948E44E406107D45A3DDF1440AB7012C5C1D44E40251FA9C514441640355F2D97AEE14E4068B1C17F3BCB1640ACF95B9423D94E40FF722CCE7A951640C6DB779806CF4E40986C00D10AEF1640D804AFEF52C84E409921AED14E141440D5F3D00069BA4E407782E3F803851040C8300E7CD3BE4E4063833303EEE71040FD2DA58948E44E40
1428	Askvoll         	Sogn og Fjordane	0103000020A210000001000000060000007782E3F803851040C8300E7CD3BE4E4045AC919A58081540C1315D73A8BE4E4030E9569EAB36164017AB3A72EAB74E4079A75DC5FD4813406340AED24EA04E4073FBA5F5706910400E8C2E086F9D4E407782E3F803851040C8300E7CD3BE4E40
2020	Porsanger       	Finnmark        	0103000020A210000001000000120000001DCFDFBF96783840541CC30284945140E086C6495F5039406AAB69F252B0514051896FC27BA33940754E8E7FADAB5140B43D79EE03F13940C602349834AF51403745115DB1F039408D470B8EAFAA51406D00581C6C1C3A40244538D500AA5140F4E7167901263A40D5BA82CBCFA2514053A1D667B7013A409BF9AFD601995140B9837C40EA0F3A40E58760EED58D5140D19B2E3C4EEA3940226EC9F7D28551403D0C18AD9FF43940568DE240B37E51401D5232E0147F3940488BF62EEA6F5140F2736DFFDD373840D5C2607F9E735140C051060A831D3840817395E33F7F51403175C13E4FE937408275037149805140AB0340D106F6374035A6346C2D86514058F4A32F572D3840F498BB75348751401DCFDFBF96783840541CC30284945140
710	Sandefjord      	Vestfold        	0103000020A21000000100000005000000288AC1A24E3C24406A1825F7E28C4D40744D407CEF4224400E9641DA4F8E4D4058E8A22C244A2440ADF28EDAF18C4D400D3B46A2C8472440B48227B37D8C4D40288AC1A24E3C24406A1825F7E28C4D40
1246	Fjell           	Hordaland       	0103000020A210000001000000050000004FCE278AC4AB11409EE8AC7DCF344E4074ED6936FBFC1340BF3B6967E33C4E40A93609050AD01440798548A023294E40BE9F435050071240E7F99707841D4E404FCE278AC4AB11409EE8AC7DCF344E40
1245	Sund            	Hordaland       	0103000020A21000000100000005000000BE9F435050071240E7F99707841D4E40B7E51B7404921440AE13F60AA4274E40889BE03BBCF314404BE9E900721D4E40C0F0FA972E301240BB94507C510D4E40BE9F435050071240E7F99707841D4E40
5043	Røyrvik         	Trøndelag       	0103000020A2100000010000000B00000064432774B5882A40289BE7CFF93650409BC9A9E000DB2A4028E0C26EC2425040919B74DA01422B407DFF3184BD465040D47D9D9DE7A62C40D2044B4E9C47504026C70DF5CEDC2B405A8D95AF9D3450405561324FDBC02A4039CD76297E2E50404DF86413932E2A401585A0CD312050402D9FA914293E2A402625F1723229504042E6E4A834142A40DF0F238123305040C7BCBB67D35C2A40AB6E0AE60430504064432774B5882A40289BE7CFF9365040
5034	Meråker         	Trøndelag       	0103000020A210000001000000090000002DCE33B99C0C2740733FD0CBA7B94F4018C3CCB642A02740CDFA60330BD14F40B44588BEAE4C2840DE53C96306CC4F4094ED6363FE6C2840E990997442BD4F4043A45A6FFCF227404DF814F975A24F4019A8A3C7E71A28403507F0F577974F40AF65CB74F6422740745B28C320974F40A5B7E14EBCE8264042A59F06C2A94F402DCE33B99C0C2740733FD0CBA7B94F40
1571	Halsa           	Møre og Romsdal 	0103000020A21000000100000005000000171FA023234D204046A7D38E358C4F407DFD8A7490342040AA3778658F904F4095B28AEFB9A421407158FA1437934F408659EB0BC77C20404FBC52F98B814F40171FA023234D204046A7D38E358C4F40
5061	Rindal          	Trøndelag       	0103000020A2100000010000000D000000688038FF71412240D4000DCBA0824F4070734AC504EB2140FA1A6DA5E98B4F40E716C6C6E5B822408FDD70631F9B4F40E340BFB7F0EF2240BD76E2A6EF964F40E6FB1A6511DD224066DFEA153F864F4029F1C2A3C72A2340867A259230814F4040312D1721DC2240F5A24C57217A4F405EDCEFE910ED2240A7CF009B986C4F404F93E730CBBA2240DCEB7449A5654F406F765F449F9D22404DFA5795DF734F4089A3A12CA83E2240A2B99E3BB1774F405BFE49E8F45A2240B4E4FEE61A7F4F40688038FF71412240D4000DCBA0824F40
5035	Stjørdal        	Trøndelag       	0103000020A2100000030000000A000000C1699C141F6E2540B888A55FFCBB4F4080FFD1BFCF4E25402F34A729CABE4F405BFF6130309725406BA4B9EF58C74F40489A21CED27427402AAE9C1FF5CB4F40A5B7E14EBCE8264042A59F06C2A94F40CA2CED44D76026400408B0CB87AC4F403C902147DFED2540E6B2647F2AAA4F40768F060D8EB525406D6CFA650EAC4F40BB777A082AAD2540E9CDF8712EBA4F40C1699C141F6E2540B888A55FFCBB4F4005000000CAF4F0C4EEB62540F88C3C2726AC4F400943926B0DBB25400442361D00AC4F4050D76063A7BD2540446DC55F2EAC4F408FF97DA9A1B72540B7EDD8F0D5AC4F40CAF4F0C4EEB62540F88C3C2726AC4F400500000034966017D0BA2540079FB60698AC4F40F5FA987EC6C12540BD209338E0AB4F40EBFD14987EC525402AD0E29C9EAC4F408DD1645A63BD254014D06866FDAC4F4034966017D0BA2540079FB60698AC4F40
5020	Osen            	Trøndelag       	0103000020A210000001000000080000002DD7DAB07A662340FD0F2CC55619504062AD03E385A622402983FDDD0623504077CAB1C04D662340E7A349E99E2E50407BE63460CADA254011487DB3EF115040D367EDB67DC425407F3C46C9440D5040146C0679002C25409B67D2067A0A5040B103CFDE7AB92440D1C649F91C1350402DD7DAB07A662340FD0F2CC556195040
1001	Kristiansand    	Vest-Agder      	0103000020A210000001000000070000004704A5E2FB8F1F40382262ED52124D409638094602701F40A53C78B0A11E4D4029C6F591285820403C064AEA37234D40084FD095124A20404469B08BB6154D40BBFA95E04CBE204052FCDBEC67F54C40F8D927A2A42C20400C90F0A590EC4C404704A5E2FB8F1F40382262ED52124D40
914	Tvedestrand     	Aust-Agder      	0103000020A2100000010000000700000047936D898F77214064C33F9BD64C4D405FC7DF3A59B621404C7348C473584D406F19D438B02522406FB7CBB9D0594D4008C920B134102340F9FE1D7E06434D40FCA716AD69BA2240B66AD72F7C364D408F108481C7F62140D41E54AA3D4B4D4047936D898F77214064C33F9BD64C4D40
2022	Lebesby         	Finnmark        	0103000020A21000000100000013000000C2F4A2D51F413A409D00CCFBACAD51406C17A1F26C953A40C3D3AE0D84B75140D655B2DC890F3B4067F5759E83D6514097EC518438C63B404B03F2F618D5514055C7742D5C9F3B4006563122C2C251401AA958F20ABA3B40650D6F3D97B2514097BD3BC542653B40E56BF6A63FA85140FF927537FC593B40EB523C729EA351401877AEDD896D3B404D6EAF1991995140FFB32E45215E3B405F6EFEE9B59251401ED7DDF07B023B40D756662EB58D514057259F11F1023B4083936C07028A51403D0C18AD9FF43940568DE240B37E5140D19B2E3C4EEA3940226EC9F7D2855140B9837C40EA0F3A40E58760EED58D5140667298CAFDFD39405980AD2677935140F4E7167901263A40D5BA82CBCFA251406D00581C6C1C3A40244538D500AA5140C2F4A2D51F413A409D00CCFBACAD5140
1836	Rødøy           	Nordland        	0103000020A2100000010000000F00000036381605BD8D284081CBC48275AE50405A3E832EB9B72740D505DD0B2FB45040AD4DCF95C6552740A503E888FFC050406DA3C18932B02840DCA565DBFAC75040A149018917C42940C07273629EB95040E94A4AF108BD294042568D9FA0B3504025CD1A2044142A40E0DB0EAFB6AF50406A30BB7F917A2A40FC4C1A89BFB150408353117CABBE2B401D10B5EF02A8504062FFA6176F8C2B4058DEE272C1A250400CDF003560A02B40DE6C4EFBF39D50404FBEA449517E2A409C8E0FDC6A9950404923F53B2D4A2A403A16A0CA79A15040E6AEE3502B9629400A31B3CCADA1504036381605BD8D284081CBC48275AE5040
1119	Hå              	Rogaland        	0103000020A21000000100000006000000AB1C196528A71440C9FEE703D34F4D400096847D9E69164043395104485A4D40FEA883FB969317409E62BC4D08504D40E0E641D222BD17405733AC628A444D407D1B6CD7021416404FFB65A18F2A4D40AB1C196528A71440C9FEE703D34F4D40
1029	Lindesnes       	Vest-Agder      	0103000020A2100000010000000900000066C4494FE0EF1C402B586E5DE3114D401058BECE88F21C40AAB4D917F11B4D40D9C75D0EE3561D40FAC75F481F204D40795AE180CCE51D400425873533134D4070A0E1FC890E1D4036977C89CBFF4C40DE4E7D19FF071D408EBF0DC97EE14C402B34E8BB4FBD1B4070E8E1E6D4E44C40177B1BC1F7211C40922D07294F044D4066C4494FE0EF1C402B586E5DE3114D40
926	Lillesand       	Aust-Agder      	0103000020A21000000100000006000000D8C58630544F20407EE4DED29C174D409CD1AC6276902040B122AF9B3B294D40B2BE91C9A0C62040E294DA99D7294D40BC6A5022F5812140783D004F6A0A4D40BBFA95E04CBE204052FCDBEC67F54C40D8C58630544F20407EE4DED29C174D40
228	Rælingen        	Akershus        	0103000020A21000000100000005000000BCA4DBAAF10926409360E8F15DF14D404DF164A8F70C26407FD8BB6737FA4D4031DBFEE2E65826402A915A1793ED4D40226382E5981326406C1ECE4C84EA4D40BCA4DBAAF10926409360E8F15DF14D40
617	Gol             	Buskerud        	0103000020A21000000100000005000000E1CFF4332A71214037CBB4BA11614E406784424F87B22140DE5117E0856F4E40BF1D0F560AAA22403B6046806D5D4E40539F27D9CBAF2140DA02B376CB504E40E1CFF4332A71214037CBB4BA11614E40
1263	Lindås          	Hordaland       	0103000020A21000000100000008000000023C07BB3D7F14405148F53039534E40A7E2FBAABECE134071FA9020816B4E4040E43C08D0A11540C46FDFD4FE594E407D17941926D81640532876269F6C4E40EF3C8331B46216406E7365B4B1524E40026AB1E4718A15406EF6117488474E40622DC18C8B261540FAEAAD2836444E40023C07BB3D7F14405148F53039534E40
436	Tolga           	Hedmark         	0103000020A2100000010000000A000000575372D7417D25404A37C673E4314F4096E80D8698F22440063C046F03404F40CE11F92E6F712540269AF4B8D04C4F400DA285B92640264078A15D32AE354F402704807B81A22640204C37A6CA344F40524CFDC5EAB026408FAC8CED692A4F406EE268EC4164274080D51667D0164F40982F97854910264035493D11231B4F4028ABBF0498F22540DCF278970D2C4F40575372D7417D25404A37C673E4314F40
604	Kongsberg       	Buskerud        	0103000020A210000001000000090000003635AC25BFD322406652F8E43AD34D40FB6D212FA5AA2240DAD88BE3ACD84D401031145D4ABC224072B016E902E44D40888A4E0D7B4A234021EBCF5EA3DD4D409D47D012B41E24403307B6378CBC4D40D0A7E535FB512340BA14511D35B44D40DF2C3E7788F12240E13E3B19B9BD4D40E17D859FD0072340556AB5F1E0C44D403635AC25BFD322406652F8E43AD34D40
631	Flesberg        	Buskerud        	0103000020A21000000100000006000000C08C9C168B602240074650B7C2EB4D40307D4452C30323405A20618D9CFE4D404BF7D80A87662340F9DA0C8517F44D40ECF34042A8712340E85C376909DF4D40F2821D78D2F722405C7C724B5BDD4D40C08C9C168B602240074650B7C2EB4D40
429	Åmot            	Hedmark         	0103000020A210000001000000080000001D9C00C77BB026409398EF5A07A44E4056407D3DFE922640987A4FE52AB54E40E54E2F6B9F8A27403BF13EC3EBC04E40EEAD392709D5274083BAE0D16DA24E4096BD20710F9926404B49D59DEF814E400F2A61925DEA254020E11400CAA04E406359120B329826402DE213A8AC994E401D9C00C77BB026409398EF5A07A44E40
520	Ringebu         	Oppland         	0103000020A210000001000000090000001065258D940E24409F549AC063CC4E40FBF7ADE1A6E92340FD2711F4FCD54E40FAAFCE6DF31A2440BADD85E639E04E40117474AD2ECF2440014CE09085D54E40DE2F9A42C6272540A5A999473ADF4E40DA25FB93FB68254088E965A12DC04E405D1A550C440E254003BC61E683B44E409BE851BF0CE623401DE3DF2012B14E401065258D940E24409F549AC063CC4E40
430	Stor-Elvdal     	Hedmark         	0103000020A2100000010000000D000000BE979464414D254093D060C90DD04E40DE2F9A42C6272540A5A999473ADF4E40117474AD2ECF2440014CE09085D54E40FAAFCE6DF31A2440BADD85E639E04E40322606956354244065EF95ECE2F04E40F1D47B7E762B2440809C0E4ACCF34E408CE666E99FE524400F161A5A61FB4E405FBDCC73FDA22540765260D796DE4E40AB5AF8B849F52540782B45B882E14E4069ACC51F80A32640A15D099361AF4E40DD5A0DB2E9AE264085BF51788E9B4E40F3E5134AB7B22540B26553CA0CA24E40BE979464414D254093D060C90DD04E40
230	Lørenskog       	Akershus        	0103000020A21000000100000005000000DBCFA17EA6D22540C0DF97F4CAF24D403CC7E9EA0D0C26402829C50FD8F74D40DA2F76566D0C26403A1E80946FEB4D408AE9C527C6DC2540357EE7A81DEB4D40DBCFA17EA6D22540C0DF97F4CAF24D40
1866	Hadsel          	Nordland        	0103000020A2100000010000000700000065DD89DC06642D40BB3E39B0F126514081F475588B042E401DA81AB1072C514040C735575AD12E40B291BD5958235140BE1C7BD0BDE22E4070AF8E4F341D514098855A17EAE62D403CBA85C06B145140B6B35542AC452C404E0113F7B31E514065DD89DC06642D40BB3E39B0F1265140
1535	Vestnes         	Møre og Romsdal 	0103000020A21000000100000006000000CC3FED4BC1531B405A41458037484F40359E458ED0B41A40A19C446AF9524F404E8178D2978E1C40083E447CBA564F40274541D861311D40EFCC3C461B454F40C5BDD8F71D691C40A22B9AA333394F40CC3FED4BC1531B405A41458037484F40
819	Nome            	Telemark        	0103000020A21000000100000007000000810CA37632A821402D96E373EAA24D40FACC7DED74C32140F26D924C00AD4D4030131832B13B2240882087CD50B14D40257BDE5AD0E22240D89E8E28E29D4D40C7386A18205622408990447138924D40857168413349224099895A28099C4D40810CA37632A821402D96E373EAA24D40
919	Froland         	Aust-Agder      	0103000020A2100000010000000C00000006F2692C92DA2040D1F7997981474D4046345B4B718420407F3D349611444D400676E03BBE5A204016AB378590514D40E5956E58D6D21F40E9C0D5461F574D403EC1D296B267204061E029E95E5C4D4038EA7A950CDB2040BB734C91F44F4D40EBCB2E79C0002140ADCB7AA0A0564D4046E6BF012C84214035DDF01D00504D407DAAC8456E7C2140E0909627C1434D406C31CB16E6382140FEEE6786F4394D401875A071E6C62040D3066170C23D4D4006F2692C92DA2040D1F7997981474D40
929	Åmli            	Aust-Agder      	0103000020A2100000010000000B000000A53C6CF14DEF1F400127658E98644D402D1870D4D404204040CBCD407B7B4D40CFBF9988F2F320401070BB1C86714D4039D330E3A12621405CDA226439774D40A17CAABFC87C2140391A8A416B6A4D40F103B743593E2140EE3C8179085F4D40D38FB601F9842140C0CADDFEB9534D4038EA7A950CDB2040BB734C91F44F4D402B0EF86328B820400B5E855921594D4044F055B008F21F40D2DB9FF2885A4D40A53C6CF14DEF1F400127658E98644D40
136	Rygge           	Østfold         	0103000020A21000000100000006000000CDF2497EB7302540FBB097BB8CAF4D4078B8985C4B7C2540759FFBC33DB84D400083919F3BA425402169FC43B7B24D405F48FBB8476225406CE9BBD59DA54D40F595BBAD7C2E2540641F424B0BA64D40CDF2497EB7302540FBB097BB8CAF4D40
239	Hurdal          	Akershus        	0103000020A21000000100000008000000FCB487AE1CAB2540B03E3F6202364E404A03F5740D5825404C351EA188374E405D425BC9366D254048F28FD517434E405B653DBB5AD825408EEDEF053C3C4E40C93375B1E9242640834E159557424E40537BE641544726406FC950E1D3324E40B0BD19244AE82540EF4C5C2E4C2B4E40FCB487AE1CAB2540B03E3F6202364E40
833	Tokke           	Telemark        	0103000020A2100000010000000C0000005DAEF20F79511E40DB22096D0FB74D403460BBEDA5801E406B46B5B81BBB4D401AFB3D18CB341E4050330A8416CB4D400028BB48645E1F40BF53245A5DCC4D4056B71D3767DD1F40962BA6485EBE4D406231F3D8A00020400630E69718C84D4013ADC2750FAE20408C48452318C64D405FC38AA8398920404FC3CEF19EBC4D4070C0DC2629A720403F1A65EEFBB34D4027AC5F598B3D204039397D1967AB4D404168213715751E409F444FE908AA4D405DAEF20F79511E40DB22096D0FB74D40
1929	Berg            	Troms           	0103000020A21000000100000008000000EF5B53042ACE3040E1B51C6D1E5F5140FC69AB9505923040EADB5D20906951405E7A0F33360E3140107B14C9AE6F514063F8C260D7C531400BB43E8B725E5140C384FF2CBDA031407967744FAA5B514051189982308E3140B88F67C4D8535140FB37751550683140368AE7601E535140EF5B53042ACE3040E1B51C6D1E5F5140
5051	Nærøy           	Trøndelag       	0103000020A2100000010000000A00000077D3B6D833C326407ACF146F6A3B5040CD3AF076F3C12640465797A1C13F50409009A5424EEB2740DADE4F30FA44504003387C71BB8D2840C237EC246D3D50401367C91F6A292940D9DE98D82B3F5040D6786DE571A828409D2F83F99F3B5040408CF8EC817B2840C529BFA1ED3350401BCC07DC465D2740E7EA2282262E5040364561E0CDEA2540FD9DE12F6B2E504077D3B6D833C326407ACF146F6A3B5040
438	Alvdal          	Hedmark         	0103000020A210000001000000080000004F71E575014F244099178A044A034F4037AA9D9F78C82440126BDFF929194F40DC03A61EECAF2440E1FE250CD1234F405E75DDFEC46F25404A4D5F87021C4F400CB931E691DD254060FF13DE0FFB4E4023A7B992618A24400F3E0A29F9F44E40FBD35128803E2440A5129D585DFC4E404F71E575014F244099178A044A034F40
437	Tynset          	Hedmark         	0103000020A2100000010000000D000000C072099DD9472440164325745E334F40B912A147EF02244017253DE370474F40ED68127DCC4924408331656600584F4042E5DC9C9C58254010B4F82468564F4014FFE01FE181254045B0E2B1EE4E4F4096E80D8698F22440063C046F03404F4028ABBF0498F22540DCF278970D2C4F40982F97854910264035493D11231B4F405E51F2F85E6F26404F87DDD1A3194F40CD2184BA41C42540179D8EE4F0024F405E75DDFEC46F25404A4D5F87021C4F409BCC56D865D92440EF4B2B1F20204F40C072099DD9472440164325745E334F40
806	Skien           	Telemark        	0103000020A2100000020000000B00000082F1B72A4FB922402EFF2F0171A44D40A3C6EC3964852240FCDEE56CE3AA4D40E69D2DEFA31A234061631C5A5EBE4D406769791BEB4923409D09BF5E9AB04D40714ACEC6E02C234049D7C134E7A74D40DD7B98F0708E2340110D12FADB984D409CAF7EFA7CD422405F72C7F6CA854D409C3382258E742240174789BC81924D404DA926B38C89224036EF59C9009C4D40257BDE5AD0E22240D89E8E28E29D4D4082F1B72A4FB922402EFF2F0171A44D400500000022E4945A67942240847FF02852934D40B2D2419D918A2240DB64FCC0EF954D40DF067CF7647F2240B6B9D2239C934D40C4FFAFBD6D942240AD478D614D934D4022E4945A67942240847FF02852934D40
1825	Grane           	Nordland        	0103000020A21000000100000012000000C52F95F9385A2A402012BBB6265F5040B190C9760D9A2A403D88EF8F796250402DCD1FEB33662A40E9808DEB516C5040B274C235FCAE2A40501CA7F0836A5040BFD7DBE9B8102B406BB9C7B94972504066060FF8527B2B403339D66348665040BD677D72666D2B40D80F0FFC7A615040EC6EC7A6C2BE2B40A23F7C3BDE5F50401A51F69F1A852B404FE21684355450401C92BB8AD9BE2B402735D2067A505040BF9634D578522B40BF6B5B4CEE465040991924F9B82B2A402214B0B609475040EA3273DE3C502A40D6996AA085495040EE711B95AF1D2A4023929DCDA54F5040297F36F085552A4092C3D02CA5515040307E735CE4132A40D8CEAD909459504094C4320DBDDD2940076FFDA370595040C52F95F9385A2A402012BBB6265F5040
517	Sel             	Oppland         	0103000020A21000000100000009000000A3EDAB4B3F3C224089AD3ECEFADA4E40AD13A099586722406A06D01C96E54E401B9C5F949EDC2240AA4BFAE962E84E409ECA3810B7A122407A70A0E7CEF14E40714E2871A1272340C0C6141A8CFA4E4058017A12F0072440F394908035F14E409B70E118266C224000A76757BAC74E40A4E4592EE13A22400FAA4138C3CB4E40A3EDAB4B3F3C224089AD3ECEFADA4E40
227	Fet             	Akershus        	0103000020A2100000010000000800000071107F71D74026404FE5FA0E1BF44D40DB020824442626408F0DCDFF80FB4D4089A5F1A66F7D26404455268A8BF94D402B7E19F7ECB526406A027169FEEE4D40132E4EF9538C2640F760B2F7B6E84D4004692F33A1B52640BB460D6799E14D40BE03FF5B7E79264010407704E4E04D4071107F71D74026404FE5FA0E1BF44D40
1520	Ørsta           	Møre og Romsdal 	0103000020A210000001000000070000007E3D1D63C0F117405CF9605D4B1B4F40E89A058D6CB01740F843CA26671E4F404BB213351F741940381FC64C7A324F40E4E80C24F2221B4034EF19219C174F40A2D6756931D01A409DD3C538C60A4F40492F2402FAE6194081E7415CDB044F407E3D1D63C0F117405CF9605D4B1B4F40
1519	Volda           	Møre og Romsdal 	0103000020A21000000100000008000000374B1256C9FD164066D15A59AD024F4048D6CB60D8701740FC08C3C1C6064F407F71A37F523B1740892D925B00114F40E89A058D6CB01740F843CA26671E4F40A6833308F5AD1940162D986CDB0D4F40A3448E1886001A40CB9A2C5C82024F407A26A1F03B251840BAC6245271FA4E40374B1256C9FD164066D15A59AD024F40
1502	Molde           	Møre og Romsdal 	0103000020A21000000100000006000000FA833DFF3DD01B4093695906E05D4F40C8EA3BFDA3FE1E4074CC0D75666F4F40F2C8E05691451F405A4AC204A7694F4069CD65536FB81E403C146F7F2F5B4F4093A0C40946681D405D73B19ABC504F40FA833DFF3DD01B4093695906E05D4F40
1919	Gratangen       	Troms           	0103000020A2100000010000000700000012900B46F1433140A2A5BAFF302B5140629A279B712931400274363B2A2F51409866528F4F6F3140D3B05BFF3B355140F3A82961B7993140337993B86A2D5140FD2E6726C8D731403BE008C74F2C5140AB2C7204E6BE31406CDC0C243D26514012900B46F1433140A2A5BAFF302B5140
1913	Skånland        	Troms           	0103000020A2100000010000000600000095FD4359CEA03040FFE98BF0562A5140629A279B712931400274363B2A2F514045A223D12E8C3140D7A1146335265140A061B75BEA933040409396D81F205140522C924425893040A98D5BB86126514095FD4359CEA03040FFE98BF0562A5140
214	Ås              	Akershus        	0103000020A21000000100000006000000C75091C06A7C25408D85F4E022D84D400A61793BB0712540CB0E137BDCE14D40D42D6A1ACB9C25403586C5C085E14D407D9111EF92C82540B8973B3DD9CD4D4039AE28717F592540AD21A48607D44D40C75091C06A7C25408D85F4E022D84D40
\.


--
-- PostgreSQL database dump complete
--

