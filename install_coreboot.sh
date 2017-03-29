#!/bin/bash
#
# Copyright (C) 2017 Purism
# Author: Youness Alaoui <youness.alaoui@puri.sm>
#
# Script that downloads and/or extracts all the required binaries for coreboot
# to work on Purism Librem 13 v1 laptops and builds the final coreboot flash image
# and flashes it.

# Dependencies : curl dmidecode flashrom sharutils

TEMPDIR=$(mktemp -d /tmp/coreboot_install.XXXXXX)
LOGFILE="${TEMPDIR}/install.log"

FLASHROM='../flashrom/flashrom'
FLASHROM_PROGRAMMER="-pinternal:laptop=force_I_want_a_brick"
DMIDECODE='dmidecode'
CBFSTOOL='../coreboot/build/cbfstool'
IFDTOOL='../coreboot/util/ifdtool/ifdtool'
UEFIEXTRACT='../UEFITool/UEFIExtract/UEFIExtract'

TIDUS_ZIP_FILENAME='chromeos_8743.85.0_tidus_recovery_stable-channel_mp-v2.bin.zip'
TIDUS_ZIP_URL='https://dl.google.com/dl/edgedl/chromeos/recovery/chromeos_8743.85.0_tidus_recovery_stable-channel_mp-v2.bin.zip'
TIDUS_ZIP_SHA1='d17650df79235dca0b13c86748e63c227e03c401'
TIDUS_BIN_FILENAME='chromeos_8743.85.0_tidus_recovery_stable-channel_mp-v2.bin'
TIDUS_BIN_SHA1='72240974b72d5328608a48c0badc97cf8653a5f4'
TIDUS_ROOTA_FILENAME='chromeos_tidus_root_a.ext2'
TIDUS_ROOTA_SHA1='038dd8cfae69565457e45c1e1a7515a411a32fb3'
TIDUS_SHELLBALL_FILENAME='chromeos-firmwareupdate'
TIDUS_SHELLBALL_SHA1='fff693b74088f79d292c17c9ef5efacdba8915f8'
TIDUS_COREBOOT_FILENAME='chromeos_tidus_bios.bin'
TIDUS_COREBOOT_SHA1='3775dd99a1e4e56932585ce311e937db12605e2f'

MRC_FILENAME='mrc.bin'
MRC_SHA1='eb2536a4e94c6d1cc6fe5dbd8952ae9b5acc535b'
REFCODE_FILENAME='refcode.bin'
REFCODE_SHA1='e3f985d23199a4bd8ec317beae3dd90ce5dfa3cc'
VGABIOS_FILENAME='vgabios.bin'
VGABIOS_SHA1='17db61b82e833a8df83c5dc4a0a68e35210a6334'

log () {
    local msg=$1
    echo "$msg"
    echo "$msg" >> ${LOGFILE}
}

die () {
    local msg=$1

    log ""
    log "$msg"
    echo "Log files are available in '${TEMPDIR}'"
    exit 1
}

check_root() {
    if [[ "$EUID" != 0 ]]; then
        die "This script must be run as root."
    fi
}

check_dependency () {
    local name=$1
    local cmd=$2
    
    if type $cmd &> ${LOGFILE}; then
        log "$name : yes"
    else
        log "$name : no"
        die "Error: Could not find required dependency"
    fi
}

check_dependencies () {
    log "Checking for dependencies :"
    check_dependency flashrom ${FLASHROM}
    check_dependency dmidecode ${DMIDECODE}
    check_dependency cbfstool ${CBFSTOOL}
    check_dependency ifdtool ${IFDTOOL}
    check_dependency UEFIExtract ${UEFIEXTRACT}
    check_dependency curl curl
    check_dependency unzip unzip
    check_dependency parted parted
    check_dependency dd dd
    check_dependency debugfs debugfs
    check_dependency uudecode uudecode
}

