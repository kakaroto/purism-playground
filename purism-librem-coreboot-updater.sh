#!/bin/bash
#
# Copyright (C) 2017 Purism
# Author: Youness Alaoui <youness.alaoui@puri.sm>
#
# Script that downloads and/or extracts all the required components for coreboot
# to work on Purism Librem 13 v1 laptops, builds the final coreboot flash image,
# and flashes it.

# Dependencies : curl dmidecode flashrom sharutils

ARGV=$1
CACHE_HOME="${XDG_CACHE_HOME}"
if [ "$CACHE_HOME" == "" ]; then
    CACHE_HOME="${HOME}/.cache"
fi
CACHE_DIR="${CACHE_HOME}/purism-librem-coreboot-updater"
mkdir -p "${CACHE_DIR}"
TEMPDIR=$(mktemp -d ${CACHE_DIR}/logs.XXXXXX)
LOGFILE="${TEMPDIR}/install.log"

DMIDECODE='dmidecode'
FLASHROM="flashrom"
CBFSTOOL="/usr/share/purism-librem-coreboot-updater/cbfstool"
RMODTOOL="/usr/share/purism-librem-coreboot-updater/rmodtool"
IFDTOOL="/usr/share/purism-librem-coreboot-updater/ifdtool"
UEFIEXTRACT="/usr/share/purism-librem-coreboot-updater/UEFIExtract"
ME_CLEANER="/usr/share/purism-librem-coreboot-updater/me_cleaner.py"

FLASHROM_PROGRAMMER="-pinternal:laptop=force_I_want_a_brick"
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
REFCODE_FILENAME='refcode.elf'
REFCODE_RMOD='refcode.rmod'
REFCODE_SHA1='e3f985d23199a4bd8ec317beae3dd90ce5dfa3cc'
VGABIOS_FILENAME='vgabios.bin'
VGABIOS_SHA1='17db61b82e833a8df83c5dc4a0a68e35210a6334'
DESCRIPTOR_FILENAME='flashregion_0_flashdescriptor.bin'
DESCRIPTOR_SIZE='4096'
DESCRIPTOR_SHA1='359101061f789e1cfc13742d5980ac441787e96c'
DESCRIPTOR_SHA1_CB='c4c00c68a56203b311e73d13be7fbc63d2e7b5af'
ME_FILENAME='flashregion_2_intel_me.bin'
ME_SIZE='2093056'
COREBOOT_FILENAME='coreboot_base_bios.rom'
COREBOOT_BZ2_FILENAME='coreboot_base_bios.rom.bz2'
COREBOOT_BASE_URL='http://kakaroto.homelinux.net/purism/coreboot_base_bios.rom.bz2'
COREBOOT_BASE_SHA1='e1673cdfbeb9b44801781b5aa43ea869b2496ddc'

COREBOOT_FINAL_IMAGE='coreboot.rom'

log_file () {
    local msg=$1
    echo "$msg" >> ${LOGFILE}
}

log () {
    local msg=$1
    echo "$msg"
    log_file "$msg"
}

die () {
    local msg=$1

    log ""
    log "$msg"
    echo "Log files are available in '${TEMPDIR}'"
    exit 1
}

welcome_msg() {
    clear
    log "Welcome to the Purism Librem Coreboot Updater"
    log ""
    log "This script will help you build a coreboot image and will update your BIOS"
    log "with the latest coreboot image for your machine."
    log ""
    log "This script currently only supports installing coreboot on Librem 13 v1 hardware"
    log ""
    log '**** NOTE: After flashing, this script will reboot your laptop ****'
    log "It is recommended not to postpone rebooting after coreboot has been installed"
    log "on your flash."
    log "We suggest you save all your documents and close all your applications"
    log "to prepare your computer for the reboot"
    log ""
    log "Press Enter to begin..."
    read
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
        log "$name: yes"
    else
        log "$name: no"
        die "Error: Could not find required dependency"
    fi
}

