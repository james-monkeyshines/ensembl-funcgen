#
# Ensembl module for Bio::EnsEMBL::DBSQL::Funcgen::ResultFeatureAdaptor
#
# You may distribute this module under the same terms as Perl itself

=head1 NAME

Bio::EnsEMBL::DBSQL::Funcgen::ResultFeatureAdaptor - A hybrid/chimaeric database adaptor for fetching and
storing ResultFeature objects.  This will automatically query the web optimised result_feature
table if a data is present, else it will query the underlying raw data tables.

How are we going to track the association between these two result sets?  We could use the supporting_set table and DataSets, but this would require hijacking the product feature set field for a result set??!!

This is not really a DataSet, but two associated result sets.
Add type to result_set, result and result_feature.  This would simply be a replicate pointing to the same cc_ids, but we can then simply test for the type and use a different table if possible.
We can healtcheck the two sets to make sure they have the same cc_ids, analysis, feaure and cell types.
How do we make the association? Query using the name, analysis, cell/feature types and different result_set type. Or we could add a parent_result_set_id

This could utilise a Binner object which would do the necessary DB compaction based on the association Feature Collection methods.  

Are we going to binary pack the scores?

We should just add another table result_feature_set.
Need to left join on this table as might not be present.
Would need update_result_feature_set method?


=head1 SYNOPSIS

my $rfeature_adaptor = $db->get_ResultFeatureAdaptor();

my @result_features = @{$rfeature_adaptor->fetch_all_by_ResultSet_Slice($rset, $slice)};


=head1 DESCRIPTION

The ResultFeatureAdaptor is a database adaptor for storing and retrieving
ResultFeature objects.

=head1 LICENSE

  Copyright (c) 1999-2009 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <ensembl-dev@ebi.ac.uk>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.


=cut

use strict;
use warnings;

package Bio::EnsEMBL::Funcgen::DBSQL::ResultFeatureAdaptor;

use Bio::EnsEMBL::Utils::Exception qw( throw warning );
use Bio::EnsEMBL::Funcgen::ResultSet;
use Bio::EnsEMBL::Funcgen::ResultFeature;
use Bio::EnsEMBL::Funcgen::Collector::ResultFeature;
use Bio::EnsEMBL::Funcgen::DBSQL::BaseFeatureAdaptor;
use Bio::EnsEMBL::Funcgen::Utils::EFGUtils qw(mean median);

#New Collection config
use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Funcgen::DBSQL::BaseFeatureAdaptor Bio::EnsEMBL::Funcgen::Collector::ResultFeature);

#Have these here on in Collector?
#These are essentially constants for this instance of the Collector
#Defined like this as new will not be called in Collector
#Which ones of these can we remove/move to Collector/::ResultFeature?
#All if we provide methods for them?


#For max zoom out of 500kb, optimal size is 714, so we need a larger bin!
#We have lost a bin here, but probably okay
#@Bio::EnsEMBL::Funcgen::Collector::window_sizes   = (0, 150, 300, 450, 600, 750);
#This is now set via set_collection_defs_by_ResultSet

#Need to check how this looks

#Are we going to hit performance here as we may have to unpack a lot more data than we actually need
#These large blobs may only be efficient if we are going to use the majority of their contents
#(Will only ever use ~700 out of 8.3 million)
#i.e. store whole chr in one, or store smaller more useable chunks may twice the actual true max_bins?
#Maybe we can store in max chunks and detect which chunk we want to substr from
#Would have to handle overlapping slices.  This would require much more code but maybe a lot faster. 
#chr 1 is ~240 million bps = 29 records
#chr 21 has ~48 million bps = 6 records
#We need to test speed of substr near end of longblob!


#Max slice length is 1MB, max default bucket size is 1429bp
#which would be 14.29 probes. Not sensible to average ovr this region as we lose too much resolution.
#We should still turn the track off at a sensible limit as the peaks are just going to be 
#averaged away.

#Standard design is 50 bp every 100 bp.
#So 150 is two probes, this should be the first bin size with 0 being the probes themselves


#we're not guaranteed to get 2 in 150.
#May have one sat in the middle
#We really need to extend to extend by the probe length
#to capture overlapping probes. 
#Not a problem between windows, as we can compare start/ends and count on the fly
#Maybe would could just omit window_size and let the Collection handle that bit
#This would reduce the amount of data stored.


#The above is dependant on the result_set type, would be 4 byte float for chip chip!
#Move these vars to methods.  This means we can potentially have 3 locations for these 
#methods, BaseFeatureAdaptor, FeatureAdaptor and non-adaptor Collector.

#These are private vars use to trim the 
#start and end bins. These need to be set in each fetch method?
#Cannot depend on $dest_slice_start/end in _objs_from_sth
#As _collection_start/end are adjusted to the nearest bin
my ($_window_size, $_scores_field, $_collection_start, $_collection_end);
#probe query extension flag - can only do extension with probe/result/feature queries
my $_probe_extend = 0;
#Default is 1 so meta_coords get updated properly in _pre_store
#This is reset for every fetch method
my $_result_feature_set = 1;



