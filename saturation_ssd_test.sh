#!/bin/bash
#SSD Test, SNIA, SSS PTS

readonly FIO="/usr/bin/fio"


#Calc disk size function
get_disk_size(){
        /usr/bin/test -b $arg1
        if [ $? -eq 0 ]
	then
	        let "SIZE = $(cat /sys/block/$(echo $arg1 | cut -d "/" -f3)/size) * $(cat /sys/block/$(echo $arg1 | cut -d "/" -f3)/queue/logical_block_size)"
	        echo "GOT SIZE=$SIZE"
	 else
	        echo "Wrong block dev, abort."
        exit 1
        fi
}

#Precondition function
precondition(){
        #Write device user capacity with 128 KiB sequential writes.
        for x in `seq 1 $capacity`;
        do
                echo "Preconditioning start:`date`"
                $FIO --name=precondition --filename=$arg1 --size=$SIZE --iodepth=16 --numjobs=1 --bs=128k --ioengine=libaio --rw=write --group_reporting --direct=1 --thread --refill_buffers
		echo
                echo "Preconditioning $x step from $capacity complete: `date`"
        done

}

#Changing scheduler to noop if avalible. Need to test this function.
prep(){
        if [ $(cat /sys/block/$(echo $arg1 | cut -d "/" -f3)/queue/scheduler | grep "noop") -eq 0 ]
	then
                #Changing scheduler to noop for fun
		echo noop > /sys/block/$(echo $arg1 | cut -d "/" -f3)/queue/scheduler
	else
                echo "Will not change scheduler, bacause NOOP scheduler is not avalible for this device"
	fi
}


#Secure erase function + scheduler
purge(){
        echo noop > /sys/block/$(echo $arg1 | cut -d "/" -f3)/queue/scheduler
        hdparm --user-master u --security-set-pass PasSWorD $arg1
        hdparm --user-master u --security-erase PasSWorD $arg1
}


#Write saturation test
saturation_test(){
        #OIO=64
        #THREADS=64
        #capacity=4
        OIO=$1
        THREADS=$2
        capacity=$3

        echo "Saturaton test"
        echo "================"
        echo "$ssd_model, OIO=$OIO, THREADS=$THREADS, UserCapacity=$capacity" > "$DIR/saturation_datapoints.csv"
	echo "Pass, IOPS" >> "$DIR/saturation_datapoints.csv"
        echo "Test range 0 to $SIZE"
        echo "OIO/thread = $OIO, Threads = $THREADS"
        echo "Test Start time: `date`"
        echo

        echo "Prior to running the test, Purge the SSS to be in compliance with PTS 1.0"
	purge
        precondition $capacity

	for PASS in `seq 1 1440`;
        do
                IOPS=`$FIO --name=job --filename=$arg1  --size=$SIZE --iodepth=$OIO --numjobs=$THREADS --bs=4k --ioengine=libaio --invalidate=1 --rw=randrw --rwmixwrite=100 --group_reporting --eta always --runtime=60 --direct=1 --norandommap --thread --refill_buffers  | grep iops | gawk 'BEGIN{FS = "="}; {print $4}' | gawk '{total = total +$1}; END {print total}'`
                echo "$PASS, $IOPS, `date`"
                echo "$PASS, $IOPS" >> "$DIR/saturation_datapoints.csv"
        done
}


#get size if had dev name, or ask for dev name and get size
if [ $# -ne 1 ]
then
        echo -n "Input block dev (example /dev/sdb): "
        read arg1
        get_disk_size $arg1
else
        arg1=$1
        get_disk_size $arg1

fi

DIR="results-`date +%d%m%Y%H%M`"
mkdir $DIR

ssd_model=$(hdparm -I $arg1 | grep Model)
echo $ssd_model


if [ $? -eq 0 ]
then

        saturation_test 32 32 4

else
        echo "Results directory $DIR exist or you don't have permissions to create directory. Remove, rename or give needed permissions. Don't forget to backup results"

fi
exit 0