check_dependencies () {
    log "Checking for dependencies :"
    check_dependency "flashrom     " ${FLASHROM}
    check_dependency "dmidecode    " ${DMIDECODE}
    check_dependency "cbfstool     " ${CBFSTOOL}
    check_dependency "rmodtool     " ${RMODTOOL}
    check_dependency "ifdtool      " ${IFDTOOL}
    check_dependency "UEFIExtract  " ${UEFIEXTRACT}
    check_dependency "me_cleaner   " ${ME_CLEANER}
    check_dependency "curl         " curl
    check_dependency "grep         " grep
    check_dependency "sed          " sed
    check_dependency "cut          " cut
    check_dependency "head         " head
    check_dependency "tail         " tail
    check_dependency "unzip        " unzip
    check_dependency "gunzip       " gunzip
    check_dependency "bunzip2      " bunzip2
    check_dependency "parted       " parted
    check_dependency "dd           " dd
    check_dependency "debugfs      " debugfs
    check_dependency "uudecode     " uudecode
    log ""
}

check_machine() {
    local MANUFACTURER=$(${DMIDECODE} -t 1 |grep -m1 "Manufacturer:"   | cut -d' ' -f 2-)
    local PRODUCT_NAME=$(${DMIDECODE} -t 1 |grep -m1 "Product Name:"   | cut -d' ' -f 3-)
    local VERSION=$(${DMIDECODE} -t 1 |grep -m1 "Version:"   | cut -d' ' -f 2-)
    local BIOS_DATE=$(${DMIDECODE} -t 0 |grep -m1 "Release Date:"   | cut -d' ' -f 3-)
    local FAMILY=$(${DMIDECODE} -t 4 |grep -m1 "Family:"   | cut -d' ' -f 2-)
    IS_LIBREM13V1=0

    if [ "${MANUFACTURER}" == "Intel Corporation" -a \
                             "${PRODUCT_NAME}" == "SharkBay Platform" -a \
                             "${VERSION}" == "0.1" -a \
                             "${FAMILY}" == "Core i5" -a \
                             "${BIOS_DATE}" == "06/18/2015" ]; then
        FLASHROM_ARGS=""
        ORIG_FILENAME="factory_bios_backup.rom"
        VENDOR=1
        IS_LIBREM13V1=1
        CACHE_DIR="${CACHE_HOME}/purism-librem-coreboot-updater/librem13v1"
        log '**** Detected Librem 13 v1 hardware with the Factory BIOS in the flash ****'
    elif [ "${MANUFACTURER}" == "Purism" -a \
                             "${PRODUCT_NAME}" == "Librem 13" -a \
                             "${VERSION}" == "1.0" ]; then
        FLASHROM_ARGS="-c MX25L6406E/MX25L6408E"
        ORIG_FILENAME="coreboot_bios_backup.rom"
        VENDOR=0
        IS_LIBREM13V1=1
        CACHE_DIR="${CACHE_HOME}/purism-librem-coreboot-updater/librem13v1"
        log '**** Detected Librem 13 v1 hardware with a coreboot BIOS in the flash **** '
    else
        die '**** This machine does not seem to be a Purism Librem 13 v1, it is not safe to use this script **** '
    fi
    mkdir -p "${CACHE_DIR}"
    cd "${CACHE_DIR}"
}

backup_original_rom() {
    log "Making a backup copy of your current BIOS. Please wait..."
    if [ -f "${ORIG_FILENAME}" ]; then
        log ""
        log "ERROR: File '${CACHE_DIR}/${ORIG_FILENAME}' already exists."
        log "We don't want to overwrite this file because it might contain a valid BIOS image."
        log "For example, if you just flashed coreboot but didn't reboot your laptop, then this script"
        log "will recognize that you are still running the factory BIOS, and that file"
        log "contains the original factory BIOS file, but reading the flash contents now would simply"
        log "overwrite it with the coreboot image you have just flashed, thus destroying your only copy"
        log "of the original Factory BIOS file."
        log ""
        log "For your security, this update process is cancelled."
        log "Please move away that file into a safe location before running this script again."
        die ""
    fi
    ${FLASHROM} -V ${FLASHROM_PROGRAMMER} ${FLASHROM_ARGS} -r ${ORIG_FILENAME} >& ${TEMPDIR}/flashrom_read.log || die "Unable to dump original BIOS from your flash"
    
    log "Your current BIOS has been backed up to the file '${ORIG_FILENAME}'"
    log ""
}

