#!/bin/bash

# log function
echoerr() { echo "$@" 1>&2; }

# general password
PASSWORD="teste"

# network information
COMPUTE_MANAGEMENT_INTERFACE="eth0"
COMPUTE_PROVIDER_INTERFACE="eth1"
COMPUTE_IP="10.0.0.3"
CONTROLLER_IP="10.0.0.2"
COMPUTE_NETWORK="10.0.0.0"
COMPUTE_NETMASK="255.255.255.0"
COMPUTE_GATEWAY="10.0.0.1"
COMPUTE_DNS="8.8.8.8"

# configure network
echoerr "configure network"
echo "compute.openstack" > /etc/hostname
echo "$COMPUTE_IP compute compute.openstack" >> /etc/hosts
echo "$CONTROLLER_IP controller controller.openstack" >> /etc/hosts

cat<<EOF > /etc/network/interfaces 
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $COMPUTE_MANAGEMENT_INTERFACE 
iface $COMPUTE_MANAGEMENT_INTERFACE inet static
   address $COMPUTE_IP 
   network $COMPUTE_NETWORK
   netmask $COMPUTE_NETMASK
   gateway $COMPUTE_GATEWAY
   dns-nameservers $COMPUTE_DNS
 
auto $COMPUTE_PROVIDER_INTERFACE
  iface $COMPUTE_PROVIDER_INTERFACE inet manual
  up ip link set dev \$IFACE up
  down ip link set dev \$IFACE down
EOF
service networking stop
service networking start
ifconfig $COMPUTE_MANAGEMENT_INTERFACE $COMPUTE_IP netmask $COMPUTE_NETMASK up
route add default gw 10.0.0.1

# install chrony
echoerr "install chrony"
apt -y install chrony
echo "server controller iburst" >> /etc/chrony/chrony.conf
service chrony stop
service chrony start

# openstack repositories
echoerr "openstack repositories"
apt -y install software-properties-common
add-apt-repository -y cloud-archive:ocata
apt update 
apt -y dist-upgrade
apt -y install python-openstackclient

# nova
echoerr "nova"
apt -y install nova-compute
sed "s/PASSWORD/$PASSWORD/g" compute/etc/nova/nova.conf > /tmp/nova.conf
sed "s/10\.0\.0\.5/$COMPUTE_IP/g" /tmp/nova.conf > /etc/nova/nova.conf
rm /tmp/nova.conf
cp compute/etc/nova/nova-compute.conf /etc/nova/nova-compute.conf
service nova-compute restart

# neutron
echoerr "neutron"
apt -y install neutron-linuxbridge-agent 
sed "s/PASSWORD/$PASSWORD/g" compute/etc/neutron/neutron.conf > /etc/neutron/neutron.conf
sed "s/enp0s8/$COMPUTE_PROVIDER_INTERFACE/g" compute/etc/neutron/plugins/ml2/linuxbridge_agent.ini > /tmp/linuxbridge_agent.ini
sed "s/10\.0\.0\.5/$COMPUTE_IP/g" /tmp/linuxbridge_agent.ini > /etc/neutron/plugins/ml2/linuxbridge_agent.ini
rm /tmp/linuxbridge_agent.ini

service nova-compute restart
service neutron-linuxbridge-agent restart


