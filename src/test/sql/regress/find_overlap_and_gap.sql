-- Test 1 -------------
-- This is test that does a obverlap and gap test on overlap_gap_input_t1.sql

-- Test that input data are ok
SELECT '1', count(*) from test_data.overlap_gap_input_t1;

-- Pipe output sql to to files sp they can executed
\o /tmp/run_cmd.sql
SELECT find_overlap_gap_make_run_cmd('test_data.overlap_gap_input_t1','geom',4258,'test_data.overlap_gap_input_t1_res',50);

\! parallel -j 4  psql postgis_reg  -c :::: /tmp/run_cmd.sql > /tmp/run_cmd_result.log


\o
SELECT '2', count(*) antall_overlap, sum(st_area(ST_Transform(geom,32633))) from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_overlap) as r where ST_Area(geom) >0;                  

SELECT '3',  count(*) antall_gap, sum(st_area(ST_Transform(geom,32633))) from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_gap) as r;                  

