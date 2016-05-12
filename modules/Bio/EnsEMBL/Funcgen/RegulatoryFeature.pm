=head1 LICENSE

Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Funcgen::RegulatoryFeature

=head1 SYNOPSIS

  use v5.10;
  use Bio::EnsEMBL::Registry;
  Bio::EnsEMBL::Registry->load_registry_from_url('mysql://anonymous@ensembldb.ensembl.org:3306/84/');

  my $regulatory_feature_adaptor = Bio::EnsEMBL::Registry->get_adaptor('human', 'funcgen', 'RegulatoryFeature');

  my $regulatory_feat = $regulatory_feature_adaptor->fetch_by_stable_id('ENSR00000000021');

  say 'Stable id:       ' . $regulatory_feat->stable_id;
  say 'Analysis:        ' . $regulatory_feat->analysis->logic_name;
  say 'Feature type:    ' . $regulatory_feat->feature_type->name;
  say 'Feature set:     ' . $regulatory_feat->feature_set->name;
  say 'Activity:        ' . $regulatory_feat->activity;
  say 'Cell type count: ' . $regulatory_feat->cell_type_count;
  say 'Slice name:      ' . $regulatory_feat->slice->name;
  say 'Coordinates:     ' . $regulatory_feat->start .' - '. $regulatory_feat->end,;

=head1 DESCRIPTION

A RegulatoryFeature object represents the output of the Ensembl RegulatoryBuild:
    http://www.ensembl.org/info/docs/funcgen/regulatory_build.html

It may comprise many histone modification, transcription factor, polymerase and open
chromatin features, which have been combined to provide a summary view and
classification of the regulatory status at a given loci.


=head1 SEE ALSO

Bio::EnsEMBL:Funcgen::DBSQL::RegulatoryFeatureAdaptor
Bio::EnsEMBL::Funcgen::SetFeature

=cut


package Bio::EnsEMBL::Funcgen::RegulatoryFeature;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument  qw( rearrange );
use Bio::EnsEMBL::Utils::Exception qw( throw deprecate );

use base qw( Bio::EnsEMBL::Funcgen::SetFeature );

=head2 new

  Arg [-SLICE]             : Bio::EnsEMBL::Slice - The slice on which this feature is located.
  Arg [-START]             : int - The start coordinate of this feature relative to the start of the slice
                             it is sitting on. Coordinates start at 1 and are inclusive.
  Arg [-END]               : int -The end coordinate of this feature relative to the start of the slice
                    	     it is sitting on. Coordinates start at 1 and are inclusive.
  Arg [-FEATURE_SET]       : Bio::EnsEMBL::Funcgen::FeatureSet - Regulatory Feature set
  Arg [-FEATURE_TYPE]      : Bio::EnsEMBL::Funcgen::FeatureType - Regulatory Feature sub type
  Arg [-BINARY_STRING]     : (optional) string - Regulatory Build binary string
  Arg [-STABLE_ID]         : (optional) string - Stable ID for this RegulatoryFeature e.g. ENSR00000000001
  Arg [-DISPLAY_LABEL]     : (optional) string - Display label for this feature
  Arg [-ATTRIBUTE_CACHE]   : (optional) HASHREF of feature class dbID|Object lists
  Arg [-PROJECTED]         : (optional) boolean - Flag to specify whether this feature has been projected or not
  Arg [-dbID]              : (optional) int - Internal database ID.
  Arg [-ADAPTOR]           : (optional) Bio::EnsEMBL::DBSQL::BaseAdaptor - Database adaptor.

  Example    : my $feature = Bio::EnsEMBL::Funcgen::RegulatoryFeature->new(
		    -SLICE         => $chr_1_slice,
		    -START         => 1000000,
		    -END           => 1000024,
		    -DISPLAY_LABEL => $text,
		    -FEATURE_SET   => $fset,
		    -FEATURE_TYPE  => $reg_ftype,
                 );


  Description: Constructor for RegulatoryFeature objects.
  Returntype : Bio::EnsEMBL::Funcgen::RegulatoryFeature
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub new {
  my $caller = shift;
  my $class = ref($caller) || $caller;
  my $self = $class->SUPER::new(@_);

  my ($stable_id, $attr_cache, $bin_string, $projected, $activity, $epigenome_count)
    = rearrange(['STABLE_ID', 'ATTRIBUTE_CACHE', 'BINARY_STRING', 'PROJECTED', 'ACTIVITY', 'EPIGENOME_COUNT'], @_);

  #None of these are mandatory at creation
  #under different use cases
  $self->{binary_string}    = $bin_string       if defined $bin_string;
  $self->{stable_id}        = $stable_id        if defined $stable_id;
  $self->{projected}        = $projected        if defined $projected;
  $self->{activity}         = $activity         if defined $activity;
  $self->{epigenome_count}  = $epigenome_count  if defined $epigenome_count;

  return $self;
}