check_machine() {
    MANUFACTURER=$(${DMIDECODE} -t 1 |grep -m1 "Manufacturer:"   | cut -d' ' -f 2-)
    PRODUCT_NAME=$(${DMIDECODE} -t 1 |grep -m1 "Product Name:"   | cut -d' ' -f 3-)
    VERSION=$(${DMIDECODE} -t 1 |grep -m1 "Version:"   | cut -d' ' -f 2-)


    if [ "${MANUFACTURER}" == "LENOVO" -a \
                           "${PRODUCT_NAME}" == "20AQCTO1WW" -a \
                           "${VERSION}" == "ThinkPad T440s" ]; then
        FLASHROM_ARGS=""
        ORIG_FILENAME="vendor_bios_backup.rom"
        VENDOR=1
        log "Vendor BIOS has been detected in your flash"
    elif [ "${MANUFACTURER}" == "Intel Corporation" -a \
                             "${PRODUCT_NAME}" == "SharkBay Platform" -a \
                             "${VERSION}" == "0.1" ]; then
        FLASHROM_ARGS=""
        ORIG_FILENAME="vendor_bios_backup.rom"
        VENDOR=1
        log "Vendor BIOS has been detected in your flash"
    elif [ "${MANUFACTURER}" == "Purism" -a \
                             "${PRODUCT_NAME}" == "Librem 13" -a \
                             "${VERSION}" == "1.0" ]; then
        FLASHROM_ARGS="-c MX25L6406E/MX25L6408E"
        ORIG_FILENAME="coreboot_bios_backup.rom"
        VENDOR=1
        log '**** Coreboot BIOS has been detected in your flash **** '
    else
        die '**** This machine does not seem to be a Purism Librem 13 v1, it is not safe to use this script **** '
    fi
}

backup_original_rom() {
    log "Making backup copy of your current BIOS"
    if [ "${MANUFACTURER}" != "LENOVO" ]; then
        ${FLASHROM} -V ${FLASHROM_PROGRAMMER} ${FLASHROM_ARGS} -r ${ORIG_FILENAME} >& ${TEMPDIR}/flashrom_read.log || die "Unable to dump original BIOS from your flash"
    fi
    
    log "Your current BIOS has been backed up to the file '${ORIG_FILENAME}'"
}

check_file_sha1 () {
    local file=$1
    local sha1=$2
    local silent=$3
    local result=''
    if [ -f "$file" ]; then
        if [ "$silent" == "" ]; then
            log "Verifying hash of file : $file"
        fi
        result=$(sha1sum "$file" | cut -d' ' -f 1)
        if [ "$result" == "$sha1" ]; then
            if [ "$silent" == "" ]; then
                log "File hash is valid : $result"
            fi
            return 0
        else
            if [ "$silent" == "" ]; then
                log "File hash is invalid. Found $result, expected $sha1"
            fi
        fi
    fi
    return 1
}

get_tidus_recovery_zip () {
    local file=${TIDUS_ZIP_FILENAME}
    local sha1=${TIDUS_ZIP_SHA1}
    if check_file_sha1 "$file" "$sha1" ; then
        log "Tidus Chromebook recovery image found. Skipping download."
    else
        log "Press Enter to start the 553MB download."
        read
        curl ${TIDUS_ZIP_URL} > chromeos_8743.85.0_tidus_recovery_stable-channel_mp-v2.bin.zip
        if ! check_file_sha1 "$file" "$sha1" ; then
            log "The downloaded image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
    fi
}

get_tidus_recovery () {
    local file=${TIDUS_BIN_FILENAME}
    local sha1=${TIDUS_BIN_SHA1}
    if check_file_sha1 "$file" "$sha1" ; then
        log "Tidus Chromebook recovery image already extracted"
    else
        get_tidus_recovery_zip
        log "Decompressing the image"
        unzip -q ${TIDUS_ZIP_FILENAME}
        if ! check_file_sha1 "$file" "$sha1" ; then
            log "The downloaded image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
    fi
}

