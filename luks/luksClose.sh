#!/bin/bash
#
#  Unmount $VOLUME from $MOUNTPOINT and lock it. Remove $MOUNTPOINT
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
declare -r NAMETAG="LUKS Close"
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
# Returns the selected value - a label representing a LUKS device to be locked
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
# connected LUKS devices and look their labels up in the config file
#
LABEL=$1
if [ "${LABEL}" == "" ] ; then
    echo "${NAMETAG} : No device label specified, reading labels from ${DISKLIST}"
    LABEL_LIST=`cat ${DISKLIST} | cut -f 2 -d " "`
    UUID_LIST=`sudo /sbin/blkid | grep LABEL` 
    UNLOCKED_LIST=""
    for CUR_LABEL in ${LABEL_LIST} ; do
        if [[ "${UUID_LIST}" == *LABEL=\"${CUR_LABEL}\"* ]] ; then 
            UNLOCKED_LIST="${UNLOCKED_LIST} "${CUR_LABEL}
        fi
    done
    # sort the list of strings before calling get_target (sort only works on lines)
    select_label `echo ${UNLOCKED_LIST} | tr " " "\n" | sort | tr "\n" " "`
    if [ "${LABEL}" == "" ] ; then
        echo "${NAMETAG} : No label selected, aborting"
        abort 2
    fi
fi

#
# using the label, get the device name from /sbin/blkid
#
echo "${NAMETAG} : Retrieving device and UUID for label ${LABEL}"
DEVICE=`sudo /sbin/blkid | grep ${LABEL} | cut -f1 -d:`
if [ "${DEVICE}" == "" ] ; then
    echo "${NAMETAG} : Unable to find unlocked device with label ${LABEL}"
    abort 3
fi
echo "${NAMETAG} : Label ${LABEL} matches device ${DEVICE}"

#
# using the same label, find the UUID
#
UUID=`sudo /sbin/blkid | grep ${LABEL}`
UUID="${UUID#*UUID=\"}"
UUID="${UUID%%\"*}"
if [ "${UUID}" == "" ] ; then
    echo "${NAMETAG} : Unable to find UUID for unlocked device with label ${LABEL}"
    abort 4
fi
echo "${NAMETAG} : Label ${LABEL} matches UUID ${UUID}"

#
#  unmount unlocked volume
#
MOUNTPOINT="${MOUNTROOT}/${UUID}"
VOLUME=${DEVICE#/dev/mapper/*}
echo "${NAMETAG} : Unmounting ${VOLUME} from ${MOUNTPOINT}"
mounted=`grep ${MOUNTPOINT} /etc/mtab | grep ${VOLUME}`
if [ ! "${mounted}" ] ; then
    echo "${NAMETAG} : Volume ${VOLUME} not mounted at ${MOUNTPOINT}"
else
    echo "${NAMETAG} : ${mounted}"
    echo "${NAMETAG} : Unmounting ${MOUNTPOINT}"
    sudo /bin/umount -v ${MOUNTPOINT}
    if [ $? -ne 0 ] ; then
        echo "${NAMETAG} : Unable to unmount ${MOUNTPOINT}, will attempt locking anyway"
    else
        echo "${NAMETAG} : Unmounted ${MOUNTPOINT}; removing mountpoint"
        /bin/rm ${MOUNTROOT}/${LABEL}
        /bin/rmdir ${MOUNTPOINT} 
    fi
fi

#
#  lock the volume
#
if [ ! -b /dev/mapper/${VOLUME} ] ; then
    echo "${NAMETAG} : Volume ${VOLUME} already locked"
else
    echo "${NAMETAG} : Locking ${VOLUME}"
    sudo /sbin/cryptsetup luksClose ${VOLUME}
    if [ $? -ne 0 ] ; then
        echo "${NAMETAG} : Unable to lock ${VOLUME}"
        abort 5
    else
        echo "${NAMETAG} : Locked ${VOLUME}"
    fi
fi

#
# exit
#
echo "${NAMETAG} : Success - volume unmounted and locked"
read -rsn1 -p "Press any key to exit... "
echo " " 
exit 0