=head2 _tables

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns the names and aliases of the tables to use for queries.
  Returntype : List of listrefs of strings
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _tables {
  my $self = shift;

  my @result_tables = ( ['result', 'r'], ['probe_feature', 'pf'] );
  push @result_tables, ( ['probe', 'p'] ) if $_probe_extend;
	
  return $_result_feature_set ? ( [ 'result_feature', 'rf' ] )
	: @result_tables;
}

=head2 _columns

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns a list of columns to use for queries.
  Returntype : List of strings
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _columns {
	my $self = shift;

	#This is dependent on whether result_set has 'result_feature' status.
	
	#No window_size as this is set as $_window_size
	my @result_columns = qw (r.score            pf.seq_region_start 
							 pf.seq_region_end  pf.seq_region_strand 
							 rsi.result_set_input_id);

	#Would need to re-add seq_region_id if we convert back to the standard hash based Feature


	if($_probe_extend){
	  #We can get this direct from the ProbeAdaptor
	  #Then we can use split/commodotised methods for generation of probe external to the ProbeAdaptor

	   push @result_columns, qw(p.probe_id  p.probe_set_id
								p.name            p.length
								p.array_chip_id    p.class);
	}
	elsif($_result_feature_set){

	  @result_columns = ('rf.seq_region_start', 'rf.seq_region_end', 'rf.seq_region_strand', "$_scores_field");
	}

	return @result_columns;
  }




=head2 _default_where_clause

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns an additional table joining constraint to use for
			   queries.
  Returntype : List of strings
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _default_where_clause{
  my $self = shift;

  return 'r.probe_id = p.probe_id' if $_probe_extend && ! $_result_feature_set;
}