get_tidus_partition () {
    local file=${TIDUS_ROOTA_FILENAME}
    local sha1=${TIDUS_ROOTA_SHA1}
    if check_file_sha1 "$file" "$sha1"; then
        log "Tidus Chromebook ROOT-A partition already extracted"
    else
        local _bs=1024
        local ROOTP=''
        local START=''
        local SIZE=''

        get_tidus_recovery
	log "Extracting ROOT-A partition"
	ROOTP=$( printf "unit\nB\nprint\nquit\n" | \
		 parted ${TIDUS_BIN_FILENAME} 2> ${TEMPDIR}/parted.log | grep "ROOT-A" )

	START=$(( $( echo $ROOTP | cut -f2 -d\ | tr -d "B" ) ))
	SIZE=$(( $( echo $ROOTP | cut -f4 -d\ | tr -d "B" ) ))

	dd if=${TIDUS_BIN_FILENAME} of=$file bs=$_bs skip=$(( $START / $_bs )) \
	   count=$(( $SIZE / $_bs ))  > ${TEMPDIR}/dd.log 2>&1

        if ! check_file_sha1 "$file" "$sha1" ; then
            log "The extracted partition failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
    fi
}

get_tidus_shellball () {
    local file=${TIDUS_SHELLBALL_FILENAME}
    local sha1=${TIDUS_SHELLBALL_SHA1}
    if check_file_sha1 "$file" "$sha1" ; then
        log "Tidus Chromebook Firmware update Shell script already extracted"
    else
        get_tidus_partition
	log "Extracting chromeos-firmwareupdate"
	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${TIDUS_SHELLBALL_FILENAME}\nquit" | \
		debugfs ${TIDUS_ROOTA_FILENAME} > ${TEMPDIR}/debugfs.log 2>&1
        if ! check_file_sha1 "$file" "$sha1" ; then
            log "The extracted shell script failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
    fi
}

get_tidus_coreboot () {
    local file=${TIDUS_COREBOOT_FILENAME}
    local sha1=${TIDUS_COREBOOT_SHA1}
    if check_file_sha1 "$file" "$sha1" ; then
        log "Tidus Chromebook Coreboot image already extracted"
    else
        get_tidus_shellball
	local _unpacked=$( mktemp -d )
        
	debug "Extracting coreboot image"
	sh ${TIDUS_SHELLBALL_FILENAME} --sb_extract $_unpacked > ${TEMPDIR}/shellball.log
	cp $_unpacked/bios.bin ${TIDUS_COREBOOT_FILENAME}
        rm -rf "$_unpacked"
        
        if ! check_file_sha1 "$file" "$sha1" ; then
            log "The coreboot image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
    fi        
}

get_mrc_blob() {
    if [ $VENDOR ]; then
        log '**** The original vendor BIOS has been detected.                    ****'
        log '**** Since this is the first time you will be upgrading to coreboot ****'
        log '**** You will need to download some of the required binary blobs.   ****'
        log '**** These binary blobs will need to be extracted from the recovery ****'
        log '**** image of the Tidus chromebook (Lenovo ThinkCentre ChromeBox).  ****'
        log '**** Since those binary are required for the hardware and memory    ****'
        log '**** initialization of the machine, but cannot be distributed       ****'
        log '**** without agreeing to draconian licenses, you will download them ****'
        log '**** directly from the Google website                               ****'

        get_tidus_coreboot
        COREBOOT_FILENAME=${TIDUS_COREBOOT_FILENAME}
    else
        COREBOOT_FILENAME=${ORIG_FILENAME}
    fi

    log "Extracting Memory Reference Code : mrc.bin"
    ${CBFSTOOL} $COREBOOT_FILENAME extract  -r BOOT_STUB -n "mrc.bin" -f ${MRC_FILENAME} > ${TEMPDIR}/cbfstool_mrc.log 2>&1 || die "Unable to extract MRC file"
    if ! check_file_sha1 "${MRC_FILENAME}" "${MRC_SHA1}" 1 ; then
        die "MRC file hash does not match the expected one"
    fi
    log "Extracting Intel Broadwell Reference Code : refcode.bin"
    ${CBFSTOOL} $COREBOOT_FILENAME extract  -r BOOT_STUB -n "fallback/refcode" -f ${REFCODE_FILENAME} -m x86 > ${TEMPDIR}/cbfstool_refcode.log 2>&1 || die "Unable to extract Refcode file"
    if ! check_file_sha1 "${REFCODE_FILENAME}" "${REFCODE_SHA1}" 1 ; then
        die "MRC file hash does not match the expected one"
    fi
}

