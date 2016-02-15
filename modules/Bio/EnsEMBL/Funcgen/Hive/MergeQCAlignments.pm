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

Bio::EnsEMBL::Hive::Funcgen::MergeQCAlignments

=head1 DESCRIPTION

Merges bam alignments from split (replicate or merged) fastq files.

=cut

package Bio::EnsEMBL::Funcgen::Hive::MergeQCAlignments;

use warnings;
use strict;

use Bio::EnsEMBL::Utils::Exception         qw( throw );
use Bio::EnsEMBL::Funcgen::Utils::EFGUtils qw( run_system_cmd );
use Bio::EnsEMBL::Funcgen::Sequencing::SeqTools;# merge_bams 

use base qw( Bio::EnsEMBL::Funcgen::Hive::BaseDB );

my %valid_flow_modes = (replicate => undef,
                        merged    => undef,
                        signal    => undef); 

sub fetch_input {  
  my $self = shift;
  
  $self->SUPER::fetch_input();
  my $rset = $self->fetch_Set_input('ResultSet');
  
  $self->get_param_method('output_dir', 'required');
  $self->get_param_method('bam_files',  'silent');
  $self->get_param_method('fastq_files',  'silent');
    
  if((! $self->bam_files ) && $self->fastq_files) {
    my $bam_file;
    $self->bam_files([ map {($bam_file = $_) =~ s/\.fastq_([0-9]+)$/.$1.bam/o; $bam_file} @{$self->fastq_files} ]);
  } elsif(! $self->bam_files) {
    $self->throw_no_retry('No bam_files or fastq_files have been defined');    
  }
  
  $self->get_param_method('set_prefix', 'required');  #This is control specific
  my $flow_mode = $self->get_param_method('flow_mode',  'required');
  $self->set_param_method('run_controls', 0); 
  
  
  if(! exists $valid_flow_modes{$flow_mode}){
    throw("$flow_mode is now a valid flow_mode parameter, please specify one of:\t".
      join(' ', keys %valid_flow_modes));  
  }
  elsif($flow_mode eq 'signal'){
    $self->get_param_method('result_set_groups', 'required');
    $self->run_controls(1); 
  }
  elsif($self->get_param_method('result_set_groups', 'silent')){
    throw("The $flow_mode flow mode is not valid for use with result_set_groups"); 
  }
  elsif($flow_mode eq 'replicate'){
    $self->get_param_method('permissive_peaks', 'required');
  }
  
  #could have recreated output_dir and merged_file_name from ResultSet and run_controls
  #as we did in MergeChunkResultSetFastqs, but passed for convenience
  my $gender = $rset->cell_type->gender;
  
  # By default the file_gender is the same as the gender
  my $file_gender = $gender;
  
  # There are no files for "mixed". The default we use is "female"
  if ($gender eq 'mixed') {
    $file_gender = 'female';
  }
  if (! defined $gender) {
    $file_gender = 'male';
  }

  $self->sam_header($file_gender);
 
  $self->init_branching_by_analysis;
  return;
}


sub run {
  my $self       = shift;
  my $rset       = $self->ResultSet;
  my $sam_header = $self->sam_header;
  my $cmd;
  
  ### CLEAN FASTQS ###
  if($self->fastq_files){
    #Run with no exit flag so we don't fail on retry
    $cmd = 'rm -f '.join(' ', @{$self->fastq_files});
    $self->helper->debug(3, "Removing fastq chunks:\n$cmd");
    run_system_cmd($cmd, 1);
  }
  
  ### MERGE BAMS ###
  my $file_prefix  = $self->get_alignment_path_prefix_by_ResultSet($rset, $self->run_controls); 
  my $unfiltered_bam     = $file_prefix.'.bam';
  
  $self->helper->debug(1, "Merging bams to:\t".$unfiltered_bam); 
  
  merge_bams({
    input_bams => $self->bam_files, 
    output_bam => $unfiltered_bam, 
    debug => $self->debug,
  });
  
  my $tmp_bam = "${unfiltered_bam}.nodups.bam";
  
  remove_duplicates_from_bam({
    input_bam  => $unfiltered_bam,
    output_bam => $tmp_bam, 
    debug      => $self->debug,
  });
  
  unlink($unfiltered_bam);
  run_system_cmd("mv $tmp_bam $unfiltered_bam");

  my %batch_params = %{$self->batch_params};
  my $flow_mode    = $self->flow_mode;
  
  if($flow_mode ne 'signal'){   #flow_mode is merged or replicate
    #This is a prime example of pros/cons of using branch numbers vs analysis names
    #Any change in the analysis name conventions in the config will break this runnable
    #However, it does mean we can change the permissive peaks analysis
    #and branch without having to change the runnable at all i.e. we don't need to handle 
    #any new branches in here 
    
    #Can of course just piggy back an analysis on the same branch
    #But that will duplicate the jobs between analyses on the same branch
    
    my %output_id = (set_type    => 'ResultSet',
                     set_name    => $self->ResultSet->name,
                     dbID        => $self->ResultSet->dbID);

    if(! $self->debug) {
      $output_id{garbage} = $self->bam_files;
    } else {  
      # Do not garbage collect in debug mode. In case we need to rerun.
      warn "Skipping garbage collection for:\n".join("\n\t", @{$self->bam_files});
    }
  
    my $lname     = 'DefineMergedDataSet';  #flow mode eq merged

    if($flow_mode eq 'replicate'){
      $output_id{peak_analysis} = $self->permissive_peaks;
      $lname                    = 'run_'.$self->permissive_peaks.'_replicate';  
    }
        
    $self->branch_job_group($lname, [{%batch_params, %output_id}]);
  } else { 
    # Run signal fastqs
    my $rset_groups = $self->result_set_groups;
    my $align_anal  = $rset->analysis->logic_name;
    
    #This bit is very similar to some of the code in DefineResultSets
    #just different enough not to be subbable tho 
    
    foreach my $rset_group(keys %{$rset_groups}) {
      my @rep_or_merged_jobs;

      for my $i(0...$#{$rset_groups->{$rset_group}{dbIDs}}){
        push @rep_or_merged_jobs, {
	  %batch_params,
	  garbage     => $self->bam_files, 
	  set_type    => 'ResultSet',
	  set_name    => $rset_groups->{$rset_group}{set_names}->[$i],
	  dbID        => $rset_groups->{$rset_group}{dbIDs}->[$i]
	};
      }
      my $branch = ($rset_group eq 'merged') ? 
        'Preprocess_'.$align_anal.'_merged' : 'Preprocess_'.$align_anal.'_replicate';   
      
      my @job_group = ($branch, \@rep_or_merged_jobs);   
         
      if($rset_group ne 'merged') {
        # Add PreprocessIDR semaphore
        push @job_group, ('PreprocessIDR', 
                          [{%batch_params,
                            dbIDs     => $rset_groups->{$rset_group}{dbIDs},
                            set_names => $rset_groups->{$rset_group}{set_names},
                            set_type  => 'ResultSet'}]);
      }
      $self->branch_job_group(@job_group);
    }
  }
  return;
}

sub write_output {
  shift->dataflow_job_groups;
  return;
}



1;
