#!/bin/bash
#
#  Unlock $DEVICE and mount it at $MOUNTPOINT
#
#  Devices are read from the $DISKLIST file as UUID / label pairs:
#
#     c78ef5bf-4e8c-49dd-9c0b-c4f9aae9fed2 MyDisk
#     394d9ea7-33da-4f2f-a56c-6725977989a0 MySecondDisk
#     ...
#
#  Parameters (optional) :
#  LABEL - descriptive name assigned to the volume (preferably filesystem label)
#
#  If the parameter is not supplied, the $DISKLIST is displayed for selection.
#
###############################################################################
# Constants
###############################################################################
declare -r NAMETAG="LUKS Open"
declare -r DISKLIST="/opt/uuid-label.txt"
declare -r MOUNTROOT="/media"

echo "${NAMETAG} version 1.1 11th Sep 2017"

###############################################################################
#
# Function ABORT
#
# Terminates the script with a message and exit code
#
# Parameters:
#  1 - exit code
#
###############################################################################
function abort()
{
    EXIT_CODE=${1}
    echo "${NAMETAG} : Operation failed. Exit code: "${EXIT_CODE}
    read -rsn1 -p "Press any key to exit... "
    echo " "
    exit $EXIT_CODE
}

###############################################################################
#
# Function SELECT_LABEL
#
# Returns the selected value - a label representing a LUKS device to be unlocked
#
# Parameters:
#  1 - List of labels corresponding to LUKS devices
#
###############################################################################
function select_label()
{
    PS3="Select LUKS device: "
    echo "Available LUKS devices: "
    select TARGET in $@ ; do
        if [ -n "${TARGET}" ] ; then
            LABEL="${TARGET}"
            return 0
        else
            echo "${NAMETAG} : No label selected, aborting"
            abort 2
        fi
    done
}

#
# the $DISKLIST file must exist
#
if [ ! -e "${DISKLIST}" ] ; then
    echo "${NAMETAG} : Unable to read UUIDs / labels from file ${DISKLIST}"
    abort 1
fi

#
# if the volume label has not been supplied on the command line, list the
# connected devices and try to look it up in the config file
#
LABEL="$1"
if [ "${LABEL}" == "" ] ; then
    echo "${NAMETAG} : No device label specified, reading labels from ${DISKLIST}"
    LABEL_LIST=""
    UUIDS=`sudo /sbin/blkid | grep LUKS | cut -f 2 -d " "` 
    for CUR_UUID in ${UUIDS} ; do
        CUR_UUID=${CUR_UUID#*UUID=\"}
        CUR_UUID=${CUR_UUID%%\"*}
        LABEL_LIST="${LABEL_LIST} "`cat ${DISKLIST} | grep ${CUR_UUID} | cut -f 2 -d " "`
    done
    # sort the list of labels before calling get_target (sort only works on lines)
    LABEL_LIST=`echo ${LABEL_LIST} | tr " " "\n" | sort | tr "\n" " "`
    select_label "${LABEL_LIST}"
    if [ "${LABEL}" == "" ] ; then
        echo "${NAMETAG} : No label selected, aborting"
        abort 2
    fi
fi

#
# using the label, get the UUID from the config file
#
echo "${NAMETAG} : Retrieving UUID for label ${LABEL}"
UUID=`cat ${DISKLIST} | grep ${LABEL} | cut -f 1 -d " "`
if [ "${UUID}" == "" ] ; then
    echo "${NAMETAG} : Unable to read UUID for label '${LABEL}' from file ${DISKLIST}"
    abort 3
fi
echo "${NAMETAG} : Label ${LABEL} has UUID ${UUID}"

#
# using the UUID, find the device from /sbin/blkid 
#
echo "${NAMETAG} : Retrieving device for given UUID"
DEVICE=`sudo /sbin/blkid | grep ${UUID} | cut -f1 -d:`
if [ "${DEVICE}" == "" ] ; then
    echo "${NAMETAG} : Unable to find device with UUID ${UUID}"
    abort 4
fi
echo "${NAMETAG} : UUID ${UUID} matches device ${DEVICE}"

#
# set a volume identifier - e.g. "sdc-crypt" for /dev/sdc
#
VOLUME=${DEVICE#/dev/*}"-crypt" 
echo "${NAMETAG} : Unlockng ${DEVICE} as volume ${VOLUME}"

#
#  unlock encrypted volume
#
if [ -b /dev/mapper/${VOLUME} ] ; then
    echo "${NAMETAG} : Volume ${VOLUME} already unlocked; skipping"
else
    echo "${NAMETAG} : Unlocking ${VOLUME}"
    sudo /sbin/cryptsetup -v luksOpen ${DEVICE} ${VOLUME}
    if [ $? -ne 0 ] ; then
        echo "${NAMETAG} : Unable to unlock ${VOLUME}"
        abort 5
    else
        echo "${NAMETAG} : Unlocked ${VOLUME}"
    fi
fi

#
# Using the volume identifier, call /sbin/blkid to get 
# the UUID of the (unlocked) filesystem 
#
echo "${NAMETAG} : Retrieving UUID for unlocked volume ${VOLUME}"
FS_UUID=`sudo /sbin/blkid | grep ${VOLUME}`
FS_UUID="${FS_UUID#*UUID=\"}"
FS_UUID="${FS_UUID%%\"*}"
if [ "${FS_UUID}" == "" ] ; then
    echo "${NAMETAG} : Unable to find UUID for unlocked volume ${VOLUME}"
    abort 6
fi
echo "${NAMETAG} : Unlocked volume ${VOLUME} has UUID ${FS_UUID}"

#
#  mount unlocked volume at ${MOUNTROOT}/${FS_UUID}
#
MOUNTPOINT="${MOUNTROOT}/${FS_UUID}"
echo "${NAMETAG} : Mounting ${DEVICE} at mount point ${MOUNTPOINT}"
mounted=`grep ${MOUNTPOINT} /etc/mtab | grep ${VOLUME}`
if [ "${mounted}" != "" ] ; then
    echo "${NAMETAG} : Volume ${VOLUME} already mounted at ${MOUNTPOINT}"
    echo "${NAMETAG} : ${mounted}"
else
    echo "${NAMETAG} : Mounting ${VOLUME} at ${MOUNTPOINT}"
    if [ ! -d "${MOUNTPOINT}" ] ; then
        echo "${NAMETAG} : Creating mountpoint ${MOUNTPOINT}"
        mkdir ${MOUNTPOINT}
    fi
    sudo /bin/mount -v -t ext4 "/dev/mapper/${VOLUME}" "${MOUNTPOINT}"
    if [ $? -ne 0 ] ; then
        echo "${NAMETAG} : Unable to mount ${VOLUME} at ${MOUNTPOINT}"
        abort 7
    else
        echo "${NAMETAG} : Mounted ${VOLUME} at ${MOUNTPOINT}"
        if [ ! -e "${MOUNTROOT}/${LABEL}" ] ; then
            echo "${NAMETAG} : Creating softlink - ${MOUNTROOT}/${LABEL}"
            ln -s "${MOUNTPOINT}" "${MOUNTROOT}/${LABEL}"
        fi
    fi
fi

#
# exit successfully
#
echo "${NAMETAG} : Success - volume unlocked and mounted"
read -rsn1 -p "Press any key to exit... "
echo " "
exit 0

