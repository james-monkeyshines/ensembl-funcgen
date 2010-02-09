#!/usr/local/bin/bash



#Test for eFG env

if [  -z "$EFG_SRC" ] || [ ! -d $EFG_SRC ]; then
   echo ":: You have not yet initialised the eFG environment"
   return	
fi


#still have to source the funcs!
#As not exported in env
. $funcs_file


#To do
#Integrate this into pipeline.env?
#This requires set up of a instance file and input dir
#Also is less visible? Need to fettle with Help to list funcs better?
#As we have no structure to the functions, but at least we have a dir structure when we have separate scripts
#add code to generate indexes if absent?
#add outdir 
#add inputdir option which will cat files fastq file, use dir name as input_name?


#This makes sure we reset the getopts ind if we have used it previously
OPTIND=1
VALID_GENDERS='male female'
gender=
species=
file=
#Set this in pipeline/efg.config?
index_home=/lustre/scratch103/ensembl/funcgen/bwa_indexes
assembly=GRCh37
mask='_unmasked'
align_type='samse'
resource='-R"select[mem>5000] rusage[mem=5000]" -M5000000'
dir=
clean=

usage="usage:\trun_bwa.sh  -s(pecies e.g. homo_sapiens)  -g(ender e.g male|female)  -f(ile e.g. your_file.fastq)  -d(ir input dir containing fastq files) [ -p(aired default is single reads)  -i(ndex_home default=$index_home)  -r(esource default=$resource)  -a(ssembly default=$assembly) -c(lean away cat'd fastq file) -h(elp) ] " #-m(asked default is unmasked)
#description='More wordy description here'



while getopts ":g:s:f:d:i:r:a:cph" opt; do
	case $opt in 
		g  ) gender=$OPTARG ;; 
		s  ) species=$OPTARG ;;
        f  ) file=$OPTARG ;;
        d  ) dir=$OPTARG ;;
		i  ) index_file=$OPTARG ;;
        r  ) resource=$OPTARG ;;
		a  ) assembly=$OPTARG ;;
	    p  ) align_type='sampe' ;;
        c  ) clean=1 ;;
		h  ) echo -e $usage; return 0;;
		\? ) echo -e $usage; exit 1;;
	esac 
done

#Paramter checks
CheckVariablesOrUsage "$usage" gender species index_home
ValidateVariableOrUsage "$usage" gender VALID_GENDERS

if [[ ! $file ]] && [[ ! $dir ]]; then
	echo "You must supply either a -f(ile) or -d(ir) parameter"
	exit
fi

if [[ $dir ]]; then

	#Do we not have a function for this unzipping/cating?

	#strip last dir name off for input
	file_name=$(echo $dir | sed -r 's/\/$//')
	file_name=$(echo $dir | sed -r 's/.*\///')
	file="${dir}/${file_name}.fastq"

	if [[ -f $file ]]; then

		if [ $clean ]; then
			echo -e "Removing old fastq file:\t${file}"
			rm -f $file
		else
			echo -e "Using old cat'd fastq file:\t$file"
		fi
	fi

	if [[ ! -f $file ]]; then
		echo "Generating fastq file:\t$file"
		#gfastq_files=($(ls ${dir}/*fastq.gz))
		#Do it this way to avoid STDERR
		fastq_files=($(ls ${dir}/*fastq*))
		
		if [[ ! $fastq_files ]]; then
			echo -e "No fastq files found in input dir:\t$dir"
		elif [[ ! -z $(echo ${fastq_files[*]} | grep '.fastq.gz') ]]; then
			echo "Unzipping fastq files"
			Execute gunzip $dir/*.fastq.gz
		fi

		fastq_files=$(ls ${dir}/*fastq)
		echo -e "Using:\t"

		for fastq_file in $fastq_files; do
			fastq_file=$(echo $fastq_file | sed -r 's/.*\///')
			echo -e "\t$fastq_file"
		done


		echo -e "Cat'ing files to:\t $file"
		Execute cat ${dir}/*fastq > $file
		echo "Gzipping all source fastq files"
		Execute gzip $fastq_files		
	fi

	#Need to rezip here really
	#echo "Gzipping all source fastq files"
	#Execute gzip $fastq_files
fi



CheckFile $file

if [[ $file != *fastq ]]; then
	echo "Your file argument needs to be a fastq file:\t$file"
	exit
fi

lc_species=$(echo $species | tr [A-Z] [a-z])
uc_species=$(echo $species | tr [a-z] [A-Z])
index_name="${lc_species}_${gender}_${assembly}${mask}.fasta"
fasta_file=${index_home}/${uc_species}/${index_name}

#Check index files
for ext in amb ann bwt pac rbwt rpac rsa sa; do
	error=$(CheckFile "${index_home}/${uc_species}/${index_name}.${ext}")

	if [ $? -ne 0 ]; then
		echo -e $error
		
		if [[ ! -f $fasta_file ]]; then
			echo -e "\nYou need to create the fasta file to index:\t$fasta_file"
			#Add how to dump here?
			echo -e "\ne.g. bsub -J ${lc_species}_top_level_unmasked -e ${lc_species}_top_level_unmasked.err -o ${lc_species}_top_level_unmasked.out -R\"select[mem>3500] rusage[mem=3500]\" -M3500000 $EFG_PERL $SRC/ensembl-analysis/scripts/sequence_dump.pl -dbhost ens-livemirror -dbuser ensro -dbname ${lc_species}_core_SCHEMA_BUILD -species $lc_species -coord_system_name toplevel -filename $lc_species_male_ASSEMBLY_unmasked.fasta"
			echo -e "Then create the female file as follows:\n\tcat ${lc_species}_male_ASSEMBLY_unmasked.fasta | /nfs/users/nfs_d/dkeefe/bin/fastagrep -t -v -P -p 'chromosome:ASSEMBLY:Y' > ${lc_species}_female_ASSEMBLY_unmasked.fasta"
		fi

		echo -e "\nYou need to generate the bwa indexes using:\n\tbsub -J ${lc_species}_bwa_indexes -o ${lc_species}_bwa_indexes.out  -e ${lc_species}_bwa_indexes.err $resource bwa index -a bwtsw $fasta_file"
		
		exit
	fi
done


file_name=$(echo $file | sed 's/\.fastq$//')

echo -e "Running bwa with following options:\n\tIndex name\t= $index_name\n\tInput file\t= $file\n\tAlignment type\t= $align_type\n"
#This is again truncating the bsub cmd and failing?!
#bjob_cmd="bsub -J bwa_${file_name} $resource -o ${file_name}.bwa.out -e ${file_name}.bwa.err 'bwa aln $index_home/${uc_species}/${index_name}  $file > ${file_name}.${align_type}.sai; bwa $align_type ${index_home}/${uc_species}/${index_name} ${file_name}.${align_type}.sai $file > ${file_name}.${align_type}.sam'"

#Use submitJob
job_name="bwa_${file_name}"
bsub_cmd="$resource -o ${file_name}.bwa.out -e ${file_name}.bwa.err"
job_cmd="'bwa aln $fasta_file  $file > ${file_name}.${align_type}.sai; bwa $align_type $fasta_file ${file_name}.${align_type}.sai $file > ${file_name}.${align_type}.sam'"

#Add this so submitJob does not fail. Move to efg.config?
export QUEUE_MANAGER=LSF
submitJob "$job_name" "$bsub_cmd" "$job_cmd" 

