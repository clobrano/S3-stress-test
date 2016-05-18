#!/usr/bin/env bash
#  S3 (suspend) stress test using rtcwake
# Available checks:
# * Check device with given VID/PID exists
# * Check modem is registered through ModemManager
# * Check modem is connected through ppp

#function usage() {
#    Usage:
#        $0 [options]
#
#    Options:
#    --check-communication: check whether the ModemManager can communicate with the device. MM's debug must be enabled in ordere to send AT+CSQ command.
#    --check-connection: check whether the modem connects at resume
#    --dev-id: the device ID in sysfs (e.g. 1-4.1, 1-8.1). This is part of the path to the power/persistance file. Not needed if --usb-persistance is not provided.
#    --state: "mem" suspends the system to RAM (S3), "disk" to memory (S4)
#    --usb-persistance: 0 disables USB persistance feature, 1 enables it
#    --shutdown-mm: disable ModemManager
#    -i|--iface: network interface to check for connection (e.g. ppp0, wwan0)
#    -n|--num-tests: number of tests to perform
#    -s|--stop-fail: stop the test at the first failure
#    -t|--time-suspend: time to wait for resume
#}

#exec 1> >(logger -s -t $(basename $0)) 2>&1

PARSED_OPTIONS=$(getopt -n "$0" -o i:n:st: --long "check-communication,check-connection,dev-id:,state:,usb-persistance:,iface:,num-tests:,shutdown-mm,stop-fail,time-suspend:" -- "$@")

# Device configuration
VID=413c
PID=81bc
DEV_ID="1-8.1"

# Test configuration defaults
STATE=mem
IFACE=wwan0
NTESTS=100
TIME_SUSPEND=10


# Test configuration fixed values
RETRIES=10
WAIT_CONNECTION_TIME=10
WAIT_DEVICE_TIME=1



eval set -- "$PARSED_OPTIONS"

while true;
do
    case $1 in
        -h|--help)
            usage
            shift;;

        --check-communication)
            CHECK_COMMUNICATION=1
            shift;;

        --check-connection)
            CHECK_CONNECTION=1
            shift;; 

        --dev-id)
            if [ -n "$2" ]; then
                DEV_ID=$2
                shift 2
            else
                echo "--dev-id requires an argument"
                usage
                exit 1
            fi
            ;;

        --shutdown-mm)
            SHUTDOWN_MM=1
            shift;;

        --state)
            if [ -n "$2" ]; then
                STATE=$2
                shift 2
            else
                echo "--state requires an argument"
                usage
                exit 1
            fi
            ;;

        --usb-persistance)
            if [ -n "$2" ]; then
                USB_PERSISTANCE=$2
                shift 2
            else
                echo "--usb-persistance requires an argument"
                usage
                exit 1
            fi
            ;;

        -i|--iface)
            if [ -n "$2" ]; then
                IFACE=$2
                shift 2
            else
                echo "-i|--iface requires an argument"
                usage
                exit 1
            fi
            ;;

        -n|--num-tests)
            if [ -n "$2" ]; then
                NTESTS=$2
                shift 2
            else
                echo "-n|--num-tests requires an argument"
                usage
                exit 1
            fi
            ;;

        -s|--stop-fail)
            STOP_FAIL=1
            shift;;

        -t|--time-suspend)
            if [ -n "$2" ]; then
                TIME_SUSPEND=$2
                shift 2
            else
                echo "-t|--time-suspend requires an argument"
                usage
                exit 1
            fi
            ;;
        --)
            shift
            break;;
    esac
done

function log () {
    echo "[+] " $@
}

function err () {
    log "[ERROR]" $@
}

function log_start () {
    log "check communication: ${CHECK_COMMUNICATION:-disabled}"
    log "check connection:    ${CHECK_CONNECTION:-disabled}"
    log "dev-id:              $DEV_ID"
    log "state:               $STATE"
    log "usb-persistance:     ${USB_PERSISTANCE:-not set}"
    log "iface:               $IFACE"
    log "num-tests:           $NTESTS"
    log "stop-fail:           ${STOP_FAIL:-disabled}"
    log "time-suspend:        $TIME_SUSPEND"
    log "shutdown-mm:         ${SHUTDOWN_MM:-disabled}"
}

function check_device_presence () {
    if [ 1 -eq $(lsusb | grep $VID:$PID | wc -l) ]; then
       log "Device $VID:$PID found"
       lsusb | grep $VID:$PID
       return 1
    fi
	log "Could not find device $VID:$PID, check again later"
	sleep 3
    return 0
}

function check_device_communication () {
    if [ -z $CHECK_COMMUNICATION ]; then
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

function check_connection_ppp () {
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

function check_connection () {
    mmid=$(mmcli -L | grep -Po "/\d+" | cut -d / -f 2)

    if [ ! -z $mmid ]; then
	[ 1 -eq $(mmcli -m $mmid | grep connected | wc -l) ] && echo "Modem is registered"
	if [ 1 -eq $(mmcli -m $mmid | grep connected | wc -l) ]; then
	    ping 8.8.8.8 -I $IFACE -c 3
            if [ 0 -eq $? ]; then
                log "Connection Test PASSED"
                return 1
            fi
	fi

	log "Modem not connected. Check again later"
        log "Giving $WAIT_CONNECTION_TIME seconds to the modem to connect"
        sleep $WAIT_CONNECTION_TIME
    fi

    log "Modem not initialized yet, check again later"
    log "Giving $WAIT_CONNECTION_TIME seconds to the ModemManager to initialize the modem"
    sleep $WAIT_CONNECTION_TIME
    return 0
}

function check_persistance () {
    PERST_PATH=/sys/bus/usb/devices/$DEV_ID/power/persist

    if  [ ! -z $DISABLE_PERST ]; then
        log "Current USB persistance value $(cat $PERST_PATH). Changing it to 0."
        echo 0 > $PERST_PATH
        log "USB persistance value is now $(cat $PERST_PATH)."
        sleep 1
    else
        log "Current USB persistance value $(cat $PERST_PATH). Keeping this value."
    fi
}

# ===================================================================================
# MAIN
# ===================================================================================
passed_tests=0

log "Test config ================"
log_start
exit 0


for i in $(seq $NTESTS); do
    log "Test #$i/$NTESTS (#$passed_tests passed): suspend $VID:$PID to $STATE for $TIME_SUSPEND sec."

    check_persistance

    rtcwake -m $STATE -s $TIME_SUSPEND

    log " "
    log "Test S3 #$i/$NTESTS: wake up"

    for j in $(seq $RETRIES); do
        log " "
        log "Test #$i/$NTESTS: Attempt $j of $RETRIES"

        check_device_presence
        [ 0 -eq $? ] && ret=-1 && continue

        check_persistance

        check_device_communication
        [ 0 -eq $? ] && ret=-2 && continue

        check_connection
        [ 0 -eq $? ] && ret=-3 && continue

        # All tests passed
        ret=0
        break
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
    log " "
done

log "Test passed $passed_tests/$NTESTS"


