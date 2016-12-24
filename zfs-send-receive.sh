#!/bin/bash
#
#	ZFS replication (send/receive) helper script 
#	Version 0.1
#
#	Created by ava1ar (mail@ava1ar.me)
#
#	Supported features:
#		* zfs send/receive on remote box in push mode (script should run on source box)
#		* supports ssh and nc as transports
#	
#	Usage example:
#		* Sending data/files dataset to data/files on remote machine with ip 192.168.1.253 using nc with verbose enabled:
#		./zfs-send-receive.sh -s data/files -d data/files -r 192.168.1.253 -t nc -v	
#		* Sending data/downloads dataset to data/downloads on remote machine with ip 192.168.1.253 using ssh with super verbose enable:
#		./zfs-send-receive.sh -s data/downloads -d data/downloads -r 192.168.1.253 -t ssh -vv	
#
#	Version history:
#		* 0.1	initial version. Supports remote replication only using ssh and nc. Following command line flags are available: -R -p -F -n -v -vv (see usage for details)
#
#	Pending features:
#		* User impersonation (change user before running zfs send/receive)
#		* Local replication
#		* Resumable zfs send/receive (-s / -t flags)
#		* Differential replication (-I flag)
#		* Large blocks / embedded data support (-l / -e flags)
#		* zfs bookmarks as a source of replication
#
#	 You may use, distribute and copy zfs-send-receive code under the terms of GNU General Public License version 2: https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
#

### HARDCODED PARAMETERS ###

# number of snapshot to keep 
MAX_SNAPSHOTS_COUNT=2
# name of the snapshot for the send/receive operation
SHAPSHOT_NAME_PREFIX="backup"
SHAPSHOT_NAME=${SHAPSHOT_NAME_PREFIX}_$(date "+%Y_%m_%d_%T"|sed s/:/_/g)
# ssh options
SSH_OPTIONS=" -c aes128-ctr "
# netcat client flags
NETCAT_PORT=" 3333 "

### CONFIGURABLE PARAMETERS ###

# source dataset
SOURCE_DATASET=""
# destination dataset
DEST_DATASET=""
# remote host
REMOTE=""
# transport
TRANSPORT=""
# zfs send flags
ZFS_SEND_FLAGS=""
# zfs receive flags
ZFS_RECEIVE_FLAGS=""
# verbose flag
VERBOSE=""
# dry run flag
DRY_RUN=""

### FUNCTIONS DEFINITIONS ###

# print message to stderr
print_error() 
{
	echo "$@" >&2
}

# print message to stderr in $VERBOSE is set
print_message() 
{
	if [ -n "$VERBOSE" ]; then
		echo "$@" >&2
	fi
}

# check if remote host is available and exit otherwise
check_remote()
{
	ping -q -c1 -t1 $1 > /dev/null
	echo $?
} 

# checks if specified transport is supported
check_transport()
{
	case $1 in
   		ssh | nc)
    		echo $1 ;;
	esac
}

# list pools/datasets with given name $1 
list_pool_dataset()
{
	zfs list -H -o name $1
}

# list snapshots for given dataset $1. Returns only snapshot names (after @ sign)
list_snapshots()
{
	zfs list -H -o name -t snapshot | grep $1 | cut -d@ -f2
}

# destroy snapshots having $SHAPSHOT_NAME_PREFIX in name for given dataset, specified as $1 except last n, where n specified as $2 
destroy_snapshots()
{
	zfs list -H -r -o name -t snapshot $1 | grep @$SHAPSHOT_NAME_PREFIX | tail -r | tail -n +$(expr $2 + 1) | tail -r | xargs -n 1 zfs destroy $VERBOSE $DRY_RUN
}

# execute passed parameters as command remotely via ssh with $SSH_OPTIONS on $REMOTE box
remote()
{
	FUNCTION_BODY=$(declare -f $1 | grep -vE "$1\ \(\)|\{|\}" | sed 's:|:\\|:g')
	if [ ! "$FUNCTION_BODY" ]; then
		remote_exec "$@"
	else 
		eval shift 1 \; remote_exec $FUNCTION_BODY
	fi
}

# perform remote execution of the command via ssh using $SSH_OPTIONS on $REMOTE box
remote_exec()
{
	ssh $SSH_OPTIONS $REMOTE "$@" 2>/dev/null
}