check_file_sha1 () {
    local file=$1
    local sha1=$2
    local silent=$3
    local result=''
    local print=''

    if [ "$silent" == "" ]; then
        print=log
    else
        print=log_file
    fi
    if [ -f "$file" ]; then
        $print "Verifying hash of file : $file"
        result=$(sha1sum "$file" | cut -d' ' -f 1)
        if [ "$result" == "$sha1" ]; then
            $print "File hash is valid: $result"
            return 0
        else
            $print "File hash is invalid. Found $result, expected $sha1"
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
        log "Press Enter to start the 606MB download."
        read
        curl ${TIDUS_ZIP_URL} > $file
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
            log "The downloaded image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS."
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
        log 'Decompressing the image...'
        unzip -q ${TIDUS_ZIP_FILENAME}
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
            log "The downloaded image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
        rm -f ${TIDUS_ZIP_FILENAME}
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
            die "Aborting the operation to prevent corruption of your BIOS."
        fi
        rm -f ${TIDUS_BIN_FILENAME}
    fi
}

get_tidus_shellball () {
    local file=${TIDUS_SHELLBALL_FILENAME}
    local sha1=${TIDUS_SHELLBALL_SHA1}
    if check_file_sha1 "$file" "$sha1" ; then
        log "Tidus Chromebook Firmware update Shell script already extracted"
    else
        get_tidus_partition
	log 'Extracting chromeos-firmwareupdate'
	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${TIDUS_SHELLBALL_FILENAME}\nquit" | \
		debugfs ${TIDUS_ROOTA_FILENAME} > ${TEMPDIR}/debugfs.log 2>&1
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
            log "The extracted shell script failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
        rm -f ${TIDUS_ROOTA_FILENAME}
    fi
}

# This will search for and extract the packed bios.bin from the shellball so
# we can extract the bios.bin without actually executing the chromebook shellball
# in case it does anything that it shouldn't
extract_bios_from_shellball () {
    shellball=$1
    bios=$2

    start=$(grep "== bios.bin ==" $shellball -n -m 1 | cut -d: -f1)
    begin=$(tail $shellball -n +${start} | grep 'begin' -n -m 1 | cut -d: -f1)
    end=$(tail $shellball -n +$(( ${start} + ${begin} - 1)) | grep 'end' -n -m 1 | cut -d: -f1)

    tail $shellball -n +$(( ${start} + ${begin} - 1)) | head -n ${end} | sed 's/^X//' | sed "s#_fwupdate/gzi#${bios}.gz#" | uudecode && gunzip ${bios}.gz && chmod 0644 $bios
}

get_tidus_coreboot () {
    local file=${TIDUS_COREBOOT_FILENAME}
    local sha1=${TIDUS_COREBOOT_SHA1}
    if check_file_sha1 "$file" "$sha1" ; then
        log "Tidus Chromebook coreboot image already extracted"
    else
        get_tidus_shellball
        
	log 'Extracting coreboot image'
        extract_bios_from_shellball ${TIDUS_SHELLBALL_FILENAME} $file
        
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
            log "The coreboot image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
        rm -f ${TIDUS_SHELLBALL_FILENAME}
    fi        
}

