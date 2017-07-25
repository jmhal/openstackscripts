#!/bin/bash

# log function
echoerr() { echo "$@" 1>&2; }

# general password
PASSWORD="teste"

# network information
CONTROLLER_MANAGEMENT_INTERFACE="eth0"
CONTROLLER_PROVIDER_INTERFACE="eth1"
CONTROLLER_IP="10.0.0.2"
COMPUTE_IP="10.0.0.3"
CONTROLLER_NETWORK="10.0.0.0"
CONTROLLER_NETMASK="255.255.255.0"
CONTROLLER_GATEWAY="10.0.0.1"
CONTROLLER_DNS="8.8.8.8"

# configure network
echoerr "configure network"
echo "controller.openstack" > /etc/hostname
echo "$CONTROLLER_IP controller controller.openstack" >> /etc/hosts
echo "$COMPUTE_IP compute compute.openstack" >> /etc/hosts

cat<<EOF > /etc/network/interfaces 
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $CONTROLLER_MANAGEMENT_INTERFACE 
iface $CONTROLLER_MANAGEMENT_INTERFACE inet static
   address $CONTROLLER_IP 
   network $CONTROLLER_NETWORK
   netmask $CONTROLLER_NETMASK
   gateway $CONTROLLER_GATEWAY
   dns-nameservers $CONTROLLER_DNS
 
auto $CONTROLLER_PROVIDER_INTERFACE
  iface $CONTROLLER_PROVIDER_INTERFACE inet manual
  up ip link set dev \$IFACE up
  down ip link set dev \$IFACE down
EOF
service networking stop
service networking start
ifconfig $CONTROLLER_MANAGEMENT_INTERFACE $CONTROLLER_IP netmask $CONTROLLER_NETMASK up
route add default gw 10.0.0.1

# install chrony
echoerr "install chrony"
apt -y install chrony
sed "s/allow 10\.0\.0\.0\/24/allow $CONTROLLER_NETWORK\/24/g" controller/etc/chrony/chrony.conf > /etc/chrony/chrony.conf
service chrony stop
service chrony start

# openstack repositories
echoerr "openstack repositories"
apt -y install software-properties-common
add-apt-repository -y cloud-archive:ocata
apt update 
apt -y dist-upgrade
apt -y install python-openstackclient

# database configuration
echoerr "database configuration"
apt -y install mariadb-server python-pymysql
cat<<EOF > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = $CONTROLLER_IP

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

service mysql restart

mysql -u root << EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$PASSWORD';
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$PASSWORD';
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost'  IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$PASSWORD';
EOF

# message queue
echoerr "message queue"
apt -y install rabbitmq-server
echo "NODENAME=rabbit@$CONTROLLER_IP" >> /etc/rabbitmq/rabbitmq-env.conf
rabbitmqctl add_user openstack $PASSWORD
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# memcached
echoerr "memcached"
apt -y install memcached python-memcache
sed "s/10\.0\.0\.4/$CONTROLLER_IP/g" controller/etc/memcached.conf > /etc/memcached.conf
service memcached stop
service memcached start

# keystone
echoerr "keystone"
apt -y install keystone
sed "s/PASSWORD/$PASSWORD/g" controller/etc/keystone/keystone.conf > /etc/keystone/keystone.conf
su -s /bin/sh -c "keystone-manage db_sync" keystone

keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password $PASSWORD --bootstrap-admin-url http://controller:35357/v3/ --bootstrap-internal-url http://controller:5000/v3/  --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne
cp controller/etc/apache2/apache2.conf /etc/apache2/apache2.conf
service apache2 stop
service apache2 start

export OS_USERNAME=admin
export OS_PASSWORD=$PASSWORD
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3

openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" demo
openstack user create --domain default --password $PASSWORD demo
openstack role create user
openstack role add --project demo --user demo user

cat<<EOF > admin-openrc
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$PASSWORD
export OS_AUTH_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
cat<<EOF > demo-openrc
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=$PASSWORD
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

# glance
echoerr "glance"
. admin-openrc
openstack user create --domain default --password $PASSWORD glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292

apt -y install glance
sed "s/PASSWORD/$PASSWORD/g" controller/etc/glance/glance-api.conf > /etc/glance/glance-api.conf
sed "s/PASSWORD/$PASSWORD/g" controller/etc/glance/glance-registry.conf > /etc/glance/glance-registry.conf
su -s /bin/sh -c "glance-manage db_sync" glance

service glance-registry restart
service glance-api restart

wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
openstack image create "cirros" --file cirros-0.3.5-x86_64-disk.img --disk-format qcow2 --container-format bare --public
rm cirros-0.3.5-x86_64-disk.img

# nova
echoerr "nova"
openstack user create --domain default --password $PASSWORD nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1
openstack user create --domain default --password $PASSWORD placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778
apt -y install nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler nova-placement-api
sed "s/PASSWORD/$PASSWORD/g" controller/etc/nova/nova.conf > /tmp/nova.conf
sed "s/10\.0\.0\.4/$CONTROLLER_IP/g" /tmp/nova.conf > /etc/nova/nova.conf
rm /tmp/nova.conf

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova

service nova-api stop 
service nova-consoleauth stop
service nova-scheduler stop
service nova-conductor stop
service nova-novncproxy stop

service nova-api start
service nova-consoleauth start
service nova-scheduler start
service nova-conductor start
service nova-novncproxy start

# neutron
echoerr "neutron"
openstack user create --domain default --password $PASSWORD neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin http://controller:9696

apt -y install neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
sed "s/PASSWORD/$PASSWORD/g" controller/etc/neutron/neutron.conf > /etc/neutron/neutron.conf
sed "s/enp0s8/$CONTROLLER_PROVIDER_INTERFACE/g" controller/etc/neutron/plugins/ml2/linuxbridge_agent.ini > /tmp/linuxbridge_agent.ini
sed "s/10\.0\.0\.4/$CONTROLLER_IP/g" /tmp/linuxbridge_agent.ini > /etc/neutron/plugins/ml2/linuxbridge_agent.ini
rm /tmp/linuxbridge_agent.ini
sed "s/PASSWORD/$PASSWORD/g" controller/etc/neutron/metadata_agent.ini > /etc/neutron/metadata_agent.ini
cp controller/etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini
cp controller/etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini
cp controller/etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

service nova-api restart
service neutron-linuxbridge-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-l3-agent restart

# launch instance
. admin-openrc
openstack network create --share --external --provider-physical-network provider --provider-network-type flat provider
openstack subnet create --network provider --allocation-pool start=10.0.1.100,end=10.0.1.200 --dns-nameserver 8.8.8.8 --gateway 10.0.1.1 --subnet-range 10.0.1.0/24 provider
. demo-openrc
openstack network create selfservice
openstack subnet create --network selfservice --dns-nameserver 8.8.4.4 --gateway 172.16.1.1 --subnet-range 172.16.1.0/24 selfservice
. admin-openrc
. demo-openrc
openstack router create router
neutron router-interface-add router selfservice
neutron router-gateway-set router provider









