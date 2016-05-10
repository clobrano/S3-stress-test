#!/usr/bin/env bash
#  S3 (suspend) stress test using rtcwake
# Available checks:
# * Check device with given VID/PID exists
# * Check modem is registered through ModemManager
# * Check modem is connected through ppp

VER=0.3.2

exec 1> >(logger -s -t $(basename $0)) 2>&1

# Device configuration
VID=413c
DEV_ID="1-8.1"

# Test configuration
IFACE=ppp0
NTESTS=200
RETRIES=10
S3_DURATION=10
WAIT_CONNECTION_TIME=10
WAIT_DEVICE_TIME=1

while getopts "cd:mn:p:s" opt; do
    case $opt in
        c)
            CHECK_CONNECTION=1
            ;;
        d)
            DEV_ID=$OPTARG
            ;;
        m)
            SHUTDOWN_MM=1
            ;;
        n)
            NTESTS=$OPTARG
            ;;
        p)
            DISABLE_PERST=1
            ;;
        s)
            CHECK_SERIAL=1
            ;;
    esac
done

echo $CHECK_CONNECTION, $DEV_ID, $SHUTDOWN_MM, $DISABLE_PERST, $CHECK_SERIAL

exit 1

while getopts "c:d:i:m:n:p:r:" opt; do
    case $opt in
    c)
        CHECK_CONNECTION=$OPTARG
        ;;
    d)
        PID=$OPTARG
        ;;
    i)
        DEV_ID=$OPTARG
        ;;
    m)
        SHUTDOWN_MM=$OPTARG
        ;;
    n)
        NTESTS=$OPTARG
        ;;
    p)
        DISABLE_PERST=$OPTARG
        ;;
    r)
        CHECK_COMMUNICATION=$OPTARG
        ;;
esac
done

PERST_PATH=/sys/bus/usb/devices/$DEV_ID/power/persist

function log () {
    echo "[+] " $@
}

function err () {
    log "[ERROR]" $@
}

function log_start() {
    echo "<<< Test #$i/$NTESTS: suspend $PID for $S3_DURATION sec. KILL_MM:$SHUTDOWN_MM. DIS_PERST:$DISABLE_PERST. DEV_ID:$DEV_ID."
}

function check_device_presence () {
    if [ 1 -eq $(lsusb | grep $VID:$PID | wc -l) ]; then
       log "Device $VID:$PID found"
       lsusb
       return 1
    fi
    return 0
}

function check_device_communication () {
    if [ -z $CHECK_SERIAL ]; then
        log "Skipping Test communication with serial device"
        return 1
    fi

    log "Checking communication with device"
    cmd="+CSQ"
    mmid=$(mmcli -L | grep -Po "/\d+" | cut -d / -f 2)
    mmcli -m $mmid --command="$cmd"

    if [ 0 -eq $(mmcli -m $mmid --command="$cmd"? 2>&1 | grep error | wc -l) ]; then
        log "Communication test PASSED"
        return 1
    fi

    err "Communication test FAILED"
    return 0
}

function check_connection () {
    if [ -z $CHECK_CONNECTION ]; then
        log "Skipping connection check"
        return 1
    fi

    log "Checking connection"
    if [ 1 -eq $(ifconfig $IFACE | wc -l) ]; then
        ping 8.8.8.8 -I $IFACE -c 3
        if [ 0 -eq $? ]; then
            log "Connection Test PASSED"
            return 1
        fi
    fi
    err "Connection test FAILED"
    return 0
}

function check_persistence () {
    log "Current USB persistence value $(cat $PERST_PATH)."
    if  [ ! -z $DISABLE_PERST ]; then
        echo 0 > $PERST_PATH
        log "New USB persistence value $(cat $PERST_PATH)."
        sleep 1
    fi
}


# MAIN
if [ 1 -eq $SHUTDOWN_MM ]; then
    log "Shutting down MM"
    systemctl stop ModemManager
else
    log "Keep MM up and running"
fi

for i in $(seq $NTESTS); do
    log_start

    check_persistence

    rtcwake -m mem -s $S3_DURATION
USB persistence value
    echo "<<< Test S3 #$i/$NTESTS: wake up"

    ret=0
    for j in $(seq $RETRIES); do

        ret=-1
        check_device_presence
        [ 0 -eq $? ] && continue

        ret=-2
        check_device_communication
        [ 0 eq $? ] && continue

        ret=-3
        sleep $WAIT_CONNECTION_TIME
        check_connection
        [ 0 eq $? ] && continue

        # All tests passed
        ret=0
        break
    done

    case $ret in
        -1)
           echo "<<< Could not find device $VID:$PID"
           lsusb
           ;;
        -2)
            echo "<<< Could not communicate with serial device"
            ;;
        -3)
            echo "<<< Modem is not connected"
            ;;
    esac

    [ $ret -lt 0 ] && echo "<<< Test #$i NOT passed" && break;
    echo "<<< Test #$i passed!"
done

