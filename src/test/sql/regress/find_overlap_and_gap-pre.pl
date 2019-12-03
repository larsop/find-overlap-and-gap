#!/usr/bin/perl
use File::Copy;
use File::Spec::Functions;

$FILE_NAME_PRE='find_overlap_and_gap-pre.sql';
print "\n Output file is $FILE_NAME_PRE \n";

open($fh_out, ">", $FILE_NAME_PRE);

# get funtion defs for overlap gab 
for my $file (glob '../../../main/sql/func*') {
	copy_file_into($file,$fh_out);
}

# get def for conetnet based grid
if ( -e '/Users/lop/dev/github/content_balanced_grid/func_grid' ) 
{
	# TODO find another way to to get data from github
	for my $file (glob '/Users/lop/dev/github/content_balanced_grid/func_grid/func*.sql') {
		copy_file_into($file,$fh_out);
	}
} 
else
{
	copy_file_into('find_overlap_gap-pre-cbg-def.sql',$fh_out);
	print "use the find_overlap_gap-pre-cbg-def.sql \n";
}

copy_file_into('find_overlap_and_gap-pre-def.sql',$fh_out);
copy_file_into('overlap_gap_input_t1.sql',$fh_out);


close($fh_out);	 

sub copy_file_into() { 
	my ($v1, $v2) = @_;
	open(my $fh, '<',$v1);
	while (my $row = <$fh>) {
	  print $v2 "$row";
	}
	close($fh);	 
    
}
