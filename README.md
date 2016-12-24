# zfs-send-receive
ZFS replication (send/receive) helper script

Created by ava1ar (mail@ava1ar.me)

###Supported features:
* zfs send/receive on remote box in push mode (script should run on source box)
* supports ssh and nc as transports
	
###Usage example:
* Sending data/files dataset to data/files on remote machine with ip 192.168.1.253 using nc with verbose enabled:

<code>./zfs-send-receive.sh -s data/files -d data/files -r 192.168.1.253 -t nc -v</code>	
* Sending data/downloads dataset to data/downloads on remote machine with ip 192.168.1.253 using ssh with super verbose enable:

<code>./zfs-send-receive.sh -s data/downloads -d data/downloads -r 192.168.1.253 -t ssh -vv</code>

###Version history:
####0.1	
* initial version. Supports remote replication only using ssh and nc. Following command line flags are available: -R -p -F -n -v -vv (see usage for details)

###Pending features:
* User impersonation (change user before running zfs send/receive)
* Local replication
* Resumable zfs send/receive (-s / -t flags)
* Differential replication (-I flag)
* Large blocks / embedded data support (-l / -e flags)
  
