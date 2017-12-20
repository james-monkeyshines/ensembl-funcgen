package Bio::EnsEMBL::Funcgen::PipeConfig::ChIPSeqAnalysis::Backbone_conf;

use strict;
use warnings;
use base 'Bio::EnsEMBL::Funcgen::PipeConfig::ChIPSeqAnalysis::Base';
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;

sub pipeline_analyses {
    my $self = shift;

    return [
        {   -logic_name  => 'start_chip_seq_analysis',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               MAIN      => 'pre_pipeline_checks',
            },
        },
        {
          -logic_name => 'pre_pipeline_checks',
          -module     => 'Bio::EnsEMBL::Funcgen::PipeConfig::ChIPSeqAnalysis::ErsaPrePipelineChecks',
            -flow_into   => {
               'MAIN->A' => 'fetch_experiments_to_process',
               'A->MAIN' => 'check_execution_plans',
            },
        },
        {   -logic_name  => 'fetch_experiments_to_process',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                db_conn    => 'funcgen:#species#',
                inputquery => '
                  select 
                    experiment_id,
                    experiment.name as experiment_name
                  from 
                    experiment 
                    join feature_type using (feature_type_id) 
                    join experimental_group using (experimental_group_id) 
                  where 
                    is_control = 0 
                    and class in (
                      "Histone", 
                      "Open Chromatin",
                      "Transcription Factor",
                      "Polymerase"
                    )
                    and experimental_group.name != "BLUEPRINT"
                ',
            },
            -flow_into => {
               2 => { 'create_execution_plan' => INPUT_PLUS },
            },
        },
        {   -logic_name  => 'create_execution_plan',
            -module     => 'Bio::EnsEMBL::Funcgen::RunnableDB::ChIPSeq::CreateExecutionPlan',
            -analysis_capacity => 1,
            -flow_into   => {
               2 => '?accu_name=execution_plan_list&accu_address=[]&accu_input_variable=plan',
            },
        },
        {   -logic_name  => 'check_execution_plans',
            -module     => 'Bio::EnsEMBL::Funcgen::RunnableDB::ChIPSeq::CheckExecutionPlans',
            -flow_into   => {
               2 => [
                'find_control_experiments',
                'seed_all_experiment_names'
               ],
            },
        },
        {   -logic_name => 'seed_all_experiment_names',
            -module     => 'Bio::EnsEMBL::Funcgen::RunnableDB::ChIPSeq::SeedAllExperimentNames',
            -flow_into   => {
               2 => 'start_fastqc',
            },
        },
        {   -logic_name => 'start_fastqc',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
        {   -logic_name  => 'find_control_experiments',
            -module     => 'Bio::EnsEMBL::Funcgen::RunnableDB::ChIPSeq::FindControlExperiments',
            -flow_into   => {
               'A->2' => 'backbone_fire_convert_to_bed',
               '3->A' => 'start_align_controls',
            },
        },
        {
            -logic_name  => 'start_align_controls',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },

        {   -logic_name  => 'backbone_fire_convert_to_bed',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               '1->A' => 'start_convert_to_bed',
               'A->1' => 'seed_jobs_from_list'
            },
        },
        {
            -logic_name  => 'start_convert_to_bed',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },

        {   -logic_name  => 'seed_jobs_from_list',
            -module      => 'Bio::EnsEMBL::Funcgen::RunnableDB::ChIPSeq::SeedJobsFromList',
            -flow_into   => {
               2 => 'backbone_fire_write_bigwig_controls',
            },
        },
        {   -logic_name  => 'backbone_fire_write_bigwig_controls',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               MAIN => [
                 'backbone_fire_align_signals',
                 'start_write_bigwig_controls',
               ]
            },
        },
        {
            -logic_name  => 'start_write_bigwig_controls',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
        {   -logic_name  => 'backbone_fire_align_signals',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               'MAIN->A' => 'start_align_signals',
               'A->MAIN' => 'backbone_fire_start_alignment_qc'
            },
        },
        {
            -logic_name  => 'start_align_signals',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },

        {   -logic_name  => 'backbone_fire_start_alignment_qc',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               MAIN => [
                 'start_alignment_qc',
                 'backbone_fire_write_bigwig',
               ]
            },
        },
        {
            -logic_name  => 'start_alignment_qc',
            -module     => 'Bio::EnsEMBL::Funcgen::RunnableDB::ChIPSeq::SeedAllAlignments',
        },

        {   -logic_name  => 'backbone_fire_write_bigwig',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               MAIN => [
                 'start_write_bigwig',
                 'backbone_fire_convert_signal_to_bed',
               ]
            },
        },
        {
            -logic_name  => 'start_write_bigwig',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },

        {   -logic_name  => 'backbone_fire_convert_signal_to_bed',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               '1->A' => 'start_convert_signal_to_bed',
               'A->1' => 'backbone_fire_idr'
            },
        },
        {
            -logic_name  => 'start_convert_signal_to_bed',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },


        {   -logic_name  => 'backbone_fire_idr',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               '1->A' => 'start_idr',
               'A->1' => 'backbone_fire_call_peaks'
            },
        },
        {
            -logic_name  => 'start_idr',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },



        {   -logic_name  => 'backbone_fire_call_peaks',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               '1->A' => 'start_call_peaks',
               'A->1' => 'backbone_fire_frip'
            },
        },
        {
            -logic_name  => 'start_call_peaks',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },



        {   -logic_name  => 'backbone_fire_frip',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
               '1->A' => 'start_frip',
               'A->1' => 'backbone_pipeline_finished'
            },
        },
        {
            -logic_name  => 'start_frip',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },






        {   -logic_name => 'backbone_pipeline_finished',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        }
    ]
}

1;