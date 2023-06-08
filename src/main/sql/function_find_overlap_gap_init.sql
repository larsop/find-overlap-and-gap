
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
	
	
	command_string := Format('INSERT INTO %1$s(%5$s)
 	SELECT ST_transform(q_grid.cell,%2$s)::Geometry(geometry,%2$s) as %5$s
 	from (
 	select(st_dump(
 	cbg_content_based_balanced_grid(%3$L,%4$s))
 	).geom as cell) as q_grid ', 
 	overlapgap_grid_, --01
 	srid_,  -- 02
 	ARRAY[table_to_analyze_ || ' ' || geo_collumn_on_test_table_::text], --03
 	max_rows_in_each_cell, --04
 	geo_collumn_name_ --05
 	);
  
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