=head2 display_label

  Example    : my $label = $feature->display_label;
  Description: Getter for the display label of this feature.
  Returntype : String
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub display_label {
  my $self = shift;

  if(! defined $self->{display_label}) {
    $self->{'display_label'}  = $self->feature_type->name.' Regulatory Feature';

    if( defined $self->epigenome ) {
      $self->{display_label} .= ' - '.$self->epigenome->name;
    }
  }

  return $self->{display_label};
}


=head2 display_id

  Example    : print $feature->display_id();
  Description: This method returns a string that is considered to be
               the 'display' identifier. In this case the stable Id is
               preferred
  Returntype : String
  Exceptions : none
  Caller     : web drawing code, Region Report tool
  Status     : Stable

=cut

sub display_id {  return shift->{stable_id}; }

=head2 stable_id

  Arg [1]    : (optional) string - stable_id e.g ENSR00000000001
  Example    : my $stable_id = $feature->stable_id();
  Description: Getter for the stable_id attribute for this feature.
  Returntype : string
  Exceptions : None
  Caller     : General
  Status     : At risk - setter functionality to be removed

=cut

sub stable_id { return shift->{stable_id}; }


# =head2 regulatory_attributes
# 
#   Arg [1]    : String (optional) - Class of feature e.g. annotated or motif
#   Example    : print "Regulatory Attributes:\n\t".join("\n\t", (map $_->feature_type->name, @{$feature->regulatory_attributes()}))."\n";
#   Description: Getter for the regulatory_attributes for this feature.
#   Returntype : ARRAYREF
#   Exceptions : Throws if feature class not valid
#   Caller     : General
#   Status     : At Risk
# 
# =cut
# 
# sub regulatory_attributes {
#   my ($self, $feature_class) = @_;
#   my @feature_classes;
#   my %adaptors = (
#     'annotated' => $self->adaptor->db->get_AnnotatedFeatureAdaptor,
#     'motif'     => $self->adaptor->db->get_MotifFeatureAdaptor     
#   );
# 
#   if (defined $feature_class) {
# 
#     if (exists $adaptors{lc($feature_class)}) {
#       @feature_classes = (lc($feature_class));
#     }
#     else {
#       throw("The feature class you specified is not valid:\t$feature_class\n".
#             "Please use one of:\t".join(', ', keys %adaptors));
#     }
#   }
#   else {
#     @feature_classes = keys %adaptors;
#   }
# 
#   foreach my $feature_class (@feature_classes) {
#     # Now structured as hash to facilitate faster has_attribute method
#     # Very little difference to array based cache
#     my @attr_dbIDs = keys %{$self->{attribute_cache}{$feature_class}};
# 
#     if (scalar(@attr_dbIDs) > 0) {
# 
#       if ( ! ( ref($self->{regulatory_attributes}{$feature_class}->[0])  &&
#                ref($self->{regulatory_attributes}{$feature_class}->[0])->isa('Bio::EnsEMBL::Feature') )) {
# 
#         $adaptors{$feature_class}->force_reslice(1); #So we don't lose attrs which aren't on the slice
#         # fetch_all_by_Slice_constraint does relevant normalised Slice projection i.e. PAR mappingg
#         $self->{'regulatory_attributes'}{$feature_class} =
#           $adaptors{$feature_class}->fetch_all_by_Slice_constraint
#             ($self->slice,
#              lc($feature_class).'_feature_id in('.join(',', @attr_dbIDs).')' );
# 
#         # Forces reslice and inclusion for attributes not contained within slice
#         $adaptors{$feature_class}->force_reslice(0);
#       }
#     } else {
#       $self->{regulatory_attributes}{$feature_class} = [];
#     }
#   }
# 
#   return [ map { @{$self->{regulatory_attributes}{$_}} } @feature_classes ];
# }

# =head2 has_attribute
# 
#   Arg [1]    : Attribute Feature dbID
#   Arg [2]    : Attribute Feature class e.g. motif or annotated
#   Example    : if($regf->has_attribute($af->dbID, 'annotated'){ #do something here }
#   Description: Identifies whether this RegulatoryFeature has a given attribute
#   Returntype : Boolean
#   Exceptions : Throws if args are not defined
#   Caller     : General
#   Status     : Stable
# 
# =cut
# 
# sub has_attribute {
#   my ($self, $dbID, $feature_class) = @_;
# 
#   throw('Must provide a dbID and a Feature class argument') if ! $dbID && $feature_class;
# 
#   return exists ${$self->attribute_cache}{$feature_class}{$dbID};
# }

=head2 _linked_regulatory_activity

  Arg [1]     : 
  Returntype  : 
  Exceptions  : 
  Description : Guaranteed to return an arrayref. If there are no linked feature sets, returns [].