usage()
{
	echo "Usage: $0 (-s SOURCE_DATASET | --source SOURCE_DATASET) (-d DEST_DATASET | --dest DEST_DATASET) (-r REMOTE | --remote REMOTE) (-t TRANSPORT | --transport TRANSPORT) [-R] [-p] [-F] [-n] [-v | -vv]"
	echo -e "-s, --source SOURCE_DATASET\t source dataset for replication"
	echo -e "-d, --dest DEST_DATASET\t\t destination dataset for replication"
	echo -e "-r, --remote REMOTE\t\t destination remote ip / machine name"
	echo -e "-t, --transport TRANSPORT\t transport for replication. ssh and nc are supported"
	echo -e "-R, --recursive\t\t\t add -R flag to zfs send command"
	echo -e "-p, --properties\t\t add -p flag to zfs send command"
	echo -e "-F, --force\t\t\t add -F flag to zfs receive command"
	echo -e "-n, --dry-run\t\t\t Do a dry-run ('No-op') operations where possible"
	echo -e "-v, --verbose\t\t\t Add -v flag to all zfs operation (except 'zfs send') and print some extra information during replication"
	echo -e "-vv\t\t\t\t Same as -v, but also add -v flag to 'zfs send'"
	exit 1
}

### COMMAND LINE PARAMETERS PROCESSING ###

# show usage and exit if executed with no parameters
[ $# -eq 0 ] && usage

# parse parameters
while [ "$1" != "" ]; do
	PARAM=$1; shift; VALUE=$1;
    case $PARAM in
        -h | --help)
        	usage
            exit
            ;;
        -s | --source)
            SOURCE_DATASET=$VALUE 
			shift
            ;;
        -d | --dest)
            DEST_DATASET=$VALUE
			shift
            ;;
        -r | --remote)
			REMOTE=$VALUE 
			shift
			;;
        -t | --transport)
			TRANSPORT=$VALUE 
			shift
			;;
		-R | --recursive)
			ZFS_SEND_FLAGS=$ZFS_SEND_FLAGS" -R" ;;
		-p | --properties)
			ZFS_SEND_FLAGS=$ZFS_SEND_FLAGS" -p" ;;
		-F | --force)
			ZFS_RECEIVE_FLAGS=$ZFS_RECEIVE_FLAGS" -F" ;;
		-n | --dry-run)
			DRY_RUN="-n"
			ZFS_SEND_FLAGS=$ZFS_SEND_FLAGS" -n" 
			ZFS_RECEIVE_FLAGS=$ZFS_RECEIVE_FLAGS" -n"
			;;
		-v | --verbose)
			VERBOSE="-v"
			ZFS_RECEIVE_FLAGS=$ZFS_RECEIVE_FLAGS" -v"
			;;
		-vv) # super verbose mode (same as verbose + -v for zfs send)
			VERBOSE="-v"
			ZFS_RECEIVE_FLAGS=$ZFS_RECEIVE_FLAGS" -v"		
			ZFS_SEND_FLAGS=$ZFS_SEND_FLAGS" -v"
			;;	
        *)
            print_error "ERROR: unknown parameter '$PARAM'"
            usage
            ;;
    esac
done

### MAIN FUNCTIONALITY IMPLEMENTATION ###

# checking if $REMOTE is available
print_message "> Checking remote '$REMOTE'..." 2>&1
if [ "$(check_remote $REMOTE)" != "0" ]; then
	print_error "ERROR: Specified remote '$REMOTE' is not accessible. Aborting..." && exit 1
fi

# checking if specified $TRANSPORT is supported
print_message "> Checking selected transport '$TRANSPORT'..." 2>&1
if [ ! "$(check_transport $TRANSPORT)" ]; then
	print_error "ERROR: Transport '$TRANSPORT' is not valid; only 'ssh' or 'nc' transports are supported. Aborting..." && exit 1
fi

# checking if $SOURCE_DATASET exists
print_message "> Checking source dataset '$SOURCE_DATASET'..." 2>&1
if [ ! "$(list_pool_dataset $SOURCE_DATASET)" ]; then
	print_error "ERROR: Source dataset name '$SOURCE_DATASET' is not valid. Aborting..." && exit 1
fi

