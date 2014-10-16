#!/bin/bash

if [ `id -u` -ne 0 ]; then 
  #attempt to promote to su, works on amazon boxes etc
  sudo -n su -
  if [ `id -u` -ne 0 ]; then 
    echo
    echo ** This script must be ran as root, unable to sudo su - to root. **
    echo
    #abort script if we aren't root, do nothing in interactive shell
    case $- in
    *i*)
      sleep 2
    ;;
    *)
      exit
    ;;
    esac
  fi
fi


if [ `id -u` -eq 0 ]; then 

#AMAZON instances remove the cloud config
umount /dev/xvdb
sed -i '/cloudconfig/d' /etc/fstab

sed -i '/exit 0/d' /etc/rc.local
cat << EOF >> /etc/rc.local
#Will use madvise if available, if not will use never
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
   echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
   echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
fi

exit 0
EOF

#disable NUMA
#assumes Amazon linux
sed -i '/^kernel/ s/$/ numa=off/g' /etc/grub.conf
#assumes ubuntu
sed -i '/^kernel/ s/$/ numa=off/g' /boot/grub/menu.lst
sed -i '/^kernel/ s/$/ apparmor=0/g' /boot/grub/menu.lst

#disable SE linux
#this needs to be updated to change anything to disabled, permissive sucks to (still does work)
if [ -f /etc/selinux/config ]; then
sudo sed -i 's/enforcing/disabled/' /etc/selinux/config
fi

#set keepalive and zone_reclaim_mode
sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
sed -i '/vm.zone_reclaim_mode/d' /etc/sysctl.conf
cat << EOF >> /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 300
vm.zone_reclaim_mode = 0
EOF
sysctl -p

#set ulimits
echo "* soft nofile 64000
* hard nofile 64000
* soft nproc 32000
* hard nproc 32000" > /etc/security/limits.conf
#various RHEL clones set things in limits.d, we don't want any of them
rm -rf /etc/security/limits.d/*

#set RA
#Note the scheduler is set to "noop", bare metal probably want to remove that/cfq
#For non-flash, read_ahead_kb is probably by 16 (which is == blockdev --setra 32 /dev/...)
cat <<EOF>> /etc/udev/rules.d/51-mongo-vm-devices.rules
SUBSYSTEM=="block", ACTION=="add|change", ATTR{bdi/read_ahead_kb}="0", ATTR{queue/scheduler}="noop"
EOF

fi