=head2 _objs_from_sth

  Arg [1]    : DBI statement handle object
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Creates Array objects from an executed DBI statement
			   handle.
  Returntype : Listref of Bio::EnsEMBL::Funcgen::Experiment objects
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _objs_from_sth {
  my ($self, $sth, $mapper, $dest_slice) = @_;
  
  #Is $dest_slice always $_query_slice?
  #dest_slice is only ever passed for Slice based queries so yes?


  if(! $dest_slice){
	throw('ResultFeatureAdaptor always requires a dest_slice argument');
	#Is this correct?
	#ExperimentalChip based normalisation?
	#Currently does not use this method
	#Never have non-Slice based fetchs, so will always have dest_slice and seq_region info.
  }
  
  my (@rfeats, $start, $end, $strand, $scores);

  #Could dynamically define simple obj hash dependant on whether feature is stranded and new_fast?
  #We never call _obj_from_sth for extended queries
  #This is only for result_feature table queries i.e. standard/new queries

  $sth->bind_columns(\$start, \$end, \$strand, \$scores);

  


  #Test slice is loaded in eFG?
  my $slice_adaptor = $self->db->get_SliceAdaptor;
  
  if(! $slice_adaptor->get_seq_region_id($dest_slice)){
	warn "Cannot get eFG slice for:".$dest_slice->name.
	  "\nThe region you are using is not present in the current dna DB";
	return;
  }

  #my $asm_cs;
  #my $cmp_cs;
  #my $asm_cs_vers;
  #my $asm_cs_name;
  #my $cmp_cs_vers;
  #my $cmp_cs_name;

  if($mapper) {
	throw('Cannot dynamically assembly map Collections yet?');

	#This would require extra code from the GeneAdaptor

	#Actually maybe we can, so long as they map cleanly?

    #$asm_cs = $mapper->assembled_CoordSystem();
    #$cmp_cs = $mapper->component_CoordSystem();
    #$asm_cs_name = $asm_cs->name();
    #$asm_cs_vers = $asm_cs->version();
    #$cmp_cs_name = $cmp_cs->name();
    #$cmp_cs_vers = $cmp_cs->version();
  }

  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  my $dest_slice_sr_name;
  my $dest_slice_sr_id;

  #if($dest_slice) {
    $dest_slice_start  = $dest_slice->start();
    $dest_slice_end    = $dest_slice->end();
    $dest_slice_strand = $dest_slice->strand();
    $dest_slice_length = $dest_slice->length();
    $dest_slice_sr_name = $dest_slice->seq_region_name();
    $dest_slice_sr_id = $dest_slice->get_seq_region_id();
  #}

  
  my $collection_cnt = 0;
  my (@scores, $unpack_template, $over_hang, $num_bins);
  my ($slice, $start_pad, $end_pad, $tmp_pad);
  
  
  while ( $sth->fetch() ) {
	$start_pad = 0;
	$end_pad   = 0;

	#This test only works as $_window_size is always set in fetch methods?
	#undef if not specified (non-result_feature sets) or 0 for non-collected ResultFeatures

	if(! $_window_size || ! $_result_feature_set){
	  #Standard array method
	  #Change this to use Bio::EnsEMBL::Funcgen::Collection::ResultFeature
	  #With just 1 score in $scores
	  #0 wsize records are always have 1 score as we have the original start/ends


	  if($_result_feature_set){
		@scores = unpack($self->pack_template, $scores);

		#For array/intensity values here we need to convert them to
		#rounded up 3sigfig i.e. the same as the original was stored in
		#sprintf"%.3f",
		#this is somewhat costly :/

		#Is for loop faster here?
		#map $_=sprintf('%.3f', $_), @scores;

		#warn "sprintingf '%.3f' scores, this should be done in the caller, so we don't have to loop twice";

		#Yes, when modifying in place
		foreach my $score(@scores){
		  $score = sprintf('%.3f', $score);
		}

	  }
	 
	  #We need to modify the start ends here based on the query_slice!
	  #Is this not just dest slice?
	  #Maybe no if we are projecting
	  #Would only ever want to project 0 window level collections!
	  #And this is normally done via store method
	  #Don't really want to do this on the fly for display?

	  # If a destination slice was provided convert the coords
	  # If the dest_slice starts at 1 and is foward strand, nothing needs doing
	  # Need to do this for both single and multiple collections
	
	  #What about 0 strand slice?

	  #if($dest_slice) {#No Slice based methods
	  if($dest_slice_start != 1 || $dest_slice_strand != 1) {
		if($dest_slice_strand == 1) {
		  
		  $start = $start - $dest_slice_start + 1;
		  $end   = $end   - $dest_slice_start + 1;
		} else {
		  my $tmp_seq_region_start = $start;
		  $start = $dest_slice_end - $end + 1;
		  $end   = $dest_slice_end - $tmp_seq_region_start + 1;
		  $strand *= -1;
		}	  
	  }
	
	
	  #throw away features off the end of the requested slice or on different seq_region
	  if($end < 1 || $start > $dest_slice_length){# ||
		#( $dest_slice_sr_id ne $seq_region_id )) {
		#This would only happen if assembly mapper had placed it on a different seq_region
		#Dynamically mapped features are not guaranteed to come back in correct order?
	  
		next FEATURE;
	  }
	  
	  #$slice = $dest_slice;
	  #}
	}
	else{
	  #No need to do this trimming now as we always bring back only those scores we want
	  #What we actually need to do is figure out the true start and end of the collection
	  #with relation to the dest slice
	  $collection_cnt++;
	  
	  if($collection_cnt > 1){
		throw('ResultFeatureAdaptor does not support cross collection queries');
		#No way to determine correct $_collection_start/end if record does not begin at 1
		#fetch query also only specifies seq_region_id i.e. no seq_region_start/end clause
	  }

	  #Cannot have a collection which does not start at 1
	  #As we cannot compute the bin start/ends correctly?
	  #Actually we can do so long as they have been stored correctly
	  #i.e. start and end are valid bin bounds(extending past the end of the seq_region if needed)
	  #Let's keep it simple for now
	  throw("Collections with a window size > 0 must start at 1, not ($start)") if $start !=1;
	  #Can remove this if we test start and end are valid bin bounds for the given wsize

	  #Account for oversized slices
	  #This is if the slice seq_region_start/end are outside of the range of the record
	  #As collections should really represent a complete seq_region
	  #This should only happen if a slice is defined outside the the bounds of a seq_region
	  #i.e. seq_region_start < collection_start or seq_region_end > slice length
	  #if a test slice has been stored which does not represent the complete seq_region
	  	  #We don't need to pad at all, just adjust the $_collection_start/ends!!!
	  #Don't need to account for slice start < 1
	  #Start and end should always be valid bin bounds
	  #These could be removed if we force only full length seq_region collections
	  $_collection_start = $start if($_collection_start < $start);
	  $_collection_end   = $end   if($_collection_end   > $end);
	  
	  #warn "col start now $_collection_start";
	  #warn "col end   now $_collection_end";
	  
	  # If the dest_slice starts at 1 and is foward strand, nothing needs doing
	  # else convert coords
	  # These need to use $_collection_start/end rather than dest_slice_start/end

	  if($dest_slice_start != 1 || $dest_slice_strand != 1) {
		if($dest_slice_strand == 1) {
		  $start = $_collection_start - $dest_slice_start + 1;
		  $end   = $_collection_end   - $dest_slice_start + 1;
		} else {
		  my $tmp_seq_region_start = $_collection_start;
		  $start = $dest_slice_end - $_collection_end + 1;
		  $end   = $dest_slice_end - $tmp_seq_region_start + 1;
		  $strand *= -1;
		}	  
	  }
	  #What about 0 strand slices?
	  
	  #throw away features off the end of the requested slice or on different seq_region
	  if($end < 1 || $start > $dest_slice_length){# ||
		#( $dest_slice_sr_id ne $seq_region_id )) {
		#This would only happen if assembly mapper had placed it on a different seq_region
		#Dynamically mapped features are not guaranteed to come back in correct order?
		
		next FEATURE;
	  }
	  
	
	@scores = unpack('('.$self->pack_template.')'.((($_collection_end - $_collection_start + 1)/$_window_size)- $start_pad - $end_pad), $scores);
	}

	
	push @rfeats, Bio::EnsEMBL::Funcgen::Collection::ResultFeature->new_fast({
																			  start  => $start,
																			  end    => $end, 
																			  strand =>$strand, 
																			  scores => [@scores], 
																			  #undef, 
																			  #undef, 
																			  window_size => $_window_size, 
																			  slice       => $dest_slice,
																			 });

  }
  
  #reset for safety, altho this should be reset in fetch method
  $_result_feature_set = 1;
  
  #Need to return a params hash here:
  #window size
  #and ??? Caller should know all other 
  #params required i.e. collection type/methods
  return \@rfeats;
}
  

