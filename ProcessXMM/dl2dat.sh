#!/bin/bash

###############################################################################
# dl2dat.sh
###############################################################################
#
# Script to download a given XMM observation and convert this to a data file 
#
# To call this script for an observation with ID=obsID, use: ./dl2dat.sh $obsID
# Before calling, all directories must be set in set_dirs.sh
#
###############################################################################


# Import directories which must be set before running
source set_dirs.sh


# The data processing involves the following steps:
# 1. Initialize the required software
# 2. Download and unpack the data
# 3. Create instrument summary files (status of XMM during observation)
# 4. Retrieve the exposure names (that label the events and other files)
# 5. Create filtered event files
# 6. Check for anomalous states
# 7. Point source identification
# 8. Create the spectra and QPB
# 9. Process data into numpy files and delete unneeded data


##########################
# 1. Initialize Software #
##########################

# Read observation ID in from command line
# NB: all obsIDs are 10 digits, don't forget the 0 at the start if present
obsID=$1
echo 'Reading in observation ID '$obsID

# Check if has already been processed
if [ -d "$xmmdata/$obsID" ]; then
    echo 'This observation has already been processed'
    echo 'Processing failed!'
    exit 1
fi

echo 'Starting the data processing'
echo -e '\nStep 1: initializing the required software'

# Initialize the HEADAS software
. $HEADAS/headas-init.sh

# Initialize the XMM-SAS software and XMM-ESAS sub-package
. $XMMSAS/setsas.sh > /dev/null # suppress launch notifications

# Define CalDB directory, contains additional files that are required for the 
# processing of both spectra and images
export CALDB=$CALDBPATH

# Source two directories that don't yet exist, but are used for data processing
export SAS_CCF=$xmmdata/$obsID/analysis/ccf.cif
export SAS_ODF=$xmmdata/$obsID/odf

# Source the CCFs
export SAS_CCFPATH=$CCFPATH

# NB: the above variables are used internally by various tools below, not just
# explicitly in the bash script, so it is important to export them

# Note the following repeatedly used abbreviations:
# - SAS: Science Analysis System 
# - CCF: Current Calibration File
# - ODF: Observation Data File
# - CIF: Calibration Index File
# - PPS: Processing Pipeline Subsystem


###########################
# 2. Download/Unpack data #
###########################

# Move to the directory to download the data into
cd $xmmdata

# Before and after the download check if the website is up, sometimes is not
# If website goes down mid download can lead to hard to diagnose errors

echo -e '\nStep 2: downloading and unpacking the data'
curl -s -o files$obsID.tar "http://nxsa.esac.esa.int/nxsa-sl/servlet/data-action-aio?obsno=$obsID" > /dev/null 

# Check if the data file was protected
# Observations for specific proposals remain private for 20 months, if using
# one of these observations the following error will be triggered
read -r firstline < files$obsID.tar
prot_err="Data protected by proprietary rights. Please check your credentials"
if [ "$firstline" = "$prot_err" ]; then
    rm -f files$obsID.tar
    echo $prot_err
    echo 'Processing failed!' 
    exit 1
fi

# After downloading the data, there are many many nested tar files that need to
# be unpacked. As there is a large number of files do not write out the output
tar -xvf files$obsID.tar > /dev/null
rm -f files$obsID.tar

# At this point we have two directories:
# 1. $obsID/odf: observational data files (currently all in a tar) 
# 2. $obsID/pps: Processing Pipeline Subsystem (PPS) files, already untared
# pps directory usually contains > 1000 files, contains the Scientific 
# Validation Report in PDF and PostScript formats, as well as the .ASC 
# Pipeline Report file which includes such basic information as the target 
# name, PI name, and other basic observatin information.

echo 'Now the data has been downloaded, all subsequent outputs will be written to summary.txt'

