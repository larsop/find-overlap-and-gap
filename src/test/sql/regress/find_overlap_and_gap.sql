-- Test 1 -------------
-- This is test that does a obverlap and gap test on overlap_gap_input_t1.sql

-- Test that input data are ok
SELECT '1', count(*) from test_data.overlap_gap_input_t1;

--psql testdb -c"\! psql -t -q -o /tmp/run_cmd.sql testdb -c\"SELECT find_overlap_gap_make_run_cmd('test_data.overlap_gap_input_t1','geom',4258,'test_data.overlap_gap_input_t1_res',50);\"; parallel -j 4  psql testdb -c :::: /tmp/run_cmd.sql" 2>> /tmp/analyze.log;

--psql testdb -c"SELECT count(*) antall_overlap, sum(st_area(ST_Transform(geom,32633))) from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_overlap) as r where ST_Area(geom) >0";                  

--psql testdb -c"SELECT count(*) antall_gap, sum(st_area(ST_Transform(geom,32633))) from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_gap) as r";                  