get_mrc_binary() {
    local coreboot_filename=""
    local region="COREBOOT"

    if [ "$VENDOR" == "1" ]; then
        log '**** The original Factory BIOS has been detected.                   ****'
        log '**** Since this is the first time you will be upgrading to coreboot ****'
        log '**** You will need to download some of the required binaries.       ****'
        log '**** These binaries will need to be extracted from the recovery     ****'
        log '**** image of the Tidus chromebook (Lenovo ThinkCentre ChromeBox).  ****'
        log '**** Since those binaries are required for the hardware and memory  ****'
        log '**** initialization of the machine, but cannot be distributed       ****'
        log '**** without agreeing to draconian licenses, this script downloads  ****'
        log '**** them directly from the Google website.                         ****'

        get_tidus_coreboot
        coreboot_filename=${TIDUS_COREBOOT_FILENAME}
        region="BOOT_STUB"
    else
        coreboot_filename=${ORIG_FILENAME}
    fi

    log "Extracting Memory Reference Code: ${MRC_FILENAME}"
    ${CBFSTOOL} $coreboot_filename extract  -r $region -n "mrc.bin" -f ${MRC_FILENAME} > ${TEMPDIR}/cbfstool_mrc.log 2>&1 || die "Unable to extract MRC file"
    if ! check_file_sha1 "${MRC_FILENAME}" "${MRC_SHA1}" 1 ; then
        die "MRC file hash does not match the expected one"
    fi
    log "Extracting Intel Broadwell Reference Code: ${REFCODE_FILENAME}"
    ${CBFSTOOL} $coreboot_filename extract  -r $region -n "fallback/refcode" -f ${REFCODE_FILENAME} -m x86 > ${TEMPDIR}/cbfstool_refcode.log 2>&1 || die "Unable to extract Refcode file"
    if ! check_file_sha1 "${REFCODE_FILENAME}" "${REFCODE_SHA1}" 1 ; then
        die "MRC file hash does not match the expected one"
    fi
}

get_vgabios_binary() {
    log "Extracting VGA BIOS image: ${VGABIOS_FILENAME}"
    if [ "$VENDOR" == "1" ]; then
        ${UEFIEXTRACT} ${ORIG_FILENAME} > ${TEMPDIR}/uefiextract.log 2>&1 || die "Unable to extract vgabios file"
        cp "${ORIG_FILENAME}.dump/2 BIOS region/2 8C8CE578-8A3D-4F1C-9935-896185C32DD3/2 9E21FD93-9C72-4C15-8C4B-E77F1DB2D792/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 Volume image section/0 8C8CE578-8A3D-4F1C-9935-896185C32DD3/237 A0327FE0-1FDA-4E5B-905D-B510C45A61D0/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 C5A4306E-E247-4ECD-A9D8-5B1985D3DCDA/body.bin" ${VGABIOS_FILENAME}
        rm -rf "${ORIG_FILENAME}.dump"
    else
        ${CBFSTOOL} $ORIG_FILENAME extract -n "pci8086,1616.rom" -f ${VGABIOS_FILENAME} > ${TEMPDIR}/cbfstool_vgabios.log 2>&1 || die "Unable to extract vgabios file"
    fi
    if ! check_file_sha1 "${VGABIOS_FILENAME}" "${VGABIOS_SHA1}" 1 ; then
        die "VGA Bios file hash does not match the expected one"
    fi
    log "The VGA BIOS binary has been extracted from your current BIOS."
}

get_descriptor_and_me_binaries() {
    log "Extracting Intel Firmware Descriptor and Intel Management Engine images"
    ${IFDTOOL} -x ${ORIG_FILENAME} > ${TEMPDIR}/ifdtool_extract.log 2>&1 || die "Unable to extract descriptor and me files"
    rm -f flashregion_1_bios.bin
    local region_0_size=0
    local region_2_size=0
    if [ -f ${DESCRIPTOR_FILENAME} ]; then
        region_0_size=$(stat -c%s "${DESCRIPTOR_FILENAME}")
    fi
    if [ -f ${ME_FILENAME} ]; then
        region_2_size=$(stat -c%s "${ME_FILENAME}")
    fi
    if [ "$region_0_size" != "${DESCRIPTOR_SIZE}" ]; then
        die "Intel Firmware Descriptor size does not match the expected file size"
    fi
    if [ "$VENDOR" == "1" ]; then
        if ! check_file_sha1 "${DESCRIPTOR_FILENAME}" "${DESCRIPTOR_SHA1}" 1 ; then
            die "Intel Firmware Descriptor file hash does not match the expected one"
        fi
    else
        if ! check_file_sha1 "${DESCRIPTOR_FILENAME}" "${DESCRIPTOR_SHA1_CB}" 1 ; then
            die "Intel Firmware Descriptor file hash does not match the expected one"
        fi
    fi
    if [ "$region_2_size" != "${ME_SIZE}" ]; then
        die "Intel Management Engine size does not match the expected file size"
    fi
}

