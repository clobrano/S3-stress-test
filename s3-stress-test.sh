#!/usr/bin/env bash
#  S3 (suspend) stress test using rtcwake
# Available checks:
# * Check device with given VID/PID exists
# * Check modem is registered through ModemManager
# * Check modem is connected through ppp

exec 1> >(logger -s -t $(basename $0)) 2>&1

# Device configuration
VID=413c
PID=81ba
DEV_ID="1-8.1"

# Test configuration
IFACE=ppp0
NTESTS=200
RETRIES=5
S3_DURATION=10
WAIT_CONNECTION_TIME=10
WAIT_DEVICE_TIME=1

while getopts "cd:mn:ps" opt; do
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
    cmd="+CSQ"
    mmid=$(mmcli -L | grep -Po "/\d+" | cut -d / -f 2)

    if [ ! -z $mmid ]; then

        mmcli -m $mmid --command="$cmd"

        if [ 0 -eq $(mmcli -m $mmid --command="$cmd" 2>&1 | grep error | wc -l) ]; then
            log "Communication test PASSED"
            return 1
        fi
    fi

    log "Modem not initialized yet, check again later"
    log "Giving $WAIT_CONNECTION_TIME seconds to the ModemManager to initialize the modem"
    sleep $WAIT_CONNECTION_TIME
    return 0
}

function check_connection () {
    if [ -z $CHECK_CONNECTION ]; then
        log "Skipping connection check"
        return 1
    fi

    log "Checking connection"
    if [ 0 -lt $(ifconfig $IFACE | wc -l) ]; then
        ping 8.8.8.8 -I $IFACE -c 3
        if [ 0 -eq $? ]; then
            log "Connection Test PASSED"
            return 1
        fi
    fi

    log "Modem not connected. Check again later"
    log "Giving $WAIT_CONNECTION_TIME seconds to the modem to connect"
    sleep $WAIT_CONNECTION_TIME

    return 0
}

function check_persistence () {
    PERST_PATH=/sys/bus/usb/devices/$DEV_ID/power/persist

    log "Current USB persistence value $(cat $PERST_PATH)."
    if  [ ! -z $DISABLE_PERST ]; then
        echo 0 > $PERST_PATH
        log "USB persistence value $(cat $PERST_PATH)."
        sleep 1
    fi
}

# ===================================================================================
# MAIN
# ===================================================================================
passed_tests=0

log "Test config ================"
[ ! -z $SHUTDOWN_MM ] && log "Disabling MM" || log "Keeping MM"
[ ! -z $DISABLE_PERST ] && log "Disabling USB persistence" || log "Not disabling USB persistence"
[ ! -z $CHECK_SERIAL ] && log "Will check serial communication"
[ ! -z $CHECK_CONNECTION ] && log "Will check connection"
echo

if [ ! -z $SHUTDOWN_MM ]; then
    systemctl stop ModemManager
fi

for i in $(seq $NTESTS); do
    echo
    log_start

    check_persistence

    rtcwake -m mem -s $S3_DURATION

    echo
    log "Test S3 #$i/$NTESTS: wake up"

    for j in $(seq $RETRIES); do
        log "Attempt $j of $RETRIES"

        check_device_presence
        [ 0 -eq $? ] && ret=-1 && continue

        check_persistence

        check_device_communication
        [ 0 -eq $? ] && ret=-2 && continue

        check_connection
        [ 0 -eq $? ] && ret=-3 && continue

        # All tests passed
        ret=0
    done

    case $ret in
        -1)
           log "Could not find device $VID:$PID"
           lsusb
           ;;
        -2)
            log "Could not communicate with serial device"
            ;;
        -3)
            log "Modem is not connected"
            ;;
    esac

    if [ $ret -lt 0 ]; then
        log "Test #$i NOT passed";
    else
        log "Test #$i passed!"
        let "passed_tests += 1"
    fi
    echo
done

log "Test passed $passed_tests/$NTESTS"