# checking if $DEST_DATASET and $DEST_POOL exists
# if remote dataset doesn't exist - show warn message and proceed
# if remote pool doesn't exist - show error message and exit
print_message "> Checking dest dataset '$DEST_DATASET'..." 2>&1
ACTUAL_DEST_DATASET=$(remote list_pool_dataset $DEST_DATASET)
if [ ! "$ACTUAL_DEST_DATASET" ]; then
	print_message "WARN: Dest dataset name '$DEST_DATASET' doesn't exist" 2>&1
	DEST_POOL=$(echo $DEST_DATASET | cut -d"/" -f1)
	if [ ! "$(remote list_pool_dataset $DEST_POOL)" ]; then
		print_error "ERROR: Dest pool name '$DEST_POOL' is not valid. Aborting..." && exit 1
	fi
fi

# getting list of source backup snapshot
LOCAL_BACKUP_SNAPSHOTS=$(list_snapshots $SOURCE_DATASET@$SHAPSHOT_NAME_PREFIX)
# getting list of dest backup snapshot
REMOTE_BACKUP_SNAPSHOTS=$(remote list_snapshots $DEST_DATASET@$SHAPSHOT_NAME_PREFIX)

# getting latest common snapshot for source and dest (will be used for incremental replication)
# NOTE: process substitution used here ("<("), which is not working on all shells, i.e. csh
SOURCE_SNAPSHOT=$(comm -12 <(echo $LOCAL_BACKUP_SNAPSHOTS | tr " " "\n") <(echo $REMOTE_BACKUP_SNAPSHOTS | tr " " "\n") | tail -1)

# if $SOURCE_SNAPSHOT is available, perform incremental replication; otherwise perform full replication
if [ -n "$SOURCE_SNAPSHOT" ]; then
	print_message "> Selected incremental replication mode on top of '$SOURCE_SNAPSHOT' snapshot" 2>&1
	# add '-i $SOURCE_SNAPSHOT' to the zfs send parameters to allow incremental replication
	ZFS_SEND_FLAGS=$ZFS_SEND_FLAGS" -i @$SOURCE_SNAPSHOT"
else
	print_message "> Selected full replication mode" 2>&1
	# no common snapshot for replication found, so full replication will be done
	# if $ACTUAL_DEST_DATASET exists, it should be renamed before replication starts (we do not want to override it)
	if [ -n "$ACTUAL_DEST_DATASET" ]; then
		print_message "> Existing remote dataset '$DEST_DATASET' will be renamed to '${DEST_DATASET}_${SHAPSHOT_NAME}'" 2>&1
		# renaming dataset
		remote zfs rename -p $DEST_DATASET ${DEST_DATASET}_${SHAPSHOT_NAME}	
	fi
fi

# creating snapshot for replication
print_message "> Creating new snapshot for '$SOURCE_DATASET'" 2>&1
zfs snapshot $SOURCE_DATASET@$SHAPSHOT_NAME

# perform replication using specified $TRANSPORT
print_message "> Performing replication of '$SOURCE_DATASET@$SHAPSHOT_NAME' to '$DEST_DATASET' on '$REMOTE' using '$TRANSPORT'..." 2>&1
case $TRANSPORT in
	ssh)
		zfs send $ZFS_SEND_FLAGS $SOURCE_DATASET@$SHAPSHOT_NAME | remote zfs receive $ZFS_RECEIVE_FLAGS $DEST_DATASET 
		;;
   	nc)
		# starting nc on remote host and using it as source for zfs receive
		remote "nc -l $NETCAT_PORT | zfs receive $ZFS_RECEIVE_FLAGS $DEST_DATASET" &
		sleep 1
		# performing zfs send to the local nc instance 
		zfs send $ZFS_SEND_FLAGS $SOURCE_DATASET@$SHAPSHOT_NAME | nc -w 10 $REMOTE $NETCAT_PORT
		;;
esac

# Cleaning outdated snapshots from source dataset (keep only $MAX_SNAPSHOTS_COUNT last snapshots)
print_message "> Removing old snapshots for source dataset '$SOURCE_DATASET'..." 2>&1
destroy_snapshots $SOURCE_DATASET $MAX_SNAPSHOTS_COUNT

# Cleaning outdated snapshots from dest dataset (keep only $MAX_SNAPSHOTS_COUNT last snapshots)
print_message "> Removing old snapshots for dest dataset '$DEST_DATASET'..." 2>&1
remote destroy_snapshots $DEST_DATASET $MAX_SNAPSHOTS_COUNT
