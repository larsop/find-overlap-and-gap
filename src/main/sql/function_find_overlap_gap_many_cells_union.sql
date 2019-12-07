

DROP FUNCTION IF EXISTS find_overlap_gap_many_cells_union(command_string_ varchar);

CREATE OR REPLACE FUNCTION find_overlap_gap_many_cells_union(command_string_ varchar) RETURNS void
AS $$DECLARE
	command_string_result text;
	

BEGIN
	
	RAISE NOTICE '%', command_string_;


	EXECUTE command_string_ INTO command_string_result;

	RAISE NOTICE '%', command_string_result;

-- So we use single calls instead


END;
$$
LANGUAGE plpgsql PARALLEL SAFE COST 1;

GRANT EXECUTE on FUNCTION find_overlap_gap_many_cells_union(command_string_ varchar) TO public;
 


