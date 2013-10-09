package Bio::GenomeUpdate::GFF::GFFRearrange;
use strict;
use warnings;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Bio::GenomeUpdate::AGP;
use Bio::GenomeUpdate::GFF;
use Scalar::Util 'looks_like_number';

=head1 NAME

    GFFRearrange - Generic Feature Format (GFF) Rearrange modifies the coordinates of a GFF file. 

=head1 SYNOPSIS

    my $variable = Bio::GenomeUpdate::GFF::GFFRearrange->new();

=head1 DESCRIPTION

    This class modifies Generic Feature Format (GFF) coordinates using old and new Accessioned Golden Path (AGP) files. It does not currently handle Tiling Path Files (TPF). It does NOT handle cases where component sizes have changed in new AGP. It only handles changes in gap sizes and component flips. GFF features than span scaffolds are not handled and written out to errors.gff3 file. 

=head2 Methods

=over

=item C<reordered_coordinates_AGP ( $agp_old, $agp_new)>

Returns a hash of updated coordinates. Uses the component names to match positions. Will need mapping function if component names are different. Names should be same in case of accessions for contigs.

=cut

sub reordered_coordinates_AGP{
	my $self = shift;
	my $agp_old = shift;
	my $agp_new = shift;
	my (%coordinates, %obj_old_start, %obj_old_end, %comp_old_or);
	
	#get coords from old AGP
	while ( my $agp_line = $agp_old->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_old_start = $agp_line->get_object_begin();
		my $agp_line_obj_old_end = $agp_line->get_object_end();
		my $agp_line_comp_old_or = $agp_line->get_orientation();
		
		$obj_old_start{$agp_line_comp} = $agp_line_obj_old_start;
		$obj_old_end{$agp_line_comp} = $agp_line_obj_old_end;
		#set 0 as + for comparison with new AGP
		if ( looks_like_number($agp_line_comp_old_or) ){
			if ($agp_line_comp_old_or == 0){
				$comp_old_or{$agp_line_comp} = '+';
			}
		}
		elsif (($agp_line_comp_old_or eq '+') || ($agp_line_comp_old_or eq '-')){
			$comp_old_or{$agp_line_comp} = $agp_line_comp_old_or;
		}
		elsif (($agp_line_comp_old_or eq '?') || ($agp_line_comp_old_or eq 'na')){
				$comp_old_or{$agp_line_comp} = '+';
		}
		
		for my $base ($agp_line_obj_old_start..$agp_line_obj_old_end){
			die "$agp_line_comp already has $base recorded, aborting.. " if exists $coordinates{$base};
			$coordinates{$base}='X';#use X to post-check for unordered coords, will cause datatype error 
		}
	}
	
	#get coords from new AGP
	while ( my $agp_line = $agp_new->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_new_start = $agp_line->get_object_begin();
		my $agp_line_obj_new_end = $agp_line->get_object_end();
		my $agp_line_comp_new_or;
		
		#set 0,na,? as + for comparison with old AGP
		if ( looks_like_number($agp_line->get_orientation()) ){
			if ($agp_line->get_orientation() == 0){
				$agp_line_comp_new_or = '+';
			}
		}
		elsif (($agp_line->get_orientation() eq '+') || ($agp_line->get_orientation() eq '-')){
			$agp_line_comp_new_or = $agp_line->get_orientation();
		}
		elsif (($agp_line->get_orientation() eq '?') || ($agp_line->get_orientation() eq 'na')){
				$agp_line_comp_new_or = '+';
		}
		
		#error check
		die "$agp_line_comp not found in old AGP, aborting.." if (!exists $obj_old_start{$agp_line_comp});
		
		#same position and strand
		if ( ($obj_old_start{$agp_line_comp} == $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} == $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} eq $agp_line_comp_new_or)){
			
			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$coordinates{$base} = $base;
			}
		}
		#same strand, moved downstream
		elsif ( ($obj_old_start{$agp_line_comp} < $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} < $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} eq $agp_line_comp_new_or)){

			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$coordinates{$base} = $base + ($agp_line_obj_new_start - $obj_old_start{$agp_line_comp});
			}
		}
		#same strand, moved upstream
		elsif ( ($obj_old_start{$agp_line_comp} > $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} > $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} eq $agp_line_comp_new_or)){

			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$coordinates{$base} = $base - ($obj_old_start{$agp_line_comp} - $agp_line_obj_new_start);
			}
		}
		#diff strand, flipped, old start = new end
		elsif ( ($obj_old_start{$agp_line_comp} == $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} == $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} ne $agp_line_comp_new_or)){
			 
			my $counter = 0;
			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$coordinates{$base} = $agp_line_obj_new_end - $counter;
					$counter++;
			}
			#err check
			die "Problem in assigning coords for flipped $agp_line_comp" if ( ($counter - 1) != $agp_line_obj_new_end - $agp_line_obj_new_start);
		}
		#diff strand, start, end
		elsif ( ($obj_old_start{$agp_line_comp} != $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} != $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} ne $agp_line_comp_new_or)){
			 
			my $counter = 0;
			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$coordinates{$base} = $agp_line_obj_new_end - $counter;
				$counter++;
			}
			#err check
			die "Problem in assigning coords for flipped/moved $agp_line_comp" if ( ($counter - 1) != $agp_line_obj_new_end - $agp_line_obj_new_start);
		}
		else{
			die "This should not happen!";
		}
	}
	return %coordinates;
}