=head2 store

  Args[0]    : List of Bio::EnsEMBL::Funcgen::ResultFeature objects
  Args[1]    : Bio::EnsEMBL::Funcgen::ResultSet
  Args[2]    : Optional - Assembly to project to e.g. GRCh37
  Example    : $rfa->store(@rfeats);
  Description: Stores ResultFeature objects in the result_feature table.
  Returntype : None
  Exceptions : Throws if a List of ResultFeature objects is not provided or if
               any of the attributes are not set or valid.
  Caller     : General
  Status     : At Risk

=cut

sub store{
  my ($self, $rfeats, $rset, $new_assembly) = @_;

  #We can't project collections to a new assembly after they have been generated 
  #as this will mess up the standardised bin bounds.
  #Just project the 0 window size and then rebuild other window_sizes form there

  $self->set_collection_defs_by_ResultSet($rset);
  throw("Must provide a list of ResultFeature objects") if(scalar(@$rfeats == 0));
 
  #These are in the order of the ResultFeature attr array(excluding probe_id, which is the result/probe_feature query only attr))
  my $sth = $self->prepare('INSERT INTO result_feature (result_set_id, seq_region_id, seq_region_start, seq_region_end, seq_region_strand, window_size, scores) VALUES (?, ?, ?, ?, ?, ?, ?)');  
  my $db = $self->db();
  my ($pack_template, $packed_string);


  #We need to set $_result_feature_set here
  #So _pre_store uses the correct table name in meta_coord
  $_result_feature_set = 1;

  #my @max_allowed_packet = $self->dbc->db_handle->selectrow_array('show variables like "max_allowed_packet"');
  
  #warn "@max_allowed_packet";

 FEATURE: foreach my $rfeat (@$rfeats) {
    
    if( ! (ref($rfeat) && $rfeat->isa('Bio::EnsEMBL::Funcgen::Collection::ResultFeature'))) {
      throw('Must be a Bio::EnsEMBL::Funcgen::Collection::ResultFeature object to store');
    }
    
	#This is the only validation! So all the validation must be done in the caller as we are simply dealing with ints?
	#Remove result_feature_set from result_set and set as status?
	
	my $seq_region_id;
	($rfeat, $seq_region_id) = $self->_pre_store($rfeat, $new_assembly);

	next if ! $rfeat;#No projection to new assembly
	#Is there a way of logging which ones don't make it?

	#This captures non full length collections at end of seq_region
	$pack_template = '('.$self->pack_template.')'.scalar(@{$rfeat->scores});

	$packed_string = pack($pack_template, @{$rfeat->scores});	

	#use Devel::Size qw(size total_size);
	#warn "Storing ".$rfeat->result_set_id,' '.$seq_region_id.' '.$rfeat->start.' '.$rfeat->end.' '.$rfeat->strand,' ',$rfeat->window_size."\nWith packed string size:\t".size($packed_string);
	
	$sth->bind_param(1, $rfeat->result_set_id, SQL_INTEGER);
	$sth->bind_param(2, $seq_region_id,        SQL_INTEGER);
    $sth->bind_param(3, $rfeat->start,         SQL_INTEGER);
    $sth->bind_param(4, $rfeat->end,           SQL_INTEGER);
	$sth->bind_param(5, $rfeat->strand,        SQL_INTEGER);
	$sth->bind_param(6, $rfeat->window_size,   SQL_INTEGER);
	$sth->bind_param(7, $packed_string,        SQL_BLOB);
	#$sth->bind_param(7, pack($self->pack_template, @{$rfeat->scores}), SQL_BLOB);
	$sth->execute();
  }
  
  return $rfeats;
}

#This is next to useless in the context of ResultFeatures
=head2 list_dbIDs

  Args       : None
  Example    : my @rsets_ids = @{$rsa->list_dbIDs()};
  Description: Gets an array of internal IDs for all ResultFeature objects in
               the current database.
  Returntype : List of ints
  Exceptions : None
  Caller     : general
  Status     : stable

=cut

sub list_dbIDs {
	my $self = shift;
	
	return $self->_list_dbIDs('result_feature');
}



=head2 fetch_all_by_Slice_ResultSet

  Arg[0]     : Bio::EnsEMBL::Slice - Slice to retrieve results from
  Arg[1]     : Bio::EnsEMBL::Funcgen::ResultSet - ResultSet to retrieve results from
  Arg[2]     : optional string - STATUS e.g. 'DIPLAYABLE'
  Example    : my @rfeatures = @{$rsa->fetch_ResultFeatures_by_Slice_ResultSet($slice, $rset, 'DISPLAYABLE')};
  Description: Gets a list of lightweight ResultFeatures from the ResultSet and Slice passed.
               Replicates are combined using a median of biological replicates based on 
               their mean techinical replicate scores
  Returntype : List of Bio::EnsEMBL::Funcgen::ResultFeature
  Exceptions : Warns if not experimental_chip ResultSet
               Throws if no Slice passed
               Warns if 
  Caller     : general
  Status     : At risk

=cut

