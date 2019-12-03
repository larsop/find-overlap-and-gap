
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


--SELECT find_overlap_gap_init('org_ar5.ar5_flate_degrees_from_utm_35_flate',
--'overlapgap_gap',
--'overlapgap_overlap',
--'overlapgap_grid',
--'overlapgap_boundery');	

-- SELECT find_overlap_gap_init('org_ar5.ar5_flate','');

--select count(*) as overlapgap_overlap from overlapgap_overlap;

--select count(*) as overlapgap_gap from overlapgap_gap;

--select cell_id, st_area as over_lap from (select i.*, st_area(st_transform(i.geo,3035)) from overlapgap_overlap i) as r order by st_area desc limit 3;

--select cell_id, st_area as st_hole from (select i.*, st_area(st_transform(i.geo,3035)) from overlapgap_gap i) as r order by st_area desc limit 3;

-- create table sl_lop.ar5_overlaps_13_11_2016 as (select i.*, st_area(st_transform(i.geo,3035)) from overlapgap_overlap i);

		


-- pg_dump -h db04.ad.skogoglandskap.no -U postgres -c -t overlapgap_overlap sl | psql sl
-- pg_dump -h db04.ad.skogoglandskap.no -U postgres -c -t overlapgap_gap sl | psql sl
-- pg_dump -h db04.ad.skogoglandskap.no -U postgres -c -t overlapgap_boundery sl | psql sl




--create table sl_lop.ar5_holes_utm35_14_11_2016 as (select i.*, st_area(st_transform(i.geo,3035)) from overlapgap_gap i where outside_data_boundery=false);
--grant select on sl_lop.ar5_holes_utm35_14_11_2016 to PUBLIC ;

--pg_dump -h db04.ad.skogoglandskap.no -U postgres -c -t sl_lop.ar5_holes_utm35_14_11_2016 sl | psql sl

--pg_dump -h db04.ad.skogoglandskap.no -U postgres -c -t sl_lop.ar5_holes_14_11_2016 sl | psql sl

--pg_dump -h db04.ad.skogoglandskap.no -U postgres -c -t sl_lop.ar5_overlap_14_11_2016 sl | psql sl


 