=item C<flipped_coordinates_AGP ( $agp_old, $agp_new)>

Returns a hash of coordinates that are flipped(0 or 1). Uses the component names to match positions. Will need mapping function if component names are different. Names should be same in case of accessions for contigs.

=cut
sub flipped_coordinates_AGP{
	my $self = shift;
	my $agp_old = shift;
	my $agp_new = shift;
	my (%flipped, %obj_old_start, %obj_old_end, %comp_old_or);
	
	#get coords from old AGP
	while ( my $agp_line = $agp_old->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_old_start = $agp_line->get_object_begin();
		my $agp_line_obj_old_end = $agp_line->get_object_end();
		my $agp_line_comp_old_or = $agp_line->get_orientation();
		
		$obj_old_start{$agp_line_comp} = $agp_line_obj_old_start;
		$obj_old_end{$agp_line_comp} = $agp_line_obj_old_end;
		$comp_old_or{$agp_line_comp} = $agp_line_comp_old_or;
		
		for my $base ($agp_line_obj_old_start..$agp_line_obj_old_end){
			die "$agp_line_comp already has $base recorded, aborting.. " if exists $flipped{$base};
			$flipped{$base}=0;#use 0 for not flipped 
		}
	}
	
	#get coords from new AGP
	while ( my $agp_line = $agp_new->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_new_start = $agp_line->get_object_begin();
		my $agp_line_obj_new_end = $agp_line->get_object_end();
		my $agp_line_comp_new_or = $agp_line->get_orientation();
		
		#error check
		die "$agp_line_comp not found in old AGP, aborting.." if (!exists $obj_old_start{$agp_line_comp});
		
		#diff strand, flipped, old start = new end
		if ( ($obj_old_start{$agp_line_comp} == $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} == $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} ne $agp_line_comp_new_or)){
			 
			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$flipped{$base} = 1;
			}
		}
		#diff strand, start, end
		elsif ( ($obj_old_start{$agp_line_comp} != $agp_line_obj_new_start) &&
			 ($obj_old_end{$agp_line_comp} != $agp_line_obj_new_end) &&
			 ($comp_old_or{$agp_line_comp} ne $agp_line_comp_new_or)){
			 
			for my $base ($obj_old_start{$agp_line_comp}..$obj_old_end{$agp_line_comp}){
				$flipped{$base} = 1;
			}
		}
		else{
			#all cases where component did not flip
		}
	}
	return %flipped;	
}

=item C<updated_coordinates_strand_AGP ( $start, $end, $strand, $agp_old, $agp_new)>

Returns a int new coordinates and strand wrt new AGP. Sets 0 to + as strand in old AGP for comparison purposes. Uses the component names to match positions. Will need mapping function if component names are different. Names should be same in case of accessions for contigs.

=cut