get_vgabios_blob() {
    log "Extracting VGA BIOS image : vgabios.bin"
    if [ $VENDOR ]; then
        ${UEFIEXTRACT} ${ORIG_FILENAME} > ${TEMPDIR}/uefiextract.log 2>&1 || die "Unable to extract vgabios file"
        cp "${ORIG_FILENAME}.dump/2 BIOS region/2 8C8CE578-8A3D-4F1C-9935-896185C32DD3/2 9E21FD93-9C72-4C15-8C4B-E77F1DB2D792/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 Volume image section/0 8C8CE578-8A3D-4F1C-9935-896185C32DD3/237 A0327FE0-1FDA-4E5B-905D-B510C45A61D0/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 C5A4306E-E247-4ECD-A9D8-5B1985D3DCDA/body.bin" ${VGABIOS_FILENAME}
        rm -rf "${ORIG_FILENAME}.dump"
    else
        ${CBFSTOOL} $ORIG_FILENAME extract -n "pci8086,1616.rom" -f "vgabios.bin" > ${TEMPDIR}/cbfstool_vgabios.log 2>&1 || die "Unable to extract vgabios file"
    fi
    if ! check_file_sha1 "${VGABIOS_FILENAME}" "${VGABIOS_SHA1}" 1 ; then
        die "VGA Bios file hash does not match the expected one"
    fi
    log "VGA BIOS blob has been extracted from your current BIOS."
}

get_descriptor_and_me_blobs() {
    log "Extracting Intel Firmware Descriptor and Intel Management Engine images"
    ${IFDTOOL} -x ${ORIG_FILENAME}
    rm -f flashregion_1_bios.bin
}

get_required_blobs() {
    get_mrc_blob
    get_vgabios_blob
    get_descriptor_and_me_blobs
    log "Binary blobs have been extracted from your current BIOS and (optionally) from the recovery image of the Tidus chromebook."
}

