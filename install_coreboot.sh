#!/bin/bash
#
# Copyright (C) 2017 Purism
# Author: Youness Alaoui <youness.alaoui@puri.sm>
#
# Script that downloads and/or extracts all the required binaries for coreboot
# to work on Purism Librem 13 v1 laptops and builds the final coreboot flash image
# and flashes it.

# Dependencies : curl dmidecode flashrom sharutils

ARGV=$1
TEMPDIR=$(mktemp -d /tmp/coreboot_install.XXXXXX)
LOGFILE="${TEMPDIR}/install.log"

FLASHROM='../flashrom/flashrom'
FLASHROM_PROGRAMMER="-pinternal:laptop=force_I_want_a_brick"
DMIDECODE='dmidecode'
CBFSTOOL='../coreboot/util/cbfstool/cbfstool'
RMODTOOL='../coreboot/util/cbfstool/rmodtool'
IFDTOOL='../coreboot/util/ifdtool/ifdtool'
UEFIEXTRACT='../UEFITool/UEFIExtract/UEFIExtract'
ME_CLEANER='../coreboot/util/me_cleaner/me_cleaner.py'

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
ME_FILENAME='flashregion_2_intel_me.bin'
ME_SIZE='2093056'
COREBOOT_FILENAME='coreboot_bios.rom'
COREBOOT_BZ2_FILENAME='coreboot_bios.rom.bz2'
COREBOOT_NATIVE_URL='http://kakaroto.homelinux.net/coreboot_native_bios.rom.bz2'
COREBOOT_NATIVE_SHA1='e8bc66ee875bac7c0f31dd424bdce89b361b4315'
COREBOOT_SECURE_URL='http://kakaroto.homelinux.net/coreboot_secure_bios.rom.bz2'
COREBOOT_SECURE_SHA1='573d7a920fe5bf3768d69902da06db0688b6ecfa'

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
    check_dependency me_cleaner ${ME_CLEANER}
    check_dependency curl curl
    check_dependency bunzip2 bunzip2
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
    IS_LIBREM13V1=0

    if [ "${MANUFACTURER}" == "Intel Corporation" -a \
                             "${PRODUCT_NAME}" == "SharkBay Platform" -a \
                             "${VERSION}" == "0.1" ]; then
        FLASHROM_ARGS=""
        ORIG_FILENAME="vendor_bios_backup.rom"
        VENDOR=1
        IS_LIBREM13V1=1
        log "Vendor BIOS has been detected in your flash"
    elif [ "${MANUFACTURER}" == "Purism" -a \
                             "${PRODUCT_NAME}" == "Librem 13" -a \
                             "${VERSION}" == "1.0" ]; then
        FLASHROM_ARGS="-c MX25L6406E/MX25L6408E"
        ORIG_FILENAME="coreboot_bios_backup.rom"
        VENDOR=1
        IS_LIBREM13V1=1
        log '**** Coreboot BIOS has been detected in your flash **** '
    else
        if [ "$ARGV" == "--test-on-non-librem" ]; then
            log '**** This machine does not seem to be a Purism Librem 13 v1, it is not safe to use this script **** '
            log 'You have enabled the --test-on-non-librem option, so this script will continue but will not'
            log 'attempt to access your flash.'
            FLASHROM_ARGS=""
            ORIG_FILENAME="vendor_bios_backup.rom"
            VENDOR=1
            IS_LIBREM13V1=0
        else
            die '**** This machine does not seem to be a Purism Librem 13 v1, it is not safe to use this script **** '
        fi
    fi
}

