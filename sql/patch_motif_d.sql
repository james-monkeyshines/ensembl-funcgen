-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2017] EMBL-European Bioinformatics Institute
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--      http://www.apache.org/licenses/LICENSE-2.0
--      
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

/**
@header patch_motif_d.sql - Create transcription_factor_complex table
@desc Stores transcription factor complexes
*/

DROP TABLE IF EXISTS `transcription_factor_complex`;
CREATE TABLE `transcription_factor_complex` (
	`transcription_factor_complex_id` int(11) NOT NULL AUTO_INCREMENT,
	`production_name` varchar(120) NOT NULL,
	`display_name` varchar(120) NOT NULL,
	PRIMARY KEY (`transcription_factor_complex_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;