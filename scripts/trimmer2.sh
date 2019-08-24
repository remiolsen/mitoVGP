#!/bin/bash

set -e

if [ -z $1 ]; then

	echo "use $0 -h for help"
	exit 0
elif [ $1 == "-h" ]; then

	cat << EOF

	This script allows to generate a trimmed version of the Canu mitocontig after short read
	polishing (map10x1.sh). The resulting contig has 100 bp overlapping ends on both sides.
	The script is still experimental.

	It requires the following software (and their dependencies) installed:
	bowtie2/2.1.0, samtools/1.7, mummer/3

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

printf "\n\n++++ running: trimmer2.sh ++++\n\n"

if [[ -e "${W_URL}/trimmed2/${FNAME}_trim2.fasta" ]]; then

	printf "\n\noutput already present: skipping.\n\n"	
	exit 0

fi

#set options

while getopts ":s:i:n:c:t:" opt; do

	case $opt in
		s)
			SPECIES=$OPTARG
			echo "Species: -s $OPTARG"
			;;
        i)
        	ID=$OPTARG
        	echo "Species ID: -i $OPTARG"
            ;;
		n)
            CONTIG=$OPTARG
			echo "Contig number: -n $OPTARG"
			;;
		c)
            GRID=$OPTARG
			echo "Cluster: -c $OPTARG"
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

#define working directory
W_URL=${SPECIES}/assembly_MT_rockefeller/intermediates
printf "Working directory: $W_URL\n\n"


FNAME="${ID}.${CONTIG}_arrow2_10x1_trim1_10x2"

CONTIG_NAME=$(cat ${W_URL}/freebayes_round2/${FNAME}.fasta | awk '$0 ~ ">" {print substr($0,2)}')

if ! [[ -e "${W_URL}/trimmed2/realigned_${ID}_all_sorted.bam" ]]; then

mkdir ${W_URL}/trimmed2

cp ${W_URL}/freebayes_round2/${FNAME}.fasta ${W_URL}/trimmed2

sed -i '2 s/^\(.\{4\}\)./\1/' ${W_URL}/trimmed2/${FNAME}.fasta

samtools sort -n ${W_URL}/bowtie2_round2/aligned_${ID}_all_trimmed_sorted.bam -o ${W_URL}/trimmed2/aligned_${ID}_all_paired.bam
samtools fastq ${W_URL}/trimmed2/aligned_${ID}_all_paired.bam -1 ${W_URL}/trimmed2/aligned_${ID}_all_1.fq -2 ${W_URL}/trimmed2/aligned_${ID}_all_2.fq -s ${W_URL}/trimmed2/aligned_${ID}_all_s.fq
bowtie2-build ${W_URL}/trimmed2/${FNAME}.fasta ${W_URL}/trimmed2/${ID}
bowtie2 -x ${W_URL}/trimmed2/${ID} -1 ${W_URL}/trimmed2/aligned_${ID}_all_1.fq -2 ${W_URL}/trimmed2/aligned_${ID}_all_2.fq -p ${NPROC} --no-mixed | samtools view -bSF4 - > "${W_URL}/trimmed2/realigned_${ID}_all.bam"
samtools sort ${W_URL}/trimmed2/realigned_${ID}_all.bam -o ${W_URL}/trimmed2/realigned_${ID}_all_sorted.bam -@ ${NPROC}
samtools index ${W_URL}/trimmed2/realigned_${ID}_all_sorted.bam
printf "\n"

fi

if ! [[ -e "${W_URL}/trimmed2/${FNAME}.delta" ]]; then

nucmer --maxmatch --nosimplify ${W_URL}/trimmed2/${FNAME}.fasta ${W_URL}/trimmed2/${FNAME}.fasta -f -p "${W_URL}/trimmed2/${FNAME}" -b 500 

fi

NUCMER_OUT=$(show-coords "${W_URL}/trimmed2/${FNAME}.delta" -lrcTHo | grep "BEGIN" | head -1)
BEGIN1=$(echo $NUCMER_OUT | awk '{print $1}')
BEGIN2=$(echo $NUCMER_OUT | awk '{print $2}')
END1=$(echo $NUCMER_OUT | awk '{print $3}')

if (( ${BEGIN2} > ${END1} )); then

echo ">${FNAME}" > "${W_URL}/trimmed2/${FNAME}_new.fasta" & grep -v ">" ${W_URL}/trimmed2/${FNAME}.fasta | tr -d '\n' | cut -c${BEGIN1}-${BEGIN2} >> "${W_URL}/trimmed2/${FNAME}_new.fasta"