=cut
sub _linked_regulatory_activity {

  my $self = shift;
  my $linked_feature_sets = shift;

  if($linked_feature_sets) {
    $self->{_linked_regulatory_activity} = $linked_feature_sets;
  }
  
  if (! defined $self->{_linked_regulatory_activity}) {
    $self->{_linked_regulatory_activity} = [];
  }
  return $self->{_linked_regulatory_activity};
}

sub has_activity_in {

  my $self = shift;
  my $feature_set = shift;
  
  foreach my $current_regulatory_activity (@{$self->_linked_regulatory_activity}) {
    if ($current_regulatory_activity->feature_set_id == $feature_set->dbID) {
      return 1;
    }
  }
  return;
}

sub has_feature_sets_with_activity {

  my $self = shift;
  my $activity = shift;
  
  foreach my $current_regulatory_activity (@{$self->_linked_regulatory_activity}) {
    if ($current_regulatory_activity->activity eq $activity) {
      return 1;
    }
  }
  return;
}

=head2 get_feature_sets_by_activity

  Arg [1]     : Activity
  Returntype  : 
  Exceptions  : 
  Description : 

=cut

sub get_feature_sets_by_activity {

  my $self     = shift;
  my $activity = shift;
  
  if (!$self->adaptor->is_valid_activity($activity)) {
    throw(
      'Please pass a valid activity to this method. Valid activities are: ' 
      . $self->adaptor->valid_activities_as_string
    );
  }
  
#   my $feature_set_dbID_list = $self->_linked_regulatory_activity->{$activity};
  
  my @feature_set_dbID_list = map { $_->feature_set_id } grep { $_->activity eq $activity } @{$self->_linked_regulatory_activity};
  
  my $feature_set_adaptor = $self->adaptor->db->get_FeatureSetAdaptor;
  
  return $feature_set_adaptor->fetch_all_by_dbID_list(\@feature_set_dbID_list);
}

=head2 epigenome_count

  Arg [1]     : None
  Returntype  : SCALAR
  Exceptions  : None
  Description : Returns the amount of epigenomes in which this regulatory feature is active

=cut

sub epigenome_count { 
  my $self = shift;
  return $self->{epigenome_count};
}

=head2 bound_seq_region_start

  Example    : my $bound_sr_start = $feature->bound_seq_region_start;
  Description: Getter for the seq_region bound_start attribute for this feature.
               Gives the 5' most start value of the underlying attribute
               features.
  Returntype : Integer
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub bound_seq_region_start { return $_[0]->seq_region_start - $_[0]->_bound_lengths->[0]; }


=head2 bound_seq_region_end

  Example    : my $bound_sr_end = $feature->bound_seq_region_end;
  Description: Getter for the seq_region bound_end attribute for this feature.
               Gives the 3' most end value of the underlying attribute
               features.
  Returntype : Integer
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub bound_seq_region_end { return $_[0]->seq_region_end + $_[0]->_bound_lengths->[1]; }

# As this 'private' method is not exposed or required to be poylymorphic,
# it would theoretically, be quicker to have this as a sub.

