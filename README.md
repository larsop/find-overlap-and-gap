# What is this function doing ?

This is a generic Postgres function that find all overlaps and gaps for a table. 
This code now depends on https://www.gnu.org/software/parallel/ to run (This should hva been fixed in Postgres)


This function now depend on 
- dblink
- Postgres 10 or higher
- https://github.com/larsop/postgres_execute_parallel
- https://github.com/larsop/content_balanced_grid

The basic idea is that you call this function and with a table name as input and a table name prefix for result tables. The result will then different tables that show overlaps, gaps and the boundary for the input table.  

[![Build Status](https://travis-ci.org/larsop/find-overlap-and-gap.svg?branch=master)](https://travis-ci.org/larsop/find-overlap-and-gap)

# How to use :
For the table we need the following information as input 
* table name
* geometry column name (could have be computed in the code)
* the srid og the geometry column (could have be computed in the code)

## Example : Here is a example we use this file 
![Parts of the input file](https://github.com/larsop/find-overlap-and-gap/blob/master/src/test/sql/regress/overlap_gap_input_t1.png)
found src/test/sql/regress/overlap_gap_input_t1.sql 

## First we run a sql command with the name of the input table, geometry column name and srid. The final parameter is prefix for the result tables.

The command creates a set of sql commands in the file /tmp/run_cmd.sql.
Then we use gnu parallel to run this commands in 4. parallel threads. 
<pre><code>
psql testdb -c"\! psql -t -q -o /tmp/run_cmd.sql testdb -c\"SELECT find_overlap_gap_run('sl_lop.overlap_gap_input_t1','geom',4258,'sl_lop.overlap_gap_input_t1_res',50);\"; parallel -j 4  psql testdb -c :::: /tmp/run_cmd.sql" 2>> /tmp/analyze.log;
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


# How to install :

git clone https://github.com/larsop/postgres_execute_parallel.git

cat postgres_execute_parallel/src/main/sql/function*.sql | psql

git clone https://github.com/larsop/content_balanced_grid

cat content_balanced_grid/func_grid/functions_*.sql | psql 

git clone https://github.com/larsop/find-overlap-and-gap.git

cat find-overlap-and-gap/src/main/sql/function*.sql | psql

psql -c'CREATE EXTENSION dblink;'
