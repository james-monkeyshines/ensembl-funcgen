#
# Ensembl module for Bio::EnsEMBL::DBSQL::Funcgen::MotifFeatureAdaptor
#
#

=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

Bio::EnsEMBL::Funcgen::DBSQL::MotifFeatureAdaptor - A database adaptor for fetching and
storing MotifFeature objects.

=head1 SYNOPSIS

my $mfa = $db->get_MotifFeatureAdaptor();

my @mfeatures = @{$mfa->fetch_all_by_Slice_Epigenome($slic, $epigenome)};


=head1 DESCRIPTION

The MotifFeatureAdaptor is a database adaptor for storing and retrieving
MotifFeature objects.


=head1 SEE ALSO

Bio::EnsEMBL::Funcgen::MotifFeature



=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.


=cut

package Bio::EnsEMBL::Funcgen::DBSQL::MotifFeatureAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw( throw warning deprecate );
use Bio::EnsEMBL::Funcgen::MotifFeature;
use Bio::EnsEMBL::Funcgen::DBSQL::BaseFeatureAdaptor;#DBI sql_types import

use base qw( Bio::EnsEMBL::Funcgen::DBSQL::BaseFeatureAdaptor );

my $true_final_clause = ' ORDER by mf.seq_region_id, mf.seq_region_start, mf.seq_region_end';
# ORDER by required by fetch_all_by_dbID_list when fetching as regulatory_attributes
# was '' to avoid use of undef warning from BaseAdaptor
my $final_clause = $true_final_clause;


# =head2 fetch_all_by_AnnotatedFeature
# 
#   Arg [1]    : Bio::EnsEMBL::AnnotatedFeature
#   Arg [2]    : optional - Bio::EnsEMBL::Slice
#   Example    : my $features = $ofa->fetch_all_by_AnnotatedFeature($af);
#   Description: Retrieves a list of all MotifFeatures linked to the given
#                AnnotatedFeature
#   Returntype : Listref of Bio::EnsEMBL::Funcgen::MotifFeature objects
#   Exceptions : Throws if AnnotatedFeature not stored and valid
#   Caller     : General
#   Status     : At Risk
# 
# =cut
# 
# sub fetch_all_by_AnnotatedFeature {
#   my ($self, $feature, $slice) = @_;
# 
#   $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::AnnotatedFeature', $feature);
# 
#   #Extend query tables
#   $self->_tables([['associated_motif_feature', 'amf']]);
#   my $constraint = 'mf.motif_feature_id = amf.motif_feature_id AND amf.annotated_feature_id=?';
#   #No need for group here as we are restricting to one af
# 
#   $self->bind_param_generic_fetch($feature->dbID, SQL_INTEGER);
# 
#   my $mfs = $self->generic_fetch($constraint, undef, $slice);
#   $self->reset_true_tables;
# 
#   return $mfs;
# }


=head2 fetch_all_by_Slice_Epigenome

  Arg [1]    : Bio::EnsEMBL::Slice
  Arg [2]    : Bio::EnsEMBL::Funcgen::Epigenome
  #Arg [3]    : (optional) string - type e.g. Jaspar/Inferred
  Example    : my $slice = $sa->fetch_by_region('chromosome', '1');
               my $features = $ofa->fetch_all_by_Slice_Epigenome($slice, $epigenome);
  Description: Retrieves a list of features on a given slice, specific for a given Epigenome.
  Returntype : Listref of Bio::EnsEMBL::MotifFeature objects
  Exceptions : Throws if Epigenome is not valid
  Caller     : General
  Status     : 

=cut

