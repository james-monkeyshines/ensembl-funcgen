#
# Ensembl module for Bio::EnsEMBL::Funcgen::DBSQL::ArrayChipAdaptor
#
# You may distribute this module under the same terms as Perl itself

=head1 NAME

Bio::EnsEMBL::Funcgen::DBSQL::ArrayChipAdaptor - A database adaptor for fetching and
storing Funcgen ArrayChip objects.

=head1 SYNOPSIS

my $ac_adaptor = $db->get_ArrayChipAdaptor();

my @achips = @{$ec_adaptor->fetch_all_by_Array($array)};


=head1 DESCRIPTION

The ArrayChipAdaptor is a database adaptor for storing and retrieving
Funcgen ArrayChip objects.

=head1 AUTHOR

This module was created by Nathan Johnson.

This module is part of the Ensembl project: http://www.ensembl.org/

=head1 CONTACT

Post comments or questions to the Ensembl development list: ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut

use strict;
use warnings;

package Bio::EnsEMBL::Funcgen::DBSQL::ArrayChipAdaptor;

use Bio::EnsEMBL::Utils::Exception qw( warning throw );
use Bio::EnsEMBL::Funcgen::ArrayChip;
use Bio::EnsEMBL::Funcgen::DBSQL::BaseAdaptor;

use vars qw(@ISA);


#May need to our this?
@ISA = qw(Bio::EnsEMBL::Funcgen::DBSQL::BaseAdaptor);

=head2 fetch_all_by_array_id

  Arg [1]    : int - dbID of Array
  Example    : my @ccs = @{$ec_a->fetch_all_by_array_dbID($array->dbID());
  Description: Does what it says on the tin
  Returntype : Listref of Bio::EnsEMBL::Funcgen::ArrayChip
  Exceptions : None
  Caller     : General
  Status     : Medium Risk

=cut

sub fetch_all_by_array_id {
    my $self = shift;
    my $array_id = shift;

    throw("Must specify an array dbID") if(! $array_id);

    my $constraint = "ac.array_id='$array_id'";

    return $self->generic_fetch($constraint);
}



=head2 fetch_by_array_design_ids

  Arg [1]    : int - dbID of Array
  Example    : my @ecs = @{$ec_a->fetch_all_by_experiment_dbID($ac_dbid);
  Description: Does what it says on the tin
  Returntype : Listref of Bio::EnsEMBL::Funcgen::ArrayChip
  Exceptions : None
  Caller     : General
  Status     : Medium Risk

=cut

sub fetch_by_array_design_ids{
    my ($self, $array_id, $design_id) = @_;

    throw("Must specify an array dbID and a design id") if(! $array_id);

    my $constraint = "ac.array_id='$array_id' and ac.design_id='$design_id'";

    my ($ac) = @{$self->generic_fetch($constraint)};
    #unique key means this always has just one element

    return $ac;
}





#fetch by Array_array_chip_name??
#would need this if we're going to check for previously imported ArrayChips, as there's no guarantee that the design_name will be populated.

=head2 _tables

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns the names and aliases of the tables to use for queries.
  Returntype : List of listrefs of strings
  Exceptions : None
  Caller     : Internal
  Status     : Medium Risk

=cut

sub _tables {
	my $self = shift;
	
	return ['array_chip', 'ac'];
}

=head2 _columns

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns a list of columns to use for queries.
  Returntype : List of strings
  Exceptions : None
  Caller     : Internal
  Status     : Medium Risk

=cut

sub _columns {
  my $self = shift;
	
  return qw( ac.array_chip_id ac.design_id ac.array_id ac.name);
}

=head2 _objs_from_sth

  Arg [1]    : DBI statement handle object
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Creates Array objects from an executed DBI statement
			   handle.
  Returntype : Listref of Bio::EnsEMBL::Funcgen::ArrayChip objects
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my (@result, $ac_id, $design_id, $array_id, $name);
  
  $sth->bind_columns(\$ac_id, \$design_id, \$array_id, \$name);
  
  while ( $sth->fetch() ) {
    my $array = Bio::EnsEMBL::Funcgen::ArrayChip->new(
						      -dbID      => $ac_id,
						      -design_id => $design_id,
						      -array_id  => $array_id,
						      -name      => $name,
						      -adaptor   => $self,
						     );
    
    push @result, $array;
    
  }
  return \@result;
}



=head2 store

  Args       : List of Bio::EnsEMBL::Funcgen::ArrayChip objects
  Example    : $arraychip_adaptor->store($ac1, $ac2, $ac3);
  Description: Stores given ArrayChip objects in the database. Should only be
               called once per ArrayChip because no checks are made for duplicates.
  Returntype : ARRAYREF
  Exceptions : warns if passed non-ArrayChip arg
  Caller     : General
  Status     : At Risk

=cut

sub store {
  my $self = shift;
  my @args = @_;
  
  #my ($stored_ac);

  #Should we implement a throw here is the caller is not Array?
  #make private _store?

  
  my $sth = $self->prepare("
			INSERT INTO array_chip
			(design_id, array_id, name)
			VALUES (?, ?, ?)"
			  );
  
    
  
  foreach my $ac (@args) {
    if ( ! $ac->isa('Bio::EnsEMBL::Funcgen::ArrayChip') ) {
      warning('Can only store ExperimentalChip objects, skipping $ec');
      next;
    }
    
    throw("ArrayChip must have an array_id to be stored") if ! $ac->array_id();

    #check for array_id here? this is done by not null in sql
    

    #check for previously stored array_chips is done in Array via add_ArrayChip
    
    
    
    if (!( $ac->dbID() && $ac->adaptor() == $self )){

      my $s_ac = $self->fetch_by_array_design_ids($ac->array_id(), $ac->design_id());

      if(! $s_ac){
	
	$sth->bind_param(1, $ac->design_id(), SQL_VARCHAR);
	$sth->bind_param(2, $ac->array_id(),  SQL_INTEGER);
	$sth->bind_param(3, $ac->name(),      SQL_VARCHAR);	
	$sth->execute();

	my $dbID = $sth->{'mysql_insertid'};
	$ac->dbID($dbID);
	$ac->adaptor($self);	
	
      }else{
	  $ac = $s_ac;
	  #	my @states = @{$self->db->fetch_all_states('experimental_chip', $ec->dbID())};
	  #	warn("Using previously stored ExperimentalChip (".$ec->unique_id().") with states\t@states\n");
	}
    }
  }
  return \@args;
}


=head2 list_dbIDs

  Args       : None
  Example    : my @array_ids = @{$ec_a->list_dbIDs()};
  Description: Gets an array of internal IDs for all ArrayChip objects in the
               current database.
  Returntype : List of ints
  Exceptions : None
  Caller     : ?
  Status     : Medium Risk

=cut

sub list_dbIDs {
    my ($self) = @_;	
    return $self->_list_dbIDs('array_chip');
}



1;