get_required_binaries() {
    get_mrc_binary
    get_vgabios_binary
    get_descriptor_and_me_binaries
    log ""
    log "All required binaries have been extracted from your current BIOS"
    if [ "$VENDOR" == "1" ]; then
        log "and from the recovery image of the Tidus chromebook."
    fi
    log ""
}

default_config_options() {
    intel_me=1
    microcode=1
    bootorder=1
    memtest=1
    delay=2500
}

configuration_wizard() {
    clear
    echo "Select which coreboot options you would like:"
    echo "1 - With a neutralized Intel ME binary (93% code removed) - recommended"
    echo "2 - With the full Intel ME binary"
    echo ""
    echo "** NOTE: The Intel Management Engine (ME) is the firmware running"
    echo "** on a hidden microcontroller in the CPU which allows remote access"
    echo "** and control to the computer and its hardware. While the remote"
    echo "** capabilities (AMT) of the Intel ME are already disabled on the Librem computers,"
    echo "** the firmware is still considered an unknown binary with code that"
    echo "** cannot be audited and which runs on your machine without restrictions."
    echo ""
    echo "** For more information, please visit: https://puri.sm/learn/intel-me/"
    intel_me=0
    while [ "$intel_me" != "1" -a "$intel_me" != "2" ]; do
        read -p "Enter your choice (default: 1): " intel_me
        if [ "$intel_me" == "" ]; then
            intel_me=1
        fi
        if [ "$intel_me" != "1" -a "$intel_me" != "2" ]; then
            echo "Invalid choice"
        fi
    done

    clear
    echo "Select which coreboot options you would like:"
    echo "1 - With CPU microcode updates (recommended)"
    echo "2 - Without CPU microcode updates"
    echo ""
    echo "** WARNING: Running your BIOS without the CPU microcode updates is not recommended."
    echo "** The microcode updates are used to fix bugs in the CPU's instructions which can"
    echo "** otherwise cause random crashes, data corruption and other unexpected behavior."
    echo "** "
    echo "** The risk level of the microcode updates is low, and running without them"
    echo "** can cause silent data corruption or random hardware lock-ups (freezes)."
    echo "** Please note that the CPU already comes with a microcode installed in its"
    echo "** silicon. This option only affects the inclusion of updates to it."
    microcode=0
    while [ "$microcode" != "1" -a "$microcode" != "2" ]; do
        read -p "Enter your choice (default: 1): " microcode
        if [ "$microcode" == "" ]; then
            microcode=1
        fi
        if [ "$microcode" != "1" -a "$microcode" != "2" ]; then
            echo "Invalid choice"
        fi
    done
   
    clear
    echo "Select the default order in which devices will attempt booting:"
    echo "1 - Boot order: M.2 SSD disk first, 2.5\" SATA disk second"
    echo "2 - Boot order: 2.5\" SATA disk first, M.2 SSD second"
    echo ""
    echo "** Note: regardless of the option chosen above, you can always select"
    echo "** a different boot device by pressing 'ESC' at boot time."
    bootorder=0
    while [ "$bootorder" != "1" -a "$bootorder" != "2" ]; do
        read -p "Enter your choice (default: 1): " bootorder
        if [ "$bootorder" == "" ]; then
            bootorder=1
        fi
        if [ "$bootorder" != "1" -a "$bootorder" != "2" ]; then
            echo "Invalid choice"
        fi
    done
    
    clear
    echo "Select whether to include Memtest86+ in the Boot menu choices: "
    echo "1 - Include Memtest86+ as a boot option"
    echo "2 - Do not include Memtest86+ as a boot option"
    echo ""
    echo "** Adding Memtest86+ as a boot option means that when pressing ESC"
    echo "** at boot time, you will have a 'memtest' option to boot into"
    echo "** regardless of the content of your hard drives."
    memtest=0
    while [ "$memtest" != "1" -a "$memtest" != "2" ]; do
        read -p "Enter your choice (default: 1): " memtest
        if [ "$memtest" == "" ]; then
            memtest=1
        fi
        if [ "$memtest" != "1" -a "$memtest" != "2" ]; then
            echo "Invalid choice"
        fi
    done

    clear
    delay=-1
    while [ "$delay" -lt "0" ]; do
        echo "Please select the amount of time (in milliseconds) to wait at the"
        read -p "boot menu prompt before selecting the default boot choice (default: 2500): " delay
        if [ "$delay" == "" ]; then
            delay=2500
        fi
        case $delay in
            ''|*[!0-9]*) 
                echo "Invalid choice: Not a positive number"
                delay=-1
                ;;
            *) ;;
        esac
    done
    
    clear
    log "Summary of your choices:"
    if [ "$intel_me" == "1" ]; then
        log "Intel ME               : Neutralized"
    else
        log "Intel ME               : Full"
    fi
    if [ "$microcode" == "1" ]; then
        log "Microcode updates      : Enabled"
    else
        log "Microcode updates      : Disabled"
    fi
    if [ "$bootorder" == "1" ]; then
        log "Boot order             : M.2 SSD first, 2.5\" SATA second"
    else
        log "Boot order             : 2.5\" SATA first, M.2 SSD second"
    fi
    if [ "$memtest" == "1" ]; then
        log "Memtest86+             : Included"
    else
        log "Memtest86+             : Not included"
    fi
    log "Boot menu wait time    : ${delay} ms"
    log ""
}

