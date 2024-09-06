#!/bin/bash
read -p '输入0执行基本配置，输入1安装docker，输入2配置openstack控制节点，输入3配置openstack计算节点，输入4配置静态ip，输入5恢复DHCP ：' install
case $install in
0)
rm -f /etc/yum.repos.d/*
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0
systemctl disable firewalld.service
systemctl stop firewalld.service
yum install -y wget net-tools bash-completion deltarpm
bash
;;
1)
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
yum makecache fast
yum install -y docker-ce docker-compose
mkdir -p /etc/docker
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://hgrce60y.mirror.aliyuncs.com"]
}
EOF
systemctl daemon-reload
systemctl enable docker
systemctl start docker
;;
2)
tee /etc/yum.repos.d/openstack.repo <<-'EOF'
[openstack]
name=openstack
baseurl=https://mirrors.aliyun.com/centos/7.9.2009/cloud/x86_64/openstack-queens/
gpgcheck=0
enable=1

[openstack-kvm]
name=kvm
baseurl=https://mirrors.aliyun.com/centos/7.9.2009/virt/x86_64/kvm-common/
gpgcheck=0
enable=1
EOF
systemctl disable NetworkManager
systemctl stop NetworkManager
wk=$(ip r|grep via|cut -d ' ' -f 5)
ip=$(ifconfig $wk|grep netmask|awk '$1=$1'|cut -d ' ' -f 2)
ym=$(ip r|grep $ip|cut -d '/' -f 2|cut -d ' ' -f 1)
wg=$(ip r|grep via|cut -d ' ' -f 3)
sed -i -e 's/ONBOOT=.*/ONBOOT=yes/g' -e 's/BOOTPROTO=.*/BOOTPROTO=none/g' /etc/sysconfig/network-scripts/ifcfg-$wk
echo 'IPADDR='$ip'
PREFIX='$ym'
GATEWAY='$wg'
DNS1=114.114.114.114' >> /etc/sysconfig/network-scripts/ifcfg-$wk
systemctl restart network
yum install chrony -y
sed -i -e '/server [1-3].*/d' -e 's/server .*/server ntp.aliyun.com iburst/g' /etc/chrony.conf
systemctl enable chronyd.service
systemctl start chronyd.service
yum install python-openstackclient libibverbs -y
yum install rabbitmq-server -y
systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service
rabbitmqctl add_user openstack RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
yum install memcached python-memcached -y
systemctl enable memcached.service
systemctl start memcached.service
yum install mariadb mariadb-server python2-PyMySQL -y
echo '[mysqld]
bind-address = '$ip'
default-storage-engine = innodb
innodb_file_per_table
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8' > /etc/my.cnf.d/openstack.cnf
systemctl enable mariadb.service
systemctl start mariadb.service
mysql_secure_installation
hostnamectl set-hostname controller
echo $ip controller >> /etc/hosts
read -p '输入计算节点ip以配置hosts ：' hosts
echo $hosts compute1 >> /etc/hosts
read -p '输入数据库root密码 ：' dbpd
mysql -uroot -p$dbpd << 'EOF'
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'GLANCE_DBPASS';
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'NEUTRON_DBPASS';
EOF
yum upgrade -y
echo -e '\n\n\e[32m####################系统环境配置完成####################\e[0m\n\n'
yum install openstack-keystone httpd mod_wsgi python2-qpid-proton -y
tee /etc/keystone/keystone.conf <<-'EOF'
[database]
connection = mysql+pymysql://keystone:KEYSTONE_DBPASS@controller/keystone
[token]
provider = fernet
EOF
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password ADMIN_PASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne
sed -i 's/#ServerName.*/ServerName controller/g' /etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable httpd.service
systemctl start httpd.service
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
openstack domain create --description "An Example Domain" example
openstack project create --domain default \
  --description "Service Project" service
openstack project create --domain default \
  --description "Demo Project" demo
openstack user create --domain default \
  --password DEMO_PASS demo
openstack role create user
openstack role add --project demo --user demo user
tee admin-openrc <<-'EOF'
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
tee demo-openrc <<-'EOF'
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=DEMO_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
. admin-openrc
echo -e '\n\n\e[32m####################Keystone配置完成####################\e[0m\n\n'
openstack user create --domain default --password GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance \
  --description "OpenStack Image" image
openstack endpoint create --region RegionOne \
  image public http://controller:9292
openstack endpoint create --region RegionOne \
  image internal http://controller:9292
openstack endpoint create --region RegionOne \
  image admin http://controller:9292