sub _bound_lengths {
  my $self = shift;

  if(! defined  $self->{_bound_lengths}){

    my @af_attrs = @{$self->regulatory_attributes('annotated')};

    if (! @af_attrs) {
      throw('Unable to set bound length, no AnnotatedFeature attributes available for RegulatoryFeature: '
            .$self->dbID);
    }

    #Adding self here accounts for core region i.e.
    #features extending beyond the core may be absent on this cell type.
    my @start_ends;

    foreach my $feat (@af_attrs, $self) {
      push @start_ends, ($feat->seq_region_start, $feat->seq_region_end);
    }

    @start_ends = sort { $a <=> $b } @start_ends;

    $self->{_bound_lengths} = [ ($self->seq_region_start - $start_ends[0]),
                                ($start_ends[$#start_ends] - $self->seq_region_end) ];
  }

  return $self->{_bound_lengths};
}

=head2 bound_start_length

  Example    : my $bound_start_length = $reg_feat->bound_start_length;
  Description: Getter for the bound_start_length attribute for this feature,
               with respect to the host slice strand
  Returntype : Integer
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub bound_start_length {
  my $self = shift;
  return ($self->slice->strand == 1) ? $self->_bound_lengths->[0] : $self->_bound_lengths->[1];
}


=head2 bound_end_length

  Example    : my $bound_end_length = $reg_feat->bound_end_length;
  Description: Getter for the bound_end length attribute for this feature,
               with respect to the host slice strand.
  Returntype : Integer
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub bound_end_length {
  my $self = shift;
  return ($self->slice->strand == 1) ? $self->_bound_lengths->[1] : $self->_bound_lengths->[0];
}

=head2 bound_start

  Example    : my $bound_start = $feature->bound_start;
  Description: Getter for the bound_start attribute for this feature.
               Gives the 5' most start value of the underlying attribute
               features in local coordinates.
  Returntype : Integer
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut
sub bound_start { return $_[0]->start - $_[0]->bound_start_length; }


=head2 bound_end

  Example    : my $bound_end = $feature->bound_start();
  Description: Getter for the bound_end attribute for this feature.
               Gives the 3' most end value of the underlying attribute
               features in local coordinates.
  Returntype : Integer
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut
sub bound_end { return $_[0]->end + $_[0]->bound_end_length; }

=head2 is_projected

  Arg [1]    : optional - boolean
  Example    : if($regf->is_projected){ #do something different here }
  Description: Getter/Setter for the projected attribute.
  Returntype : Boolean
  Exceptions : None
  Caller     : General
  Status     : At risk - remove setter functionality

=cut
sub is_projected {
  my $self = shift;

  if(@_){
	#added v67
    warn "RegulatoryFeature::is_projected setter functionality is being removed\n";
    $self->{'projected'} = shift;
  }

  return $self->{'projected'};
}


=head2 get_underlying_structure

  Example    : my @web_image_structure = @{$regf->get_underlying_structure};
  Description: Getter for the bound_end attribute for this feature.
               Gives the 3' most end value of the underlying attribute
               features.
  Returntype : Arrayref
  Exceptions : None
  Caller     : Webcode
  Status     : At Risk

=cut

#Could precompute these as core region loci
#and store in the DB to avoid the MF attr fetch?

#This is also sensitive to projection/transfer after we have called it.
#Would have to do one of the following
#1 Projecting all motif_features. This could be done by extending/overwriting
#  Feature::project/transfer, and make all feature projection code use that e.g. BaseFeatureAdaptor
#2 Cache the start, end and strand of slice, and update when changed by transforming motif_feature_loci

# This is only ever used for web which will never call until any projection is complete.
# Hence no real need for this to be sensitive to pre & post projection calling
# Leave for now with above useage caveat

sub get_underlying_structure{
  my $self = shift;

  if (! defined $self->{underlying_structure}) {
    my @mf_loci;

    foreach my $mf (@{$self->regulatory_attributes('motif')}) {
      push @mf_loci, ($mf->start, $mf->end);
    }

    $self->{underlying_structure} = [
                                     $self->bound_start, $self->start,
                                     @mf_loci,
                                     $self->end, $self->bound_end
                                    ];
  }

  $self->{underlying_structure};
}


=head2 summary_as_hash

  Example       : $regf_summary = $regf->summary_as_hash;
  Description   : Retrieves a textual summary of this RegulatoryFeature.
  Returns       : Hashref of descriptive strings
  Status        : Intended for internal use (REST)

=cut
sub summary_as_hash {
  my $self   = shift;

  return {
    ID                      => $self->stable_id,
    epigenome               => $self->epigenome->name,
    bound_start             => $self->bound_seq_region_start,
    bound_end               => $self->bound_seq_region_end,
    start                   => $self->seq_region_start,
    end                     => $self->seq_region_end,
    strand                  => $self->strand,
    seq_region_name         => $self->seq_region_name,
    activity                => $self->activity,
    description             => $self->feature_type->description,
    feature_type            => "regulatory",
  };
}

# Deprecated methods

sub has_evidence {
    deprecate('"has_evidence" is now deprecated. Please use "activity"
        which reports the state of the Regulatory Feature');
  return shift->activity;
}

sub cell_type_count { 
  my $self = shift;
  deprecate(
        "Bio::EnsEMBL::Funcgen::RegulatoryFeature::cell_type_count has been deprecated and will be removed in Ensembl release 89."
            . " Please use Bio::EnsEMBL::Funcgen::RegulatoryFeature::epigenome_count instead"
  );
  return $self->epigenome_count;
}

sub is_unique_to_FeatureSets { deprecate('"is_unique_to_FeatureSets" is deprecated. '); return; }
sub get_other_RegulatoryFeatures { deprecate('"get_other_RegulatoryFeatures" is deprecated. '); return; }
sub get_focus_attributes    { deprecate('"get_focus_attributes" is deprecated.');  return; }
sub get_nonfocus_attributes { deprecate('"get_nonfocus_attributes" is deprecated.');  return; }

sub activity {
  throw(
    "activity is no longer supported for regulatory features. You can use "
    . "get_feature_sets_by_activity('ACTIVE') to find feature sets in which "
    . "this regulatory feature are active."
  );
}

sub feature_set {
  throw(
    "feature_set is no longer supported for regulatory features. You can use "
    . "get_feature_sets_by_activity('ACTIVE') to find feature sets in which "
    . "this regulatory feature are active."
  );
}

1;