backup_original_rom() {
    log "Making backup copy of your current BIOS"
    if [ "${IS_LIBREM13V1}" == "1" ]; then
        ${FLASHROM} -V ${FLASHROM_PROGRAMMER} ${FLASHROM_ARGS} -r ${ORIG_FILENAME} >& ${TEMPDIR}/flashrom_read.log || die "Unable to dump original BIOS from your flash"
    else
        if ! check_file_sha1 "${ORIG_FILENAME}" "1860c3e14f700dd060d974ea2612271eaa4307da" 1 ; then
            log 'This is not a Librem 13 machine, so a Vendor bios will be downloaded for testing purposes'
            curl -s "http://kakaroto.homelinux.net/vendor_bios_backup.rom.bz2" > ${ORIG_FILENAME}.bz2
            rm -f ${ORIG_FILENAME}
            bunzip2 ${ORIG_FILENAME}.bz2
            if ! check_file_sha1 "${ORIG_FILENAME}" "1860c3e14f700dd060d974ea2612271eaa4307da" 1 ; then
                die "Vendor BIOS hash does not match the expected one"
            fi
        fi
    fi
    
    log "Your current BIOS has been backed up to the file '${ORIG_FILENAME}'"
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
            $print "File hash is valid : $result"
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
        log "Press Enter to start the 553MB download."
        read
        curl ${TIDUS_ZIP_URL} > chromeos_8743.85.0_tidus_recovery_stable-channel_mp-v2.bin.zip
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
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
        log '**** Decompressing the image ****'
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
            die "Aborting the operation to prevent corruption of your BIOS"
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
	log '**** Extracting chromeos-firmwareupdate ****'
	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${TIDUS_SHELLBALL_FILENAME}\nquit" | \
		debugfs ${TIDUS_ROOTA_FILENAME} > ${TEMPDIR}/debugfs.log 2>&1
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
            log "The extracted shell script failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
        rm -f ${TIDUS_ROOTA_FILENAME}
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
        
	log '**** Extracting coreboot image ****'
	sh ${TIDUS_SHELLBALL_FILENAME} --sb_extract $_unpacked &> ${TEMPDIR}/shellball.log
	cp $_unpacked/bios.bin ${TIDUS_COREBOOT_FILENAME}
        rm -rf "$_unpacked"
        
        if ! check_file_sha1 "$file" "$sha1" 1 ; then
            log "The coreboot image failed to match the expected file hash."
            die "Aborting the operation to prevent corruption of your BIOS"
        fi
        rm -f ${TIDUS_SHELLBALL_FILENAME}
    fi        
}

get_mrc_blob() {
    local coreboot_filename=""
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
        coreboot_filename=${TIDUS_COREBOOT_FILENAME}
    else
        coreboot_filename=${ORIG_FILENAME}
    fi

    log "Extracting Memory Reference Code : ${MRC_FILENAME}"
    ${CBFSTOOL} $coreboot_filename extract  -r BOOT_STUB -n "mrc.bin" -f ${MRC_FILENAME} > ${TEMPDIR}/cbfstool_mrc.log 2>&1 || die "Unable to extract MRC file"
    if ! check_file_sha1 "${MRC_FILENAME}" "${MRC_SHA1}" 1 ; then
        die "MRC file hash does not match the expected one"
    fi
    log "Extracting Intel Broadwell Reference Code : ${REFCODE_FILENAME}"
    ${CBFSTOOL} $coreboot_filename extract  -r BOOT_STUB -n "fallback/refcode" -f ${REFCODE_FILENAME} -m x86 > ${TEMPDIR}/cbfstool_refcode.log 2>&1 || die "Unable to extract Refcode file"
    if ! check_file_sha1 "${REFCODE_FILENAME}" "${REFCODE_SHA1}" 1 ; then
        die "MRC file hash does not match the expected one"
    fi
}

