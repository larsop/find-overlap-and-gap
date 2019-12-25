# What is this function doing ?

This is a generic Postgres function that find all overlaps and gaps for a table. 

The basic idea is that you call this function and with a table name as input and a table name prefix for result tables. The result will then different tables that show overlaps, gaps and the boundary for the input table.  

This function now depend on 
- dblink (this replaced code from https://www.gnu.org/software/parallel)
- Postgres 10 or higher
- https://github.com/larsop/postgres_execute_parallel
- https://github.com/larsop/content_balanced_grid


[![Build Status](https://travis-ci.org/larsop/find-overlap-and-gap.svg?branch=master)](https://travis-ci.org/larsop/find-overlap-and-gap)

# How to use :
For the table we need the following information as input 
* table name
* geometry column name (could have be computed in the code)
* the srid og the geometry column (could have be computed in the code)

## Example : Here is a example we use this file 
![Parts of the input file](https://github.com/larsop/find-overlap-and-gap/blob/master/src/test/sql/regress/overlap_gap_input_t1.png)
found src/test/sql/regress/overlap_gap_input_t1.sql 

## Exsample 
We run a singel sql command 
- name of the input table, 
- geometry column name
- srid for geo column
- prefix for the result tables.
- number of threads
- max number polygons in each content based cell

with 1 parallel thread (sl_lop.overlap_gap_input_t1 is very small)
<pre><code>
time psql sl  -c"CALL find_overlap_gap_run('sl_lop.overlap_gap_input_t1','geom',4258,'sl_lop.overlap_gap_input_t1_res',1,50)" 2>> /tmp/analyze.log;
real	0m28.139s
</pre></code>

with 2 parallel threads (sl_lop.overlap_gap_input_t1 is very small)
<pre><code>
time psql sl  -c"CALL find_overlap_gap_run('sl_lop.overlap_gap_input_t1','geom',4258,'sl_lop.overlap_gap_input_t1_res',1,50)" 2>> /tmp/analyze.log;
real	0m14.124s
</pre></code>

## When done we can check overlaps and gaps

Check the number of overlaps and overlapping areas in this way. 
<pre><code>
psql testdb -c"SELECT count(*) antall_overlap, sum(st_area(ST_Transform(geom,32633))) from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_overlap) as r where ST_Area(geom) >0";                  
</pre></code>
![Parts of the of the overlap's](https://github.com/larsop/find-overlap-and-gap/blob/master/src/test/sql/regress/overlap_gap_input_t1_res_overlap.png)
                  
Check the number of gaps and gap areas in this way. 
<pre><code>
psql testdb -c"SELECT count(*) antall_gap, sum(st_area(ST_Transform(geom,32633))) from (SELECT  (ST_dump(geom)).geom as geom, cell_id from test_data.overlap_gap_input_t1_res_gap) as r";                  
</pre></code>
![Parts of the of the gap's](https://github.com/larsop/find-overlap-and-gap/blob/master/src/test/sql/regress/overlap_gap_input_t1_res_gap.png)

## An examlple going from 20 to 40 paralell threads and running twice as fast

with 20 parallel threads (a more normal sized data set)
<pre><code>
time psql sl  -c"CALL find_overlap_gap_run('org_ar.ar250_flate','geo',4258,'sl_lop.ar250_flate_res',20,1000);" 2>> /tmp/analyze.log;
Time: 2128491.119 ms (35:28.491)
</pre></code>

with 40 parallel threads (a more normal sized data set)
<pre><code>
time psql sl  -c"CALL find_overlap_gap_run('org_ar.ar250_flate','geo',4258,'sl_lop.ar250_flate_res',40,1000);" 2>> /tmp/analyze.log;
Time: 1076647.282 ms (17:56.647)
</pre></code>





# How to install :

git clone https://github.com/larsop/postgres_execute_parallel.git

cat postgres_execute_parallel/src/main/sql/function*.sql | psql

git clone https://github.com/larsop/content_balanced_grid

cat content_balanced_grid/func_grid/functions_*.sql | psql 

git clone https://github.com/larsop/find-overlap-and-gap.git

cat find-overlap-and-gap/src/main/sql/function*.sql | psql

psql -c'CREATE EXTENSION dblink;'
