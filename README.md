# Ubuntu Cloud KVM

This script automatically creates and launches an Ubuntu cloud instance locally within KVM. It uses a single Ubuntu Cloud image and maps layers writes to separate disks. Multiple VMs share the same cloud image and write to their own delta disks. The script also sets up a static IP assignment and creates entries in `/etc/hosts` for each guest.

Once created, machines can be managed through `virsh` or `virt-manager` (or any `libvirt`-aware tool).
# Usage

Run using `./make_image.sh machine_name`. The script uses some **insecure** defaults that can be changed by modifying the script or exporting them before running it.

## Defaults

The script will setup AMD64 Ubuntu 14.04 images by default.

The created machines will be given 4 virtual CPUs and 1GB of RAM, with a maximum of 16GB.

The machine will be given an IP in the /24 range for the host IP of the `default` KVM QEMU network, starting from 2. The script looks at existing static mappings to choose the first available IP. For example, if the QEMU virtual network has the IP address 192.168.122.1, the first guest will be assigned 192.168.122.2.

The username defaults to `ubuntu` and the password is set to the machine name by default.

## Customisation

The script uses a NoCloud ISO image to set configuration parameters. You can change these to have the VMs set themselves up differently. The supplied config leaves password authentication open for SSH and doesn't enforce password changes.

## Insecure by Default

The defaults shipping with the script make the machines very insecure. The default `ubuntu` username and the likelihood that machine names (and therefore passwords) are short/dictionary words mean these VMs need hardening before they are exposed to the network. The machines won't be reachable externally after being set up (they're on a private network with NAT), but change passwords and disable password authentication before exposing their SSH daemons.

## Issues 

###Cleaning up

The script doesn't clean up after itself. Machines (and their images) can be safely deleted but the DHCP reservations and hosts will persist. To clean these up, use `virsh net-edit default` to remove the `<host>` entries for removed machines, and remove the matching line from `/etc/hosts`.

###Reusing machine names

The script will refuse to create the machine if the disk image is found. To create a new machine with an existing name, remove the disk image, either via `virt-manager` or rm the file in `/var/lib/libvirt/images/`.

# Example

		 mat@kvm-server:~$ ./make_image.sh test6
		 Machine Details
		 Name: test6
		 UUID: dd9b630c-dea2-4411-be71-a295ce859283
		 MAC Address: 52:54:00:7e:2c:a7
		 IP Address: 192.168.122.11
		 Hostname: virtual-test6 (set in /etc/hosts)
		 Username: ubuntu
		 Password: test6

The machine can then be accessed via `ssh ubuntu@virtual-test6` using the password `test6`.