configuration_wizard() {
    clear
    echo "Select which coreboot options you would like :"
    echo "1 - With a neutured Intel ME binary (93% code removed) (recommended)"
    echo "2 - With the full Intel Management Engine (ME) binary"
    echo ""
    echo "** DISCLAIMER: The Intel Management Engine is the firmware running"
    echo "** on a hidden microcontroller in the CPU which allows remote access"
    echo "** and control to the computer and its hardware. While the remote"
    echo "** capabilities of the Intel ME are already disabled on the Librem computers,"
    echo "** the firmware is still considered an unknown binary blob with code that"
    echo "** cannot be audited and which runs on your machine without restrictions."
    intel_me=0
    while [ "$intel_me" != "1" -a "$intel_me" != "2" ]; do
        read -p "Enter your choice (default: 1) : " intel_me
        if [ "$intel_me" == "" ]; then
            intel_me=1
        fi
        if [ "$intel_me" != "1" -a "$intel_me" != "2" ]; then
            echo "Invalid choice"
        fi
    done

    clear
    echo "Select which coreboot options you would like :"
    echo "1 - With CPU microcode updates (RECOMMENDED)"
    echo "2 - Without CPU microcode updates"
    echo ""
    echo "** WARNING: Running your BIOS without the CPU microcode updates is not recommended."
    echo "** The microcode updates are used to fix bugs in the CPU's instructions"
    echo "** which can cause random crashes, data corruption"
    echo "** The risk level of the microcode is low, and running without them can"
    echo "** cause silent data corruption or random lock-ups of the hardware"
    microcode=0
    while [ "$microcode" != "1" -a "$microcode" != "2" ]; do
        read -p "Enter your choice (default: 1) : " microcode
        if [ "$microcode" == "" ]; then
            microcode=1
        fi
        if [ "$microcode" != "1" -a "$microcode" != "2" ]; then
            echo "Invalid choice"
        fi
    done
    
    clear
    echo "Select which coreboot options you would like :"
    echo "1 - Run the VGA BIOS natively (recommended)"
    echo "2 - Run the VGA BIOS in a CPU emulator"
    echo ""
    echo "** DISCLAIMER: The VGA BIOS is used to initialize the graphics card."
    echo "** If you are worried about it potentialy being used to install hypervisors"
    echo "** or other malicious modules, then you can run it in a CPU emulator which"
    echo "** eliminates the potential security risks but greatly increases the boot"
    echo "** time, as the CPU emulator is significantly slower than a native run."
    vbios_emulator=0
    while [ "$vbios_emulator" != "1" -a "$vbios_emulator" != "2" ]; do
        read -p "Enter your choice (default: 1) : " vbios_emulator
        if [ "$vbios_emulator" == "" ]; then
            vbios_emulator=1
        fi
        if [ "$vbios_emulator" != "1" -a "$vbios_emulator" != "2" ]; then
            echo "Invalid choice"
        fi
    done

    clear
    echo "Select which SeaBIOS options you would like :"
    echo "1 - Boot order : M.2 SSD -> 2.5\" HDD"
    echo "2 - Boot order : 2.5\" HDD-> M.2 SSD"
    echo ""
    echo "** Please select the default boot order. You can always select a"
    echo "** different boot device by pressing 'ESC' at boot time"
    bootorder=0
    while [ "$bootorder" != "1" -a "$bootorder" != "2" ]; do
        read -p "Enter your choice (default: 1) : " bootorder
        if [ "$bootorder" == "" ]; then
            bootorder=1
        fi
        if [ "$bootorder" != "1" -a "$bootorder" != "2" ]; then
            echo "Invalid choice"
        fi
    done
    
    clear
    delay=-1
    while [ "$delay" -lt "0" ]; do
        echo "Please select the amount of time (in milliseconds) to wait at the"
        read -p "boot menu prompt before selecting the default boot choice (default: 2500) : " delay
        if [ "$delay" == "" ]; then
            delay=2500
        fi
        case $delay in
            ''|*[!0-9]*) 
                echo "Invalid choice : Not a positive number"
                delay=-1
                ;;
            *) ;;
        esac
    done
    
    clear
    log "Summary of your choices :"
    log -n "Intel ME                : "
    if [ "$intel_me" == "1" ]; then
        log "Neutered"
    else
        log "Full"
    fi
    log -n "Microcode updates       : "
    if [ "$microcode" == "1" ]; then
        log "Enabled"
    else
        log "Disabled"
    fi
    log -n "VGA BIOS Execution mode : "
    if [ "$vbios_emulator" == "1" ]; then
        log "Native"
    else
        log "Secured"
    fi
    log -n "Boot order              : "
    if [ "$bootorder" == "1" ]; then
        log "M.2 SSD -> 2.5\" HDD"
    else
        log "2.5\" HDD -> M.2 SSD"
    fi
    log "Boot menu wait time     : ${delay} ms"
    log ""
}


clear
check_root
check_dependencies
check_machine
backup_original_rom
get_required_blobs
log "Press Enter to start the configuration wizard for coreboot"
read
configuration_wizard
