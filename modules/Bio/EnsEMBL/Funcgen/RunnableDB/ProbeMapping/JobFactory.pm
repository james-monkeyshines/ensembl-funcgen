package Bio::EnsEMBL::Funcgen::RunnableDB::ProbeMapping::JobFactory;

use strict;
use base ('Bio::EnsEMBL::Hive::Process');

sub run {
    my $self = shift;
    my $probe_directories = $self->param('probe_directories');
    my $species           = $self->param('species');

    use Bio::EnsEMBL::Utils::Logger;
    my $logger = Bio::EnsEMBL::Utils::Logger->new();
    
    use Data::Dumper;
    use File::Spec;

    opendir(D, $probe_directories) || die "Can't open directory $probe_directories: $!\n";
    my @list = grep !/^\.\.?$/, readdir(D);
    closedir(D);

    my $funcgen_adaptor = Bio::EnsEMBL::Registry->get_DBAdaptor($species, 'funcgen');
    
    my $input_id = [];
    DIR: foreach my $subdirectory (@list) {
    
      my $full_path = File::Spec->catfile($probe_directories, $subdirectory);
      
      # Skip any files that may be in there, only directories are processed.
      #
      next DIR if (! -d $full_path);
      next DIR if ($full_path =~ /GENOMICSEQS/);
      next DIR if ($full_path =~ /TRANSCRIPTSEQS/);
      
      my $arrayref_of_arrayref_with_one_element_which_is_the_name = $funcgen_adaptor->dbc->db_handle->selectall_arrayref(
	qq(select name from array where class="$subdirectory")
      );

#       # Dereference the individual array refs so we get an array of array 
#       # names
#       #
#       my @array_of_array_names = map { @$_ } @$arrayref_of_arrayref_with_one_element_which_is_the_name;
# 
#       if (! @array_of_array_names) {
# 	die("Can't find an array with class $subdirectory");
#       }

#       my $all_array_names = join " ", @array_of_array_names;

      push @$input_id, {
	array_class    => $subdirectory,
	probe_file     => File::Spec->catfile($full_path, 'arrays.'.$subdirectory.'.fasta'),
	species        => $species,
	
	# Used for rollback
# 	all_array_names => $all_array_names,
      };
    }
    foreach my $current_input_id (@$input_id) {
      $self->dataflow_output_id( $current_input_id, 1 );
    }
}

1;
