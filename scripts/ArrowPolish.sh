#!/bin/bash

set -e

if [ -z $1 ]; then

	echo "use $0 -h for help"
	exit 0
elif [ $1 == "-h" ]; then

	cat << EOF

	This script (ArrowPolish.sh) is used to polish the assembly generated by the script
	mtDNApipe.sh using Canu. It performs two rounds of Arrow polishing using the same reads used
	by Canu to generate the assembly. These are retrieved from the raw Pacbio data
	using information from Canu intermediate files.

	It requires the following software (and their dependencies) installed:
	samtools/1.9, pbmm2/1.0.0, variantCaller/2.2.2, picard/2.18.22

	For picard to work, it requires the absolute file to the jar to be defined in the code.

	Note: Arrow polishing is performed on an existing alignment, and Arrow assumes reference
	as linear. Therefore, to avoid spurious (e.g. NUMTs) polishing, only reads from the Canu
	assembly are employed. This results in a lower coverage than that potentially achievable
	if no subsequent short-read polishing is performed, and consequently at least
	30-40x coverage is required to avoid sequence errors in the final consensus.

	Required arguments are:
		-s the species name (e.g. Calypte_anna)
		-i the VGP species ID (e.g. bCalAnn1)
		-n the contig ID identified from the BLAST search by the script blastMT.sh
		-t the number of threads

	Optional arguments are:
		-c if run on cluster. Supported options are:
			SLURM
			None (Default)

EOF

exit 0

fi

printf "\n\n++++ running: ArrowPolish.sh ++++\n\n"

if [[ -e "${W_URL}/arrow/arrow_round2/${ID}.${CONTIG}_arrow2.fasta" ]]; then

	printf "\n\noutput already present: skipping.\n\n"
	exit 0

fi

#set options

while getopts ":s:i:c:n:t:" opt; do

	case $opt in
		s)
			SPECIES=$OPTARG
			echo "Species: -s $OPTARG"
			;;
        i)
        	ID=$OPTARG
        	echo "Species ID: -i $OPTARG"
            ;;
		c)
            GRID=$OPTARG
			echo "Cluster: -c $OPTARG"
			;;
		n)
            CONTIG=$OPTARG
			echo "Contig number: -n $OPTARG"
			;;
		t)
			NPROC=$OPTARG
			echo "Number of threads: -t $OPTARG" >&2
            ;;
		\?)
			echo "ERROR - Invalid option: -$OPTARG" >&2
			exit 1
			;;
	esac

printf "\n"

done

if [[  ${GRID} == "SLURM" ]]; then

echo Starting at `date`
echo This is job $SLURM_JOB_ID
echo Running on `hostname`

fi

printf "\n"

#define working directory
W_URL=${SPECIES}/assembly_MT_rockefeller/intermediates
printf "Working directory: $W_URL\n\n"

if ! [[ -e "${W_URL}/arrow" ]]; then

	mkdir -p ${W_URL}/arrow

fi