get_librem13v1_coreboot () {
    local sha1=''
    if ! check_file_sha1 "${COREBOOT_FILENAME}" "${COREBOOT_BASE_SHA1}" 1 ; then
        log 'Downloading coreboot BIOS image'
        curl ${COREBOOT_BASE_URL} > ${COREBOOT_BZ2_FILENAME}
        rm -f ${COREBOOT_FILENAME}
        log 'Decompressing coreboot BIOS image'
        bunzip2 ${COREBOOT_BZ2_FILENAME}
    fi
    if ! check_file_sha1 "${COREBOOT_FILENAME}" "${COREBOOT_BASE_SHA1}" 1 ; then
        die "The coreboot image hash does not match the expected one."
    fi
}

build_flash_image() {
    log 'Building coreboot Flash Image...'
    dd if=/dev/zero bs=8388608 count=1 2> /dev/null | tr '\000' '\377' > ${COREBOOT_FINAL_IMAGE}
    dd if=${DESCRIPTOR_FILENAME} of=${COREBOOT_FINAL_IMAGE} conv=notrunc > ${TEMPDIR}/dd_descriptor.log 2>&1
    ${IFDTOOL} -i ME:${ME_FILENAME} ${COREBOOT_FINAL_IMAGE} > ${TEMPDIR}/ifdtool_inject_me.log 2>&1
    mv ${COREBOOT_FINAL_IMAGE}.new ${COREBOOT_FINAL_IMAGE}
    ${IFDTOOL} -i BIOS:${COREBOOT_FILENAME} ${COREBOOT_FINAL_IMAGE} > ${TEMPDIR}/ifdtool_inject_bios.log 2>&1
    mv ${COREBOOT_FINAL_IMAGE}.new ${COREBOOT_FINAL_IMAGE}
    ${IFDTOOL} -u ${COREBOOT_FINAL_IMAGE} > ${TEMPDIR}/ifdtool_unlock.log 2>&1
    mv ${COREBOOT_FINAL_IMAGE}.new ${COREBOOT_FINAL_IMAGE}

}

