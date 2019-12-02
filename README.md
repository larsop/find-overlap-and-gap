# What is this function doing ?

This is a generic Postgres function that find all overlaps and gaps for a table. 
This code now depends on https://www.gnu.org/software/parallel/ to run (This should hva been fixed in Postgres)

The basic idea is that you call this function and with a table name as input and a table name prefix for result tables. The result will then different tables that show overlaps, gaps and the boundary for the input table.  

# How to use :
For the table we need the following information as input 
* table name
* geometry column name (could have be computed in the code)
* the srid og the geometry column (could have be computed in the code)

## Example : Here is a example where we use Gnu parallel .

First we run a sql command with the name of the input table, geometry column name and srid. The final parameter is prefix for the result tables.
This command produce a set new sql commands in the file run_cmd.sql.
<pre><code>psql -h pgserver -U username -t -q -o run_cmd.sql sl -c"SELECT find_overlap_gap_make_run_cmd('schema_name.table_to_analyze','geo',4258,'schema_name_result.table_to_analyze_res')"</pre></code>

Then we use gnu to run this commands in paralell. This case below we use 40 threads. 
<pre><code>parallel --citation -verbose -j 40  psql -h pgserver -U username sl -c :::: run_cmd.sql  2>> /tmp/analyze.log;</pre></code>

When done, we can check the number of overlaps and overlapping areas in this way. 
<pre><code>SELECT count(*) antall_overlap, sum(st_area(ST_Transform(geo,32633))) from (SELECT  (ST_dump(geo)).geom as geo, cell_id from schema_name_result.table_to_analyze_res_overlap) as r where ST_Area(geo) >0;</pre></code>
                  
Gaps are ares where this is now data inside the bounding box for the layer.
<pre><code>SELECT count(*) antall_gap, sum(st_area(ST_Transform(geo,32633))) from (SELECT  (ST_dump(geo)).geom as geo, cell_id from schema_name_result.table_to_analyze_res_gap) as r;</pre></code>


# How to install :
git clone https://github.com/larsop/content_balanced_grid

cat content_balanced_grid/func_grid/functions_*.sql | psql 

git clone https://github.com/larsop/find-overlap-and-gap.git

cat find-overlap-and-gap/src/main/sql/function*.sql | psql