get_vgabios_blob() {
    log "Extracting VGA BIOS image : ${VGABIOS_FILENAME}"
    if [ $VENDOR ]; then
        ${UEFIEXTRACT} ${ORIG_FILENAME} > ${TEMPDIR}/uefiextract.log 2>&1 || die "Unable to extract vgabios file"
        cp "${ORIG_FILENAME}.dump/2 BIOS region/2 8C8CE578-8A3D-4F1C-9935-896185C32DD3/2 9E21FD93-9C72-4C15-8C4B-E77F1DB2D792/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 Volume image section/0 8C8CE578-8A3D-4F1C-9935-896185C32DD3/237 A0327FE0-1FDA-4E5B-905D-B510C45A61D0/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 C5A4306E-E247-4ECD-A9D8-5B1985D3DCDA/body.bin" ${VGABIOS_FILENAME}
        rm -rf "${ORIG_FILENAME}.dump"
    else
        ${CBFSTOOL} $ORIG_FILENAME extract -n "pci8086,1616.rom" -f ${VGABIOS_FILENAME} > ${TEMPDIR}/cbfstool_vgabios.log 2>&1 || die "Unable to extract vgabios file"
    fi
    if ! check_file_sha1 "${VGABIOS_FILENAME}" "${VGABIOS_SHA1}" 1 ; then
        die "VGA Bios file hash does not match the expected one"
    fi
    log "VGA BIOS blob has been extracted from your current BIOS."
}

get_descriptor_and_me_blobs() {
    log "Extracting Intel Firmware Descriptor and Intel Management Engine images"
    ${IFDTOOL} -x ${ORIG_FILENAME} > ${TEMPDIR}/ifdtool_extract.log 2>&1 || die "Unable to extract descriptor and me files"
    rm -f flashregion_1_bios.bin
    local region_2_size=0
    if [ -f ${ME_FILENAME} ]; then
        region_2_size=$(stat -c%s "${ME_FILENAME}")
    fi
    if ! check_file_sha1 "${DESCRIPTOR_FILENAME}" "${DESCRIPTOR_SHA1}" 1 ; then
        die "Intel Firmware Descriptor hash does not match the expected one"
    fi
    if [ "$region_2_size" != "${ME_SIZE}" ]; then
        die "Intel Management Engine size does not match the expected file size"
    fi
}

get_required_blobs() {
    get_mrc_blob
    get_vgabios_blob
    get_descriptor_and_me_blobs
    log '**** Binary blobs have been extracted from your current BIOS and (optionally) from the recovery image of the Tidus chromebook. ****'
}

default_config_options() {
    intel_me=1
    microcode=1
    vbios_emulator=1
    bootorder=1
    memtest=1
    delay=2500
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
    echo "** capabilities (AMT) of the Intel ME are already disabled on the Librem computers,"
    echo "** the firmware is still considered an unknown binary blob with code that"
    echo "** cannot be audited and which runs on your machine without restrictions."
    echo ""
    echo "** For more information, please visit : https://puri.sm/learn/intel-me/"
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
    echo "** which can cause random crashes, data corruption and other unexpected"
    echo "** behavior."
    echo "** The risk level of the microcode updates is low, and running without them can"
    echo "** cause silent data corruption or random lock-ups of the hardware"
    echo "** Please note that the CPU already comes with a microcode installed in its"
    echo "** silicon. This option only affects the inclusion of updates to it."
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
    echo "Select whether to include Memtest86+ in the Boot options : "
    echo "1 - Include Memtest86+ as a boot option"
    echo "2 - Do not include Memtest86+ as a boot option"
    echo ""
    echo "** Adding Memtest86+ as a boot option means that when pressing ESC"
    echo "** at boot time, you will have a 'memtest' option to boot into"
    echo "** regardless of the content of your hard drives"
    memtest=0
    while [ "$memtest" != "1" -a "$memtest" != "2" ]; do
        read -p "Enter your choice (default: 1) : " memtest
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
    if [ "$intel_me" == "1" ]; then
        log "Intel ME                : Neutered"
    else
        log "Intel ME                : Full"
    fi
    if [ "$microcode" == "1" ]; then
        log "Microcode updates       : Enabled"
    else
        log "Microcode updates       : Disabled"
    fi
    if [ "$vbios_emulator" == "1" ]; then
        log "VGA BIOS Execution mode : Native"
    else
        log "VGA BIOS Execution mode : Secured"
    fi
    if [ "$bootorder" == "1" ]; then
        log "Boot order              : M.2 SSD -> 2.5\" HDD"
    else
        log "Boot order              : 2.5\" HDD -> M.2 SSD"
    fi
    if [ "$memtest" == "1" ]; then
        log "Memtest86+              : Included"
    else
        log "Memtest86+              : Not included"
    fi
    log "Boot menu wait time     : ${delay} ms"
    log ""
}