build_cbfs_image() {
    ${RMODTOOL} -i ${REFCODE_FILENAME} -o ${REFCODE_RMOD} > ${TEMPDIR}/rmodtool.log 2>&1
    ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} add-stage -f ${REFCODE_RMOD} -n fallback/refcode  -c LZMA  -r COREBOOT > ${TEMPDIR}/cbfstool_refcode.log 2>&1
    rm -f ${REFCODE_RMOD}
    ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} add -f ${VGABIOS_FILENAME} -n pci8086,1616.rom -t optionrom   -r COREBOOT > ${TEMPDIR}/cbfstool_vga.log 2>&1
    ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} add -f ${MRC_FILENAME} -n mrc.bin -t mrc   -r COREBOOT  -b 0xfffa0000  > ${TEMPDIR}/cbfstool_mrc.log 2>&1
}

apply_config_options() {
    log 'Applying configuration options'
    if [ "$intel_me" == "1" ]; then
        log 'Neutralizing the Intel Management Engine using me_cleaner'
        ${ME_CLEANER} ${COREBOOT_FINAL_IMAGE} > ${TEMPDIR}/me_cleaner.log 2>&1
    fi
    if [ "$microcode" != "1" ]; then
        log 'Removing microcode updates from the generated coreboot image'
        ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} remove -n cpu_microcode_blob.bin > ${TEMPDIR}/cbfstool_microcode.log 2>&1
    fi
    log 'Setting boot order and delay'
    if [ "$bootorder" == "1" ]; then
        cat > bootorder.txt <<EOF
/pci@i0cf8/*@1f,2/drive@3/disk@0
/pci@i0cf8/*@1f,2/drive@0/disk@0
/rom@img/memtest
EOF
    else
        cat > bootorder.txt <<EOF
/pci@i0cf8/*@1f,2/drive@0/disk@0
/pci@i0cf8/*@1f,2/drive@3/disk@0
/rom@img/memtest
EOF
    fi
    ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} remove -n bootorder > ${TEMPDIR}/cbfstool_remove_bootorder.log 2>&1
    ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} add -f bootorder.txt -n bootorder -t raw   -r COREBOOT > ${TEMPDIR}/cbfstool_add_bootorder.log 2>&1
    ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} add-int -i ${delay} -n etc/boot-menu-wait > ${TEMPDIR}/cbfstool_add_bootwait.log 2>&1
    rm -f bootorder.txt

    if [ "$memtest" != "1" ]; then
        log 'Removing MemTest86+ from the generated coreboot image'
        ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} remove -n img/memtest > ${TEMPDIR}/cbfstool_remove_memtest.log 2>&1
    fi
    log ""

}

check_battery() {
    local capacity=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo -ne "0")
    local online=$(cat /sys/class/power_supply/AC/online 2>/dev/null || cat /sys/class/power_supply/ADP*/online 2>/dev/null || echo -ne "0")
    local failed=0
    

    if [ "${online}" == "0" ] ; then
        log "Please connect your Librem computer to the AC adapter"
        failed=1
    fi
    if [ "${capacity}" -lt 25 ]; then
        log "Please charge your battery to at least 25% (currently ${capacity}%)"
        failed=1
    fi
    if [ $failed == "1" ]; then
        log ""
        log "To prevent accidental shutdowns, we recommend to only run this script when"
        log "your laptop is plugged in to the power supply AND"
        log "the battery is present and sufficiently charged (over 25%)."
        exit 1
    else
        log ""
        log "Your laptop is currently connected to the power supply, "
        log "and your battery is at ${capacity}% of capacity."
        log "We recommend that you do not disconnect the laptop from the power supply"
        log "in order to avoid any potential accidental shutdowns."
        log ""
    fi
}

