CREATE EXTENSION dblink; -- needed by  execute_parallel

-- Test 1 -------------
-- This is test that does a obverlap and gap test on overlap_gap_input_t1.sql

-- Test that input data are ok
SELECT '1 spheroid-true overlap_gap_input_t1', count(*), ROUND(sum(st_area(geom,true))::numeric,0) from test_data.overlap_gap_input_t1;
SELECT '1 transform 3035 overlap_gap_input_t1', count(*), ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from test_data.overlap_gap_input_t1;

-- Call this the overlap and gap function to find overlap and gap
-- The geometry column is named 'geom' in the test dataset and uses srid 4258, 	
-- We place the results in test_data.overlap_gap_input_t1_res*
-- || '_overlap'; -- The schema.table name for the overlap/intersects found in each cell 
-- || '_gap'; -- The schema.table name for the gaps/holes found in each cell 
-- || '_grid'; -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
-- || '_boundery'; -- The schema.table name the outer boundery of the data found in each cell 
-- It will run with 10 paralell threads and max 50 polygons in each content based cell  
CALL find_overlap_gap_run('test_data.overlap_gap_input_t1','geom',4258,'test_data.overlap_gap_input_t1_res',10,50);

-- Check the result
SELECT 'check overlap table overlap_gap_input_t1', count(*) num_overlap, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from (SELECT  (ST_dump(geom)).geom as geom, cell_id 
from test_data.overlap_gap_input_t1_res_overlap) as r where ST_Area(geom) >0;                  

SELECT 'check gap table overlap_gap_input_t1',  count(*) num_gap, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) 
from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_gap) as r;                  

SELECT 'check grid table overlap_gap_input_t1',  count(*) num_grid, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from (SELECT  (ST_dump(geom)).geom as geom, id 
from test_data.overlap_gap_input_t1_res_grid) as r;                  

SELECT 'check boundery table overlap_gap_input_t1',  count(*) num_boudery, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from (SELECT  (ST_dump(geom)).geom as geom, id 
from test_data.overlap_gap_input_t1_res_boundery) as r;                  


/**


CREATE table test_data.hovedokosystem_fylke_24_05_2023_flate AS prosj_mdir_hovedokosystem.hovedokosystem_fylke_24_05_2023_flate

CREATE TABLE test_data.hovedokosystem_fylke_24_05_2023_flate AS
    TABLE prosj_mdir_hovedokosystem.hovedokosystem_fylke_24_05_2023_flate
    WITH NO DATA;
	
479059


INSERT INTO test_data.hovedokosystem_fylke_24_05_2023_flate 
SELECT * 
FROM prosj_mdir_hovedokosystem.hovedokosystem_fylke_24_05_2023_flate WHERE 
id in (479059,531702);

*/ 


-- Test 2 -------------
-- This is test that does a obverlap and gap test on hovedokosystem_fylke_24_05_2023_flate.sql

-- Test that input data are ok
SELECT '1 spheroid-true hovedokosystem_fylke_24_05_2023_flate', count(*), ROUND(sum(st_area(geom,true))::numeric,0) from test_data.hovedokosystem_fylke_24_05_2023_flate;
SELECT '1 transform 3035 hovedokosystem_fylke_24_05_2023_flate', count(*), ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from test_data.hovedokosystem_fylke_24_05_2023_flate;

-- Call this the overlap and gap function to find overlap and gap
-- The geometry column is named 'geom' in the test dataset and uses srid 4258, 	
-- We place the results in test_data.hovedokosystem_fylke_24_05_2023_flate_res*
-- || '_overlap'; -- The schema.table name for the overlap/intersects found in each cell 
-- || '_gap'; -- The schema.table name for the gaps/holes found in each cell 
-- || '_grid'; -- The schema.table name of the grid that will be created and used to break data up in to managle pieces
-- || '_boundery'; -- The schema.table name the outer boundery of the data found in each cell 
-- It will run with 10 paralell threads and max 50 polygons in each content based cell  
CALL find_overlap_gap_run('test_data.hovedokosystem_fylke_24_05_2023_flate','geom',4258,'test_data.hovedokosystem_fylke_24_05_2023_flate_res',10,50);

-- Check the result
SELECT 'check overlap table hovedokosystem_fylke_24_05_2023_flate', count(*) num_overlap, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from (SELECT  (ST_dump(geom)).geom as geom, cell_id 
from test_data.hovedokosystem_fylke_24_05_2023_flate_res_overlap) as r where ST_Area(geom) >0;                  

SELECT 'check gap table hovedokosystem_fylke_24_05_2023_flate',  count(*) num_gap, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) 
from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.hovedokosystem_fylke_24_05_2023_flate_res_gap) as r;                  

SELECT 'check grid table hovedokosystem_fylke_24_05_2023_flate',  count(*) num_grid, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from (SELECT  (ST_dump(geom)).geom as geom, id 
from test_data.hovedokosystem_fylke_24_05_2023_flate_res_grid) as r;                  

SELECT 'check boundery table hovedokosystem_fylke_24_05_2023_flate',  count(*) num_boudery, ROUND(sum(st_area(ST_Transform(geom,3035)))::numeric,0) from (SELECT  (ST_dump(geom)).geom as geom, id 
from test_data.hovedokosystem_fylke_24_05_2023_flate_res_boundery) as r;                  