get_librem13v1_coreboot () {
    local sha1=''
    if [ "$vbios_emulator" == "1" ]; then
        url=${COREBOOT_NATIVE_URL}
        sha1=${COREBOOT_NATIVE_SHA1}
    else
        url=${COREBOOT_SECURE_URL}
        sha1=${COREBOOT_SECURE_SHA1}
    fi
    if ! check_file_sha1 "${COREBOOT_FILENAME}" "$sha1" 1 ; then
        log '**** Downloading Coreboot BIOS image ****'
        curl $url > ${COREBOOT_BZ2_FILENAME}
        rm -f ${COREBOOT_FILENAME}
        log '**** Decompressing Coreboot BIOS image ****'
        bunzip2 ${COREBOOT_BZ2_FILENAME}
    fi
    if ! check_file_sha1 "${COREBOOT_FILENAME}" "$sha1" 1 ; then
        die "Coreboot image hash does not match the expected one"
    fi
}

build_flash_image() {
    log '**** Building Coreboot Flash Image ****'
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
    intel_me=1
    microcode=1
    vbios_emulator=1
    bootorder=1
    memtest=1
    delay=2500

    log '**** Applying configuration options ****'
    if [ "$intel_me" == "1" ]; then
        ${ME_CLEANER} ${COREBOOT_FINAL_IMAGE} > ${TEMPDIR}/me_cleaner.log 2>&1
    fi
    if [ "$microcode" != "1" ]; then
        log '**** Removing microcode updates from the generated coreboot image ****'
        ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} remove -n cpu_microcode_blob.bin > ${TEMPDIR}/cbfstool_microcode.log 2>&1
    fi
    log '**** Setting boot order and delay ****'
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
        log '**** Removing MemTest86+ from the generated coreboot image ****'
        ${CBFSTOOL} ${COREBOOT_FINAL_IMAGE} remove -n img/memtest > ${TEMPDIR}/cbfstool_remove_memtest.log 2>&1
    fi
    log ""

}

check_battery() {
    local capacity=$(cat /sys/class/power_supply/BAT0/capacity)
    local status=$(cat /sys/class/power_supply/BAT0/status)
    local failed=0
    

    if [ ${status} != "Charging" -a ${status} != "Full" ] ; then
        log "Please connect your Librem computer to the AC adapter"
        failed=1
    fi
    if [ ${capacity} -lt 25 ]; then
        log "Please charge your battery to at least 25% (currently ${capacity}%)"
        log "then retry updating your coreboot installation"
        failed=1
    fi
    if [ $failed == "1" ]; then
        log ""
        log "To prevent accidental shutdowns, we recommend to only update your"
        log "flash when your laptop is plugged in to the power supply and"
        log "the battery is sufficiently charged (25% minimum)."
        exit 1
    fi
}
flash_coreboot() {
    log ''
    log ''
    log 'Your coreboot image is now ready! We will now flash your BIOS with coreboot.'
    log ''
    log 'WARNING: Make sure not to power off your computer or interrupt this process in any way!'
    log 'Interrupting this process could result in irreparable damage to your computer'
    log 'and you may not be able to boot it afterwards (brick)'
    log ''
    log 'Press Enter to start the flashing process'
    read
    if [ "${IS_LIBREM13V1}" == "1" ]; then
        log '**** Flashing Coreboot to your BIOS Flash ****'
        ${FLASHROM} -V ${FLASHROM_PROGRAMMER} ${FLASHROM_ARGS} -w ${COREBOOT_FINAL_IMAGE} >& ${TEMPDIR}/flashrom_write.log || flashing_failure
    fi
    
    log 'Congratulations! you now have coreboot installed on your machine'
    log 'All you need to do is to reboot your computer and enjoy your computer'
    log 'with a little bit more freedom in it'
    log ''
    echo "Log files are available in '${TEMPDIR}'"
}

check_root
check_dependencies
check_machine
backup_original_rom
get_required_blobs
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
