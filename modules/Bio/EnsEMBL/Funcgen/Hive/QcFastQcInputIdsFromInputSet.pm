
=pod 

=head1 NAME

Bio::EnsEMBL::Funcgen::Hive::QcFastQcInputIdsFromInputSet

=head1 DESCRIPTION

default_stuff='out_db => {"-dbname" => "mn1_faang2_tracking_homo_sapiens_funcgen_81_38","-host" => "ens-genomics1","-pass" => "ensembl","-port" => 3306,"-user" => "ensadmin"}, work_root_dir => "/lustre/scratch109/ensembl/funcgen/mn1/ersa/faang/debug", data_root_dir => "/lustre/scratch109/ensembl/funcgen/mn1/ersa/faang/", pipeline_name => "blah", use_tracking_db => 1, dnadb => {"-dnadb_host" => "ens-livemirror","-dnadb_name" => "homo_sapiens_core_82_38","-dnadb_pass" => "","-dnadb_port" => 3306,"-dnadb_user" => "ensro"}'

standaloneJob.pl Bio::EnsEMBL::Funcgen::Hive::QcFastQcInputIdsFromInputSet -input_id "{ $default_stuff, input_subset_id => 1234, }"

{

"alignment_analysis" => "bwa_samse","checksum_optional" => 0,"input_subset_ids" => {"HEL9217:hist:BR2_H3K27ac_3526" => [3220,3249,3385,3404,3436],"HEL9217:hist:BR2_H3K27me3_3526" => [3272,3347,3378],"HEL9217:hist:BR2_H3K4me3_3526" => [3259,3287,3322,3348,3437],"controls" => [3456]}

}

=cut

package Bio::EnsEMBL::Funcgen::Hive::QcFastQcInputIdsFromInputSet;

use warnings;
use strict;

use base qw( Bio::EnsEMBL::Funcgen::Hive::BaseDB );

sub run {
  my $self = shift;
  my $input_subset_ids = $self->param('input_subset_ids');
  
  die ('Type error') unless(ref $input_subset_ids eq 'HASH');
  
  my @keys = keys %$input_subset_ids;
  
  my @input_subset_id;
  foreach my $current_key (@keys) {
    my $current_input_subset_id = $input_subset_ids->{$current_key};

    die ('Type error') unless(ref $current_input_subset_id eq 'ARRAY');
    push @input_subset_id, @$current_input_subset_id;
  }
  
  foreach my $current_input_subset_id (@input_subset_id) {
    $self->dataflow_output_id(
      { input_subset_id => $current_input_subset_id }, 
      2
    );
  }
#   use Data::Dumper;
#   $Data::Dumper::Maxdepth = 0;
#   print Dumper(\@input_subset_id);
  
#  my $input_id = $self->create_input_id($input_subset_ids);  
  #$self->dataflow_output_id($input_id, 2);
  return;
}

sub create_input_id {

  my $self = shift;
  my $input_subset_id = shift;
  my $work_dir = $self->param_required('work_root_dir');
  my $temp_dir = "$work_dir/temp/Qc/FastQc/$input_subset_id";
  my $out_db = $self->param('out_db');

  my $input_id = {
      tempdir               => $temp_dir,
      input_subset_id       => $input_subset_id,
      
      # Connection details for the db to which the results will be written
      tracking_db_user   => $out_db->dbc->user,
      tracking_db_pass   => $out_db->dbc->password,
      tracking_db_host   => $out_db->dbc->host,
      tracking_db_name   => $out_db->dbc->dbname,
      tracking_db_port   => $out_db->dbc->port,
  };
  return $input_id;
}

1;