if ! [[ -e "${W_URL}/arrow/arrow_round1" ]]; then

	mkdir -p ${W_URL}/arrow/arrow_round1

	#retrieve the names of Pacbio reads used in Canu assembly
	awk '$2 == "'$(echo "${CONTIG}" | sed -e 's/tig0*//g' -e 's/tig0*//g')'" {print $1}' ${W_URL}/canu/${ID}.contigs.layout.readToTig > ${W_URL}/arrow/arrow_round1/${ID}_${CONTIG}_IDs.txt

	gunzip -c ${W_URL}/canu/${ID}.trimmedReads.fasta.gz > ${W_URL}/arrow/arrow_round1/${ID}.trimmedReads.fasta

	READS=$(grep -c ">" ${W_URL}/arrow/arrow_round1/${ID}.trimmedReads.fasta)

	echo "$READS reads were trimmed by Canu"

	while read IDs; do grep -A 1 "id=\b${IDs}\b" ${W_URL}/arrow/arrow_round1/${ID}.trimmedReads.fasta; done < ${W_URL}/arrow/arrow_round1/${ID}_${CONTIG}_IDs.txt > ${W_URL}/arrow/arrow_round1/${ID}.trimmedReads.${CONTIG}.fasta

	grep -o -P '(?<=>)(\S*)' ${W_URL}/arrow/arrow_round1/${ID}.trimmedReads.${CONTIG}.fasta | uniq -u > ${W_URL}/arrow/arrow_round1/${ID}_${CONTIG}_names.txt

	READS_AS_U=$(grep -c "m" ${W_URL}/arrow/arrow_round1/${ID}_${CONTIG}_names.txt)

	echo "of which $READS_AS_U were used in the assembly of contig ${CONTIG}\n"

	sed ':a;N;/>/!s/\n//;ta;P;D' ${W_URL}/canu/${ID}.contigs.fasta | grep -A1 "${CONTIG} " > ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}.fasta

	pbmm2 index ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}.fasta ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}.fasta.mmi 

	pbmm2 align ${W_URL}/reference/${REF%.*}.fasta.mmi ${W_URL}/pacbio_bam/*.subreads.bam ${W_URL}/pacbio_bam/aligned_${p%.*}.bam -j ${NPROC} secondary=no

	if ! [[ -e "${W_URL}/arrow/arrow_round1/picard" ]]; then

		mkdir -p ${W_URL}/arrow/arrow_round1/picard

	fi

	#extract reads used by Canu using their names
	samtools view -H ${W_URL}/arrow/arrow_round1/${ID}.realigned_raw_reads.bam | sed "s/SO:UNKNOWN/SO:unknown/g" | samtools reheader - ${W_URL}/arrow/arrow_round1/${ID}.realigned_raw_reads.bam > ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh.bam
	picard FilterSamReads I=${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh.bam O=${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}.bam READ_LIST_FILE=${W_URL}/arrow/arrow_round1/${ID}_${CONTIG}_names.txt FILTER=includeReadList VALIDATION_STRINGENCY=STRICT

	#Arrow polishing using only reads from the Canu assembly
	samtools faidx ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}.fasta

	samtools sort ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}.bam -o ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_sorted.bam

	rm ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}.bam  

	pbindex ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_sorted.bam

	variantCaller ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_sorted.bam -r ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}.fasta -o ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}_arrow.fasta --algorithm=arrow --numWorkers ${NPROC}

fi

if ! [[ -e "${W_URL}/arrow/arrow_round2" ]]; then

	pbmm2 index ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}_arrow.fasta ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}_arrow.fasta.mmi 
	pbmm2 align ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}_arrow.fasta.mmi ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_sorted.bam ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl.bam -j ${NPROC} secondary=no

	samtools faidx ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}_arrow.fasta

	samtools sort ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl.bam -o ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl_sorted.bam

	rm ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl.bam

	pbindex  ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl_sorted.bam

	mkdir -p ${W_URL}/arrow/arrow_round2

	variantCaller ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl_sorted.bam -r ${W_URL}/arrow/arrow_round1/${ID}.${CONTIG}_arrow.fasta -o ${W_URL}/arrow/arrow_round2/${ID}.${CONTIG}_arrow2.fasta --algorithm=arrow --numWorkers ${NPROC}

	#generate a final alignment for debugging

	pbmm2 index ${W_URL}/arrow/arrow_round2/${ID}.${CONTIG}_arrow2.fasta ${W_URL}/arrow/arrow_round2/${ID}.${CONTIG}_arrow2.fasta.mmi 
	pbmm2 align ${W_URL}/arrow/arrow_round2/${ID}.${CONTIG}_arrow2.fasta.mmi ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl_sorted.bam ${W_URL}/arrow/arrow_round1/picard/${ID}.realigned_raw_reads_rh_${CONTIG}_pl.bam ${W_URL}/arrow/arrow_round2/${ID}.realigned_raw_reads_rh_${CONTIG}_pl2.bam -j ${NPROC} secondary=no

fi