flashrom_progress() {
    local current=0
    local total_bytes=0x800000
    local percent=0
    local IN=''
    local spin='-\|/'
    local spin_idx=0
    local progressbar=''
    local progressbar2=$(for ((i=0; i < 49; i++)) do echo -ne ' ' ; done)
    local status='init'
   
    echo "Initializing internal Flash Programmer"
    while [ 1 ]; do
        read -d' ' IN || break
        current=$(echo "$IN" | egrep -o '0x[0-9a-f]+-0x[0-9a-f]+:.*' | egrep -o "0x[0-9a-f]+" | tail -n 1)
        if [ "${current}" != "" ]; then
            percent=$(echo $((100 * (${current} + 1) / ${total_bytes})) )
            progressbar=$(for ((i=0; i < $(($percent/2)); i++)) do echo -ne '#' ; done)
            progressbar2=$(for ((i=0; i < $((49 - $percent/2)); i++)) do echo -ne ' ' ; done)
        fi
        if [ $percent -eq 100 ]; then
            spin_idx=4
        else
            spin_idx=$(( (spin_idx+1) %4 ))
        fi
        if [ "$status" == "init" ]; then
            if [ "$IN" == "contents..." ]; then
                status="reading"
                echo "Reading old flash contents. Please wait..."
            fi
        fi
        if [ "$status" == "reading" ]; then
            if echo "${IN}" | grep "done." > /dev/null ; then
                status="writing"
            fi
        fi
        if [ "$status" == "writing" ]; then
            echo -ne "Flashing: [${progressbar}${spin:$spin_idx:1}${progressbar2}] (${percent}%)\r"
            if echo "$IN" | grep "Verifying" > /dev/null ; then
                status="verifying"
                echo ""
                echo "Verifying flash contents. Please wait..."
            fi
        fi
        if [ "$status" == "verifying" ]; then
            if echo "${IN}" | grep "VERIFIED." > /dev/null ; then
                status="done"
                echo "The flash contents were verified and the image was flashed correctly."
            fi
        fi
    done
    echo ""
}


flash_coreboot() {
    local answer='no'
    log ''
    log ''
    log 'Your coreboot image is now ready. We can now flash your BIOS with coreboot.'
    log ''
    log 'WARNING: Make sure not to power off your computer or interrupt this process in any way!'
    log 'Interrupting this process may result in irreparable damage to your computer'
    log 'and you may not be able to boot it afterwards (it would be a "brick").'
    log ''
    while [ "$answer" != "yes" ]; do
        log "Please make a copy of the files in '${CACHE_DIR}' to a safe location outside of this computer."
        echo -ne "Please type 'yes' to start the flashing process, followed by the reboot : "
        read answer
    done
    if [ "${IS_LIBREM13V1}" == "1" ]; then
        log '**** Flashing coreboot to your BIOS Flash ****'
        ${FLASHROM} -V ${FLASHROM_PROGRAMMER} ${FLASHROM_ARGS} -w ${COREBOOT_FINAL_IMAGE} 2>&1 | tee ${TEMPDIR}/flashrom_write.log | flashrom_progress
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            log ''
            log ''
            log ''
            tail -n 20 ${TEMPDIR}/flashrom_write.log
            log ''
            log ''
            log ''
            log 'ERROR: It appears that flashing your BIOS has failed. '
            log 'Do NOT power off or restart your computer. Try running this script again until'
            log 'it succeeds, or try to flash back the BIOS using your original BIOS backup file'
            log "which is available in the file '${CACHE_DIR}/${ORIG_FILENAME}' "
            echo "Log files are available in '${TEMPDIR}'"
            exit 1
        fi
    fi
    
    log 'Congratulations! You now have coreboot installed on your machine'
    log 'You can now reboot your computer and enjoy increased security and freedom.'
    log 'Keep an eye on https://puri.sm/news/ for any potential future coreboot updates.'
    log ''
    echo "Log files are available in '${TEMPDIR}'"
    echo ''
    local sec=10
    while [ $sec -gt 0 ]; do
        echo -ne "Your computer will reboot in : $sec seconds    \r"
        sleep 1
        sec=$(($sec -1))
    done
}

welcome_msg
check_root
check_dependencies
check_machine
check_battery
backup_original_rom
get_required_binaries
default_config_options
log "Press Enter to start the configuration wizard for coreboot"
read
configuration_wizard
get_librem13v1_coreboot
build_flash_image
build_cbfs_image
apply_config_options
check_battery
flash_coreboot
reboot
