# Ensembl module for Bio::EnsEMBL::Funcgen::BindingMatrix

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

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.


=head1 NAME

Bio::EnsEMBL::Funcgen::BindingMatrix - A module to represent a BindingMatrix. 
In EFG this represents the binding affinities of a Transcription Factor to DNA.

=head1 SYNOPSIS

=head1 DESCRIPTION


=head1 SEE ALSO

Bio::EnsEMBL::Funcgen::DBSQL::BindingMatrixAdaptor
Bio::EnsEMBL::Funcgen::MotifFeature

=cut

package Bio::EnsEMBL::Funcgen::BindingMatrix;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Scalar    qw( assert_ref check_ref );
use Bio::EnsEMBL::Utils::Argument  qw( rearrange );
use Bio::EnsEMBL::Utils::Exception qw( throw );
use Bio::EnsEMBL::Funcgen::Sequencing::MotifTools qw( parse_matrix_line 
                                                      reverse_complement_matrix );
  
use base qw( Bio::EnsEMBL::Funcgen::Storable );

=head2 new

  Arg [-name]       : Scalar - Name of matrix
  Arg [-analysis]   : Bio::EnsEMBL::Analysis - analysis describing how the matrix was obtained
  Arg [-source]     : String (Mandatory) - A string describing the source of the matrix, i.e. SELEX
  Arg [-threshold]  : Scalar (optional) - Numeric minimum relative affinity for binding sites of this matrix
  Arg [-description]: Scalar (optional) - Descriptiom of matrix
  Example    : my $matrix = Bio::EnsEMBL::Funcgen::BindingMatrix->new(
                                                               -name  => "MA0122.1",
                                                               -analysis => $analysis,
                                                               -description => "Jaspar Matrix",
                                                                );
  Description: Constructor method for BindingMatrix class
  Returntype : Bio::EnsEMBL::Funcgen::BindingMatrix
  Exceptions : Throws if name or/and type not defined
  Caller     : General
  Status     : Medium risk

=cut

sub new {
    my $caller    = shift;
    my $obj_class = ref($caller) || $caller;
    my $self      = $obj_class->SUPER::new(@_);

    my ( $name, $source, $threshold, $frequencies,
        $associated_transcription_factors )
        = rearrange(
        [   'NAME',      'SOURCE',
            'THRESHOLD', 'FREQUENCIES',
            'ASSOCIATED_TRANSCRIPTION_FACTORS'
        ],
        @_
        );

    throw('Must supply a -name parameter')   if !defined $name;
    throw('Must supply a -source parameter') if !defined $source;

    $self->{name}        = $name;
    $self->{source}      = $source;
    $self->{threshold}   = $threshold if defined $threshold;
    $self->{frequencies} = $frequencies if defined $frequencies;
    $self->{associated_transcription_factors}
        = $associated_transcription_factors
        if defined $associated_transcription_factors;

    return $self;
}

=head2 name

  Example    : my $name = $matrix->name();
  Description: Getter for the name attribute
  Returntype : String
  Exceptions : None
  Caller     : General
  Status     : Stable

=cut

sub name { return shift->{name}; }

=head2 threshold

  Arg [1]    : Scalar (optional) - Numeric threshold
  Example    : if($score >= $matrix->threshold) { # Do something here }
  Description: Getter/setter for threshold attribute 
  Returntype : Scalar - numeric
  Exceptions : None
  Caller     : General
  Status     : At Risk

=cut

# Do we ever really want to set this after construction? 
# thresholds are updated via direct sql, so unlikely unless
# someone if loading these via another path

sub threshold {
  my $self = shift;
  $self->{threshold} = shift if @_;
  return $self->{threshold};
}

=head2 source

  Example    : print '>'.$matrix->name."\n".$matrix->source;
  Description: Getter/Setter for source attribute
  Returntype : Scalar - string
  Exceptions : None
  Caller     : General
  Status     : At Risk

=cut

sub source {
  my $self = shift;
  $self->{source} = shift if @_;
  return $self->{source};
}



sub _frequencies {
    my ($self) = @_;

    if ( !$self->{frequencies} ) {

        my $binding_matrix_frequencies_adaptor
            = $self->adaptor->db()->get_adaptor('BindingMatrixFrequencies');

        my $binding_matrix_frequencies
            = $binding_matrix_frequencies_adaptor->fetch_all_by_BindingMatrix(
            $self);

        for my $bmf ( @{$binding_matrix_frequencies} ) {
            $self->{frequencies}->{ $bmf->position() }->{ $bmf->nucleotide() }
                = $bmf->frequency();
        }
    }

    return $self->{frequencies};
}



sub get_frequency_by_position_nucleotide {
    my ( $self, $position, $nucleotide ) = @_;

    throw('Must supply a position parameter')   if !defined $position;
    throw('Must supply a nucleotide parameter') if !defined $nucleotide;

    my %valid_nucleotides = ( 'A' => 1, 'C' => 1, 'G' => 1, 'T' => 1 );

    if ( !$valid_nucleotides{$nucleotide} ) {
        throw('Supplied nucleotide not valid');
    }

    return $self->_frequencies()->{$position}->{$nucleotide};
}


sub get_frequencies_as_string {
    my ($self) = @_;

    my $frequencies_string;

    my @nucleotide_order = ( 'A', 'C', 'G', 'T' );

    for my $nucleotide (@nucleotide_order) {
        for ( my $position = 1; $position <= $self->length(); $position++ ) {
            my $frequency
                = $self->get_frequency_by_position_nucleotide( $position,
                $nucleotide );
            $frequencies_string .= $frequency . "\t";
        }
        $frequencies_string .= "\n";
    }

    return $frequencies_string;
}


=head2 length

  Example    : my $length = $bm->length;
  Description: Returns the length of the the matrix
  Returntype : Scalar - numeric (int)
  Exceptions : None
  Caller     : General
  Status     : At Risk

=cut

sub length {
    my $self = shift;

    if ( !$self->{length} ) {
        $self->{length} = scalar keys %{ $self->_frequencies() };
    }

    return $self->{length};
}


=head2 summary_as_hash

  Example       : $binding_matrix_summary = $binding_matrix->summary_as_hash;
  Description   : Retrieves a textual summary of this BindingMatrix.
  Returns       : Hashref of descriptive strings
  Status        : Intended for internal use (REST)

=cut

sub summary_as_hash {
    my $self = shift;

    return {
        name        => $self->name(),
        source      => $self->source(),
        threshold   => $self->threshold(),
        length      => $self->length(),
        frequencies => $self->_frequencies(),
    };
}


1;