# Check if uncompressing failed, "-d" check if directory exists
# If not manually set up the directories (occurs for e.g. 0653860101)
if [ ! -d "$obsID/odf" ]; then
    mkdir $obsID && mkdir $obsID/odf && mkdir $obsID/pps
    echo 'Continuing log for ID '$obsID > $obsID/summary.txt
    echo 'files'$obsID'.tar did not untar correctly.' >> $obsID/summary.txt
    mv *_$obsID* $obsID/odf/ && mv *MANIFEST* $obsID/odf/
else
    echo 'Continuing log for ID '$obsID > $obsID/summary.txt
fi

# Unpack compressed files within the directories 
# First in the observation data file directory
cd $obsID/odf 
tar -zxvf $obsID.tar.gz > ../untar_output.txt 2>&1
# Have now unpacked the following (REV is revolution when data was taken):
# ${REV}_${OBSID}_SCX00000SUM.SAS - ASCII observation summary file
# ${REV}_${OBSID}_SCX00000TCS.FIT - Spacecraft Time correlation file
# ${REV}_${OBSID}_SCX00000ATS.FIT - Spacecraft Attitude file
# ${REV}_${OBSID}_SCX00000ROS.FIT - Spacecraft Reconstructed Orbit File
# ${REV}_${OBSID}_SCX00000RAS.FIT - Raw Attitude File 
tar -xvf *.TAR > ../untar_output.txt 2>&1
# This step unpacks several hundred FIT files, including (ENUM=exposure number)
# ${REV}_${OBSID}_OMS${ENUM}00WDX.FIT - Exposure priority window file
# ${REV}_${OBSID}_OMS${ENUM}00THX.FIT - Exposure tracking history file
# ${REV}_${OBSID}_OMS${ENUM}00IMI.FIT - Exposure image file
# There are many other outputs, e.g. DII (diagnostic images), D1H/D2H (CCD 
# readout settings), OFX (offset files), DLI (discarded lines data), RFX
# (reference frame data), PEH (periodic housekeeping), and several others

# Secondly in the pipeline processing subsystem directory, unzip .FTZ files
# No new files appear
cd ../pps
rename .FTZ .FIT.gz *.FTZ > ../untar_output.txt 2>&1
gunzip -f *.FIT.gz > ../untar_output.txt 2>&1

# Copy the PPS summary file and the PPS MSG file to the obsID directory
cp *PPSMSG*.ASC ../pps_run_message.ASC
cp *PPSSUM*.HTM ../pps_summary.HTM
cd ..

# Check that the observation data was taken during or after revolution 42.
# Before this time the CCDs were behaving differently
# and special calibration files must be used.
# Find revolution information in the PPS MSG file
revolution_line=$(grep 'Revolution' pps_run_message.ASC)
revolution=${revolution_line:11}
if [ $revolution -lt 42 ]; then 
    rm -rf odf/
    rm -rf pps/
    echo 'The observation data was taken before revolution 42. It cannot be processed.' >> summary.txt
    echo 'Processing failed!' >> summary.txt
    echo 'The observation data was taken before revolution 42. It cannot be processed.'
    echo 'Processing failed!'
    exit 1
fi


#########################
# 3. Instrument Summary #
#########################

# Use SAS tools to determine the status of the instrument during the obsID
# e.g. flag parts of the detector that were not functioning, these will be cut
# from the data at the next step

echo -e '\nStep 3: making the ccf and odf instrument summary files' >> ./summary.txt

# Run the commands and write all details into their output files
# NB: from hereon we will also output all of the commands executed
mkdir analysis && cd analysis
# Create the ccf.cif file in the analysis directory, which is the CCF Index File (CIF)
echo 'cifbuild withccfpath=no analysisdate=now category=XMMCCF calindexset=$SAS_CCF fullpath=yes > ../cifbuild_output.txt 2>&1' >> ../summary.txt
cifbuild withccfpath=no analysisdate=now category=XMMCCF calindexset=$SAS_CCF fullpath=yes > ../cifbuild_output.txt 2>&1
# Create /odf/${REV}_${OBSID}_SCX00000SUM.SAS, the detailed summary file
echo 'odfingest odfdir=$SAS_ODF outdir=$SAS_ODF > ../odfingest_output.txt 2>&1' >> ../summary.txt
odfingest odfdir=$SAS_ODF outdir=$SAS_ODF > ../odfingest_output.txt 2>&1