yum install openstack-glance -y
tee /etc/glance/glance-api.conf <<-'EOF'
[database]
connection = mysql+pymysql://glance:GLANCE_DBPASS@controller/glance
[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = GLANCE_PASS
[paste_deploy]
flavor = keystone
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
EOF
tee /etc/glance/glance-registry.conf <<-'EOF'
[database]
connection = mysql+pymysql://glance:GLANCE_DBPASS@controller/glance
[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = GLANCE_PASS
[paste_deploy]
flavor = keystone
EOF
su -s /bin/sh -c "glance-manage db_sync" glance
systemctl enable openstack-glance-api.service \
  openstack-glance-registry.service
systemctl start openstack-glance-api.service \
  openstack-glance-registry.service
wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
openstack image create "cirros" \
  --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --public
echo -e '\n\n\e[32m####################Glance配置完成####################\e[0m\n\n'
openstack user create --domain default --password NOVA_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova \
  --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne \
  compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute admin http://controller:8774/v2.1
openstack user create --domain default --password PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778
yum install openstack-nova-api openstack-nova-conductor \
  openstack-nova-console openstack-nova-novncproxy \
  openstack-nova-scheduler openstack-nova-placement-api -y
echo '[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:RABBIT_PASS@controller
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver
my_ip = '$ip'
[api_database]
connection = mysql+pymysql://nova:NOVA_DBPASS@controller/nova_api
[database]
connection = mysql+pymysql://nova:NOVA_DBPASS@controller/nova
[api]
auth_strategy = keystone
[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = NOVA_PASS
[vnc]
enabled = true
server_listen = $my_ip
server_proxyclient_address = $my_ip
[glance]
api_servers = http://controller:9292
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[placement]
os_region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = PLACEMENT_PASS
[scheduler]
discover_hosts_in_cells_interval = 300' > /etc/nova/nova.conf
echo '
<Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
</Directory>' >> /etc/httpd/conf.d/00-nova-placement-api.conf
systemctl restart httpd
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
nova-manage cell_v2 list_cells
systemctl enable openstack-nova-api.service \
  openstack-nova-consoleauth.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service
systemctl start openstack-nova-api.service \
  openstack-nova-consoleauth.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service
echo -e '\n\n\e[32m####################Nova配置完成####################\e[0m\n\n'
openstack user create --domain default --password NEUTRON_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron \
  --description "OpenStack Networking" network
openstack endpoint create --region RegionOne \
  network public http://controller:9696
openstack endpoint create --region RegionOne \
  network internal http://controller:9696
openstack endpoint create --region RegionOne \
  network admin http://controller:9696
yum install openstack-neutron openstack-neutron-ml2 \
  openstack-neutron-linuxbridge ebtables -y
echo '[database]
connection = mysql+pymysql://neutron:NEUTRON_DBPASS@controller/neutron
[DEFAULT]
core_plugin = ml2
service_plugins =
transport_url = rabbit://openstack:RABBIT_PASS@controller
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = NEUTRON_PASS
[nova]
auth_url = http://controller:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = NOVA_PASS
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp' > /etc/neutron/neutron.conf
echo '[ml2]
type_drivers = flat,vlan
tenant_network_types =
mechanism_drivers = linuxbridge
extension_drivers = port_security
[ml2_type_flat]
flat_networks = provider
[securitygroup]
enable_ipset = true' > /etc/neutron/plugins/ml2/ml2_conf.ini
echo '[linux_bridge]
physical_interface_mappings = provider:'$wk'
[vxlan]
enable_vxlan = false
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' > /etc/neutron/plugins/ml2/linuxbridge_agent.ini
echo '[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true' > /etc/neutron/dhcp_agent.ini
echo '[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = METADATA_SECRET' > /etc/neutron/metadata_agent.ini
echo '[neutron]
url = http://controller:9696
auth_url = http://controller:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRON_PASS
service_metadata_proxy = true
metadata_proxy_shared_secret = METADATA_SECRET' >> /etc/nova/nova.conf
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
systemctl restart openstack-nova-api.service
systemctl enable neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
systemctl start neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
echo -e '\n\n\e[32m####################Neutron配置完成####################\e[0m\n\n'
yum install openstack-dashboard -y
sed -i -e 's/OPENSTACK_HOST = .*/OPENSTACK_HOST = "controller"/g' -e "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/g" /etc/openstack-dashboard/local_settings
sed -i -e '165,169d' -e "s/    'enable_router': True,/    'enable_router': False,/g" -e "s/    'enable_quotas': True,/    'enable_quotas': False,/g" -e "s/    'enable_fip_topology_check': True,/    'enable_fip_topology_check': False,/g" -e "/    'enable_ha_router': False,/a    'enable_lb': False," -e "/    'enable_ha_router': False,/a    'enable_firewall': False," -e "/    'enable_ha_router': False,/a    'enable_vpn': False," /etc/openstack-dashboard/local_settings
#echo "SESSION_ENGINE = 'django.contrib.sessions.backends.cache'" >> /etc/openstack-dashboard/local_settings
echo "CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': 'controller:11211',
    }
}" >> /etc/openstack-dashboard/local_settings
echo 'OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}' >> /etc/openstack-dashboard/local_settings
sed -i 's+TIME_ZONE = "UTC"+TIME_ZONE = "Asia/Shanghai"+g' /etc/openstack-dashboard/local_settings
echo WSGIApplicationGroup %{GLOBAL} >> /etc/httpd/conf.d/openstack-dashboard.conf
systemctl restart httpd.service memcached.service
echo -e '\n\n\e[32m####################Horizon配置完成####################\e[0m\n\n'
bash
;;
3)
tee /etc/yum.repos.d/openstack.repo <<-'EOF'
[openstack]
name=openstack
baseurl=https://mirrors.aliyun.com/centos/7.9.2009/cloud/x86_64/openstack-queens/
gpgcheck=0
enable=1

