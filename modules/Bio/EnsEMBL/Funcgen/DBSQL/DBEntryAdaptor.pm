# EnsEMBL External object reference reading writing adaptor for mySQL
#
# Copyright EMBL-EBI 2001
#
# Author: Arne Stabenau
# 
# Date : 06.03.2001
#

=head1 NAME

Bio::EnsEMBL::DBSQL::DBEntryAdaptor -
MySQL Database queries to load and store external object references.

=head1 SYNOPSIS

$db_entry_adaptor = $db_adaptor->get_DBEntryAdaptor();
$db_entry = $db_entry_adaptor->fetch_by_dbID($id);

my $gene = $db_adaptor->get_GeneAdaptor->fetch_by_stable_id('ENSG00000101367');
@db_entries = @{$db_entry_adaptor->fetch_all_by_Gene($gene)};
@gene_ids = $db_entry_adaptor->list_gene_ids_by_extids('BAB15482');


=head1 CONTACT

Post questions to the EnsEMBL developer list <ensembl-dev@ebi.ac.uk>

=head1 METHODS

=cut

package Bio::EnsEMBL::Funcgen::DBSQL::DBEntryAdaptor;

use Bio::EnsEMBL::DBSQL::DBEntryAdaptor;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::EnsEMBL::DBEntry;
use Bio::EnsEMBL::IdentityXref;
use Bio::EnsEMBL::GoXref;

use Bio::EnsEMBL::Utils::Exception qw(deprecate throw warning);

use vars qw(@ISA @EXPORT);
use strict;

@ISA = qw( Bio::EnsEMBL::DBSQL::DBEntryAdaptor Bio::EnsEMBL::DBSQL::BaseAdaptor);
@EXPORT = (@{$DBI::EXPORT_TAGS{'sql_types'}});

=head2 fetch_by_db_accession

  Arg [1]    : string $dbname - The name of the database which the provided
               accession is for.
  Arg [2]    : string $accession - The accesion of the external reference to
               retrieve.
  Example    : my $xref = $dbea->fetch_by_db_accession('Interpro','IPR003439');
               print $xref->description(), "\n" if($xref);
  Description: Retrieves a DBEntry (xref) via the name of the database it is
               from and its primary accession in that database. Undef is
               returned if the xref cannot be found in the database.
  Returntype : Bio::EnsEMBL::DBSQL::DBEntry
  Exceptions : thrown if arguments are incorrect
  Caller     : general, domainview
  Status     : Stable

=cut

#Is this different to the core code?
#Yes we don't have a max rows limit!

