
=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

Bio::EnsEMBL::Hive::Funcgen::PrprocessFastqs

=head1 DESCRIPTION

This analysis validates the composition of the ResultSet and merges
and chunks control or signal fastq files appropriately, in preparation
for running the alignment of individual chunks.

=cut

package Bio::EnsEMBL::Funcgen::Hive::PreprocessFastqs;

use warnings;
use strict;

use Bio::EnsEMBL::Utils::Exception         qw( throw );
use Bio::EnsEMBL::Funcgen::Utils::EFGUtils qw( is_gzipped run_system_cmd 
                                               run_backtick_cmd check_file );
use base qw( Bio::EnsEMBL::Funcgen::Hive::BaseDB );

#TODO... use and update the tracking database dependant on no_tracking...

#todo
# Add status tracking support for identifying which InputSubsets might already have been aligned?
# Is this actually relevant? The files may have been moved away? Options here are to force re-run
# or move files back from archive. We should enable archive access of bams?
# Normal mode would simply try and copy the files back? There maybe parallel processes doing trying to do this
# hence checksum is necessay here. Reruns of job may pick up complete copy later on.
# We need to copy the check sum file first.
# There is still a very slight risk of a race condition when files are tested and copied.
# Hence we probably need to flock here?
# dynamic file archiving should not run on controls, leave this as a manual post pipeline step
# to minimise these risks
# Add ignore_checksums flag, this should stil create them, jsut not check them?
#



sub fetch_input {  
  my $self = shift;
  $self->SUPER::fetch_input();
  my $rset = $self->fetch_Set_input('ResultSet');


  #RunAligner need not know anything about the ResultSet
  #So we can validate all that here and simply pass the files through to align
  #Need to leave module validation to RunAligner
  #but can pass the params directly, rather than in ResultSet
  

  
  #get/validate merge and run_controls
  #what about dataflow onwards, this will differ
  #dependant the next analysis 
  #e.g. DefineMergedDataSet, Run_BWA_and_QC_merged, DefineReplicateDataSet or BWA_ReplicateFactory
  #or can we do this implicitly just by check if we have set_names/ids set?
  
  #This may allow unmerged controls, if we set merge to 0 in the analysis config
  my $run_controls = $self->get_param_method('result_set_groups', 'silent') ? 1 : 0;
  $self->set_param_method('run_controls', $run_controls);
  my $merge        = $self->get_param_method('merge', 'silent', $run_controls); 
  $self->get_param_method('checksum_optional', 'silent');
  
     
  
  
  
  #we really need to define a Base Aligner class similar to the PeakCaller class
  #define a standard interface/requirements
  #location of indexes needs to be built here
  #based an analysis name
  #do we need a index_required sub?
  #Let's do all of this in BWA for now? 
  
  #Hmm this is just chunking the files! and submitting the individual jobs!
  #Hence we need more analyses:
  #1 to run the individual BWA jobs
  #2 to merge the alignments and perform QC!
  
  
  

  $self->get_param_method('fastq_chunk_size', 'silent', '16000000');#default should run in 30min-1h 
  #does this even support input sets yet?

  
  #We need to define the work dir here for the intermediate chunk/alignments files
  #output_dir here is for alignment (no need for repository)
  $self->get_output_work_dir_methods($self->alignment_dir($rset, 1, $run_controls));#default output_dir 
  return;
}