sub updated_coordinates_strand_AGP{
	my $self = shift;
	my $start = shift;
	my $end = shift;
	my $strand = shift;
	my $agp_old = shift;
	my $agp_new = shift;
	my (%obj_old_start, %obj_old_end, %comp_old_or, %obj_new_start, %obj_new_end, %comp_new_or);
	my ($nstart, $nend, $nstrand);
	
	#reset current line number if already processed once
	$agp_old->set_current_agp_line_number(1);
	$agp_new->set_current_agp_line_number(1);
	
	#get coords from old AGP
	while ( my $agp_line = $agp_old->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_old_start = $agp_line->get_object_begin();
		my $agp_line_obj_old_end = $agp_line->get_object_end();
		my $agp_line_comp_old_or = $agp_line->get_orientation();
		
		$obj_old_start{$agp_line_comp} = $agp_line_obj_old_start;
		$obj_old_end{$agp_line_comp} = $agp_line_obj_old_end;
		
		#set 0,?,na as + for comparison with new AGP
		if ( looks_like_number($agp_line_comp_old_or) ){
			if ($agp_line_comp_old_or == 0){
				$comp_old_or{$agp_line_comp} = '+';
			}
		}
		elsif (($agp_line_comp_old_or eq '+') || ($agp_line_comp_old_or eq '-')){
			$comp_old_or{$agp_line_comp} = $agp_line_comp_old_or;
		}
		elsif (($agp_line_comp_old_or eq '?') || ($agp_line_comp_old_or eq 'na')){
				$comp_old_or{$agp_line_comp} = '+';
		}
	}

	#get coords from new AGP
	while ( my $agp_line = $agp_new->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_new_start = $agp_line->get_object_begin();
		my $agp_line_obj_new_end = $agp_line->get_object_end();
		my $agp_line_comp_new_or = $agp_line->get_orientation();

		$obj_new_start{$agp_line_comp} = $agp_line_obj_new_start;
		$obj_new_end{$agp_line_comp} = $agp_line_obj_new_end;
		
		#set 0,na,? as + for comparison with old AGP
		if ( looks_like_number($agp_line_comp_new_or) ){
			if ($agp_line_comp_new_or == 0){
				$comp_new_or{$agp_line_comp} = '+';
			}
		}
		elsif (($agp_line_comp_new_or eq '+') || ($agp_line_comp_new_or eq '-')){
			$comp_new_or{$agp_line_comp} = $agp_line_comp_new_or;
		}
		elsif (($agp_line_comp_new_or eq '?') || ($agp_line_comp_new_or eq 'na')){
				$comp_new_or{$agp_line_comp} = '+';
		}
	}

	#get component from old AGP
	my ($component) = $self->get_component_AGP($start, $agp_old);
	
	#presuming start component == end components. Diff if gff record for full chromosome (assembly.gff)
#	die "Diff component for start and stop.\nStart: ",$start,' Component: ',$self->get_component_AGP($start, $agp_old),
#		"\nEnd: ",$end,' Component: ',$self->get_component_AGP($end, $agp_old),"\n" 
#		if( ($self->get_component_AGP($start, $agp_old)) ne ($self->get_component_AGP($end, $agp_old)));
	if( ($self->get_component_AGP($start, $agp_old)) ne ($self->get_component_AGP($end, $agp_old))){
		print STDERR "Diff component for start and stop.\nStart: ",$start,' Component: ',
			$self->get_component_AGP($start, $agp_old),"\nEnd: ",$end,' Component: ',
			$self->get_component_AGP($end, $agp_old),"\n";
		return (0,0,0);
	}
	#same position and strand
	elsif(($obj_old_start{$component} == $obj_new_start{$component}) &&
		($obj_old_end{$component} == $obj_new_end{$component}) &&
		($comp_old_or{$component} eq $comp_new_or{$component})){
			$nstart = $start;
			$nend = $end;
			$nstrand = $strand;
	}
	#same strand, moved downstream
	elsif (($obj_old_start{$component} < $obj_new_start{$component}) &&
			($obj_old_end{$component} < $obj_new_end{$component}) &&
			($comp_old_or{$component} eq $comp_new_or{$component})){
				$nstart = $start + ($obj_new_start{$component} - $obj_old_start{$component});
				$nend = $end + ($obj_new_start{$component} - $obj_old_start{$component});
				$nstrand = $strand;
	}
	#same strand, moved upstream
	elsif ( ($obj_old_start{$component} > $obj_new_start{$component}) &&
			($obj_old_end{$component} > $obj_new_end{$component}) &&
			($comp_old_or{$component} eq $comp_new_or{$component})){
				$nstart = $start - ($obj_old_start{$component} - $obj_new_start{$component});
				$nend = $end - ($obj_old_start{$component} - $obj_new_start{$component});
				$nstrand = $strand;
	}
	#diff strand i.e. flipped
	elsif ( ($comp_old_or{$component} ne $comp_new_or{$component})){
			if ( $strand eq '+' ){
				$nstart = $obj_new_end{$component} - (($end - $start) + ($start - $obj_old_start{$component}));
				$nend = $obj_new_end{$component} - ($start - $obj_old_start{$component});
				$nstrand = '-';
			}
			elsif ( $strand eq '-' ){
				$nstart = $obj_new_start{$component} + (($obj_old_end{$component} - $end));
				$nend = $obj_new_start{$component} + (($obj_old_end{$component} - $end) + ($end - $start));
				$nstrand = '+';
			}
	}
	else{
		die "This should not happen!";
	}

	return ($nstart, $nend, $nstrand);
}

=item C<get_component_AGP ( $base, $agp)>

Returns component name given a base and associated AGP file.

=cut

sub get_component_AGP{
	my $self = shift;
	my $base = shift;
	my $agp = shift;
	my $component;
	my $found = 0;
	
	#ERR
	#print "get_component_AGP called for $base\n";
	
	my $current_agp_line_number = $agp->get_current_agp_line_number();
	$agp->set_current_agp_line_number(1);
	
	while ( my $agp_line = $agp->get_next_agp_line()){
		
		next if ( ref($agp_line) eq 'Bio::GenomeUpdate::AGP::AGPGapLine');
		
		my $agp_line_comp = $agp_line->get_component_id();
		my $agp_line_obj_start = $agp_line->get_object_begin();
		my $agp_line_obj_end = $agp_line->get_object_end();
		
		if (($base >= $agp_line_obj_start) && ($base <= $agp_line_obj_end)){
			$component = $agp_line_comp;
			$found = 1;
			last;
		}
	}	
	die "No component found containing $base. Exiting..." if($found == 0);

	$agp->set_current_agp_line_number($current_agp_line_number);
	
	return ($component);
}



###
1;				#do not remove
###

=back

=head1 LICENSE

    Same as Perl.

=head1 AUTHORS

    Surya Saha <suryasaha@cornell.edu , @SahaSurya>   

=cut