sub fetch_by_db_accession {
  my $self = shift;
  my $dbname = shift;
  my $accession = shift;

  my $sth = $self->prepare(
   "SELECT xref.xref_id, xref.dbprimary_acc, xref.display_label,
           xref.version, xref.description,
           exDB.dbprimary_acc_linkable, exDB.display_label_linkable, exDB.priority,
           exDB.db_name, exDB.db_display_name, exDB.db_release, es.synonym,
           xref.info_type, xref.info_text, exDB.type, exDB.secondary_db_name,
           exDB.secondary_db_table
    FROM   (xref, external_db exDB)
    LEFT JOIN external_synonym es on es.xref_id = xref.xref_id
    WHERE  xref.dbprimary_acc = ?
    AND    exDB.db_name = ?
    AND    xref.external_db_id = exDB.external_db_id");

  $sth->bind_param(1,$accession,SQL_VARCHAR);
  $sth->bind_param(2,$dbname,SQL_VARCHAR);
  $sth->execute();

  if(!$sth->rows() && lc($dbname) eq 'interpro') {
    #
    # This is a minor hack that means that results still come back even
    # when a mistake was made and no interpro accessions were loaded into
    # the xref table.  This has happened in the past and had the result of
    # breaking domainview
    #
    $sth->finish();
    $sth = $self->prepare
      ("SELECT null, i.interpro_ac, i.id, null, null, 'Interpro', null, null ".
       "FROM interpro i where i.interpro_ac = ?");
    $sth->bind_param(1,$accession,SQL_VARCHAR);
    $sth->execute();
  }

  my $exDB;

  while ( my $arrayref = $sth->fetchrow_arrayref()){
    my ( $dbID, $dbprimaryId, $displayid, $version, $desc, 
	 $primary_id_linkable, $display_id_linkable, $priority, $dbname, $db_display_name,
         $release, $synonym, $info_type, $info_text, $type, $secondary_db_name,
	 $secondary_db_table) = @$arrayref;

    if(!$exDB) {
      $exDB = Bio::EnsEMBL::DBEntry->new
        ( -adaptor => $self,
          -dbID => $dbID,
          -primary_id => $dbprimaryId,
          -display_id => $displayid,
          -version => $version,
          -release => $release,
          -dbname => $dbname,
	  -primary_id_linkable => $primary_id_linkable,
	  -display_id_linkable => $display_id_linkable,
	  -priority => $priority,
	  -db_display_name=>$db_display_name,
	  -info_type => $info_type,
	  -info_text => $info_text,
	  -type => $type,
	  -secondary_db_name => $secondary_db_name,
	  -secondary_db_table => $secondary_db_table);

      $exDB->description( $desc ) if ( $desc );
    }

    $exDB->add_synonym( $synonym )  if ($synonym);
  }

  $sth->finish();

  return $exDB;
}


=head2 _fetch_by_object_type

  Arg [1]    : string $ensID
  Arg [2]    : string $ensType
  			   (object type to be returned) 
  Arg [3]    : optional $exdbname (external database name)
  Arf [4]    : optional $exdb_type (external database type)
  Example    : $self->_fetch_by_object_type( $translation_id, 'Translation' )
  Description: Fetches DBEntry by Object type
  Returntype : arrayref of DBEntry objects; may be of type IdentityXref if
               there is mapping data, or GoXref if there is linkage data.
  Exceptions : none
  Caller     : fetch_all_by_Gene
               fetch_all_by_Translation
               fetch_all_by_Transcript
  Status     : Stable

=cut

#We need to modify this to return full DBEntries with ensembl_object and linkage annotation
#for a given external_id/accession
#Currently can only list reg feat IDs for a given external_id
#But we want 


sub _fetch_by_object_type {
  my ( $self, $ensID, $ensType, $exdbname, $exdb_type ) = @_;

  my @out;

  if ( !defined($ensID) ) {
    throw("Can't fetch_by_EnsObject_type without an object");
  }

  if ( !defined($ensType) ) {
    throw("Can't fetch_by_EnsObject_type without a type");
  }

  #  my $sth = $self->prepare("
  my $sql = (<<SSQL);
    SELECT xref.xref_id, xref.dbprimary_acc, xref.display_label, xref.version,
           xref.description,
           exDB.dbprimary_acc_linkable, exDB.display_label_linkable,
           exDB.priority,
           exDB.db_name, exDB.db_release, exDB.status, exDB.db_display_name,
           exDB.secondary_db_name, exDB.secondary_db_table,
           oxr.object_xref_id,
           es.synonym,
           idt.query_identity, idt.target_identity, idt.hit_start,
           idt.hit_end, idt.translation_start, idt.translation_end,
           idt.cigar_line, idt.score, idt.evalue, idt.analysis_id,
           gx.linkage_type,
           xref.info_type, xref.info_text, exDB.type, gx.source_xref_id,
           oxr.linkage_annotation
    FROM   (xref xref, external_db exDB, object_xref oxr)
    LEFT JOIN external_synonym es on es.xref_id = xref.xref_id 
    LEFT JOIN identity_xref idt on idt.object_xref_id = oxr.object_xref_id
    LEFT JOIN go_xref gx on gx.object_xref_id = oxr.object_xref_id
    WHERE  xref.xref_id = oxr.xref_id
      AND  xref.external_db_id = exDB.external_db_id 
      AND  oxr.ensembl_id = ?
      AND  oxr.ensembl_object_type = ?
SSQL
  $sql .= " AND exDB.db_name like '" . $exdbname . "' " if ($exdbname);
  $sql .= " AND exDB.type like '" . $exdb_type . "' "   if ($exdb_type);
  my $sth = $self->prepare($sql);

  $sth->bind_param( 1, $ensID,   SQL_INTEGER );
  $sth->bind_param( 2, $ensType, SQL_VARCHAR );
  $sth->execute();

  my ( %seen, %linkage_types, %synonyms );

  my $max_rows = 1000;

  while ( my $rowcache = $sth->fetchall_arrayref( undef, $max_rows ) ) {
    while ( my $arrRef = shift( @{$rowcache} ) ) {
      my ( $refID,                  $dbprimaryId,
           $displayid,              $version,
           $desc,                   $primary_id_linkable,
           $display_id_linkable,    $priority,
           $dbname,                 $release,
           $exDB_status,            $exDB_db_display_name,
           $exDB_secondary_db_name, $exDB_secondary_db_table,
           $objid,                  $synonym,
           $queryid,                $targetid,
           $query_start,            $query_end,
           $translation_start,      $translation_end,
           $cigar_line,             $score,
           $evalue,                 $analysis_id,
           $linkage_type,           $info_type,
           $info_text,              $type,
           $source_xref_id,          $link_annotation
      ) = @$arrRef;

      my $linkage_key =
        ( $linkage_type || '' ) . ( $source_xref_id || '' );

      my %obj_hash = ( 'adaptor'            => $self,
                       'dbID'               => $refID,
                       'primary_id'         => $dbprimaryId,
                       'display_id'         => $displayid,
                       'version'            => $version,
                       'release'            => $release,
                       'info_type'          => $info_type,
                       'info_text'          => $info_text,
                       'type'               => $type,
                       'secondary_db_name'  => $exDB_secondary_db_name,
                       'secondary_db_table' => $exDB_secondary_db_table,
                       'dbname'             => $dbname,
					   'linkage_annotation' => $link_annotation);

      # Using an outer join on the synonyms as well as on identity_xref,
      # we now have to filter out the duplicates (see v.1.18 for
      # original). Since there is at most one identity_xref row per
      # xref, this is easy enough; all the 'extra' bits are synonyms.
      if ( !$seen{$refID} ) {
        my $exDB;

        if ( ( defined($queryid) ) ) {  # an xref with similarity scores
          $exDB = Bio::EnsEMBL::IdentityXref->new_fast( \%obj_hash );
          $exDB->query_identity($queryid);
          $exDB->target_identity($targetid);

          if ( defined($analysis_id) ) {
            my $analysis =
              $self->db()->get_AnalysisAdaptor()
              ->fetch_by_dbID($analysis_id);

            if ( defined($analysis) ) { $exDB->analysis($analysis) }
          }

          $exDB->cigar_line($cigar_line);
          $exDB->query_start($query_start);
          $exDB->translation_start($translation_start);
          $exDB->translation_end($translation_end);
          $exDB->score($score);
          $exDB->evalue($evalue);

        } elsif ( defined $linkage_type && $linkage_type ne "" ) {
          $exDB = Bio::EnsEMBL::GoXref->new_fast( \%obj_hash );
          my $source_xref = ( defined($source_xref_id)
                              ? $self->fetch_by_dbID($source_xref_id)
                              : undef );
          $exDB->add_linkage_type( $linkage_type, $source_xref || () );
          $linkage_types{$refID}->{$linkage_key} = 1;

        } else {
          $exDB = Bio::EnsEMBL::DBEntry->new_fast( \%obj_hash );
        }

        if ( defined($desc) )        { $exDB->description($desc) }
        if ( defined($exDB_status) ) { $exDB->status($exDB_status) }

        $exDB->primary_id_linkable($primary_id_linkable);
        $exDB->display_id_linkable($display_id_linkable);
        $exDB->priority($priority);
        $exDB->db_display_name($exDB_db_display_name);

        push( @out, $exDB );
        $seen{$refID} = $exDB;

      } ## end if ( !$seen{$refID} )

      # $exDB still points to the same xref, so we can keep adding GO
      # evidence tags or synonyms.

      if ( defined($synonym) && !$synonyms{$refID}->{$synonym} ) {
        if ( defined($synonym) ) {
          $seen{$refID}->add_synonym($synonym);
        }
        $synonyms{$refID}->{$synonym} = 1;
      }

      if (    defined($linkage_type)
           && $linkage_type ne ""
           && !$linkage_types{$refID}->{$linkage_key} )
      {
        my $source_xref = ( defined($source_xref_id)
                            ? $self->fetch_by_dbID($source_xref_id)
                            : undef );
        $seen{$refID}
          ->add_linkage_type( $linkage_type, $source_xref || () );
        $linkage_types{$refID}->{$linkage_key} = 1;
      }
    } ## end while ( my $arrRef = shift...
  } ## end while ( my $rowcache = $sth...

  return \@out;
} ## end sub _fetch_by_object_type



#Placeholders to catch error
#These now work in reverse as the Gene/Transcript/Translation 
#is the xref not the ensembl_object as with the core code

sub fetch_all_by_Gene {
  my ( $self, $gene) = @_;
 
  if(! (ref($gene) && $gene->isa('Bio::EnsEMBL::Gene'))) {
    throw("Bio::EnsEMBL::Gene argument expected.");
  }

  throw('Not yet implemented for eFG');


  #This is going to be a bit of a work around as we should really have a separate fetch method
  #fetch_all_by_external_name_object_type?
  #No!! Because this simply pulls back the xrefs, not the object xrefs!!
  #This is the same for the fetch_by_dbID method???

  #_fetch_by_external_id
  #The problem here is that we want to return ox info aswell.
  #Just rewrite _fetch_by_object_type




}

sub fetch_all_by_Transcript {
  my ( $self, $trans) = @_;

  throw('Not implemented in eFG, maybe you want the core DBEntryAdaptor?');  


  if(! $trans->isa('Bio::EnsEMBL::Transcript')){
	throw('Must provide a valid stored Bio::EnsEMBL::Transcript');
  }
  #Thsi method doesn't work like this and just returns the xref with no object_xref info/join.
  $self->fetch_by_db_accession($trans->stable_id, 'ensembl_core_Gene');
}


sub fetch_all_by_Translation {
  my ( $self, $trans) = @_;
  throw('Not implemented in eFG, maybe you want the core DBEntryAdaptor?');  
}

#Haven't we replaced these for eFG feature with a direct call in the object/object_adaptor?


sub list_gene_ids_by_external_db_id{
   my ($self,$external_db_id) = @_;

throw('Not implemented in eFG, maybe you want the core DBEntryAdaptor?');



   my %T = map { ($_, 1) }
       $self->_type_by_external_db_id( $external_db_id, 'Translation', 'gene' ),
       $self->_type_by_external_db_id( $external_db_id, 'Transcript',  'gene' ),
       $self->_type_by_external_db_id( $external_db_id, 'Gene' );
   return keys %T;
}



sub list_gene_ids_by_extids {
  my ( $self, $external_name, $external_db_name ) = @_;

throw('Not implemented in eFG, maybe you want the core DBEntryAdaptor?');



  my %T = map { ( $_, 1 ) }
    $self->_type_by_external_id( $external_name, 'Translation', 'gene',
                                 $external_db_name ),
    $self->_type_by_external_id( $external_name, 'Transcript', 'gene',
                                 $external_db_name ),
    $self->_type_by_external_id( $external_name, 'Gene', undef,
                                 $external_db_name );

  return keys %T;
}


=head2 list_transcript_ids_by_extids

  Arg [1]    : string $external_name
  Arg [2]    : (optional) string $external_db_name
  Example    : @tr_ids = $dbea->list_gene_ids_by_extids('BCRA2');
  Description: Retrieve a list transcript ids by an external identifier that 
               is linked to any of the genes transcripts, translations or the 
               gene itself 
  Returntype : list of ints
  Exceptions : none
  Caller     : unknown
  Status     : Stable

=cut

sub list_transcript_ids_by_extids {
  my ( $self, $external_name, $external_db_name ) = @_;

throw('Not implemented in eFG, maybe you want the core DBEntryAdaptor?');



  my %T = map { ( $_, 1 ) }
    $self->_type_by_external_id( $external_name, 'Translation',
                                 'transcript',   $external_db_name
    ),
    $self->_type_by_external_id( $external_name, 'Transcript', undef,
                                 $external_db_name );

  return keys %T;
}



sub list_translation_ids_by_extids {
  my ( $self, $external_name, $external_db_name ) = @_;

  throw('Not implemented in eFG, maybe you want the core DBEntryAdaptor?');


  return
    $self->_type_by_external_id( $external_name, 'Translation', undef,
                                 $external_db_name );
}


=head2 list_feature_type_ids_by_extid

  Arg [1]    : string $external_name
  Arg [2]    : (optional) string $external_db_name
  Example    : @tr_ids = $dbea->list_feature_type_ids_by_extid('BEAF-32');
  Description: Gets a list of regulatory_feature IDs by external display IDs
  Returntype : list of Ints
  Exceptions : none
  Caller     : unknown
  Status     : At risk

=cut

sub list_feature_type_ids_by_extid {
  my ( $self, $external_name, $external_db_name ) = @_;

  return $self->_type_by_external_id( $external_name, 'FeatureType', 
									  undef, $external_db_name );
}



=head2 list_regulatory_feature_ids_by_extid

  Arg [1]    : string $external_name
  Arg [2]    : (optional) string $external_db_name
  Example    : @tr_ids = $dbea->list_regulatory_feature_ids_by_extid('GO:0004835');
  Description: Gets a list of regulatory_feature IDs by external display IDs
  Returntype : list of Ints
  Exceptions : none
  Caller     : unknown
  Status     : At risk

=cut

sub list_regulatory_feature_ids_by_extid {
  my ( $self, $external_name, $external_db_name ) = @_;

 
  return $self->_type_by_external_id( $external_name, 'RegulatoryFeature', 
									  undef, $external_db_name );
}

=head2 list_external_feature_ids_by_extid

  Arg [1]    : string $external_name
  Arg [2]    : (optional) string $external_db_name
  Example    : @tr_ids = $dbea->list_external_feature_ids_by_extid('GO:0004835');
  Description: Gets a list of external_feature IDs by external display IDs
  Returntype : list of Ints
  Exceptions : none
  Caller     : unknown
  Status     : At risk

=cut

sub list_external_feature_ids_by_extid {
  my ( $self, $external_name, $external_db_name ) = @_;

  return
    $self->_type_by_external_id( $external_name, 'ExternalFeature', undef,
                                 $external_db_name );
}

=head2 list_annotated_feature_ids_by_extid

  Arg [1]    : string $external_name
  Arg [2]    : (optional) string $external_db_name
  Example    : @tr_ids = $dbea->list_annotated_feature_ids_by_extid('GO:0004835');
  Description: Gets a list of annotated_feature IDs by external display IDs
  Returntype : list of Ints
  Exceptions : none
  Caller     : unknown
  Status     : At risk

=cut

sub list_annotated_feature_ids_by_extid {
  my ( $self, $external_name, $external_db_name ) = @_;

  return
    $self->_type_by_external_id( $external_name, 'AnnotatedFeature', undef,
                                 $external_db_name );
}

=head2 list_probe_feature_ids_by_extid

  Arg [1]    : string $external_name
  Arg [2]    : (optional) string $external_db_name
  Example    : @tr_ids = $dbea->list_annotated_feature_ids_by_extid('ENST000000000001');
  Description: Gets a list of annotated_feature IDs by external display IDs
  Returntype : list of Ints
  Exceptions : none
  Caller     : unknown
  Status     : At risk

=cut

sub list_probe_feature_ids_by_extid {
  my ( $self, $external_name, $external_db_name ) = @_;

  return
    $self->_type_by_external_id( $external_name, 'ProbeFeature', undef,
                                 $external_db_name );
}


=head2 list_regulatory_feature_ids_by_external_db_id

  Arg [1]    : string $external_id
  Example    : @gene_ids = $dbea->list_regulatory_feature_ids_by_external_db_id(1020);
  Description: Retrieve a list of regulatory_feature ids by an external identifier that is
               linked to  any of the genes transcripts, translations or the
               gene itself. NOTE: if more than one external identifier has the
               same primary accession then genes for each of these is returned.
  Returntype : list of ints
  Exceptions : none
  Caller     : unknown
  Status     : Stable

=cut

sub list_regulatory_feature_ids_by_external_db_id{
   my ($self,$external_db_id) = @_;

   my %T = map { ($_, 1) }
            $self->_type_by_external_db_id( $external_db_id, 'RegulatoryFeature' );
   return keys %T;
}





=head2 _type_by_external_id

  Arg [1]    : string $name - dbprimary_acc
  Arg [2]    : string $ensType - ensembl_object_type
  Arg [3]    : (optional) string $extraType
  Arg [4]    : (optional) string $external_db_name
  	       other object type to be returned
  Example    : $self->_type_by_external_id($name, 'regulatory_feature');
  Description: Gets
  Returntype : list of dbIDs (regulatory_feature, external_feature )
  Exceptions : none
  Caller     : list_regulatory/external_feature_ids_by_extid
  Status     : Stable

=cut

sub _type_by_external_id {
  my ( $self, $name, $ensType, $extraType, $external_db_name ) = @_;

  my $from_sql  = '';
  my $where_sql = '';
  my $ID_sql    = "oxr.ensembl_id";

  if ( defined $extraType ) {

	throw('Extra types not accomodated in eFG xref schema');

    if ( lc($extraType) eq 'translation' ) {
      $ID_sql = "tl.translation_id";
    } else {
      $ID_sql = "t.${extraType}_id";
    }

    if ( lc($ensType) eq 'translation' ) {
      $from_sql  = 'transcript t, translation tl, ';
      $where_sql = qq(
          t.transcript_id = tl.transcript_id AND
          tl.translation_id = oxr.ensembl_id AND
          t.is_current = 1 AND
      );
    } else {
      $from_sql  = 'transcript t, ';
      $where_sql = 't.'
        . lc($ensType)
        . '_id = oxr.ensembl_id AND '
        . 't.is_current = 1 AND ';
    }
  }

  #if ( lc($ensType) eq 'gene' ) {
  #  $from_sql  = 'gene g, ';
  #  $where_sql = 'g.gene_id = oxr.ensembl_id AND g.is_current = 1 AND ';
  #} elsif ( lc($ensType) eq 'transcript' ) {
  #  $from_sql = 'transcript t, ';
  #  $where_sql =
  #    't.transcript_id = oxr.ensembl_id AND t.is_current = 1 AND ';
  #} elsif ( lc($ensType) eq 'translation' ) {
  #  $from_sql  = 'transcript t, translation tl, ';
  #  $where_sql = qq(
  #      t.transcript_id = tl.transcript_id AND
  #      tl.translation_id = oxr.ensembl_id AND
  #      t.is_current = 1 AND
  #  );
  #}
  #


  if(lc($ensType) eq 'regulatoryfeature'){
	$from_sql  = 'regulatory_feature rf, ';
	$where_sql = qq( rf.regulatory_feature_id = oxr.ensembl_id AND );
  }
  elsif(lc($ensType) eq 'externalfeature'){
	$from_sql  = 'external_feature ef, ';
	$where_sql = qq( ef.external_feature_id = oxr.ensembl_id AND );
  } 
  elsif(lc($ensType) eq 'annotatedfeature'){
	$from_sql  = 'annotated_feature af, ';
	$where_sql = qq( af.annotated_feature_id = oxr.ensembl_id AND );
  }
  elsif(lc($ensType) eq 'featuretype'){
	$from_sql  = 'featuretype ft, ';
	$where_sql = qq( ft.feature_type_id = oxr.ensembl_id AND );
  }
  elsif(lc($ensType) eq 'probefeature'){
	$from_sql  = 'probe_feature pf, ';
	$where_sql = qq( pf.probe_feature_id = oxr.ensembl_id AND );
  }

  

  if ( defined($external_db_name) ) {
    # Involve the 'external_db' table to limit the hits to a particular
    # external database.

    $from_sql .= 'external_db xdb, ';
    $where_sql .=
        'xdb.db_name LIKE '
      . $self->dbc()->db_handle()->quote( $external_db_name . '%' )
      . ' AND xdb.external_db_id = x.external_db_id AND';
  }

  my @queries = (
    "SELECT $ID_sql
       FROM $from_sql xref x, object_xref oxr
      WHERE $where_sql x.dbprimary_acc = ? AND
             x.xref_id = oxr.xref_id AND
             oxr.ensembl_object_type= ?",
    "SELECT $ID_sql 
       FROM $from_sql xref x, object_xref oxr
      WHERE $where_sql x.display_label = ? AND
             x.xref_id = oxr.xref_id AND
             oxr.ensembl_object_type= ?"
  );

  if ( defined $external_db_name ) {
    # If we are given the name of an external database, we need to join
    # between the 'xref' and the 'object_xref' tables on 'xref_id'.

    push @queries, "SELECT $ID_sql
       FROM $from_sql xref x, object_xref oxr, external_synonym syn
      WHERE $where_sql syn.synonym = ? AND
             x.xref_id = oxr.xref_id AND
             oxr.ensembl_object_type= ? AND
             syn.xref_id = oxr.xref_id";
  } else {
    # If we weren't given an external database name, we can get away
    # with less joins here.

    push @queries, "SELECT $ID_sql
       FROM $from_sql object_xref oxr, external_synonym syn
      WHERE $where_sql syn.synonym = ? AND
             oxr.ensembl_object_type= ? AND
             syn.xref_id = oxr.xref_id";
  }

  # Increase speed of query by splitting the OR in query into three
  # separate queries.  This is because the 'or' statments render the
  # index useless because MySQL can't use any fields in it.

  my %hash   = ();
  my @result = ();

  foreach (@queries) {
    my $sth = $self->prepare($_);
    $sth->bind_param( 1, "$name",  SQL_VARCHAR );
    $sth->bind_param( 2, $ensType, SQL_VARCHAR );
    $sth->execute();

    while ( my $r = $sth->fetchrow_array() ) {
      if ( !exists $hash{$r} ) {
        $hash{$r} = 1;
        push( @result, $r );
      }
    }
  }

  return @result;
} ## end sub _type_by_external_id

=head2 _type_by_external_db_id

  Arg [1]    : string $type - external_db type
  Arg [2]    : string $ensType - ensembl_object_type
  Arg [3]    : (optional) string $extraType
  	       other object type to be returned
  Example    : $self->_type_by_external_id(1030, 'Translation');
  Description: Gets
  Returntype : list of dbIDs (gene_id, transcript_id, etc.)
  Exceptions : none
  Caller     : list_translation_ids_by_extids
               translationids_by_extids
  	       geneids_by_extids
  Status     : Stable

=cut

sub _type_by_external_db_id{
  my ($self, $external_db_id, $ensType, $extraType) = @_;

  my $from_sql = '';
  my $where_sql = '';
  my $ID_sql = "oxr.ensembl_id";

  if (defined $extraType) {

	throw('Extra types not accomodated in eFG xref schema');

    if (lc($extraType) eq 'translation') {
      $ID_sql = "tl.translation_id";
    } else {
      $ID_sql = "t.${extraType}_id";
    }

    if (lc($ensType) eq 'translation') {
      $from_sql = 'transcript t, translation tl, ';
      $where_sql = qq(
          t.transcript_id = tl.transcript_id AND
          tl.translation_id = oxr.ensembl_id AND
          t.is_current = 1 AND
      );
    } else {
      $from_sql = 'transcript t, ';
      $where_sql = 't.'.lc($ensType).'_id = oxr.ensembl_id AND '.
          't.is_current = 1 AND ';
    }
  }

 # if (lc($ensType) eq 'gene') {
 #   $from_sql = 'gene g, ';
 #   $where_sql = 'g.gene_id = oxr.ensembl_id AND g.is_current = 1 AND ';
 # } elsif (lc($ensType) eq 'transcript') {
 #   $from_sql = 'transcript t, ';
 #   $where_sql = 't.transcript_id = oxr.ensembl_id AND t.is_current = 1 AND ';
 # } elsif (lc($ensType) eq 'translation') {
 #   $from_sql = 'transcript t, translation tl, ';
  #   $where_sql = qq(
  #       t.transcript_id = tl.transcript_id AND
  #       tl.translation_id = oxr.ensembl_id AND
  #       t.is_current = 1 AND
  #   );
 # }els

  if(lc($ensType) eq 'regulatoryfeature'){
	$from_sql  = 'regulatory_feature rf, ';
	$where_sql = qq( rf.regulatory_feature_id = oxr.ensembl_id AND );
  }
  elsif(lc($ensType) eq 'externalfeature'){
	$from_sql  = 'external_feature ef, ';
	$where_sql = qq( ef.external_feature_id = oxr.ensembl_id AND );
  } 
  elsif(lc($ensType) eq 'annotatedfeature'){
	$from_sql  = 'annotated_feature af, ';
	$where_sql = qq( af.annotated_feature_id = oxr.ensembl_id AND );
  }
  elsif(lc($ensType) eq 'featuretype'){
	$from_sql  = 'featuretype ft, ';
	$where_sql = qq( ft.feature_type_id = oxr.ensembl_id AND );
  }
  elsif(lc($ensType) eq 'probefeature'){
	$from_sql  = 'probe_feature pf, ';
	$where_sql = qq( pf.probe_feature_id = oxr.ensembl_id AND );
  }


  my $query = 
    "SELECT $ID_sql
       FROM $from_sql xref x, object_xref oxr
      WHERE $where_sql x.external_db_id = ? AND
  	     x.xref_id = oxr.xref_id AND oxr.ensembl_object_type= ?";

# Increase speed of query by splitting the OR in query into three separate 
# queries. This is because the 'or' statments render the index useless 
# because MySQL can't use any fields in the index.

  my %hash = ();
  my @result = ();


  my $sth = $self->prepare( $query );
  $sth->bind_param(1, "$external_db_id", SQL_VARCHAR);
  $sth->bind_param(2, $ensType, SQL_VARCHAR);
  $sth->execute();
  while( my $r = $sth->fetchrow_array() ) {
    if( !exists $hash{$r} ) {
      $hash{$r} = 1;
      push( @result, $r );
    }
  }
  return @result;
}


1;

