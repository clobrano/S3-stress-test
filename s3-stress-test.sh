#!/usr/bin/env bash
#  S3 (suspend) stress test using rtcwake
# Available checks:
# * Check device with given VID/PID exists
# * Check modem is registered through ModemManager
# * Check modem is connected through ppp

VER=0.3.1

exec 1> >(logger -s -t $(basename $0)) 2>&1

# Device configuration
VID=413c
DEV_ID="1-8.1"
PERST_PATH=/sys/bus/usb/devices/$DEV_ID/power/persist

# Test configuration
DISABLE_PERST=1
IFACE=ppp0
NTESTS=200
RETRIES=10
S3_DURATION=10
SHUTDOWN_MM=0
WAIT_DEVICE_TIME=1
WAIT_CONNECTION_TIME=10
CHECK_CONNECTION=1
CHECK_REGISTRATION=1

while getopts "p:n:m:d:i:" opt; do
    case $opt in
    d)
        PID=$OPTARG
        ;;
    c)
        CHECK_CONNECTION=$OPTARG
        ;;
    i)
        DEV_ID=$OPTARG
        ;;
    m)
        SHUTDOWN_MM=$OPTARG
        ;;
    n)
        NTESTS=200
        ;;
    p)
        DISABLE_PERST=$OPTARG
        ;;
    r)
        CHECK_REGISTRATION=$OPTARG
        ;;
esac
done

function is_device_present () {
    [ 1 -eq $(lsusb | grep $VID:$PID | wc -l) ] && echo 1 || echo 0
}

function is_registered () {
    # Get modem id
    echo "<<< is registered?"
    mmid=$(mmcli -L | grep -Po "/\d+" | cut -d / -f 2)
    echo "<<< $mmid"

    [ 0 -eq $(mmcli -m $mmid --command=+CSQ 2>&1 | grep error | wc -l) ] && return 1
    return 0
}

function is_connected () {
    if [ 1 -eq $(ifconfig $IFACE | wc -l) ]; then
        ping 8.8.8.8 -I $IFACE -c 3
        if [ 0 -eq $? ]; then
            echo 1
            return
        fi
    fi
    echo 0
}

if [ 1 -eq $SHUTDOWN_MM ]; then
    echo "<<< Shutting down MM"
    systemctl stop ModemManager
else
    echo "<<< Keep MM up and running"
fi

for i in $(seq $NTESTS); do
    echo "<<< Test #$i/$NTESTS: suspend $PID for $S3_DURATION sec. MM:$SHUTDOWN_MM. DIS_PERST:$DISABLE_PERST. DEV_ID:$DEV_ID."

    echo "<<< Current persistent value $(cat $PERST_PATH)."
    if  [ 1 -eq $DISABLE_PERST ]; then
        echo 0 > $PERST_PATH
        echo "<<< New persistent value $(cat $PERST_PATH)."
        sleep 1
    fi

    rtcwake -m mem -s $S3_DURATION
 
    echo "<<< Test S3 #$i/$NTESTS: wake up"
    ret=0
    for j in $(seq $RETRIES); do
        if [ 0 -ne $PID ]; then
            [ 0 -eq $ret ] && [ 0 -eq $(is_device_present) ] && sleep 1 && continue
            lsusb | grep $VID:$PID
            ret=1
        fi

        sleep $WAIT_CONNECTION_TIME

        if [ 1 -eq $CHECK_REGISTRATION ]; then
            is_registered
            [ 1 -eq $? ] && continue
            ret=3
            break
        fi

        if [ 1 -eq $CHECK_CONNECTION ]; then
            [ 0 -eq $(ifconfig $IFACE | wc -l) ] && continue
            ping -I $IFACE -c 3 8.8.8.8
            [ 0 -ne $? ] && continue
            echo "<<< Device reconnected!"
            ret=2
        fi
        
        break
    done

    case $ret in
        0)
           echo "<<< Could not find device $VID:$PID"
           lsusb
           ;;
        1)
            echo "<<< Could not connect"
            ;;
        2)
            echo "<<< Test #$i passed!"
            ;;
        3)
            echo "<<< Could not register"
            ;;
    esac

    [ 2 -ne $ret ] && echo "<<< Test #$i NOT passed" && break;
done