# Ensure the ODF file is correctly read using the following command
# This command was provided by the helpdesk
# Again note SAS_ODF is used internally by the commands below
cd ../odf
export SAS_ODF=$(readlink -f *SUM.SAS)


########################
# 4. Detector Prefixes #
########################

# The instrument has three cameras comprising the European Photon Imaging Camera 
# (EPIC) two are MOS (Metal Oxide Semi-conductor) CCD arrays and one pn-CCD 
# array. Per observation, each camera will have taken some set of exposures, 
# labeled <det><prefix>; <det> is mos or pn, and prefix is of the form 
# [S,U][0-9][0-9][0-9] for pn or [1-2][S,U][0-9][0-9][0-9] for mos
# The S or U designates whether the exposure is scheduled or unscheduled
# This has no bearing on the validity of the data
# The last three numbers notate the exposure
# For mos, the [1-2] designates which mos camera
# These prefixes will be passed in as parameters to various commands

echo -e '\nStep 4: Determine the detector prefixes' >> ../summary.txt

# Create files mos_exposures.txt and pn_exposures.txt
# that contain the science exposures for the observation
python $cdir/get_science_exposures.py --xmmdata $xmmdata --obsID $obsID

# Check if exposure files created or if python was unsuccessful
if ls ../*_exposures.txt 1> /dev/null 2>&1; then
    echo 'Successfully created science exposures' >> ../summary.txt
else
    cd ..
    rm -rf odf/
    rm -rf pps/
    rm -rf analysis/ 
    echo 'There are no science exposures for this observation.' >> ./summary.txt
    echo 'Processing failed!' >> ./summary.txt
    echo 'There are no science exposures for this observation.'
    echo 'Processing failed!'
    exit 1
fi

# Get array of the mos prefixes
if [ ! -f ../mos_exposures.txt ]; then
    mosprefixes=''
else
    mosprefixes=$(<../mos_exposures.txt)
fi
# Get array of the pn prefixes and count number of exposures
if [ ! -f ../pn_exposures.txt ]; then
    pnprefixes=''
else
    pnprefixes=$(<../pn_exposures.txt)
fi

echo 'MOS prefixes: '$mosprefixes >> ../summary.txt
echo 'PN prefixes: '$pnprefixes >> ../summary.txt


######################
# 5. Filtered Events #
######################

# Process the data to remove bad periods
# The two cameras are filtered separately

echo -e '\nStep 5: Filtering event files...' >> ../summary.txt

# Firstly process the PN camera events
echo '...for the PN camera' >> ../summary.txt

# epchain generates an event list for the pn camera
# Out of Time (OOT) are events that arrived while the CCD was being readout
# NB: epchain needs to be run once for each pn exposure
# Files created in odf/ of the form P{$obsID}PN{$PREFIX}

for pref in $pnprefixes; do
    schedule=${pref:0:1}
    exposure=${pref:1:3}
    echo 'epchain withoutoftime=true odfaccess=odf exposure='$exposure' schedule='$schedule' > ../epchain'$pref'oot_output.txt 2>&1' >> ../summary.txt
    epchain withoutoftime=true odfaccess=odf exposure=$exposure schedule=$schedule > ../epchain${pref}oot_output.txt 2>&1
    echo 'epchain odfaccess=odf exposure='$exposure' schedule='$schedule' > ../epchain'$pref'_output.txt 2>&1' >> ../summary.txt
    epchain odfaccess=odf exposure=$exposure schedule=$schedule > ../epchain${pref}_output.txt 2>&1
    
    # Check that epchain completed successfully
    # There are sometimes errors where the TCX file is nearly empty and the epchain cannot complete
    # If so the file should be rerun using the TCS timing information
    if ( grep -q "TooFewTimeCorrelationDataPoints" ../epchain${pref}oot_output.txt ) || ( grep -q "TooFewTimeCorrelationDataPoints" ../epchain${pref}_output.txt ); then
        echo 'TCX file is almost empty. Rerunning with the TCS file.'
        echo 'TCX file is almost empty. Rerunning with the TCS file.' >> ../summary.txt
        export SAS_TIMECORR=TCS
        echo 'epchain withoutoftime=true odfaccess=odf exposure='$exposure' schedule='$schedule' > ../epchain'$pref'oot_output.txt 2>&1' >> ../summary.txt
        epchain withoutoftime=true odfaccess=odf exposure=$exposure schedule=$schedule > ../epchain${pref}oot_output.txt 2>&1
        echo 'epchain odfaccess=odf exposure='$exposure' schedule='$schedule' > ../epchain'$pref'_output.txt 2>&1' >> ../summary.txt
        epchain odfaccess=odf exposure=$exposure schedule=$schedule > ../epchain${pref}_output.txt 2>&1
    fi
done


# Run epspatialcti on all of the PN event lists
# This corrects the event list for the spatial variation in
# the charge transfer inefficiency
for pref in $pnprefixes; do
    detpref=PN$pref
    evlists=$(find *${detpref}*EVLI*.FIT)
    # Run on both the PI list and the out-of-time list, labeled by type
    for evli in $evlists; do
        type=${evli:17:-12}
        echo 'epspatialcti table='$evli' >> ../epspatialcti_PN'${pref}${type}'_output.txt 2>&1' >> ../summary.txt
        epspatialcti table=$evli >> ../epspatialcti_PN${pref}${type}_output.txt 2>&1
    done
done

# pn-filter then filters the event list generated for good time intervals
# Produces fits files in odf/ including list of time intervals, and importantly
# *-clean.fits – The filtered photon event files
echo 'pn-filter > ../pn-filter_output.txt 2>&1' >> ../summary.txt
pn-filter > ../pn-filter_output.txt 2>&1

# Confirm the output was created successfully, if not remove this exposure
# The filter step will fail if the exposure is empty, as happened for the 1U002
# and 2U002 MOS exposures of observation 0165570101
pnexpclean=''
for pref in $pnprefixes; do
    if [ ! -f 'pn'$pref'-clean.fits' ]; then
        echo 'pn'$pref'-clean.fits was not created successfully.' >> ../summary.txt
    else
        pnexpclean=$pnexpclean' '$pref
    fi
done
pnprefixes=$pnexpclean


# Secondly process the MOS camera events
echo '...for the MOS camera' >> ../summary.txt

# emchain/mos-filter are the analogs of epchain/pn-filter
# However emchain does not need to be run for each mos exposure
# In each case the output is essentially the same as for the PN camera, and stored in odf
echo 'emchain > ../emchain_output.txt 2>&1' >> ../summary.txt
emchain > ../emchain_output.txt 2>&1

# Check that emchain completed successfully
# There are sometimes errors where the TCX file is nearly empty and the emchain cannot complete
# If so the file should be rerun using the TCS timing information
if grep -q "TooFewTimeCorrelationDataPoints" ../emchain_output.txt; then
    echo 'TCX file is almost empty. Rerunning with the TCS file.'
    echo 'TCX file is almost empty. Rerunning with the TCS file.' >> ../summary.txt
    export SAS_TIMECORR=TCS
    echo 'emchain > ../emchain_output.txt 2>&1' >> ../summary.txt
    emchain > ../emchain_output.txt 2>&1
fi


echo 'mos-filter > ../mos-filter_output.txt 2>&1' >> ../summary.txt
mos-filter > ../mos-filter_output.txt 2>&1

# Check if the processing was successful
mosexpclean=''
for pref in $mosprefixes; do
    if [ ! -f 'mos'$pref'-clean.fits' ]; then
        echo 'mos'$pref'-clean.fits was not created successfully.' >> ../summary.txt
    else
        mosexpclean=$mosexpclean' '$pref
    fi
done
mosprefixes=$mosexpclean


#######################
# 6. Anomalous states #
#######################

# The above process does not check for anomalous states in the data
# This only impacts data below 1 keV, but if the hardness is 0 the CCD is 
# unusable. This occurs if e.g. a camera was hit by a micrometeorite
# Note this only impacts the MOS cameras

echo -e '\nStep 6: Checking for anomalous states' >> ../summary.txt

# Get str of the line numbers where an anomalous CCD is listed
# Only mos CCDs are anomalous at this time
# Briefly, the syntax below is -F is for searching for special characters (like *)
# and -n gives the line number. Lines ending in " ****" have hardness 0
# The prefix then cuts the returned list to give only the line numbers
# (specifically it returns everything before : in that line)
anomalous_lines=`grep -Fn " ****" ../mos-filter_output.txt | cut -f1 -d:`


##################################
# 7. Point source identification #
##################################

# Search for an identify point sources, and create a *-cheese.fits mask file
# This is later used by mos-spectra and pn-spectra by setting mask=1

echo -e '\nStep 7: Searching for point sources and create appropriate mask' >> ../summary.txt

# Run cheese once for each prefix
# prefixm only takes 2 arguments and prefixp only takes 1
# But sometimes there are more than 3 exposures, so must do this loop
# The output is the masks placed into odf/, the most relevant are the "cheese.fits" files

for pref in $mosprefixes; do
    echo 'cheese prefixm='$pref' prefixp='\"\"' scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_mos'${pref}'_output.txt 2>&1' >> ../summary.txt
    cheese prefixm=$pref prefixp="" scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_mos${pref}_output.txt 2>&1
    # Sometimes cheese fails, but works upon rerunning, so check and rerun if need
    if [ ! -f 'mos'$pref'-cheese.fits' ]; then
        echo "Cheese failed, trying again" >> ../summary.txt
        cheese prefixm=$pref prefixp="" scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_mos${pref}_output.txt 2>&1
    fi
    if [ ! -f 'mos'$pref'-cheese.fits' ]; then
        echo "Cheese failed, trying again" >> ../summary.txt
        cheese prefixm=$pref prefixp="" scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_mos${pref}_output.txt 2>&1
    fi
done

for pref in $pnprefixes; do
    echo 'cheese prefixm='\"\"' prefixp='$pref' scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_pn'${pref}'_output.txt2>&1' >> ../summary.txt
    cheese prefixm="" prefixp=$pref scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_pn${pref}_output.txt 2>&1
    # Sometimes cheese fails, but works upon rerunning, so check and rerun if need
    if [ ! -f 'pn'$pref'-cheese.fits' ]; then
        echo "Cheese failed, trying again" >> ../summary.txt
        cheese prefixm="" prefixp=$pref scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_pn${pref}_output.txt 2>&1
    fi
    if [ ! -f 'pn'$pref'-cheese.fits' ]; then
        echo "Cheese failed, trying again" >> ../summary.txt
        cheese prefixm="" prefixp=$pref scale=0.25 rate=1.0 dist=40.0 clobber=1 elow=3000 ehigh=4000 > ../cheese_pn${pref}_output.txt 2>&1
    fi
done


#############################
# 8. Create Spectra and QPB #
#############################

# Create the spectra and image files for the data.

echo -e '\nStep 8: Create Spectra and QPB' >> ../summary.txt

# For the MOS camera the following outputs are created in odf
# Each prefix has a series of mos${prefix} files. These include mos${prefix}-[1-7]
# which are files for the individual CCD cameras, which we won't use
# Then there are files for the full observation, either spatial maps for the full
# energy range or energy maps for the full observation.

# The key files we will use are:
# - mos${prefix}-obj.pi: observation data binned in energy
# - mos${prefix}.arf: the Auxiliary Response File (ARF)
# - mos${prefix}.rmf: the Redistribution Matrix File (RMF)
# - mos${prefix}-back.pi: the Quiescent Particle Background (QPB)
# NB: we can get the effective area as a function of output channel from the ARF 
# file, which includes vignetting in each energy bin!
# The RMF encodes the effective energy resolution, as it explains how to map
# from input channel to output channel, and is thus a matrix


for prefix in $mosprefixes; do

    echo 'Creating spectra and images for mos'$prefix >> ../summary.txt
    # First need to determine which CCDs are anomalous
    # mos has 7 CCDs, 1 means the CCD is usable
    # Assume no anomalous states
    mosccds="1 1 1 1 1 1 1"
    # Find the line where the prefix's info is listed
    prefix_line=`grep -Fxn "$prefix" ../mos-filter_output.txt | cut -f1 -d:`

    for line in $anomalous_lines; do
        # Do some math based on the formatting of '../mos-filter_output.txt'
        CCD_num=`expr $line - $prefix_line + 1`
        # The if statement ensures that only anomalous CCDs corresponding to $prefix are found
        if [ $CCD_num -lt 8 ] && [ $CCD_num -gt 0 ]; then
            # If a CCD is anomalous, change its position in the str to be 0
            sedarg=s/[0-9]/0/$CCD_num
            mosccds=`echo $mosccds | sed $sedarg`
        fi
    done

    # Make sure at least one outer CCD was collecting data
    # Outer CCDs are necessary to determine the QPB (first index is central CCD)
    if [ "$mosccds" != "1 0 0 0 0 0 0" ]; then
        # Record the CCD states into individual variables for readability
        set -- $mosccds
        ccd1=$1
        ccd2=$2
        ccd3=$3
        ccd4=$4
        ccd5=$5
        ccd6=$6
        ccd7=$7

        # Record the CCDs selected for analysis into an external file
        echo 'The CCDs selected for mos'$prefix' are '$mosccds >> ../summary.txt

        # Create the source spectra, RMFs, and ARFs
        echo 'Creating source spectra and images' >> ../summary.txt
        
        # If no sources were found, run with mask=0
        if grep -Eq 'nonPositiveSrcBkg|Number of excluded sources:            0' '../cheese_mos'$prefix'_output.txt'; then
            echo 'mos-spectra prefix='$prefix' caldb=$CALDB mask=0 elow=0 ehigh=0 ccd1='$ccd1' ccd2='$ccd2' ccd3='$ccd3' ccd4='$ccd4' ccd5='$ccd5' ccd6='$ccd6' ccd7='$ccd7' > ../mos'$prefix'-spectra_output.txt 2>&1' >> ../summary.txt
            mos-spectra prefix=$prefix caldb=$CALDB mask=0 elow=0 ehigh=0 ccd1=$ccd1 ccd2=$ccd2 ccd3=$ccd3 ccd4=$ccd4 ccd5=$ccd5 ccd6=$ccd6 ccd7=$ccd7 > ../mos$prefix-spectra_output.txt 2>&1
        else
            echo 'mos-spectra prefix='$prefix' caldb=$CALDB mask=1 elow=0 ehigh=0 ccd1='$ccd1' ccd2='$ccd2' ccd3='$ccd3' ccd4='$ccd4' ccd5='$ccd5' ccd6='$ccd6' ccd7='$ccd7' > ../mos'$prefix'-spectra_output.txt 2>&1' >> ../summary.txt
            mos-spectra prefix=$prefix caldb=$CALDB mask=1 elow=0 ehigh=0 ccd1=$ccd1 ccd2=$ccd2 ccd3=$ccd3 ccd4=$ccd4 ccd5=$ccd5 ccd6=$ccd6 ccd7=$ccd7 > ../mos$prefix-spectra_output.txt 2>&1
        fi

        # Check if there are insufficient events to estimate the background
        if grep -q 'Illegal division by zero' '../mos'$prefix'-spectra_output.txt'; then
            echo 'There was insufficient corner data to estimate the QPB background for mos'$prefix
            echo 'There was insufficient corner data to estimate the QPB background for mos'$prefix >> ../summary.txt
        else 
            # Create the Quiescent Particle Background (QPB) file
            echo 'mos_back prefix='$prefix' caldb=$CALDB diag=0 elow=0 ehigh=0 ccd1='$ccd1' ccd2='$ccd2' ccd3='$ccd3' ccd4='$ccd4' ccd5='$ccd5' ccd6='$ccd6' ccd7='$ccd7' > ../mos'$prefix'_back_output.txt 2>&1' >> ../summary.txt
            mos_back prefix=$prefix caldb=$CALDB diag=0 elow=0 ehigh=0 ccd1=$ccd1 ccd2=$ccd2 ccd3=$ccd3 ccd4=$ccd4 ccd5=$ccd5 ccd6=$ccd6 ccd7=$ccd7 > ../mos${prefix}_back_output.txt 2>&1
        fi

        echo 'Finished mos'$prefix >> ../summary.txt
    else
        # Record that this prefix is not usuable for further analysis
        echo 'Finished mos'$prefix >> ../summary.txt
        echo 'All CCDs were anomalous for 'mos$prefix >> ../summary.txt
    fi
done

# For the PN camera, outputs are again created in odf and are identical
# to those for the MOS as described above, being labelled pn${prefix}

for prefix in $pnprefixes; do

    echo 'Creating spectra and images for pn'$prefix >> ../summary.txt

    # There have been no issues with the PN cameras
    # Follow same procedure as for mos for clarity
    pnquads="1 1 1 1"
    set -- $pnquads
    quad1=$1
    quad2=$2
    quad3=$3
    quad4=$4

    # Record the CCDs selected for analysis into an external file
    echo 'The CCDs selected for pn'$prefix' are '$pnquads >> ../summary.txt

    # Create the source spectra, RMFs, and ARFs
    echo 'Creating source spectra and images' >> ../summary.txt

    # If no sources were found, run with mask=0
    if grep -Eq 'nonPositiveSrcBkg|Number of excluded sources:            0' '../cheese_pn'$prefix'_output.txt'; then
        echo 'pn-spectra prefix='$prefix' caldb=$CALDB mask=0 elow=0 ehigh=0 quad1='$quad1' quad2='$quad2' quad3='$quad3' quad4='$quad4' > ../pn'$prefix'-spectra_output.txt 2>&1' >> ../summary.txt
        pn-spectra prefix=$prefix caldb=$CALDB mask=0 elow=0 ehigh=0 quad1=$quad1 quad2=$quad2 quad3=$quad3 quad4=$quad4 > ../pn$prefix-spectra_output.txt 2>&1
    else
        echo 'pn-spectra prefix='$prefix' caldb=$CALDB mask=1 elow=0 ehigh=0 quad1='$quad1' quad2='$quad2' quad3='$quad3' quad4='$quad4' > ../pn'$prefix'-spectra_output.txt 2>&1' >> ../summary.txt
        pn-spectra prefix=$prefix caldb=$CALDB mask=1 elow=0 ehigh=0 quad1=$quad1 quad2=$quad2 quad3=$quad3 quad4=$quad4 > ../pn$prefix-spectra_output.txt 2>&1
    fi

    # Check if there are insufficient events to estimate the background
    if grep -q 'Illegal division by zero' '../pn'$prefix'-spectra_output.txt'; then
        echo 'There was insufficient corner data to estimate the QPB background for pn'$prefix
        echo 'There was insufficient corner data to estimate the QPB background for pn'$prefix >> ../summary.txt
    else
        # Create the Quiescent Particle Background (QPB) file
        echo 'pn_back prefix='$prefix' caldb=$CALDB diag=0 elow=0 ehigh=0 quad1='$quad1' quad2='$quad2' quad3='$quad3' quad4='$quad4' > ../pn'$prefix'_back_output.txt 2>&1' >> ../summary.txt
        pn_back prefix=$prefix caldb=$CALDB diag=0 elow=0 ehigh=0 quad1=$quad1 quad2=$quad2 quad3=$quad3 quad4=$quad4 > ../pn${prefix}_back_output.txt 2>&1
    fi

    echo 'Finished pn'$prefix >> ../summary.txt
done


#######################
# 9. Process & Delete #
#######################

# Process the raw output into python files in the $obsID directory, and delete
# the remaining files afterwards

echo -e '\nStep 9: Process the output data and delete intermediate files' >> ../summary.txt

for prefix in $mosprefixes; do
    pref=mos$prefix

    # Check if requisite files are present
    if [ ! -f $pref'-obj.pi' ]; then
        echo $pref'-obj.pi does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    if [ ! -f $pref'.arf' ]; then
        echo $pref'.arf does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    if [ ! -f $pref'.rmf' ]; then
        echo $pref'.rmf does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    if [ ! -f $pref'-back.pi' ]; then
        echo $pref'-back.pi does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi 
    
    echo 'python '$cdir'/spc2dat.py --xmmdata '$xmmdata' --obsID '$obsID' --prefix '$pref >> ../summary.txt 
    python $cdir/spc2dat.py --xmmdata $xmmdata --obsID $obsID --prefix $pref
done

for prefix in $pnprefixes; do
    pref=pn$prefix

    # Check if requisite files are present
    if [ ! -f $pref'-obj.pi' ]; then
        echo $pref'-obj.pi does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    if [ ! -f $pref'.arf' ]; then
        echo $pref'.arf does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    if [ ! -f $pref'.rmf' ]; then
        echo $pref'.rmf does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    if [ ! -f $pref'-back.pi' ]; then
        echo $pref'-back.pi does not exist, data cannot be processed.' >> ../summary.txt
        continue
    fi

    echo 'python '$cdir'/spc2dat.py --xmmdata '$xmmdata' --obsID '$obsID' --prefix '$pref >> ../summary.txt
    python $cdir/spc2dat.py --xmmdata $xmmdata --obsID $obsID --prefix $pref
done

# Delete the data that is no longer required
cd ..
rm -rf odf/
rm -rf pps/
rm -rf analysis/

# Check if python output successfully written, otherwise failed
if ls ./*_processed.h5 1> /dev/null 2>&1; then
    echo 'At least one hdf5 output created' >> ./summary.txt
else
    echo 'No python output created' >> ./summary.txt
    echo 'Processing failed!' >> ./summary.txt
    echo 'No python output created'
    echo 'Processing failed!'
    exit 1
fi

# Check which files were not successfully created
for prefix in $mosprefixes; do
    pref=mos$prefix
    if [ ! -f $pref'_processed.h5' ]; then
        echo $pref'_processed.h5 was not successfully created' >> ./summary.txt
        echo $pref'_processed.h5 was not successfully created'
    fi
done

for prefix in $pnprefixes; do
    pref=pn$prefix
    if [ ! -f $pref'_processed.h5' ]; then
        echo $pref'_processed.h5 was not successfully created' >> ./summary.txt
        echo $pref'_processed.h5 was not successfully created'
    fi
done

# Done!
echo -e '\nComplete!' >> ./summary.txt
echo 'Complete!'