[openstack-kvm]
name=kvm
baseurl=https://mirrors.aliyun.com/centos/7.9.2009/virt/x86_64/kvm-common/
gpgcheck=0
enable=1
EOF
systemctl disable NetworkManager
systemctl stop NetworkManager
wk=$(ip r|grep via|cut -d ' ' -f 5)
ip=$(ifconfig $wk|grep netmask|awk '$1=$1'|cut -d ' ' -f 2)
ym=$(ip r|grep $ip|cut -d '/' -f 2|cut -d ' ' -f 1)
wg=$(ip r|grep via|cut -d ' ' -f 3)
sed -i -e 's/ONBOOT=.*/ONBOOT=yes/g' -e 's/BOOTPROTO=.*/BOOTPROTO=none/g' /etc/sysconfig/network-scripts/ifcfg-$wk
echo 'IPADDR='$ip'
PREFIX='$ym'
GATEWAY='$wg'
DNS1=114.114.114.114' >> /etc/sysconfig/network-scripts/ifcfg-$wk
systemctl restart network
hostnamectl set-hostname compute1
echo $ip compute1 >> /etc/hosts
yum install chrony -y
sed -i -e '/server [1-3].*/d' -e 's/server .*/server ntp.aliyun.com iburst/g' /etc/chrony.conf
systemctl enable chronyd.service
systemctl start chronyd.service
yum install python-openstackclient -y
read -p '输入控制节点ip以配置hosts ：' hosts
echo $hosts controller >> /etc/hosts
yum upgrade -y
echo -e '\n\n\e[32m####################系统环境配置完成####################\e[0m\n\n'
yum install openstack-nova-compute python2-qpid-proton -y
echo '[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:RABBIT_PASS@controller
my_ip = '$ip'
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver
[api]
auth_strategy = keystone
[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = NOVA_PASS
[vnc]
enabled = True
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html
[glance]
api_servers = http://controller:9292
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[placement]
os_region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = PLACEMENT_PASS
[libvirt]
virt_type = qemu' > /etc/nova/nova.conf
systemctl enable libvirtd.service openstack-nova-compute.service
systemctl start libvirtd.service openstack-nova-compute.service
echo -e '\n\n\e[32m####################Nova配置完成####################\e[0m\n\n'
yum install openstack-neutron-linuxbridge ebtables ipset -y
echo '[DEFAULT]
transport_url = rabbit://openstack:RABBIT_PASS@controller
auth_strategy = keystone
[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = NEUTRON_PASS
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp' > /etc/neutron/neutron.conf
echo '[linux_bridge]
physical_interface_mappings = provider:'$wk'
[vxlan]
enable_vxlan = false
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' > /etc/neutron/plugins/ml2/linuxbridge_agent.ini
echo '[neutron]
url = http://controller:9696
auth_url = http://controller:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRON_PASS' >> /etc/nova/nova.conf
systemctl restart openstack-nova-compute.service
systemctl enable neutron-linuxbridge-agent.service
systemctl start neutron-linuxbridge-agent.service
echo -e '\n\n\e[32m####################Neutron配置完成####################\e[0m\n\n'
echo -e '\n\n\e[31m如果出现nova无法启动的情况，等待控制节点nova安装完成执行    systemctl restart openstack-nova-compute.service    \e[0m\n\n'
bash
;;
4)
wk=$(ip r|grep via|cut -d ' ' -f 5)
ip=$(ifconfig $wk|grep netmask|awk '$1=$1'|cut -d ' ' -f 2)
ym=$(ip r|grep $ip|cut -d '/' -f 2|cut -d ' ' -f 1)
wg=$(ip r|grep via|cut -d ' ' -f 3)
sed -i -e 's/ONBOOT=.*/ONBOOT=yes/g' -e 's/BOOTPROTO=.*/BOOTPROTO=none/g' /etc/sysconfig/network-scripts/ifcfg-$wk
echo 'IPADDR='$ip'
PREFIX='$ym'
GATEWAY='$wg'
DNS1=114.114.114.114' >> /etc/sysconfig/network-scripts/ifcfg-$wk
systemctl restart network
;;
5)
wk=$(ip r|grep via|cut -d ' ' -f 5)
sed -i -e 's/ONBOOT=.*/ONBOOT=yes/g' -e 's/BOOTPROTO=.*/BOOTPROTO=dhcp/g' -e '/IPADDR=.*/d' -e '/GATEWAY=.*/d' -e '/PREFIX=.*/d' -e '/NETMASK=.*/d' -e '/DNS.*=.*/d' /etc/sysconfig/network-scripts/ifcfg-$wk
systemctl restart network
esac