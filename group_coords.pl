#!/usr/bin/perl
=head1

place_bacs.pl

=head1 SYNOPSIS

    group_coords.pl -i [coords file] -g [gap size]

=head1 COMMAND-LINE OPTIONS

 -i  COORDS file created by show-coords
 -u  Sequence ID of chromosome with unmapped contigs 
 -g  Gap size
 -t  Print header
 -h  Help

=cut

use strict;
use warnings;

use Getopt::Std;
use File::Slurp;
use Bio::GenomeUpdate::AlignmentCoords;
use Bio::GenomeUpdate::AlignmentCoordsGroup;

our ($opt_i, $opt_g, $opt_u, $opt_t, $opt_h);
getopts("i:g:u:t:h");
if (!$opt_i || !$opt_g || !$opt_u) {
  help();
}
if ($opt_h) {
  help();
}
my $input_file;
my $gap_size_allowed = 10000;
my $unmapped_ID;
$unmapped_ID = "SL2.40ch00";
my $print_header = "T";
$input_file = $opt_i || die("-i input_file required\n");
if ($opt_g) {
  $gap_size_allowed=$opt_g;
  print STDERR "Gg: $opt_u\n";
}
if ($opt_u) {
  $unmapped_ID = $opt_u;
}
if ($opt_t) {
  if ($opt_t eq "T") {
    $print_header="T";
  } elsif ($opt_t eq "F") {
    $print_header="F";
  } else {
    die ("-t must be T or F\n");
  }
}

###parameter not working.  hard coded
#$gap_size_allowed = 100000;


my $total=0;
my $total_smaller_than_20k=0;
my $total_mixed=0;
my $total_over=0;
my $total_alt=0;
my $total_full_length=0;
my $total_to_end=0;
my $total_extend=0;




print STDERR "G0: $gap_size_allowed\n";
my @lines = read_file($input_file);
my $startline = 5;
my $currentline = 0;
my @alignment_coords_array;
my $last_line_query_id;
my $last_query_id;
my $last_query_length;
print "query\treference\tref_start\tref_end\tlength\tq_start\tq_end\tq_length\tseq_in_clusters\tdirection\tref_count\tincludes_0\tfull_length\tfrom_start\tfrom_end\tinternal_gap\tis_overlapping\tsize_of_alt\talternates\t\n";
foreach my $line (@lines) {
  $currentline++;
  if ($currentline < $startline) {
    next;
  }
  my @row;
  @row = split('\t',$line);
  my $current_query_id = $row[14];
  my $current_query_length = $row[8];
  if (!defined($last_line_query_id)) {
    $last_line_query_id = $current_query_id;
  }    
  if (!($current_query_id eq $last_line_query_id)) {
    calc_and_print_info(\@alignment_coords_array, $last_query_id, $last_query_length);
    @alignment_coords_array = ();
  }
  my $aln_coords = Bio::GenomeUpdate::AlignmentCoords->new();
  $aln_coords->set_reference_id($row[13]);
  $aln_coords->set_query_id($row[14]);
  $aln_coords->set_reference_start_coord($row[0]);
  $aln_coords->set_reference_end_coord($row[1]);
  $aln_coords->set_query_start_coord($row[2]);
  $aln_coords->set_query_end_coord($row[3]);
  push(@alignment_coords_array, $aln_coords);
  #deal with last row
  if ($currentline==scalar(@lines)) {
    calc_and_print_info(\@alignment_coords_array, $current_query_id, $current_query_length,$gap_size_allowed);
    @alignment_coords_array = ();
  }
  $last_line_query_id = $current_query_id;
  $last_query_id = $current_query_id;
  $last_query_length = $current_query_length;
}

sub calc_and_print_info {
  my ($aref,$q_id,$q_length) = @_;
  my $align_group =  Bio::GenomeUpdate::AlignmentCoordsGroup->new();
  $align_group->set_array_of_alignment_coords($aref);
  my $zero_chromosome_id = $unmapped_ID;
  #    print STDERR "G1: $gap_size_allowed\n";
  my ($ref_id, $query_id, $ref_start, $ref_end, $query_start, $query_end, $sequence_aligned_in_clusters,$direction,$is_overlapping,$size_of_next_largest_match,$alternates) = $align_group->get_id_coords_and_direction_of_longest_alignment_cluster_group($gap_size_allowed);
  my $is_full_length;
  my $start_gap_length = $query_start-1;
  my $end_gap_length = $q_length-$query_end;
  my $internal_gap_length = ($q_length-$sequence_aligned_in_clusters) - ($start_gap_length + $end_gap_length);
  if (($query_start == 1) && ($query_end == $q_length)) {
    $is_full_length = "Contains";
  } else {
    $is_full_length = "Partial";
  }
  print $q_id."\t";
  print $ref_id."\t";
  print $ref_start."\t";
  print $ref_end."\t";
  print $ref_end-$ref_start."\t";
  print $query_start."\t";
  print $query_end."\t";
  print $q_length."\t";
  print $sequence_aligned_in_clusters."\t";
  print $direction."\t";
  print $align_group->get_count_of_reference_sequence_ids()."\t";;
  print $align_group-> includes_reference_id($zero_chromosome_id)."\t";
  print $is_full_length."\t";    
  print $start_gap_length."\t";
  print $end_gap_length."\t";
  print $internal_gap_length."\t";
  print $is_overlapping."\t";
  print $size_of_next_largest_match."\t";
  print $alternates."\t";
  #if (defined($second_id)){
  #print $second_id."\t";
  #print $second_size."\t"
  #}
  #else {
  #print "None\tNone\t";
  #}
  print "\n";

  my $flagged = 0;

  $total++;
  if ($ref_end-$ref_start < 20000) {
    $total_smaller_than_20k++;
    $flagged=1;
  }
  if ($direction == 0) {
    $total_mixed++;
    $flagged=1;
  }
  if ($is_overlapping == 1) {
    $total_over++;
    $flagged=1;
  }
  if ($size_of_next_largest_match > 10000) {
    $total_alt++;
    $flagged=1;
  }
  if ($start_gap_length < 10 && $end_gap_length < 10 && $flagged==0) {
    $total_full_length++;
  }
  if (($start_gap_length < 10 || $end_gap_length < 10) && $flagged==0) {
    $total_to_end++;
  }
  if ($flagged==0) {
    $total_extend += $start_gap_length + $end_gap_length;
  }
}



  ##summary info
print STDERR "Total:\t$total\n";
print STDERR "Total smaller than 5000:\t$total_smaller_than_20k\n";
print STDERR "Total with mixed orientation:\t$total_mixed\n";
print STDERR "Total with overlapping alignment clusters:\t$total_over\n";
print STDERR "Total with alternate alignments > 10,000:\t$total_alt\n";
print STDERR "Total full length:\t$total_full_length\n";
print STDERR "Total with alignment to at least one end:\t$total_to_end\n";
print STDERR "Total sequence extended by BACs:\t$total_extend\n";




sub help {
  print STDERR <<EOF;
  $0:

    Description:

     This script groups aligned clusters and creates a tab delimited file with BAC alignment details.

    Usage:
      group_coords.pl -i [coords file] -g [gap size]

    Flags:

       -i  <coords file>             COORDS file created by show-coords (required)
       -g  <int>                     Gap size allowed (required)
       -u  <str>                     Sequence ID(seqid) of chromosome with unmapped contigs/scaffolds. Typically chromosome 0. (required)
       -t  <T/F>                     Print header. Must be T or F. Default is T
       -h  <help>
EOF
exit (1);
}
