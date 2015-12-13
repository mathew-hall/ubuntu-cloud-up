#!/usr/bin/env bash

set -e
#set -x 

VERSION=14.04
ARCH=amd64
BASE_IMG=ubuntu-$VERSION-server-cloudimg-$ARCH-disk1.img
BASE_DIR=${BASE_DIR-/var/lib/libvirt/images}

DISKSIZE=${DISKSIZE-200G}

UUID=$(uuidgen)
NAME=$1
MAC=52:54:00$(dd if=/dev/urandom bs=1 count=3 2>/dev/null | xxd -p | sed 's/\(..\)/:\1/g')
INIT=init-$NAME
PASSWORD=${PASSWORD-$NAME}

function say {
	if [ -n "$DEBUG" ]; then
		echo "[+]" $@
	fi
}

if [ -z "$1" ]; then
	echo "Usage: $0 disk name"
fi

if [ -f "${BASE_DIR}/$1.img" ]; then
	echo "${BASE_DIR}/$1.img already exists"
	exit -1
fi

# Fetch the base image if it doesn't already exist
if [ ! -d ${BASE_DIR}/base ]; then
	echo "[+] Creating ${BASE_DIR}/base"
	sudo mkdir -p ${BASE_DIR}/base
fi
if [ ! -f ${BASE_DIR}/base/${BASE_IMG} ]; then
	echo "[+] Fetching Ubuntu ${VERSION} ${ARCH} cloud image"
	URL=http://cloud-images.ubuntu.com/server/releases/14.04/release/${BASE_IMG}
	DIR=$(mktemp -d image.XXXX)
	wget ${URL} -O ${DIR}/${BASE_IMG}
	qemu-img resize ${DIR}/${BASE_IMG} +${DISKSIZE} > /dev/null
	sudo mv ${DIR}/${BASE_IMG} ${BASE_DIR}/base/${BASE_IMG}
	rm -r "${DIR}/${BASE_IMG}"
	echo "[+] Image stored at ${BASE_DIR}/base/${BASE_IMG}"
	
fi


if [ ! -d ${BASE_DIR}/init ]; then
	sudo mkdir -p ${BASE_DIR}/init
fi

if ! virsh net-info default >/dev/null 2>&1; then 
	echo "[!] Virtual network default not found"
	echo "    Create a virtual network (using virt-manager) with the following settings:"
	echo "    Name: default"
	echo "    Network: (any subnet)"
	echo "    Enable DHCP"
	echo "    Start/End should be (subnet).2 and (subnet).254"
	echo "    Forward to any physical device with NAT"
	exit -1
fi

IP_ADDR=$(ifconfig $(virsh net-info default | grep Bridge | awk '{print $2}') | grep "inet addr" | head -n 1 | cut -d : -f 2 | awk '{print $1}')
IF_SUBNET=${IP_ADDR%.*}
SUBNET=${SUBNET-$IF_SUBNET}

say "Using net prefix $SUBNET"

N=$(virsh net-dumpxml default | grep host | cut -d = -f 4 | tr -d \' | cut -d . -f 4 | tr -d /\> | awk '$0>x{x=$0};END{print x}')
if [ ${N:-0} -eq 0 ]; then
	N=1
fi
N=$(( N + 1 ))
IP=${SUBNET}.$N

DIR=$(mktemp -d init.XXXX)

say "Generating NoCloud config ISO"
sed -e s/\\\$NAME\\\$/$NAME/g meta-data.template > ${DIR}/meta-data
sed -e s/\\\$NAME\\\$/$NAME/g -e s/\\\$PASSWORD\\\$/$PASSWORD/g user-data.template > ${DIR}/user-data

genisoimage -output ${DIR}/${INIT}.iso -volid cidata -joliet -rock ${DIR}/user-data ${DIR}/meta-data > /dev/null 2>&1

sudo mv ${DIR}/${INIT}.iso ${BASE_DIR}/init/$INIT.iso

say "Creating root disk image"

qemu-img create -f qcow2 -b ${BASE_DIR}/base/${BASE_IMG}-base ${DIR}/${NAME}.img >/dev/null 2>&1

sudo mv ${DIR}/${NAME}.img ${BASE_DIR}/${NAME}.img

say "Creating machine descriptor"

sed -e s/\\\$NAME\\\$/$NAME/g \
-e s/\\\$UUID\\\$/$UUID/g \
-e s/\\\$MAC\\\$/$MAC/g \
-e s/\\\$INIT\\\$/$INIT/g \
template.xml > "${DIR}/${NAME}.xml"

say "Adding static IP assignment"

if virsh net-dumpxml default | grep "\($NAME\|$MAC\)" > /dev/null; then
	#If macaddr or name already exists, modify the existing mapping
	virsh net-update --network default \
	modify ip-dhcp-host \
	--xml "<host mac='$MAC' name='$NAME' ip='$IP' />" --live --config  >/dev/null
else
	virsh net-update --network default \
	add-last ip-dhcp-host \
	--xml "<host mac='$MAC' name='$NAME' ip='$IP' />" --live --config  >/dev/null	
fi


say "Creating and booting VM"

virsh define ${DIR}/$NAME.xml  >/dev/null
virsh start $NAME >/dev/null

rm -r "${DIR}"

say "Creating static IP mapping in /etc/hosts"

echo "$IP	virtual-$NAME" | sudo tee -a  /etc/hosts > /dev/null

echo "Machine Details"
echo "Name: $NAME"
echo "UUID: $UUID"
echo "MAC Address: $MAC"
echo "IP Address: $IP"
echo "Hostname: virtual-$NAME (set in /etc/hosts)"
echo "Username: ubuntu"
echo "Password: $PASSWORD"