nucmer --maxmatch --nosimplify "${W_URL}/trimmed2/${FNAME}_new.fasta" "${W_URL}/trimmed2/${FNAME}_new.fasta" -f -p "${W_URL}/trimmed2/${FNAME}" -b 500 

CONTIG="${W_URL}/trimmed2/${FNAME}_new.fasta"

NUCMER_OUT=$(show-coords "${W_URL}/trimmed2/${FNAME}.delta" -lrcTHo | grep "BEGIN" | head -1)
BEGIN1=$(echo $NUCMER_OUT | awk '{print $1}')
BEGIN2=$(echo $NUCMER_OUT | awk '{print $2}')
END1=$(echo $NUCMER_OUT | awk '{print $3}')
	
fi

END2=$(echo $NUCMER_OUT | awk '{print $4}')
MIDDLE="$(( ${BEGIN2} + 1 ))-$(( ${END1} - 1 ))"

echo ">${ID}" > "${W_URL}/trimmed2/${FNAME}_trim2.fasta" & grep -v ">" ${W_URL}/trimmed2/${FNAME}.fasta | tr -d '\n' | cut -c${MIDDLE} >> "${W_URL}/trimmed2/${FNAME}_trim2.fasta"

echo ">${FNAME}_begin_${BEGIN1}-${BEGIN2}" > "${W_URL}/trimmed2/${FNAME}_ends.fasta" & grep -v ">" ${W_URL}/trimmed2/${FNAME}.fasta | tr -d '\n' | cut -c${BEGIN1}-${BEGIN2} >> "${W_URL}/trimmed2/${FNAME}_ends.fasta"
echo ">${FNAME}_end_${END1}-${END2}" >> "${W_URL}/trimmed2/${FNAME}_ends.fasta" & grep -v ">" ${W_URL}/trimmed2/${FNAME}.fasta | tr -d '\n' | cut -c${END1}-${END2} >> "${W_URL}/trimmed2/${FNAME}_ends.fasta"

arrCOV1=($(samtools depth -aa -r ${CONTIG_NAME}:${BEGIN1}-${BEGIN2} --reference ${W_URL}/trimmed2/${FNAME}.fasta ${W_URL}/trimmed2/realigned_${ID}_all_sorted.bam | awk '{print $3}'))
arrCOV2=($(samtools depth -aa -r ${CONTIG_NAME}:${END1}-${END2} --reference ${W_URL}/trimmed2/${FNAME}.fasta ${W_URL}/trimmed2/realigned_${ID}_all_sorted.bam | awk '{print $3}'))

if ! [[ -e "${W_URL}/trimmed2/${FNAME}_ends_aligned.fasta" ]]; then

printf "\n"
muscle -in ${W_URL}/trimmed2/${FNAME}_ends.fasta -out ${W_URL}/trimmed2/${FNAME}_ends_aligned.fasta

fi

if ! [[ -e "${W_URL}/trimmed2/${FNAME}_ends_aligned.table" ]]; then

NAM1=$(cat ${W_URL}/trimmed2/${FNAME}_ends_aligned.fasta | awk '/^[>;]/ { if (seq) { print seq }; seq=""; print } /^[^>;]/ { seq = seq $0 } END { print seq }' | awk 'NR==1')
SEQ1=$(cat ${W_URL}/trimmed2/${FNAME}_ends_aligned.fasta | awk '/^[>;]/ { if (seq) { print seq }; seq=""; print } /^[^>;]/ { seq = seq $0 } END { print seq }' | awk 'NR==2')
NAM2=$(cat ${W_URL}/trimmed2/${FNAME}_ends_aligned.fasta | awk '/^[>;]/ { if (seq) { print seq }; seq=""; print } /^[^>;]/ { seq = seq $0 } END { print seq }' | awk 'NR==3')
SEQ2=$(cat ${W_URL}/trimmed2/${FNAME}_ends_aligned.fasta | awk '/^[>;]/ { if (seq) { print seq }; seq=""; print } /^[^>;]/ { seq = seq $0 } END { print seq }' | awk 'NR==4')

arrSEQ1=($(fold -w1 <<< "$SEQ1"))
arrSEQ2=($(fold -w1 <<< "$SEQ2"))

printf "%s\n" ${NAM1} > ${W_URL}/trimmed2/${FNAME}_ends_aligned_1.table
printf "%s\n" "${arrSEQ1[@]}" >> ${W_URL}/trimmed2/${FNAME}_ends_aligned_1.table

COUNTER=0

