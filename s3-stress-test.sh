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
PID=81ba
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

function log () {
    echo "[+] " $@
}

function err () {
    log "[ERROR]" $@
}

function log_start() {
    log "Test #$i/$NTESTS: suspend $VID:$PID for $S3_DURATION sec."
}

function check_device_presence () {
    if [ 1 -eq $(lsusb | grep $VID:$PID | wc -l) ]; then
       log "Device $VID:$PID found"
       lsusb | grep $VID:$PID
       return 1
    fi
    return 0
}

function check_device_communication () {
    if [ -z $CHECK_SERIAL ]; then
        log "Skipping check communication with serial device"
        return 1
    fi

    log "Checking communication with device"

    log "Giving $WAIT_CONNECTION_TIME seconds to the modem to register"
    sleep $WAIT_CONNECTION_TIME

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

    log "Giving $WAIT_CONNECTION_TIME seconds to the modem to connect"
    sleep $WAIT_CONNECTION_TIME

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
    PERST_PATH=/sys/bus/usb/devices/$DEV_ID/power/persist

    log "Current USB persistence value $(cat $PERST_PATH)."
    if  [ ! -z $DISABLE_PERST ]; then
        echo 0 > $PERST_PATH
        log "New USB persistence value $(cat $PERST_PATH)."
        sleep 1
    fi
}


# MAIN
log "Test config ================"
[ ! -z $SHUTDOWN_MM ] && log "Disabling MM" || log "Keeping MM"
[ ! -z $DISABLE_PERST ] && log "Disabling USB persistence" || log "Not disabling USB persistence"
[ ! -z $CHECK_SERIAL ] && log "Will check serial communication"
[ ! -z $CHECK_CONNECTION ] && log "Will check connection"
echo

if [ ! -z $SHUTDOWN_MM ]; then
    log "Shutting down MM"
    systemctl stop ModemManager
else
    log "Keep MM up and running"
fi

for i in $(seq $NTESTS); do
    log_start

    check_persistence

    rtcwake -m mem -s $S3_DURATION
    
    echo "<<< Test S3 #$i/$NTESTS: wake up"

    ret=0
    for j in $(seq $RETRIES); do

        ret=-1
        check_device_presence
        [ 0 -eq $? ] && continue

        ret=-2
        check_device_communication
        [ 0 -eq $? ] && continue

        ret=-3
        check_connection
        [ 0 -eq $? ] && continue

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