sub fetch_all_by_Slice_Epigenome {

  my ($self, $slice, $epigenome, $type) = @_;

  #could add logic_name here for motif mapper analysis, motif source analysis
  $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::Epigenome', $epigenome);

  #Extend query tables
  $self->_tables([['feature_set', 'fs'],
                  ['associated_motif_feature', 'amf'],
                  ['annotated_feature', 'af']]);

  my $constraint = 'mf.motif_feature_id = amf.motif_feature_id AND '.
  'amf.annotated_feature_id=af.annotated_feature_id and '.
    'af.feature_set_id=fs.feature_set_id AND fs.epigenome_id = ?';

  #Group here as the mf may be linked to multiple afs
  $final_clause = ' GROUP BY mf.motif_feature_id';


  $self->bind_param_generic_fetch( $epigenome->dbID(), SQL_INTEGER);
  my $mfs = $self->SUPER::fetch_all_by_Slice_constraint($slice, $constraint);
  $self->reset_true_tables;
  $final_clause = $true_final_clause;

  return $mfs;
}

=head2 fetch_all_by_Slice_BindingMatrix

  Arg [1]    : Bio::EnsEMBL::Slice
  Arg [2]    : Bio::EnsEMBL::Funcgen::BindingMatrix
  #Arg [3]    : (optional) string - type e.g. Jaspar/Inferred
  Example    : my $slice = $sa->fetch_by_region('chromosome', '1');
               my $features = $ofa->fetch_all_by_Slice_BindingMatric($slice, $bm);
  Description: Retrieves a list of features on a given slice, specific for a given BindingMatrix.
  Returntype : Listref of Bio::EnsEMBL::MotifFeature objects
  Exceptions : Throws if BindinMatrix is not valid
  Caller     : General
  Status     : At Risk - implement/change type to Analysis

=cut

sub fetch_all_by_Slice_BindingMatrix {
  my ($self, $slice, $bm, $type) = @_;

  #could add logic_name here for motif mapper analysis, motif source analysis
  $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::BindingMatrix', $bm);

  my $constraint = 'mf.binding_matrix_id = ?';

  $self->bind_param_generic_fetch( $bm->dbID(), SQL_INTEGER);
  my $mfs = $self->SUPER::fetch_all_by_Slice_constraint($slice, $constraint);
  $self->reset_true_tables;

  return $mfs;
}


=head2 fetch_all_by_Slice_FeatureSets

  Arg [1]    : Bio::EnsEMBL::Slice
  Arg [2]    : arrayref of Bio::EnsEMBL::Funcgen::FeatureSet objects
  #Arg [3]    : (optional) string - type e.g. Jaspar/Inferred
  Example    : my $slice = $sa->fetch_by_region('chromosome', '1');
               my $features = $ofa->fetch_all_by_Slice_FeatureSet($slice, $fset);
  Description: Retrieves a list of features on a given slice, specific for a given FeatureSet.
  Returntype : Listref of Bio::EnsEMBL::MotifFeature objects
  Exceptions : Throws if FeatureSet is not valid
  Caller     : General
  Status     : At Risk - implement/change type to Analysis

=cut

sub fetch_all_by_Slice_FeatureSets {
  my ($self, $slice, $fsets, $type) = @_;

  #could add logic_name here for motif mapper analysis, motif source analysis
  #$self->db->are_stored_and_valid('Bio::EnsEMBL::Funcgen::FeatureSet', $fsets);
  foreach my $fset (@$fsets){
    $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::FeatureSet', $fset);
  }

  #Extend query tables
  $self->_tables([['associated_motif_feature', 'amf'], ['annotated_feature', 'af']]);

  my $constraint = 'mf.motif_feature_id = amf.motif_feature_id AND '.
	'amf.annotated_feature_id=af.annotated_feature_id and af.feature_set_id IN('.join(',', (map $_->dbID, @$fsets)).')';
  #Can't bind_param in lists

  #Group here as the mf may be linked to multiple afs across fsets
  $final_clause = ' GROUP BY mf.motif_feature_id';

  my $mfs = $self->SUPER::fetch_all_by_Slice_constraint($slice, $constraint);
  $self->reset_true_tables;
  $final_clause = $true_final_clause;

  return $mfs;
}