sub run {
  my $self         = shift;
  my $rset         = $self->ResultSet;
  my $run_controls = $self->run_controls;
  my $merge        = $self->merge;
 
  #Maybe we need to handle pre-aligned ResultSets here
  #check status and file
  
  #unsafe to check individual input_subsets, as these may have been processed
  #in an incomplete manner previously
  #Although we need to be mindful that a ResultSet may have had an InputSubset added
  #hence we can't re-use an old alignment file
  #this should be handled when creating/rolling back the ResultSet
  
  
  #This status needs to be CS specific!!
  my $align_status = 'ALIGNED';#$self->get_coord_system_status('ALIGNED');#put this in BaseSequenceAnalysis
  $align_status   .= '_CONTROL' if $run_controls;
  
  #We have an inheritance issue here
  #BaseSequenceAnalysis isa BaseImporter?
  
  warn $rset->name.' states '.join(' ', @{$rset->get_all_states});
  
  if($rset->has_status($align_status)){
    throw("Need to implement force/recover_alignment. Found $align_status ResultSet:\t".
      $rset->name."\n");
     
    #Actually, this should only be allowed if we are recovering
    #force should have rolled back the ResultSet ALIGNED status
    #although ideally this should be handled in the previous analysis
    #and flowed directly to DefineReplicate/MergedDataSet
    #Hence we should never reuse the merged fastq?
    #if we are recovering, we want the bam file (given the reps are the same)
    #if we are forcing or rolling back, then we should probably redo everything
  }
  
  
  

  my @fastqs;
  my $throw = '';
  
  foreach my $isset(@{$rset->get_support('input_subset')}){

    if(($isset->is_control && ! $run_controls) ||
       ($run_controls && ! $isset->is_control)){
      next;    
    }
 
    if(! $self->tracking_adaptor->fetch_InputSubset_tracking_info($isset)){
       $throw .= "Could not find tracking info for InputSubset:\t".
        $isset->name."\n";
      next;
    }
    
    if(! defined $isset->local_url){
      $throw .= "Found an InputSubset without a local_url, has this been downloaded?:\t".
        $isset->name."\n";
      next;  
    }

    my $found_path;
    my $params = {};#{gunzip => 1};
    #Instead of gunzipping in the warehouse, zcat is now used to 
    #pipe directly split directly into the work area
    #This reduces tidy up and keeps footprint low, so we don't hit
    #out of space errors when running with a full warehouse
    #or a nearly full scratch space
    #This will also prevent any clashes between unzipping files in the warehouse
    #188 secs to zcat 227MB gzipped fastq
    #vs
    #10 secs to gunzip (to 1.2GB) and cat
    #This does not include rezip and tidy up time of ~90 secs 
    #(which could arguably be defered to after the pipeline run)
    #This is quite a large difference, but with and average of 2 or 3 reps 
    #this will probably make this run to ~10mins, which is negligable
    #compared to the down time from managing failed jobs due to out of space 
    #issues.
    
    #Set checksum   
    #As we already know we don't have a checksum, simply omit it here
    #which will mean validate_checksum will not be called
    #Alterntive is to set an undef checksum and checksum_optinal
    #This will cause validate_checksum to try and find a checksum from a file
    #But we know these checksums are stored in the DB
        
    if(defined $isset->md5sum || ! $self->checksum_optional ){
      warn "Specifying checksum";
      $params->{checksum} = $isset->md5sum; 
    }
    
    #This needs to unzip them too!
    my $local_url = $isset->local_url;
    my $suffix = 'gz' if $local_url !~ /\.gz$/o;                
    eval { $found_path = check_file($local_url, 'gz', $params); };
 
    if($@){
      $throw .= "$@\n";
      next;  
    }
    elsif(! defined $found_path){
      $throw .= "Could not find fastq file, is either not downloaded, has been deleted or is in warehouse:\t".
        $local_url."\n";
      #Could try warehouse here?
    }
    elsif($found_path !~ /\.gz$/o){
      #use is_compressed here?
      run_system_cmd("gzip $found_path");
      $found_path .= '.gz';  
    }
    
     
    push @fastqs, $found_path;  
  }
 
  throw($throw) if $throw;
  
  if((scalar(@fastqs) > 1) &&
     ! $merge){
    throw('ResultSet '.$rset->name.
      " has more than one InputSubset, but merge has not been specified:\n\t".
      join("\n\t", @fastqs));    
  }  
 
  #This currently fails as it tries to launch an X11 window!
 
  ### RUN FASTQC
  #18-06-10: Version 0.4 released ... Added full machine parsable output for integration into pipelines
  #use -casava option for filtering
  
  #We could set -t here to match the number of cpus on the node?
  #This will need reflecting in the resource spec for this job
  #How do we specify non-interactive mode???
  #I think it just does this when file args are present
  
  #Can fastqc take compressed files?
  #Yes, but it seems to want to use Bzip to stream the data in
  #This is currently failing with:
  #Exception in thread "main" java.lang.NoClassDefFoundError: org/itadaki/bzip2/BZip2InputStream
  #Seems like there are some odd requirements for installing fastqc 
  #although this seems galaxy specific 
  #http://lists.bx.psu.edu/pipermail/galaxy-dev/2011-October/007210.html
  
  #This seems to happen even if the file is gunzipped!
  #and when executed from /dsoftware/ensembl/funcgen  
  #and when done in interative mode by loading the fastq through the File menu
  
  #This looks to be a problem with the fact that the wrapper script has been moved from the 
  #FastQC dir to the parent bin dir. Should be able to fix this with a softlink
  #Nope, this did not fix things!
  
  warn "DEACTIVATED FASTQC FOR NOW:\nfastqc -f fastq -o ".$self->output_dir." @fastqs";
  #run_system_cmd('fastqc -o '.$self->output_dir." @fastqs");
  

  
  
  
  #todo parse output for failures
  #also fastscreen?

  warn("Need to add parsing of fastqc report here to catch module failures");
  
  #What about adaptor trimming? and quality score trimming?
  #FASTX? quality_trimmer, clipper (do we have access to the primers?) and trimmer?
  #Should also probably do some post alignment comparison of GC content
  
  
  #Pass $run_controls, as they may not be from this experiment/study, 
  #hence will need to look at the InputSubset
  my $set_prefix = $self->get_set_prefix_from_Set($rset, $run_controls);
         

  #For safety, clean away any that match the prefix
  #todo, check that split append an underscore
  run_system_cmd('rm -f '.$self->work_dir."/${set_prefix}.fastq_*");#no exit?
     
  my $cmd = 'zcat '.join(' ', @fastqs).' | split -d -a 4 -l '.
    $self->fastq_chunk_size.' - '.$self->work_dir.'/'.$set_prefix.'.fastq_';
  $self->helper->debug(1, "run_system_cmd\t$cmd"); 
  run_system_cmd($cmd);

  #Get files to data flow to individual alignment jobs
  @fastqs = map { chomp($_) && $_; } run_backtick_cmd('ls '.$self->work_dir."/${set_prefix}.fastq_*");
  $self->set_param_method('fastq_files', \@fastqs);

  foreach my $fq_file(@{$self->fastq_files}){
  
    #Data flow to RunAligner for each of the chunks 
    #do we need to pass result set to aligner?
    #Would need to pass gender, analysis logic_name 
    
    $self->branch_job_group(2, [{set_type   => 'ResultSet',
                                 set_name   => $rset->name,
                                 dbID       => $rset->dbID,
                                 output_dir => $self->work_dir, #we could regenerate this from result_set and run controls
                                 fastq_file => $fq_file}]);
  }

  my %signal_info;
  
  if($run_controls){
    %signal_info = (result_set_groups => $self->result_set_groups);
    #for flow to MergeControlAlignments_and_QC
  }

  # Data flow to the MergeQCAlignements job 
  
  #This was a config problem, we had a circular semaphore using the same branch
  
  $self->branch_job_group(3, [{%{$self->batch_params},
                             set_type   => 'ResultSet',
                             set_name   => $rset->name,
                             dbID       => $rset->dbID,
                             #bam_files should really be accu'd from the RunAligner jobs
                             #but we know what they should be here 
                             #$_ =~ s/fastq_[0-9]+/bam/o
                             bam_files  => [ map {$_ =~ s/\.fastq_([0-9]+)$/.$1.bam/o; $_} @{$self->fastq_files} ], 
                             #we could regenerate these from result_set and run controls
                             #but passed for convenience
                             output_dir => $self->output_dir,
                             set_prefix => $set_prefix,
                             #run_controls => $run_controls,#now implicit from %signal_info
                             %signal_info}]);



  return;
}


sub write_output {  # Create the relevant jobs
  shift->dataflow_job_groups;
  return;
}



1;