while read i;
	do
		if [ "$i" == ${NAM1} ]; then
			printf "%s\t%s\n" ${NAM1} "Cov" > ${W_URL}/trimmed2/${FNAME}_ends_aligned_1_with_cov.table
		elif [ "$i" == "-" ]; then
			printf "%s\t%s\n" "$i" "NA" >> ${W_URL}/trimmed2/${FNAME}_ends_aligned_1_with_cov.table
		else
			printf "%s %s\n" "$i" "${arrCOV1[$COUNTER]}" >> ${W_URL}/trimmed2/${FNAME}_ends_aligned_1_with_cov.table
			let COUNTER=COUNTER+1	
		fi
	done < ${W_URL}/trimmed2/${FNAME}_ends_aligned_1.table

printf "%s\n" $NAM2 > ${W_URL}/trimmed2/${FNAME}_ends_aligned_2.table
printf "%s\n" "${arrSEQ2[@]}" >> ${W_URL}/trimmed2/${FNAME}_ends_aligned_2.table

COUNTER=0

while read i;
	do
		if [ "$i" == ${NAM2} ]; then
			printf "%s\t%s\n" ${NAM2} "Cov" > ${W_URL}/trimmed2/${FNAME}_ends_aligned_2_with_cov.table
		elif [ "$i" == "-" ]; then
			printf "%s\t%s\n" "$i" "NA" >> ${W_URL}/trimmed2/${FNAME}_ends_aligned_2_with_cov.table
		else
			printf "%s %s\n" "$i" "${arrCOV2[$COUNTER]}" >> ${W_URL}/trimmed2/${FNAME}_ends_aligned_2_with_cov.table
			let COUNTER=COUNTER+1
		fi
	done < ${W_URL}/trimmed2/${FNAME}_ends_aligned_2.table

paste ${W_URL}/trimmed2/${FNAME}_ends_aligned_1_with_cov.table ${W_URL}/trimmed2/${FNAME}_ends_aligned_2_with_cov.table > ${W_URL}/trimmed2/${FNAME}_ends_aligned.table

fi

S=""

COUNTER=0

arrN1=( $(awk 'FNR == 1 {next} {print $1}' ${W_URL}/trimmed2/${FNAME}_ends_aligned.table) )
arrQ1=( $(awk 'FNR == 1 {next} {print $2}' ${W_URL}/trimmed2/${FNAME}_ends_aligned.table) )
arrN2=( $(awk 'FNR == 1 {next} {print $3}' ${W_URL}/trimmed2/${FNAME}_ends_aligned.table) )
arrQ2=( $(awk 'FNR == 1 {next} {print $4}' ${W_URL}/trimmed2/${FNAME}_ends_aligned.table) )

while [  $COUNTER -lt ${#arrN1[@]} ]
	do
		N1=${arrN1[$COUNTER]}
		Q1=${arrQ1[$COUNTER]}
		N2=${arrN2[$COUNTER]}
		Q2=${arrQ2[$COUNTER]}
		VER=$COUNTER
		if [  ${N1} == ${N2} ]; then
			S="${S}${N1}"
		elif [  ${N1} == "-" ]; then
			while [  ${arrN1[${VER}]} == "-" ]; do
				if [[ ${arrQ1[$VER-1]} == ?(-)+([0-9]) ]] && (( ${arrQ1[$VER-1]} > ${Q2} )); then
				:
				elif [[ ${arrQ1[$VER-1]} == ?(-)+([0-9]) ]] && (( ${arrQ1[$VER-1]} < ${Q2} )); then
					S="${S}${N2}"
				fi			
    			let VER-=1
         	done
		elif [  ${N2} == "-" ]; then
			while [  ${arrN2[$VER]} == "-" ]; do
				if [[ ${arrQ2[$VER-1]} == ?(-)+([0-9]) ]] && (( ${arrQ2[$VER-1]} > ${Q1} )); then
				:
				elif [[ ${arrQ2[$VER-1]} == ?(-)+([0-9]) ]] && (( ${arrQ2[$VER-1]} < ${Q1} )); then
					S="${S}${N1}"
				fi			
    			let VER-=1
         	done
		elif [  ${N1} != "-" ] && [  ${N1} != ${N2} ]; then
				if ((  ${Q1} > ${Q2} )); then
					S="${S}${N1}"
				else
					S="${S}${N2}"
				fi				
		fi
		
		let COUNTER=COUNTER+1
		
	done

sed -i "$ s/$/$S/" ${W_URL}/trimmed2/${FNAME}_trim2.fasta

printf "\nFinal sequence:\n\n"
cat ${W_URL}/trimmed2/${FNAME}_trim2.fasta

GSIZE=$(awk 'BEGIN {FS="\t"} $0 !~ ">" {sum+=length($0)} END {print sum}' ${W_URL}/trimmed2/${FNAME}_trim2.fasta)
	
printf "\nMitogenome size: ${GSIZE} bp\n"