=head2 _fetch_overlapping_Peak

  Arg [1]    : Bio::EnsEMBL::Funcgen::MotifFeature
  Example    : None
  Description: Fetches the overlapping Peak for a particular MotifFeature
  Returntype : Bio::EnsEMBL::Funcgen::Peak object
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _fetch_overlapping_Peak {
    my ( $self, $motif_feature ) = @_;

    if (! defined $motif_feature){
      throw('Must provide a MotifFeature parameter');
    }

    my $sth = $self->prepare( "
      SELECT peak_id FROM motif_feature_peak
      WHERE motif_feature_id=?
      " );

    $sth->execute( $motif_feature->dbID() );

    my @peak_ids;

    while ( my @row = $sth->fetchrow_array ) {
        push @peak_ids, $row[0];
    }

    my $peak_adaptor
        = $self->db->get_adaptor('Peak');

    my @peaks;

    for my $id (@peak_ids) {
        push @peaks, $peak_adaptor->fetch_by_dbID($id);
    }

    return $peaks[0];
}


=head2 _final_clause

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns an ORDER BY clause. Sorting by probe_feature_id would be
			   enough to eliminate duplicates, but sorting by location might
			   make fetching features on a slice faster.
  Returntype : String
  Exceptions : None
  Caller     : generic_fetch
  Status     : At Risk

=cut

sub _final_clause {
	return $final_clause;
}


=head2 _true_tables

  Args       : None
  Example    : None
  Description: Returns the names and aliases of the tables to use for queries.
  Returntype : List of listrefs of strings
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _true_tables {
  return (['motif_feature', 'mf']);
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
  return qw(
			mf.motif_feature_id   mf.seq_region_id
			mf.seq_region_start   mf.seq_region_end
			mf.seq_region_strand  mf.binding_matrix_id
			mf.display_label      mf.score
			mf.interdb_stable_id
		   );
}



=head2 _objs_from_sth

  Arg [1]    : DBI statement handle object
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Creates MotifFeature objects from an executed DBI statement
			   handle.
  Returntype : Listref of Bio::EnsEMBL::MotifFeature objects
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _objs_from_sth {
	my ($self, $sth, $mapper, $dest_slice) = @_;

	my $sa = $self->db->dnadb->get_SliceAdaptor();
	my $bm_adaptor = $self->db->get_BindingMatrixAdaptor();
	my (@features, %bm_hash,
      %slice_hash, %sr_name_hash, %sr_cs_hash);

	my ($motif_feature_id,  $seq_region_id,
	    $seq_region_start,  $seq_region_end,
	    $seq_region_strand, $bm_id,
      $display_label,     $score,
      $stable_id);

	$sth->bind_columns(\$motif_feature_id,  \$seq_region_id,
                     \$seq_region_start,  \$seq_region_end,
                     \$seq_region_strand, \$bm_id,
                     \$display_label,     \$score,
                     \$stable_id);

	my ($asm_cs, $cmp_cs, $asm_cs_name, $asm_cs_vers, $cmp_cs_name, $cmp_cs_vers);

	if ($mapper) {
		$asm_cs      = $mapper->assembled_CoordSystem();
		$cmp_cs      = $mapper->component_CoordSystem();
		$asm_cs_name = $asm_cs->name();
		$asm_cs_vers = $asm_cs->version();
		$cmp_cs_name = $cmp_cs->name();
		$cmp_cs_vers = $cmp_cs->version();
	}

	my ($dest_slice_start, $dest_slice_end, $dest_slice_strand,
      $dest_slice_length, $dest_slice_sr_name, $slice, $sr_name, $sr_cs);

	if ($dest_slice) {
		$dest_slice_start   = $dest_slice->start();
		$dest_slice_end     = $dest_slice->end();
		$dest_slice_strand  = $dest_slice->strand();
		$dest_slice_length  = $dest_slice->length();
		$dest_slice_sr_name = $dest_slice->seq_region_name();
	}

 FEATURE: while ( $sth->fetch() ) {
	  #Get the BindingMatrix object
	  $bm_hash{$bm_id} = $bm_adaptor->fetch_by_dbID($bm_id) if(! exists $bm_hash{$bm_id});


	  # Get the slice object
	  $slice = $slice_hash{'ID:'.$seq_region_id};

	  if (! $slice) {
      $slice                            = $sa->fetch_by_seq_region_id($seq_region_id);
      $slice_hash{'ID:'.$seq_region_id} = $slice;
      $sr_name_hash{$seq_region_id}     = $slice->seq_region_name();
      $sr_cs_hash{$seq_region_id}       = $slice->coord_system();
	  }

	  $sr_name = $sr_name_hash{$seq_region_id};
	  $sr_cs   = $sr_cs_hash{$seq_region_id};

	  # Remap the feature coordinates to another coord system if a mapper was provided
	  if ($mapper) {
	  return [];
      throw("Not yet implmented mapper, check equals are Funcgen calls too!");

      ($sr_name, $seq_region_start, $seq_region_end, $seq_region_strand)
        = $mapper->fastmap($sr_name, $seq_region_start, $seq_region_end, $seq_region_strand, $sr_cs);

      # Skip features that map to gaps or coord system boundaries
      next FEATURE if ! defined $sr_name;

      # Get a slice in the coord system we just mapped to
      if ( $asm_cs == $sr_cs || ( $cmp_cs != $sr_cs && $asm_cs->equals($sr_cs) ) ) {
        $slice = $slice_hash{"NAME:$sr_name:$cmp_cs_name:$cmp_cs_vers"}
          ||= $sa->fetch_by_region($cmp_cs_name, $sr_name, undef, undef, undef, $cmp_cs_vers);
      } else {
        $slice = $slice_hash{"NAME:$sr_name:$asm_cs_name:$asm_cs_vers"}
          ||= $sa->fetch_by_region($asm_cs_name, $sr_name, undef, undef, undef, $asm_cs_vers);
      }
	  }

	  # If a destination slice was provided convert the coords
	  # If the destination slice starts at 1 and is forward strand, nothing needs doing
	  if ($dest_slice) {

      unless ($dest_slice_start == 1 && $dest_slice_strand == 1) {
        if ($dest_slice_strand == 1) {
          $seq_region_start = $seq_region_start - $dest_slice_start + 1;
          $seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
        } else {
          my $tmp_seq_region_start = $seq_region_start;
          $seq_region_start        = $dest_slice_end - $seq_region_end       + 1;
          $seq_region_end          = $dest_slice_end - $tmp_seq_region_start + 1;
          $seq_region_strand      *= -1;
        }
      }

      # Throw away features off the end of the requested slice
      if (! $self->force_reslice) {
        #force_reslice set by RegulatoryFeature::regulatory_attributes
        #so we don't lose attrs which are not on the dest_slice

        next FEATURE if $seq_region_end < 1 || $seq_region_start > $dest_slice_length
          || ( $dest_slice_sr_name ne $sr_name );
      }

      $slice = $dest_slice;
	  }

    push @features, Bio::EnsEMBL::Funcgen::MotifFeature->new_fast
		  ({
        start             => $seq_region_start,
        end               => $seq_region_end,
        strand            => $seq_region_strand,
        slice             => $slice,
        adaptor           => $self,
        dbID              => $motif_feature_id,
        score             => $score,
        display_label     => $display_label,
        binding_matrix    => $bm_hash{$bm_id},
        interdb_stable_id => $stable_id,
		   });
	}

	return \@features;
}


=head2 store

  Args       : List of Bio::EnsEMBL::Funcgen::MotifFeature objects
  Example    : $ofa->store(@features);
  Description: Stores given MotifFeature objects in the database. Should only
               be called once per feature because no checks are made for
			   duplicates. Sets dbID and adaptor on the objects that it stores.
  Returntype : Listref of stored MotifFeatures
  Exceptions : Throws if a list of MotifFeature objects is not provided or if
               the Analysis, Epigenome and FeatureType objects are not attached or stored
  Caller     : General
  Status     : At Risk

=cut

sub store{
	my ($self, @mfs) = @_;

	if (scalar(@mfs) == 0) {
		throw('Must call store with a list of MotifFeature objects');
	}

	my $sth = $self->prepare("
		INSERT INTO motif_feature (
			seq_region_id,   seq_region_start,
			seq_region_end,  seq_region_strand,
            binding_matrix_id,  display_label, score, interdb_stable_id
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	");

	my $db = $self->db();

  FEATURE: foreach my $mf (@mfs) {

	  if( ! (ref($mf) && $mf->isa('Bio::EnsEMBL::Funcgen::MotifFeature'))){
		throw('Feature must be an MotifFeature object');
	  }

    # if ( $mf->is_stored($db) ) {
  	# 	warning('MotifFeature [' . $mf->dbID() . '] is already stored in the database');
  	# 	next FEATURE;
	  # }

	  $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::BindingMatrix', $mf->binding_matrix);


	  my $seq_region_id;
	  ($mf, $seq_region_id) = $self->_pre_store($mf);

	  my $dlabel = $mf->display_label;

	  if(! defined $dlabel){
		$dlabel = $mf->binding_matrix->feature_type->name.':'
		  .$mf->binding_matrix->name();
	  }

	  $sth->bind_param(1, $seq_region_id,              SQL_INTEGER);
	  $sth->bind_param(2, $mf->start(),                SQL_INTEGER);
	  $sth->bind_param(3, $mf->end(),                  SQL_INTEGER);
	  $sth->bind_param(4, $mf->strand(),               SQL_TINYINT);
	  $sth->bind_param(5, $mf->binding_matrix->dbID(), SQL_INTEGER);
	  $sth->bind_param(6, $dlabel,                     SQL_VARCHAR);
	  $sth->bind_param(7, $mf->score(),                SQL_DOUBLE);
	  $sth->bind_param(8, $mf->interdb_stable_id(),           SQL_INTEGER);

	  $sth->execute();

	  $mf->dbID( $self->last_insert_id );
	  $mf->adaptor($self);
	}

  return \@mfs;
}


=head2 store_associated_AnnotatedFeature

  Args[1]    : Bio::EnsEMBL::Funcgen::MotifFeature
  Args[2]    : Bio::EnsEMBL::Funcgen::Peak
  Example    : $mfa->store_associated_Peak($mf, $peak);
  Description: Store link between TF peaks and MotifFeatures
  Returntype : Bio::EnsEMBL::Funcgen::MotifFeature
  Exceptions : Throws if args are not valid, warns if association already exists
  Caller     : General
  Status     : At Risk - likely to change to TranscriptFactorFeature

=cut

#Will always load AFs first, as we need them to generate BMs and MFs
#Hence we may not have all the associated AFs when we store the MF for the first time
#So we need to be able to update these, and will most likely be 1 AF at a time

#Where will these be stored?
#reciprocal methods here and in AF/TFF?
#Just in MF for now untill we write TFF

#When loading MFs, need a wayway to identify if
#it has already been loaded for a previous set
#possiblity of parallel processes loading same MF at same time.
#load scripts should handle multiple fsets, and only ever be run in series
#wrt to fset, can chunk slice wise

#Should only ever rollback associations relevant to fsets in question
#this may leave orphaned MFs which may then cause duplicates

#Duplicate may also be cause if some fsets are run in series, so we definitely
#need to test for MF using feature Slice and BindingMatrix


sub store_associated_AnnotatedFeature{
  my ($self, $mf, $af) = @_;

  $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::MotifFeature', $mf);
  $self->db->is_stored_and_valid('Bio::EnsEMBL::Funcgen::AnnotatedFeature', $af);

    # Replace provided motif feature with the one which is stored in the db
    my $existing_motif_feature
        = $self->fetch_by_BindingMatrix_Slice_start_strand(
        $mf->binding_matrix(), $mf->slice(), $mf->start(), $mf->strand() );
    
    $self->db->is_stored_and_valid( 'Bio::EnsEMBL::Funcgen::MotifFeature', $existing_motif_feature );
    $mf = $existing_motif_feature;

    # Check for existing association
    my $existing_peak = $mf->fetch_overlapping_Peak;
    if ( $existing_peak and $existing_peak->dbID == $peak->dbID ) {
      warn "You are trying to store a pre-existing Peak association";
      return;
    }

    # Validate MotifFeature is entirely contained within the Peak
    if (
        !(
               ( $peak->seq_region_start <= $mf->seq_region_start )
            && ( $mf->seq_region_end <= $peak->seq_region_end )
        )
      )
    {
        throw('MotifFeature is not entirely contained within associated Peak');
    }

    my $sth = $self->prepare(
"INSERT INTO motif_feature_peak (motif_feature_id, peak_id) VALUES (?, ?)"
    );

    $sth->bind_param( 1, $mf->dbID,   SQL_INTEGER );
    $sth->bind_param( 2, $peak->dbID, SQL_INTEGER );
    $sth->execute();

    # $mf->{associated_Peak} = $peak;

    return $mf;
}

=head2 store_associated_RegulatoryFeature

  Args[1]    : Bio::EnsEMBL::Funcgen::MotifFeature
  Args[2]    : Bio::EnsEMBL::Funcgen::RegulatoryFeature
  Example    : $mfa->store_associated_RegulatoryFeature($mf, $regulatory_feature);
  Description: Store link between RegulatoryFeatures and MotifFeatures
  Returntype : Bio::EnsEMBL::Funcgen::MotifFeature
  Exceptions : Throws if args are not valid, warns if association already exists
  Caller     : General
  Status     : Stable

=cut

sub store_associated_RegulatoryFeature {
	my ( $self, $mf, $regulatory_feature, $epigenome, $has_matching_Peak ) = @_;

	$self->db->is_stored_and_valid( 'Bio::EnsEMBL::Funcgen::RegulatoryFeature', $regulatory_feature );
	
  my $epigenome_id = undef;
  if ($epigenome){
    $self->db->is_stored_and_valid( 'Bio::EnsEMBL::Funcgen::Epigenome', $epigenome );
    $epigenome_id = $epigenome->dbID();
  }

	# Replace provided motif feature with the one which is stored in the db
	my $existing_motif_feature= 
    $self->fetch_by_BindingMatrix_Slice_start_strand
    ($mf->binding_matrix(), $mf->slice(), $mf->start(), $mf->strand() );

	$self->db->is_stored_and_valid( 'Bio::EnsEMBL::Funcgen::MotifFeature', $existing_motif_feature );
	$mf = $existing_motif_feature;

    # Validate MotifFeature is entirely contained within the Peak
    if (
        !(
               ( $regulatory_feature->seq_region_start <= $mf->seq_region_start )
            && ( $mf->seq_region_end <= $regulatory_feature->seq_region_end )
        )
      )
    {
        throw('MotifFeature is not entirely contained within associated RegulatoryFeature');
    }

    my $sth = $self->prepare(
"INSERT INTO motif_feature_regulatory_feature 
(motif_feature_id, regulatory_feature_id, epigenome_id, has_matching_Peak) VALUES (?, ?, ?, ?)"
    );

    $sth->bind_param( 1, $mf->dbID,   SQL_INTEGER );
    $sth->bind_param( 2, $regulatory_feature->dbID, SQL_INTEGER );
    $sth->bind_param( 3, $epigenome_id, SQL_INTEGER );
    $sth->bind_param( 4, $has_matching_Peak, SQL_TINYINT );
    $sth->execute();

    # push @{ $mf->{associated_Peaks} }, $peak;

    return $mf;
}

=head2 fetch_by_interdb_stable_id

  Arg [1]    : Integer $stable_id - The 'interdb stable id' of the motif feature to retrieve
  Example    : my $rf = $rf_adaptor->fetch_by_interdb_stable_id(1);
  Description: Retrieves a motif feature via its stable id. This is really an internal
               method to facilitate inter DB linking.
  Returntype : Bio::EnsEMBL::Funcgen::MotifFeature
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub fetch_by_interdb_stable_id {
  my ($self, $stable_id) = @_;

  $self->bind_param_generic_fetch($stable_id, SQL_INTEGER);

  return $self->generic_fetch('mf.interdb_stable_id=?')->[0];
}

1;