sub fetch_all_by_Slice_ResultSet{
  my ($self, $slice, $rset, $ec_status, $with_probe, $max_bins, $window_size, $constraint) = @_;
  #Change to params hash?
  #add option to force probe_feature based retrieval?

  if(! (ref($slice) && $slice->isa('Bio::EnsEMBL::Slice'))){
	throw('You must pass a valid Bio::EnsEMBL::Slice');
  }

  $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::ResultSet', $rset);

  if($rset->table_name eq 'channel'){
	warn('Can only get ResultFeatures for an ExperimentalChip level ResultSet');
	return;
  }

  #Set temp global private vars for use in _obj_from_sth
  $_result_feature_set = $rset->has_status('RESULT_FEATURE_SET');
  #Just test for table_name eq input_set too?
  #This will save a query
  #We need to set this for all InputSets? Or just ID that it is an InputSet?
  $_probe_extend       = $with_probe if defined $with_probe;
  undef $_window_size; #Clean this from the last query 

  #warn "hardcoding for result feature set = 0";#and wsize==0";
  #$_result_feature_set = 0;
  #$window_size = 0;


  if($_result_feature_set){

	if($_probe_extend){
	  throw("Cannot retrieve Probe information from a RESULT_FEATURE_SET query");
	}

	#Set the pack size and template for _obj_from_sth
	$self->set_collection_defs_by_ResultSet($rset);

	if($window_size && $max_bins){
	  warn "Over-riding max_bins with specific window_size, omit window_size to calculate window_size using max_bins";
	}

	my @sizes = @{$self->window_sizes};
	#we need to remove wsize 0 if ResultSet was generated from high density seq reads
	#0 should always be first
	shift @sizes if ($sizes[0] == 0 && ($rset->table_name eq 'input_set'));
	$max_bins ||= 700;#This is default size of display?
	
	#The speed of this track is directly proportional
	#to the display size, unlike other tracks!
	#e.g
	#let's say we have 300000bp
	#700  pixels will use 450 wsize > Faster but lower resolution
	#2000 pixels will use 150 wsize > Slower but higher resolution

	if(defined $window_size){

	  if(! grep(/^${window_size}$/, @sizes)){
		warn "The ResultFeature window_size specifed($window_size) is not valid, the next largest will be chosen from:\t".join(', ', @sizes);
	  }
	  else{
		$_window_size = $window_size;
	  }
	}
	else{#! defined $window_size
	  
	  #Work out window size here based on Slice length
	  #Select 0 wsize if slice is small enough
	  #As loop will never pick 0
	  #probably half 150 max length for current wsize
	  #Will also be proportional to display size
	  #This depends on size ordered window sizes arrays

	  $window_size = ($slice->length)/$max_bins;

	  if($rset->table_name ne 'input_set'){
		my $zero_wsize_limit = ($max_bins * $sizes[1])/2;

		if($slice->length <= $zero_wsize_limit){
		  $_window_size = 0;
		}
	  }
	} 
	
	#Let's try and avoid this loop if we have already grep'd or set to 0
	#In the browser this is only ever likely to speed up the 0 window
	
	if(! defined $_window_size){
	  #default is maximum
	  $_window_size = $sizes[$#sizes];

	  #Try and find the next biggest window
	  #As we don't want more bins than there are pixels
	  for (my $i = 0; $i <= $#sizes; $i++) {
		#We have problems here if we want to define just one window size
		#In the store methods, this reset the wsizes so we can only pick from those
		#specified, hence we cannot force the use of 0
		#@sizes needs to always be the full range of valid windows sizes
		#Need to always add 0 and skip_zero window if 0 not defined in window_sizes?
	  
		if ($window_size <= $sizes[$i]){
		  $_window_size = $sizes[$i];
		  last;    
		}
	  }
	}

	#warn "wsize is $_window_size";

	$constraint .= ' AND ' if defined $constraint;
	$constraint .= 'rf.result_set_id='.$rset->dbID.' and rf.window_size='.$_window_size;


	#Finally set scores field
	if($_window_size == 0){
	  $_scores_field = 'rf.scores';
	}else{
	  #We want a substring of a whole seq_region collection

	  #Correct to the nearest bin bounds	  
	  #int rounds towards 0, not always down!
	  #down if +ve or up if -ve
	  #This causes problems with setting start as we round up to zero

	  my $start_bin      = $slice->start/$_window_size;
	  $_collection_start = int($slice->start/$_window_size);

	  if($_collection_start < $start_bin){
		$_collection_start +=1;#Add 1 to the bin due to int rounding down
	  }
	  	  
	  $_collection_start = ($_collection_start * $_window_size) - $_window_size + 1 ;#seq_region
	  #Need to sub this?
	  #warn 'collection start is '.$_collection_start;

	  $_collection_end   = int($slice->end/$_window_size) * $_window_size;#This will be <= $slice->end

	  #Add another window if the end doesn't meet the end of the slice
	  if(($_collection_end > 0) &&
		 ($_collection_end < $slice->end)){
		$_collection_end += $_window_size;
	  }
	  #warn "collection end = $_collection_end";
	


 
	  #Now correct for packed size
	  #Substring on a blob returns bytes not 2byte ascii chars!
	  #start at the first char of the first bin
	  my $sub_start = (((($_collection_start - 1)/$_window_size) * $self->packed_size) + 1);#add first char
	  #Default to 1 as mysql substring starts < 1 do funny things
	  $sub_start = 1 if $sub_start < 1;
	  
	  #Don't need to handle end overhang as substring automatically trims
	  #my $sub_end = $_collection_end;
	  #if($_collection_end > $slice->adaptor->fetch_by_name(undef, $slice->seq_region_name)->end){
	  my $sub_end   = (($_collection_end/$_window_size) * ($self->packed_size));
	  

	  #Finally set scores column for fetch
	  $_scores_field = "substring(rf.scores, $sub_start, $sub_end)";
	  #We could set pack template here with ($sub_end-$sub_start+1)/$self->packed_size	  
	  #warn $_scores_field;
	}

	return [$self->fetch_all_by_Slice_constraint($slice, $constraint),  {window_size => $_window_size}];
  }


  #This is the old method from ResultSetAdaptor
  #warn "Using non-RESULT_FEATURE_SET probe/result method";


 
  my (@rfeatures, %biol_reps, %rep_scores, @filtered_ids);
  my ($biol_rep, $score, $start, $end, $strand, $cc_id, $old_start, $old_end, $probe_field, $old_strand);


  my ($padaptor, $probe, $array,);
  my ($probe_id, $probe_set_id, $pname, $plength, $arraychip_id, $pclass, $probeset);
  my (%array_cache, %probe_set_cache, $ps_adaptor, $array_adaptor);

  my $ptable_syn = '';
  my $pjoin = '';
  my $pfields = '';

  #This with probe function should now needs to be limited to the lowest window size

  if($with_probe){
	#This would be in BaseAdaptor? or core DBAdaptor?
	#This would work on assuming that the default foreign key would be the primary key unless specified
	
	#my($table_info, $fields, $adaptor) = @{$self->validate_and_get_join_fields('probe')};
	$padaptor = $self->db->get_ProbeAdaptor;
	$ps_adaptor = $self->db->get_ProbeSetAdaptor;
	$array_adaptor = $self->db->get_ArrayAdaptor;


	#This would return table and syn and syn.fields
	#Would also need access to obj_from_sth_values
	#could return code ref or adaptor
	$ptable_syn = ', probe p';
	
	#Some of these will be redundant: probe_id
	#Can we remove the foreign key from the returned fields?
	#But we need it here as it isn't being returned
	$pfields =  ', p.probe_id, p.probe_set_id, p.name, p.length, p.array_chip_id, p.class ';
  
	#will this make a difference if we join on pf instead of r?
	$pjoin = ' AND r.probe_id = p.probe_id ';
  }

  
  my @ids = @{$rset->table_ids()};
  #should we do some more optimisation of method here if we know about presence or lack or replicates?


  if($ec_status){
    @filtered_ids = @{$self->status_filter($ec_status, 'experimental_chip', @ids)};

    if(! @filtered_ids){

      warn("No ExperimentalChips have the $ec_status status, No ResultFeatures retrieved");
      return \@rfeatures;
    }
  }


  #we need to build a hash of cc_id to biolrep value
  #Then we use the biolrep as a key, and push all techrep values.
  #this can then be resolved in the method below, using biolrep rather than cc_id


  my $sql = "SELECT ec.biological_replicate, rsi.result_set_input_id from experimental_chip ec, result_set_input rsi 
             WHERE rsi.table_name='experimental_chip'
             AND ec.experimental_chip_id=rsi.table_id
             AND rsi.table_id IN(".join(', ', (map $_->dbID(), @{$rset->get_ExperimentalChips()})).")";

  
 # warn $sql;
  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->bind_columns(\$biol_rep, \$cc_id);
  #could maybe do a selecthashref here?

  while($sth->fetch()){
	$biol_rep ||= 'NO_REP_SET';

	$biol_reps{$cc_id} = $biol_rep;
  }

  if(grep(/^NO_REP_SET$/, values %biol_reps)){
	warn 'You have ExperimentalChips with no biological_replicate information, these will be all treated as one biological replicate';
  }

  #we don't need to account for strnadedness here as we're dealing with a double stranded feature
  #need to be mindful if we ever consider expression
  #we don't need X Y here, as X Y for probe will be unique for cc_id.
  #any result with the same cc_id will automatically be treated as a tech rep

 
  #This does not currently handle multiple CSs i.e. level mapping
  my $mcc =  $self->db->get_MetaCoordContainer();
  my $fg_cs = $self->db->get_FGCoordSystemAdaptor->fetch_by_name(
																$slice->coord_system->name(), 
																$slice->coord_system->version()
																);

  my $max_len = $mcc->fetch_max_length_by_CoordSystem_feature_type($fg_cs, 'probe_feature');

 

 #This join between sr and pf is causing the slow down.  Need to select right join for this.
  #just do two separate queries for now.

  #$sql = "SELECT seq_region_id from seq_region where core_seq_region_id=".$slice->get_seq_region_id().
  #	" AND schema_build='".$self->db->_get_schema_build($slice->adaptor->db())."'";

  #my ($seq_region_id) = $self->db->dbc->db_handle->selectrow_array($sql);


  
  #This by passes fetch_all_by_Slice_constraint
  #So we need to build the seq_region_cache here explicitly.
  $self->build_seq_region_cache($slice);
  my $seq_region_id = $self->get_seq_region_id_by_Slice($slice);


  if(! $seq_region_id){
	#We have tried to access a slice which has not been stored in the funcgen DB
	return [];
  }

  #Can we push the median calculation onto the server?
  #group by pf.seq_region_start?
  #will it always be a median?


  $sql = 'SELECT STRAIGHT_JOIN r.score, pf.seq_region_start, pf.seq_region_end, pf.seq_region_strand, rsi.result_set_input_id '.$pfields.
	' FROM probe_feature pf, result r, result_set_input rsi '.$ptable_syn.' WHERE rsi.result_set_id = '. $rset->dbID();
	#' FROM probe_feature pf, '.$rset->get_result_table().' r, chip_channel cc '.$ptable_syn.' WHERE cc.result_set_id = '.
	  $rset->dbID();

  $sql .= ' AND rsi.table_id IN ('.join(' ,', @filtered_ids).')' if ((@filtered_ids != @ids) && $ec_status);


  $sql .= ' AND rsi.result_set_input_id = r.result_set_input_id'.
	' AND r.probe_id=pf.probe_id'.$pjoin.
	  ' AND pf.seq_region_id='.$seq_region_id.
		' AND pf.seq_region_start<='.$slice->end();
  
  if($max_len){
	my $start = $slice->start - $max_len;
	$start = 0 if $start < 0;
	$sql .= ' AND pf.seq_region_start >= '.$start;
  }

  $sql .= ' AND pf.seq_region_end>='.$slice->start().
	' ORDER by pf.seq_region_start'; #do we need to add probe_id here as we may have probes which start at the same place

  #can we resolves replicates here by doing a median on the score and grouping by cc_id some how?
  #what if a probe_id is present more than once, i.e. on plate replicates?

  #To extend this to perform median calculation we'd have to group by probe_id, and ec.biological_replicate
  #THen perform means across biol reps.  This would require nested selects 
  #would this group correctly on NULL values if biol rep not set for a chip?
  #This would require an extra join too. 

  #warn "$sql";

  $sth = $self->prepare($sql);
  $sth->execute();
  
  if($with_probe){
	$sth->bind_columns(\$score, \$start, \$end, \$strand, \$cc_id, \$probe_id, \$probe_set_id, 
					   \$pname, \$plength, \$arraychip_id, \$pclass);
  }
  else{
	$sth->bind_columns(\$score, \$start, \$end, \$strand, \$cc_id);
  }
  my $position_mod = $slice->start() - 1;
  

  my $new_probe = 0;
  my $first_record = 1;


  while ( $sth->fetch() ) {

    #we need to get best result here if start and end the same
    #set start end for first result
    $old_start ||= $start;
    $old_end   ||= $end;
	$old_strand||= $strand;
    

	#This is assuming that a feature at the exact same locus is from the same probe
	#This may not be correct and will collapse probes with same sequence into one ResultFeature
	#This is okay for analysis purposes, but obscures the probe to result relationship
	#we arguably need to implement r.probe_id check here for normal ResultFeatures

    if(($start == $old_start) && ($end == $old_end)){#First result and duplicate result for same feature?

	  #only if with_probe(otherwise we have a genuine on plate replicate)
	  #if probe_id is same then we're just getting the extra probe for a different array?
	  #cc_id might be different for same probe_id?

	  #How can we differentiate between an on plate replicate and just the extra probe records?
	  #If array_chip_id is the same?  If it is then we have an on plate replicate (differing x/y vals in result)
	  #Otherwise we know we're getting another probe record from a different Array/ArrayChip.
	  #It is still possible for the extra probe record on a different ArrayChip to have a result, 
	  #the cc_id would be different and would be captured?
	  #This would still be the same probe tho, so still one RF

	  #When do we want to split?
	  #If probe_id is different...do we need to order by probe_id?	  
	  #probe will never be defined without with_probe
	  #so can omit from test

	  if(defined $probe && ($probe->dbID != $probe_id)){
		$new_probe = 1;
	  }
	  else{
		push @{$rep_scores{$biol_reps{$cc_id}}}, $score;
	  }
    }
	else{#Found new location
	  $new_probe = 1;
	}

	if($new_probe){
	  #store previous feature with best result from @scores
		#Do not change arg order, this is an array object!!


	  push @rfeatures, Bio::EnsEMBL::Funcgen::Collection::ResultFeature->new_fast
		({
		  start  => ($old_start - $position_mod), 
		  end    => ($old_end - $position_mod),
		  strand => $old_strand,
		  scores => [$self->resolve_replicates_by_ResultSet(\%rep_scores, $rset)],
		  probe       => $probe, 
		  #undef, 
		  window_size => 0,
		 });
	
	 
	  undef %rep_scores;
	  $old_start = $start;
      $old_end = $end;
	  
      #record new score

	  @{$rep_scores{$biol_reps{$cc_id}}} = ($score);
	}

	if($with_probe){

	  #This would be done via the ProbeAdaptor->obj_from_sth_values
	  #We need away ti maintain the Array/ProbeSet caches in obj_from_sth fetch
	  #Pulling into an array would increase memory usage over the fetch loop
	  #Can we maintain an object level cache which we would then have to reset?
	  #Wouldn't be the end of the world if it wasn't, but would use memory

	  
	  #This is recreating the Probe->_obj_frm_sth
	  #We need to be mindful that we can get multiple records for a probe
	  #So we need to check whether the probe_id is the same
	  #It may be possible to get two of the same probes contiguously
	  #So we would also have to check on seq_region_start

	  #Do we really need to set these?
	  #We are getting the advantage that we're cacheing
	  #Rather than a fetch for each object
	  #But maybe we don't need this information?
	  #Can we have two mode for obj_from_sth?

	  $array = $array_cache{$arraychip_id} || $self->db->get_ArrayAdaptor()->fetch_by_array_chip_dbID($arraychip_id);

	  if($probe_set_id){
		$probeset = $probe_set_cache{$probe_set_id} || $self->db->get_ProbeSetAdaptor()->fetch_by_dbID($probe_set_id);
	  }


	  if($first_record || $new_probe){

		$probe = Bio::EnsEMBL::Funcgen::Probe->new
			  (
			   -dbID          => $probe_id,
			   -name          => $pname,
			   -array_chip_id => $arraychip_id,
			   -array         => $array,
			   -probe_set     => $probeset,
			   -length        => $plength,
			   -class         => $pclass,
			   -adaptor       => $padaptor,
			);

	  } 
	  else {
		# Extend existing probe
		$probe->add_array_chip_probename($arraychip_id, $pname, $array);
	  }
	}

	$new_probe = 0;
	$first_record = 0;
  }
  
  #store last feature  
  #Do not change arg order, this is an array object!!
  #only if found previosu results
  if($old_start){
    push @rfeatures, Bio::EnsEMBL::Funcgen::Collection::ResultFeature->new_fast
      ({
		start  => ($old_start - $position_mod), 
		end    => ($old_end - $position_mod),
		strand => $old_strand,
		scores => [$self->resolve_replicates_by_ResultSet(\%rep_scores, $rset)],
		probe  => $probe, 
		#undef, 
		window_size => 0,
	   });
	
	#(scalar(@scores) == 0) ? $scores[0] : $self->_get_best_result(\@scores)]);
  }
  
  return [\@rfeatures,  {window_size => 0}];
}





=head2 resolve_replicates_by_ResultSet

  Arg[0]     : HASHREF - result_set_input_id => @scores pairs
  #Arg[1]     : Bio::EnsEMBL::Funcgen::ResultSet - ResultSet to retrieve results from
  Example    : my @rfeatures = @{$rsa->fetch_ResultFeatures_by_Slice_ResultSet($slice, $rset, 'DISPLAYABLE')};
  Description: Gets a list of lightweight ResultFeatures from the ResultSet and Slice passed.
               Replicates are combined using a median of biological replicates based on 
               their mean techinical replicate scores
  Returntype : List of Bio::EnsEMBL::Funcgen::ResultFeature
  Exceptions : None
  Caller     : general
  Status     : At risk

=cut


#this may be done better inline rather than sub'd as we're going to have to rebuild the duplicate data each time?
#Rset should return a hash of cc_ids keys with replicate name values.
#these can then beused to build replicate name keys, with an array technical rep score values.
#mean each value then give median of all.


sub resolve_replicates_by_ResultSet{
  my ($self, $rep_ref) = @_;#, $rset) = @_;

  my ($score, @scores, $biol_rep);

  #deal with simplest case first and fastest?
  #can we front load this with the replicate set info, i.e. if we know we only have one then we don't' have to do all this testing and can do a mean

  if(scalar(keys %{$rep_ref}) == 1){
	
	($biol_rep) = keys %{$rep_ref};

	@scores = @{$rep_ref->{$biol_rep}};

	if (scalar(@scores) == 1){
	  $score = $scores[0];
	}else{
	  $score = mean(\@scores)
	}
  }else{#deal with biol replicates

	foreach $biol_rep(keys %{$rep_ref}){
	  push @scores, mean($rep_ref->{$biol_rep});
	}

	@scores = sort {$a<=>$b} @scores;

	$score = median(\@scores);

  }

  return $score;
}


=head2 fetch_results_by_probe_id_ResultSet

  Arg [1]    : int - probe dbID
  Arg [2]    : Bio::EnsEMBL::Funcgen::ResultSet
  Example    : my @probe_results = @{$ofa->fetch_results_by_ProbeFeature_ResultSet($pid, $result_set)};
  Description: Gets result for a given probe in a ResultSet
  Returntype : ARRAYREF
  Exceptions : throws if args not valid
  Caller     : General
  Status     : At Risk - Change to take Probe?

=cut

sub fetch_results_by_probe_id_ResultSet{
  my ($self, $probe_id, $rset) = @_;
  
  throw("Need to pass a valid stored Bio::EnsEMBL::Funcgen::ResultSet") if (! ($rset  &&
									       $rset->isa("Bio::EnsEMBL::Funcgen::ResultSet")
									       && $rset->dbID()));
  
  throw('Must pass a probe dbID') if ! $probe_id;
  
  
  
  my $cc_ids = join(',', @{$rset->result_set_input_ids()});

  my $query = "SELECT r.score from result r where r.probe_id ='${probe_id}'".
    " AND r.result_set_input_id IN (${cc_ids}) order by r.score;";

  #without a left join this will return empty results for any probes which may have been remapped 
  #to the a chromosome, but no result exist for a given set due to only importing a subset of
  #a vendor specified mapping


  #This converts no result to a 0!

  my @results = map $_ = "@$_", @{$self->dbc->db_handle->selectall_arrayref($query)};
  

  return \@results;
}





1;

