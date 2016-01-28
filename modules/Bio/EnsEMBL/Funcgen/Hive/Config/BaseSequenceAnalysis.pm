package Bio::EnsEMBL::Funcgen::Hive::Config::BaseSequenceAnalysis;

use strict;
use warnings;
use base qw(Bio::EnsEMBL::Funcgen::Hive::Config::BaseDB);

sub default_options {
  my $self = shift;  
  
  return {
    %{$self->SUPER::default_options},
     
     #default feature_set_analyses
     default_peaks       => 'SWEmbl_R015', 
     default_tight_peaks => 'SWEmbl_R0025', 
     default_broad_peaks => 'ccat_histone',
     permissive_peaks    => 'SWEmbl_R0005',
     idr_peaks           => 'SWEmbl_R0005_IDR', 

    broad_peak_feature_types => ['H3K36me3', 'H3K27me3'],
#     broad_peak_feature_types => [
#       'H3K36me3', 'H3K79me2', 'H3K27me3', 'H3K9me3', 'H3K9me1'
#     ],

    default_peak_analyses => {
      Histone             => $self->o('default_peaks'),
      'Transcription Factor' => $self->o('default_peaks'), 
      'Polymerase'        => $self->o('default_peaks'), 
      DNase1              => $self->o('default_tight_peaks'),
      
      H3K36me3            => $self->o('default_broad_peaks'), 
      H3K27me3            => $self->o('default_broad_peaks'), 
#       H3K79me2            => $self->o('default_broad_peaks'), 
#       H3K9me3             => $self->o('default_broad_peaks'), 
#       H3K9me1             => $self->o('default_broad_peaks'), 
     }, 
   
 
    'control_feature_types' => ['Goat-IgG', 'Rabbit-IgG', 'WCE', 'rat-IgG-control', 'rabbit-IgG-control', 'mouse-IgG-control', 'GFP'], 
    'checksum_optional' => 0,   
   };
  
}

sub pipeline_wide_parameters {
  my $self = shift;
    
  return {
    %{$self->SUPER::pipeline_wide_parameters}, 

    'control_feature_types'    => $self->o('control_feature_types'),    
    'broad_peak_feature_types' => $self->o('broad_peak_feature_types'), 
    'checksum_optional'        => $self->o('checksum_optional'),

    batch_param_names => [
       'no_write', #For use with runWorker.pl -no_write, so we can write some STDOUT in run
                   #is this already available in the job, or is it just passed ot the worker?
        #Generic optional params (used in Helper and elsewhere)
        'rollback',
        'full_delete',
        'slices',
        'skip_slices',
        ### More optional Helper params (currently used in DefineOutputSet)
        'result_set_only',
        'result_set_mode', #Can only be set to recover at present
        'recover',         #is this an Importer or a Helper param?
        
        'alignment_analysis',
        'peak_analysis',
        'permissive_peaks',
        'control_feature',
        
        #ReadAlignments.pm batch params
        'no_idr', #This is required
        'indexed_ref_fasta',
        'max_peaks',
        'checksum_optional'
      ],
    };
}

sub pipeline_analyses {
  my $self = shift;
  return [
    {
     -logic_name  => 'DefineMergedDataSet',
     -module      => 'Bio::EnsEMBL::Funcgen::Hive::DefineDataSet',     
     -parameters  => {
       default_feature_set_analyses => $self->o('default_peak_analyses'),
       feature_set_analysis_type    => 'peak',
       check_analysis_can_run       => 1,
      },
     -analysis_capacity => 100,
     -rc_name           => 'default',
     -batch_size        => 10, 
    },
   ];
}

1;
