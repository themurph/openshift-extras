#!/bin/sh

CONF_PREFIX="${CONF_PREFIX:-demo}"
CONF_DOMAIN="${CONF_PREFIX}.cloudydemo.com"
CONF_APPS_DOMAIN="apps.${CONF_PREFIX}.cloudydemo.com"

CONF_NO_NTP=true
# During a kickstart you can tail the log file showing %post execution
# by using the following command:
#    tailf /mnt/sysimage/root/anaconda-post.log

# You can use sed to extract just the %post section:
#    sed -e '0,/^%post/d;/^%end/,$d'
# Be sure to reboot after installation if using the %post this way.

# Log the command invocations (and not merely output) in order to make
# the log more useful.
set -x


########################################################################

# Synchronize the system clock to the NTP servers and then synchronize
# hardware clock with that.
synchronize_clock()
{
  # Synchronize the system clock using NTP.
  ntpdate clock.redhat.com

  # Synchronize the hardware clock to the system clock.
  hwclock --systohc
}


# Install SSH keys.  We hardcode a key used for internal OpenShift
# development, but the hardcoded key can be replaced with another or
# with a wget command to download a key from elsewhere.
install_ssh_keys()
{
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  cat >> /root/.ssh/authorized_keys << KEYS
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDkMc2jArUbWICi0071HXrt5uofQam11duqo5KEDWUZGtHuMTzuoZ0XEtzpqoRSidya9HjbJ5A4qUJBrvLZ07l0OIjENQ0Kvz83alVGFrEzVVUSZyiy6+yM9Ksaa/XAYUwCibfaFFqS9aVpVdY0qwaKrxX1ycTuYgNAw3WUvkHagdG54/79M8BUkat4uNiot0bKg6VLSI1QzNYV6cMJeOzz7WzHrJhbPrgXNKmgnAwIKQOkbATYB+YmDyHpA4m/O020dWDk9vWFmlxHLZqddCVGAXFyQnXoFTszFP4wTVOu1q2MSjtPexujYjTbBBxraKw9vrkE25YZJHvbZKMsNm2b libra_onprem
KEYS
}


configure_rhel_repo()
{
  # In order for the %post section to succeed, it must have a way of 
  # installing from RHEL. The post section cannot access the method that
  # was used in the base install. This configures a RHEL yum repo which
  # you must supply.
  cat > /etc/yum.repos.d/rhel.repo <<YUM
[rhel6]
name=RHEL 6 base OS
baseurl=${CONF_RHEL_REPO}
enabled=1
gpgcheck=0
sslverify=false
priority=2
sslverify=false
exclude=tomcat6*

YUM
}

configure_optional_repo()
{
  cat > /etc/yum.repos.d/rheloptional.repo <<YUM
[rhel6_optional]
name=RHEL 6 Optional
baseurl=${CONF_RHEL_OPTIONAL_REPO}
enabled=1
gpgcheck=0
sslverify=false
priority=2
sslverify=false

YUM
}

configure_client_tools_repo()
{
  # Enable repo with the puddle for broker packages.
  cat > /etc/yum.repos.d/openshift-client.repo <<YUM
[openshift_client]
name=OpenShift Client
baseurl=${CONF_REPOS_BASE}/Client/x86_64/os/
enabled=1
gpgcheck=0
sslverify=false
priority=1
sslverify=false

YUM
}

configure_broker_repo()
{
  # Enable repo with the puddle for broker packages.
  cat > /etc/yum.repos.d/openshift-infrastructure.repo <<YUM
[openshift_infrastructure]
name=OpenShift Infrastructure
baseurl=${CONF_REPOS_BASE}/Infrastructure/x86_64/os/
enabled=1
gpgcheck=0
sslverify=false
priority=1
sslverify=false

YUM
}

configure_node_repo()
{
  # Enable repo with the puddle for node packages.
  cat > /etc/yum.repos.d/openshift-node.repo <<YUM
[openshift_node]
name=OpenShift Node
baseurl=${CONF_REPOS_BASE}/Node/x86_64/os/
enabled=1
gpgcheck=0
sslverify=false
priority=1
sslverify=false

YUM
}

configure_jbosseap_cartridge_repo()
{
  # Enable repo with the puddle for the JBossEAP cartridge package.
  cat > /etc/yum.repos.d/openshift-jboss.repo <<YUM
[openshift_jbosseap]
name=OpenShift JBossEAP
baseurl=${CONF_REPOS_BASE}/JBoss_EAP6_Cartridge/x86_64/os/
enabled=1
gpgcheck=0
sslverify=false
priority=1
sslverify=false

YUM
}

configure_jbosseap_repo()
{
  # The JBossEAP cartridge depends on Red Hat's JBoss packages.

  if [ "x${CONF_JBOSS_REPO_BASE}" != "x" ]
  then
  ## configure JBossEAP repo
    cat <<YUM > /etc/yum.repos.d/jbosseap.repo
[jbosseap]
name=jbosseap
baseurl=${CONF_JBOSS_REPO_BASE}/jbeap/6/os
enabled=1
priority=3
gpgcheck=0
sslverify=false

YUM

  fi
}

configure_jbossews_repo()
{
  # The JBossEWS cartridge depends on Red Hat's JBoss packages.
  if [ "x${CONF_JBOSS_REPO_BASE}" != "x" ]
  then
  ## configure JBossEWS repo
    cat <<YUM > /etc/yum.repos.d/jbossews.repo
[jbossews]
name=jbossews
baseurl=${CONF_JBOSS_REPO_BASE}/jbews/2/os
enabled=1
priority=3
gpgcheck=0
sslverify=false

YUM

  fi
}

yum_install_or_exit()
{
  yum install $*
  if [ $? -ne 0 ]
  then
    echo "yum install failed; aborting installation. Please ensure you have configured the relevant repos/subscriptions."
    exit 1
  fi
}

# Install the client tools.
install_rhc_pkg()
{
  yum install -y rhc
  # set up the system express.conf so this broker will be used by default
  echo -e "\nlibra_server = '${broker_hostname}'" >> /etc/openshift/express.conf
}

# Install broker-specific packages.
install_broker_pkgs()
{
  pkgs="openshift-origin-broker"
  pkgs="$pkgs openshift-origin-broker-util"
  pkgs="$pkgs rubygem-openshift-origin-msg-broker-mcollective"
  pkgs="$pkgs rubygem-openshift-origin-auth-remote-user"
  pkgs="$pkgs rubygem-openshift-origin-dns-nsupdate"
  pkgs="$pkgs openshift-origin-console"

  yum_install_or_exit -y $pkgs
}

# Currently, ruby193-rubygem-passenger-native creates
# /usr/var/log/passenger-analytics as its log directory, but our
# software expects it to be at /var/log/passenger-analytics, and the
# broker doesn't work if this folder isn't present and
# accessible. This function fixes that.
fix_passenger()
{
  mkdir /var/log/passenger-analytics
  chmod 750 /var/log/passenger-analytics
  chown apache:apache /var/log/passenger-analytics
}

# Install node-specific packages.
install_node_pkgs()
{
  pkgs="rubygem-openshift-origin-node ruby193-rubygem-passenger-native"
  pkgs="$pkgs openshift-origin-port-proxy"
  pkgs="$pkgs openshift-origin-node-util"
  # We use semanage in this script, so we need to install
  # policycoreutils-python.
  pkgs="$pkgs policycoreutils-python"

  yum_install_or_exit -y $pkgs
}

# Install any cartridges developers may want.
install_cartridges()
{
  # Following are cartridge rpms that one may want to install here:
  if is_true "$node_v2_enable"
  then
    # Embedded cron support. This is required on node hosts.
    carts="openshift-origin-cartridge-cron"

    # diy app.
    carts="$carts openshift-origin-cartridge-diy"

    # haproxy support.
    carts="$carts openshift-origin-cartridge-haproxy"

    # JBossEWS support.
    # Note: Be sure to subscribe to the JBossEWS entitlements during the
    # base install or in configure_jbossews_repo.
    carts="$carts openshift-origin-cartridge-jbossews"
 
    # JBossEAP support.
    # Note: Be sure to subscribe to the JBossEAP entitlements during the
    # base install or in configure_jbosseap_repo.
    carts="$carts openshift-origin-cartridge-jbosseap"
 
    # Jenkins server for continuous integration.
    carts="$carts openshift-origin-cartridge-jenkins"
 
    # Embedded jenkins client.
    carts="$carts openshift-origin-cartridge-jenkins-client"
 
    # Embedded MySQL.
    carts="$carts openshift-origin-cartridge-mysql"
 
    # mod_perl support.
    carts="$carts openshift-origin-cartridge-perl"
  
    # PHP support.
    carts="$carts openshift-origin-cartridge-php"
  
    # Embedded PostgreSQL.
    carts="$carts openshift-origin-cartridge-postgresql"
  
    # Python support.
    carts="$carts openshift-origin-cartridge-python"
  
    # Ruby Rack support running on Phusion Passenger
    carts="$carts openshift-origin-cartridge-ruby"
  else
    # Embedded cron support. This is required on node hosts.
    carts="openshift-origin-cartridge-cron-1.4"

    # diy app.
    carts="$carts openshift-origin-cartridge-diy-0.1"

    # haproxy-1.4 support.
    carts="$carts openshift-origin-cartridge-haproxy-1.4"

    # JBossEWS1.0 support.
    # Note: Be sure to subscribe to the JBossEWS entitlements during the
    # base install or in configure_jbossews_repo.
    carts="$carts openshift-origin-cartridge-jbossews-1.0"

    # JBossEAP6.0 support.
    # Note: Be sure to subscribe to the JBossEAP entitlements during the
    # base install or in configure_jbosseap_repo.
    carts="$carts openshift-origin-cartridge-jbosseap-6.0"

    # Jenkins server for continuous integration.
    carts="$carts openshift-origin-cartridge-jenkins-1.4"

    # Embedded jenkins client.
    carts="$carts openshift-origin-cartridge-jenkins-client-1.4"

    # Embedded MySQL.
    carts="$carts openshift-origin-cartridge-mysql-5.1"

    # mod_perl support.
    carts="$carts openshift-origin-cartridge-perl-5.10"

    # PHP 5.3 support.
    carts="$carts openshift-origin-cartridge-php-5.3"

    # Embedded PostgreSQL.
    carts="$carts openshift-origin-cartridge-postgresql-8.4"

    # Python 2.6 support.
    carts="$carts openshift-origin-cartridge-python-2.6"

    # Ruby Rack support running on Phusion Passenger (Ruby 1.8).
    carts="$carts openshift-origin-cartridge-ruby-1.8"

    # Ruby Rack support running on Phusion Passenger (Ruby 1.9).
    carts="$carts openshift-origin-cartridge-ruby-1.9-scl"
  fi

  # When dependencies are missing, e.g. JBoss subscriptions,
  # still install as much as possible.
  carts="$carts --skip-broken"

  yum install -y $carts
}

# Fix up SELinux policy on the broker.
configure_selinux_policy_on_broker()
{
  # We combine these setsebool commands into a single semanage command
  # because separate commands take a long time to run.
  (
    # Allow console application to access executable and writable memory
    echo boolean -m --on httpd_execmem

    # Allow the broker to write files in the http file context.
    echo boolean -m --on httpd_unified

    # Allow the broker to access the network.
    echo boolean -m --on httpd_can_network_connect
    echo boolean -m --on httpd_can_network_relay

    # Enable some passenger-related permissions.
    #
    # The name may change at some future point, at which point we will
    # need to delete the httpd_run_stickshift line below and enable the
    # httpd_run_openshift line.
    echo boolean -m --on httpd_run_stickshift
    #echo boolean -m --on httpd_run_openshift

    # Allow the broker to communicate with the named service.
    echo boolean -m --on allow_ypbind
  ) | semanage -i -

  fixfiles -R ruby193-rubygem-passenger restore
  fixfiles -R ruby193-mod_passenger restore

  restorecon -rv /var/run
  # This should cover everything in the SCL, including passenger
  restorecon -rv /opt
}

# Fix up SELinux policy on the node.
configure_selinux_policy_on_node()
{
  # We combine these setsebool commands into a single semanage command
  # because separate commands take a long time to run.
  (
    # Allow the node to write files in the http file context.
    echo boolean -m --on httpd_unified

    # Allow the node to access the network.
    echo boolean -m --on httpd_can_network_connect
    echo boolean -m --on httpd_can_network_relay

    # Allow httpd on the node to read gear data.
    #
    # The name may change at some future point, at which point we will
    # need to delete the httpd_run_stickshift line below and enable the
    # httpd_run_openshift line.
    echo boolean -m --on httpd_run_stickshift
    #echo boolean -m --on httpd_run_openshift
    echo boolean -m --on httpd_read_user_content
    echo boolean -m --on httpd_enable_homedirs

    # Enable polyinstantiation for gear data.
    echo boolean -m --on allow_polyinstantiation
  ) | semanage -i -


  restorecon -rv /var/run
  restorecon -rv /usr/sbin/mcollectived /var/log/mcollective.log /var/run/mcollectived.pid
  restorecon -rv /var/lib/openshift /etc/openshift/node.conf /etc/httpd/conf.d/openshift
}

configure_pam_on_node()
{
  sed -i -e 's|pam_selinux|pam_openshift|g' /etc/pam.d/sshd

  for f in "runuser" "runuser-l" "sshd" "su" "system-auth-ac"
  do
    t="/etc/pam.d/$f"
    if ! grep -q "pam_namespace.so" "$t"
    then
      echo -e "session\t\trequired\tpam_namespace.so no_unmount_on_close" >> "$t"
    fi
  done

  # if the user does not exist on the system an error will show up in
  # /var/log/secure.
  user_list="root,adm,apache"
  for user in gdm activemq mongodb; do
      id -u "$user" >/dev/null 2>&1
      if [ X"$?" == X"0" ]; then
          user_list="${user_list},${user}"
      fi
  done
  echo "/tmp        \$HOME/.tmp/      user:iscript=/usr/sbin/oo-namespace-init ${user_list}" > /etc/security/namespace.d/tmp.conf
  echo "/dev/shm  tmpfs  tmpfs:mntopts=size=5M:iscript=/usr/sbin/oo-namespace-init ${user_list}" > /etc/security/namespace.d/shm.conf
}

configure_cgroups_on_node()
{
  cp -vf /opt/rh/ruby193/root/usr/share/gems/doc/openshift-origin-node-*/cgconfig.conf /etc/cgconfig.conf
  restorecon -rv /etc/cgconfig.conf
  mkdir -p /cgroup
  restorecon -rv /cgroup
  chkconfig cgconfig on
  chkconfig cgred on
  chkconfig openshift-cgroups on
}

configure_quotas_on_node()
{
  # Get the mountpoint for /var/lib/openshift (should be /).
  geardata_mnt=$(df -P /var/lib/openshift 2>/dev/null | tail -n 1 | awk '{ print $6 }')

  if ! [ x"$geardata_mnt" != x ]
  then
    echo 'Could not enable quotas for gear data: unable to determine mountpoint.'
  else
    # Enable user quotas for the device housing /var/lib/openshift.
    sed -i -e "/^[^[:blank:]]\\+[[:blank:]]\\+${geardata_mnt////\/\\+[[:blank:]]}/{/usrquota/! s/[[:blank:]]\\+/,usrquota&/4;}" /etc/fstab

    # Remount to get quotas enabled immediately.
    mount -o remount "${geardata_mnt}"

    # Generate user quota info for the mount point.
    quotacheck -cmug "${geardata_mnt}"

    # fix up selinux perms
    restorecon "${geardata_mnt}"aquota.user

    # (re)enable quotas
    quotaon "${geardata_mnt}"
  fi
}

# Turn some sysctl knobs.
configure_sysctl_on_node()
{
  # Increase kernel semaphores to accomodate many httpds.
  echo "kernel.sem = 250  32000 32  4096" >> /etc/sysctl.conf

  # Move ephemeral port range to accommodate app proxies.
  echo "net.ipv4.ip_local_port_range = 15000 35530" >> /etc/sysctl.conf

  # Increase the connection tracking table size.
  echo "net.netfilter.nf_conntrack_max = 1048576" >> /etc/sysctl.conf

  # Reload sysctl.conf to get the new settings.
  #
  # Note: We could add -e here to ignore errors that are caused by
  # options appearing in sysctl.conf that correspond to kernel modules
  # that are not yet loaded.  On the other hand, adding -e might cause
  # us to miss some important error messages.
  sysctl -p /etc/sysctl.conf
}


configure_sshd_on_node()
{
  # Configure sshd to pass the GIT_SSH environment variable through.
  echo 'AcceptEnv GIT_SSH' >> /etc/ssh/sshd_config

  # Up the limits on the number of connections to a given node.
  perl -p -i -e "s/^#MaxSessions .*$/MaxSessions 40/" /etc/ssh/sshd_config
  perl -p -i -e "s/^#MaxStartups .*$/MaxStartups 40/" /etc/ssh/sshd_config
}

# Configure MongoDB datastore.
configure_datastore()
{
  # Install MongoDB.
  yum_install_or_exit -y mongodb-server

  # Require authentication.
  perl -p -i -e "s/^#auth = .*$/auth = true/" /etc/mongodb.conf

  # Use a smaller default size for databases.
  if [ "x`fgrep smallfiles=true /etc/mongodb.conf`x" != "xsmallfiles=truex" ]
  then
    echo 'smallfiles=true' >> /etc/mongodb.conf
  fi

  # Iff mongod is running on a separate host from the broker, open up
  # the firewall to allow the broker host to connect.
  if broker
  then
    echo 'The broker and data store are on the same host.'
    echo 'Skipping firewall and mongod configuration;'
    echo 'mongod will only be accessible over localhost).'
  else
    echo 'The broker and data store are on separate hosts.'

    echo 'Configuring the firewall to allow connections to mongod...'
    lokkit --nostart --port=27017:tcp

    echo 'Configuring mongod to listen on external interfaces...'
    perl -p -i -e "s/^bind_ip = .*$/bind_ip = 0.0.0.0/" /etc/mongodb.conf
  fi

  # Configure mongod to start on boot.
  chkconfig mongod on

  # Start mongod so we can perform some administration now.
  service mongod start

  # The init script lies to us as of version 2.0.2-1.el6_3: The start 
  # and restart actions return before the daemon is ready to accept
  # connections (appears to take time to initialize the journal). Thus
  # we need the following to wait until the daemon is really ready.
  echo "Waiting for MongoDB to start ($(date +%H:%M:%S))..."
  while :
  do
    echo exit | mongo && break
    sleep 5
  done
  echo "MongoDB is ready! ($(date +%H:%M:%S))"

  if is_false "$CONF_NO_DATASTORE_AUTH_FOR_LOCALHOST"
  then
    # Add an administrative user and a user that the broker will use.
    mongo <<EOF
use admin
db.addUser("${mongodb_admin_user}", "${mongodb_admin_password}")

db.auth("${mongodb_admin_user}", "${mongodb_admin_password}")

use ${mongodb_name}
db.addUser("${mongodb_broker_user}", "${mongodb_broker_password}")
EOF
  else
    # Add a user that the broker will use.
    mongo <<EOF
use ${mongodb_name}
db.addUser("${mongodb_broker_user}", "${mongodb_broker_password}")
EOF
  fi
}


# Open up services required on the node for apps and developers.
configure_port_proxy()
{
  lokkit --nostart --port=35531-65535:tcp

  chkconfig openshift-port-proxy on
}

configure_gears()
{
  # Make sure that gears are restarted on reboot.
  chkconfig openshift-gears on
}


# Enable services to start on boot for the node.
enable_services_on_node()
{
  # We use --nostart below because activating the configuration here 
  # will produce errors.  Anyway, we only need the configuration 
  # activated Anaconda reboots, so --nostart makes sense in any case.

  lokkit --nostart --service=ssh
  lokkit --nostart --service=https
  lokkit --nostart --service=http

  # Allow connections to openshift-node-web-proxy
  lokkit --nostart --port=8000:tcp
  lokkit --nostart --port=8443:tcp

  chkconfig httpd on
  chkconfig network on
  is_false "$CONF_NO_NTP" && chkconfig ntpd on
  chkconfig sshd on
  chkconfig oddjobd on
  chkconfig openshift-node-web-proxy on
}


# Enable services to start on boot for the broker and fix up some issues.
enable_services_on_broker()
{
  # We use --nostart below because activating the configuration here 
  # will produce errors.  Anyway, we only need the configuration 
  # activated after Anaconda reboots, so --nostart makes sense.

  lokkit --nostart --service=ssh
  lokkit --nostart --service=https
  lokkit --nostart --service=http

  chkconfig httpd on
  chkconfig network on
  is_false "$CONF_NO_NTP" && chkconfig ntpd on
  chkconfig sshd on

  # Remove VirtualHost from the default ssl.conf to prevent a warning
   sed -i '/VirtualHost/,/VirtualHost/ d' /etc/httpd/conf.d/ssl.conf

  # make sure mcollective client log is created with proper ownership.
  # if root owns it, the broker (apache user) can't log to it.
  touch /var/log/mcollective-client.log
  chown apache:root /var/log/mcollective-client.log
}


# Configure mcollective on the broker to use qpid.
configure_mcollective_for_qpid_on_broker()
{
  yum_install_or_exit -y mcollective-client

  cat <<EOF > /etc/mcollective/client.cfg
topicprefix = /topic/
main_collective = mcollective
collectives = mcollective
libdir = /opt/rh/ruby193/root/usr/libexec/mcollective
loglevel = debug
logfile = /var/log/mcollective-client.log

# Plugins
securityprovider = psk
plugin.psk = unset
connector = qpid
plugin.qpid.host = ${broker_hostname}
plugin.qpid.secure = false
plugin.qpid.timeout = 5

# Facts
factsource = yaml
plugin.yaml = /etc/mcollective/facts.yaml
EOF

}


# Configure mcollective on the broker to use qpid.
configure_mcollective_for_qpid_on_node()
{
  yum_install_or_exit -y mcollective openshift-origin-msg-node-mcollective

  cat <<EOF > /etc/mcollective/server.cfg
topicprefix = /topic/
main_collective = mcollective
collectives = mcollective
libdir = /opt/rh/ruby193/root/usr/libexec/mcollective
logfile = /var/log/mcollective.log
loglevel = debug
daemonize = 1
direct_addressing = n

# Plugins
securityprovider = psk
plugin.psk = unset
connector = qpid
plugin.qpid.host = ${broker_hostname}
plugin.qpid.secure = false
plugin.qpid.timeout = 5

# Facts
factsource = yaml
plugin.yaml = /etc/mcollective/facts.yaml
EOF

  chkconfig mcollective on
}


# Configure mcollective on the broker to use ActiveMQ.
configure_mcollective_for_activemq_on_broker()
{
  yum_install_or_exit -y mcollective-client

  cat <<EOF > /etc/mcollective/client.cfg
topicprefix = /topic/
main_collective = mcollective
collectives = mcollective
libdir = /opt/rh/ruby193/root/usr/libexec/mcollective
logfile = /var/log/mcollective-client.log
loglevel = debug

# Plugins
securityprovider=psk
plugin.psk=unset

connector = stomp
plugin.stomp.host = ${activemq_hostname}
plugin.stomp.port = 61613
plugin.stomp.user = ${mcollective_user}
plugin.stomp.password = ${mcollective_password}
EOF
}


# Configure mcollective on the node to use ActiveMQ.
configure_mcollective_for_activemq_on_node()
{
  yum_install_or_exit -y mcollective openshift-origin-msg-node-mcollective

  cat <<EOF > /etc/mcollective/server.cfg
topicprefix = /topic/
main_collective = mcollective
collectives = mcollective
libdir = /opt/rh/ruby193/root/usr/libexec/mcollective
logfile = /var/log/mcollective.log
loglevel = debug
daemonize = 1
direct_addressing = n
registerinterval = 30

# Plugins
securityprovider = psk
plugin.psk = unset

connector = stomp
plugin.stomp.host = ${activemq_hostname}
plugin.stomp.port = 61613
plugin.stomp.user = ${mcollective_user}
plugin.stomp.password = ${mcollective_password}

# Facts
factsource = yaml
plugin.yaml = /etc/mcollective/facts.yaml
EOF

  chkconfig mcollective on
}


# Configure ActiveMQ.
configure_activemq()
{
  # Install the service.
  yum_install_or_exit -y activemq

  cat <<EOF > /etc/activemq/activemq.xml
<!--
    Licensed to the Apache Software Foundation (ASF) under one or more
    contributor license agreements.  See the NOTICE file distributed with
    this work for additional information regarding copyright ownership.
    The ASF licenses this file to You under the Apache License, Version 2.0
    (the "License"); you may not use this file except in compliance with
    the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
-->
<beans
  xmlns="http://www.springframework.org/schema/beans"
  xmlns:amq="http://activemq.apache.org/schema/core"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans-2.0.xsd
  http://activemq.apache.org/schema/core http://activemq.apache.org/schema/core/activemq-core.xsd">

    <!-- Allows us to use system properties as variables in this configuration file -->
    <bean class="org.springframework.beans.factory.config.PropertyPlaceholderConfigurer">
        <property name="locations">
            <value>file:\${activemq.conf}/credentials.properties</value>
        </property>
    </bean>

    <!--
        The <broker> element is used to configure the ActiveMQ broker.
    -->
    <broker xmlns="http://activemq.apache.org/schema/core" brokerName="${activemq_hostname}" dataDirectory="\${activemq.data}">

        <!--
            For better performances use VM cursor and small memory limit.
            For more information, see:

            http://activemq.apache.org/message-cursors.html

            Also, if your producer is "hanging", it's probably due to producer flow control.
            For more information, see:
            http://activemq.apache.org/producer-flow-control.html
        -->

        <destinationPolicy>
            <policyMap>
              <policyEntries>
                <policyEntry topic=">" producerFlowControl="true" memoryLimit="1mb">
                  <pendingSubscriberPolicy>
                    <vmCursor />
                  </pendingSubscriberPolicy>
                </policyEntry>
                <policyEntry queue=">" producerFlowControl="true" memoryLimit="1mb">
                  <!-- Use VM cursor for better latency
                       For more information, see:

                       http://activemq.apache.org/message-cursors.html

                  <pendingQueuePolicy>
                    <vmQueueCursor/>
                  </pendingQueuePolicy>
                  -->
                </policyEntry>
              </policyEntries>
            </policyMap>
        </destinationPolicy>


        <!--
            The managementContext is used to configure how ActiveMQ is exposed in
            JMX. By default, ActiveMQ uses the MBean server that is started by
            the JVM. For more information, see:

            http://activemq.apache.org/jmx.html
        -->
        <managementContext>
            <managementContext createConnector="false"/>
        </managementContext>

        <!--
            Configure message persistence for the broker. The default persistence
            mechanism is the KahaDB store (identified by the kahaDB tag).
            For more information, see:

            http://activemq.apache.org/persistence.html
        -->
        <persistenceAdapter>
            <kahaDB directory="\${activemq.data}/kahadb"/>
        </persistenceAdapter>

        <!-- add users for mcollective -->

        <plugins>
          <statisticsBrokerPlugin/>
          <simpleAuthenticationPlugin>
             <users>
               <authenticationUser username="${mcollective_user}" password="${mcollective_password}" groups="mcollective,everyone"/>
               <authenticationUser username="admin" password="${activemq_admin_password}" groups="mcollective,admin,everyone"/>
             </users>
          </simpleAuthenticationPlugin>
          <authorizationPlugin>
            <map>
              <authorizationMap>
                <authorizationEntries>
                  <authorizationEntry queue=">" write="admins" read="admins" admin="admins" />
                  <authorizationEntry topic=">" write="admins" read="admins" admin="admins" />
                  <authorizationEntry topic="mcollective.>" write="mcollective" read="mcollective" admin="mcollective" />
                  <authorizationEntry queue="mcollective.>" write="mcollective" read="mcollective" admin="mcollective" />
                  <authorizationEntry topic="ActiveMQ.Advisory.>" read="everyone" write="everyone" admin="everyone"/>
                </authorizationEntries>
              </authorizationMap>
            </map>
          </authorizationPlugin>
        </plugins>

          <!--
            The systemUsage controls the maximum amount of space the broker will
            use before slowing down producers. For more information, see:
            http://activemq.apache.org/producer-flow-control.html
            If using ActiveMQ embedded - the following limits could safely be used:

        <systemUsage>
            <systemUsage>
                <memoryUsage>
                    <memoryUsage limit="20 mb"/>
                </memoryUsage>
                <storeUsage>
                    <storeUsage limit="1 gb"/>
                </storeUsage>
                <tempUsage>
                    <tempUsage limit="100 mb"/>
                </tempUsage>
            </systemUsage>
        </systemUsage>
        -->
          <systemUsage>
            <systemUsage>
                <memoryUsage>
                    <memoryUsage limit="64 mb"/>
                </memoryUsage>
                <storeUsage>
                    <storeUsage limit="100 gb"/>
                </storeUsage>
                <tempUsage>
                    <tempUsage limit="50 gb"/>
                </tempUsage>
            </systemUsage>
        </systemUsage>

        <!--
            The transport connectors expose ActiveMQ over a given protocol to
            clients and other brokers. For more information, see:

            http://activemq.apache.org/configuring-transports.html
        -->
        <transportConnectors>
            <transportConnector name="openwire" uri="tcp://0.0.0.0:61616"/>
            <transportConnector name="stomp" uri="stomp://0.0.0.0:61613"/>
        </transportConnectors>

    </broker>

    <!--
        Enable web consoles, REST and Ajax APIs and demos

        Take a look at \${ACTIVEMQ_HOME}/conf/jetty.xml for more details
    -->
    <import resource="jetty.xml"/>

</beans>
<!-- END SNIPPET: example -->
EOF

  # secure the ActiveMQ console
  sed -i -e '/name="authenticate"/s/false/true/' /etc/activemq/jetty.xml

  # only add the host property if it's not already there
  # (so you can run the script multiple times)
  grep '<property name="host" value="127.0.0.1" />' /etc/activemq/jetty.xml > /dev/null
  if [ $? -ne 0 ]; then
    sed -i -e '/name="port"/a<property name="host" value="127.0.0.1" />' /etc/activemq/jetty.xml
  fi

  sed -i -e "/admin:/s/admin,/${activemq_admin_password},/" /etc/activemq/jetty-realm.properties


  # Allow connections to ActiveMQ.
  lokkit --nostart --port=61613:tcp

  # Configure ActiveMQ to start on boot.
  chkconfig activemq on
}


# Configure qpid. Deprecated for ActiveMQ.
configure_qpid()
{
  if [[ "x`fgrep auth= /etc/qpidd.conf`" == xauth* ]]
  then
    sed -i -e 's/auth=yes/auth=no/' /etc/qpidd.conf
  else
    echo "auth=no" >> /etc/qpidd.conf
  fi

  # Allow connections to qpidd.
  lokkit --nostart --port=5672:tcp

  # Configure qpidd to start on boot.
  chkconfig qpidd on
}


# Configure BIND.
configure_named()
{
  yum_install_or_exit -y bind bind-utils

  # $keyfile will contain a new DNSSEC key for our domain.
  keyfile=/var/named/${domain}.key

  if [ "x$bind_key" = x ]
  then
    # Generate the new key for the domain.
    pushd /var/named
    rm -f /var/named/K${domain}*
    dnssec-keygen -a HMAC-MD5 -b 512 -n USER -r /dev/urandom ${domain}
    bind_key="$(grep Key: K${domain}*.private | cut -d ' ' -f 2)"
    popd
  fi

  # Ensure we have a key for service named status to communicate with BIND.
  rndc-confgen -a -r /dev/urandom
  restorecon /etc/rndc.* /etc/named.*
  chown root:named /etc/rndc.key
  chmod 640 /etc/rndc.key

  # Set up DNS forwarding.
  cat <<EOF > /var/named/forwarders.conf
forwarders { ${nameservers} } ;
EOF
  restorecon /var/named/forwarders.conf
  chmod 644 /var/named/forwarders.conf

  # Install the configuration file for the OpenShift Enterprise domain
  # name.
  rm -rf /var/named/dynamic
  mkdir -p /var/named/dynamic


  # Create the initial BIND database.
  nsdb=/var/named/dynamic/${domain}.db
  cat <<EOF > $nsdb
\$ORIGIN .
\$TTL 1	; 1 seconds (for testing only)
${domain}		IN SOA	${named_hostname}. hostmaster.${domain}. (
				2011112904 ; serial
				60         ; refresh (1 minute)
				15         ; retry (15 seconds)
				1800       ; expire (30 minutes)
				10         ; minimum (10 seconds)
				)
			NS	${named_hostname}.
			MX	10 mail.${domain}.
\$ORIGIN ${domain}.
${named_hostname%.${domain}}			A	${named_ip_addr}
EOF

  # Add A records any other components that are being installed locally.
  broker && echo "${broker_hostname%.${domain}}			A	${broker_ip_addr}" >> $nsdb
  node && echo "${node_hostname%.${domain}}			A	${node_ip_addr}${nl}" >> $nsdb
  activemq && echo "${activemq_hostname%.${domain}}			A	${cur_ip_addr}${nl}" >> $nsdb
  datastore && echo "${datastore_hostname%.${domain}}			A	${cur_ip_addr}${nl}" >> $nsdb
  echo >> $nsdb

  # Install the key for the OpenShift Enterprise domain.
  cat <<EOF > /var/named/${domain}.key
key ${domain} {
  algorithm HMAC-MD5;
  secret "${bind_key}";
};
EOF

  chown named:named -R /var/named
  restorecon -rv /var/named

  # Replace named.conf.
  cat <<EOF > /etc/named.conf
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//

options {
	listen-on port 53 { any; };
	directory 	"/var/named";
	dump-file 	"/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
	allow-query     { any; };
	recursion yes;

	/* Path to ISC DLV key */
	bindkeys-file "/etc/named.iscdlv.key";

	// set forwarding to the next nearest server (from DHCP response
	forward only;
        include "forwarders.conf";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

// use the default rndc key
include "/etc/rndc.key";
 
controls {
	inet 127.0.0.1 port 953
	allow { 127.0.0.1; } keys { "rndc-key"; };
};

include "/etc/named.rfc1912.zones";

include "${domain}.key";

zone "${domain}" IN {
	type master;
	file "dynamic/${domain}.db";
	allow-update { key ${domain} ; } ;
};
EOF
  chown root:named /etc/named.conf
  chcon system_u:object_r:named_conf_t:s0 -v /etc/named.conf

  # Configure named to start on boot.
  lokkit --nostart --service=dns
  chkconfig named on

  # Start named so we can perform some updates immediately.
  service named start
}


# Make resolv.conf point to our named service, which will resolve the
# host names used in this installation of OpenShift.  Our named service
# will forward other requests to some other DNS servers.
update_resolv_conf()
{
  # Update resolv.conf to use our named.
  #
  # We will keep any existing entries so that we have fallbacks that
  # will resolve public addresses even when our private named is
  # nonfunctional.  However, our private named must appear first in
  # order for hostnames private to our OpenShift PaaS to resolve.
  sed -i -e "1i# The named we install for our OpenShift PaaS must appear first.\\nnameserver ${named_ip_addr}\\n" /etc/resolv.conf
}


# Update the controller configuration.
configure_controller()
{
  if [ "x$broker_auth_salt" = "x" ]
  then
    echo "Warning: broker authentication salt is empty!"
  fi

  # Configure the console with the correct domain
  sed -i -e "s/^DOMAIN_SUFFIX=.*$/DOMAIN_SUFFIX=${domain}/" \
      /etc/openshift/console.conf

  # Configure the broker with the correct hostname, and use random salt
  # to the data store (the host running MongoDB).
  sed -i -e "s/^CLOUD_DOMAIN=.*$/CLOUD_DOMAIN=${domain}/" \
      /etc/openshift/broker.conf
  echo AUTH_SALT=${broker_auth_salt} >> /etc/openshift/broker.conf

  # Configure the session secret for the broker
  sed -i -e "s/# SESSION_SECRET=.*$/SESSION_SECRET=${broker_session_secret}/" \
      /etc/openshift/broker.conf

  # Configure the session secret for the console
  if [ `grep -c SESSION_SECRET /etc/openshift/console.conf` -eq 0 ]
  then
    echo "SESSION_SECRET=${console_session_secret}" >> /etc/openshift/console.conf
  fi

  if ! datastore
  then
    #mongo not installed locally, so point to given hostname
    sed -i -e "s/^MONGO_HOST_PORT=.*$/MONGO_HOST_PORT=\"${datastore_hostname}:27017\"/" /etc/openshift/broker.conf
  fi

  # configure MongoDB access
  sed -i -e "s/MONGO_PASSWORD=.*$/MONGO_PASSWORD=\"${mongodb_broker_password}\"/
            s/MONGO_USER=.*$/MONGO_USER=\"${mongodb_broker_user}\"/
            s/MONGO_DB=.*$/MONGO_DB=\"${mongodb_name}\"/" \
      /etc/openshift/broker.conf

  # Configure the broker service to start on boot.
  chkconfig openshift-broker on
  chkconfig openshift-console on
}

# Configure the broker to use the remote-user authentication plugin.
configure_remote_user_auth_plugin()
{
  cp /etc/openshift/plugins.d/openshift-origin-auth-remote-user.conf{.example,}
}

# Configure the broker to use the MongoDB-based authentication plugin.
#
# NB: It is assumed that configure_datastore has previously been run on
# this host to install and configure MongoDB.
configure_mongo_auth_plugin()
{
  cp /etc/openshift/plugins.d/openshift-origin-auth-mongo.conf{.example,}

  if ! datastore
  then
    # MongoDB is running on a remote host, so we must modify the
    # plug-in configuration to point it to that host.
    sed -i -e "s/^MONGO_HOST_PORT=.*$/MONGO_HOST_PORT=\"${datastore_hostname}:27017\"/" /etc/openshift/plugins.d/openshift-origin-auth-mongo.conf
  fi

  # We must specify the --host, --username, and --password options iff the
  # datastore is being installed on the current host.
  if datastore
  then
    mongo_opts=""
  else
    mongo_opts="--host ${datastore_hostname} --username openshift --password mooo"
  fi

  # The init script is broken as of version 2.0.2-1.el6_3: The start 
  # and restart actions return before the daemon is ready to accept
  # connections (it appears to take time to initialize the journal).
  # Thus we need the following hack to wait until the daemon is ready.
  echo "Waiting for MongoDB to start ($(date +%H:%M:%S))..."
  while :
  do
    echo exit | mongo $mongo_opts && break
    sleep 5
  done
  echo "MongoDB is ready! ($(date +%H:%M:%S))"

  hashed_password="$(printf 'admin' | md5sum -b | cut -d' ' -f1)"
  hashed_salted_password="$(printf '%s' "$hashed_password$broker_auth_salt" | md5sum | cut -d' ' -f1)"

  # Add user "admin" with password "admin" for oo-register-user.
  mongo $mongodb_name $mongo_opts --eval 'db.auth_user.update({"_id":"admin"}, {"_id":"admin","user":"admin","password":"'"$hashed_salted_password"'"}, true)'
}

configure_messaging_plugin()
{
  cp /etc/openshift/plugins.d/openshift-origin-msg-broker-mcollective.conf{.example,}
}

# Configure the broker to use the BIND DNS plug-in.
configure_dns_plugin()
{
  if [ "x$bind_key" = x ]
  then
    echo 'WARNING: No key has been set for communication with BIND.'
    echo 'You will need to modify the value of BIND_KEYVALUE in'
    echo '/etc/openshift/plugins.d/openshift-origin-dns-nsupdate.conf'
    echo 'after installation.'
  fi

  mkdir -p /etc/openshift/plugins.d
  cat <<EOF > /etc/openshift/plugins.d/openshift-origin-dns-nsupdate.conf
BIND_SERVER="${named_ip_addr}"
BIND_PORT=53
BIND_KEYNAME="${domain}"
BIND_KEYVALUE="${bind_key}"
BIND_ZONE="${domain}"
EOF
}

# Configure httpd for authentication.
configure_httpd_auth()
{
  # Install the Apache configuration file.
  cp /var/www/openshift/broker/httpd/conf.d/openshift-origin-auth-remote-user-basic.conf.sample \
     /var/www/openshift/broker/httpd/conf.d/openshift-origin-auth-remote-user.conf

  cp /var/www/openshift/console/httpd/conf.d/openshift-origin-auth-remote-user-basic.conf.sample \
     /var/www/openshift/console/httpd/conf.d/openshift-origin-auth-remote-user.conf

  # The above configuration file configures Apache to use
  # /etc/openshift/htpasswd for its password file.
  #
  # Here we create a test user:
  htpasswd -bc /etc/openshift/htpasswd "$openshift_user1" "$openshift_password1"
  #
  # Use the following command to add more users:
  #
  #  htpasswd /etc/openshift/htpasswd username

  # TODO: In the future, we will want to edit
  # /etc/openshift/plugins.d/openshift-origin-auth-remote-user.conf to
  # put in a random salt.
}

# if the broker and node are on the same machine we need to manually update the
# nodes.db
fix_broker_routing()
{
  cat <<EOF >> /var/lib/openshift/.httpd.d/nodes.txt
__default__ REDIRECT:/console
__default__/console TOHTTPS:127.0.0.1:8118/console
__default__/broker TOHTTPS:127.0.0.1:8080/broker
EOF

  httxt2dbm -f DB -i /etc/httpd/conf.d/openshift/nodes.txt -o /etc/httpd/conf.d/openshift/nodes.db
  chown root:apache /etc/httpd/conf.d/openshift/nodes.txt /etc/httpd/conf.d/openshift/nodes.db
  chmod 750 /etc/httpd/conf.d/openshift/nodes.txt /etc/httpd/conf.d/openshift/nodes.db
}

configure_access_keys_on_broker()
{
  # Generate a broker access key for remote apps (Jenkins) to access 
  # the broker.
  openssl genrsa -out /etc/openshift/server_priv.pem 2048
  openssl rsa -in /etc/openshift/server_priv.pem -pubout > /etc/openshift/server_pub.pem

  # If a key pair already exists, delete it so that the ssh-keygen
  # command will not have to ask the user what to do.
  rm -f /root/.ssh/rsync_id_rsa /root/.ssh/rsync_id_rsa.pub

  # Generate a key pair for moving gears between nodes from the broker
  ssh-keygen -t rsa -b 2048 -P "" -f /root/.ssh/rsync_id_rsa
  cp ~/.ssh/rsync_id_rsa* /etc/openshift/
  # the .pub key needs to go on nodes, but there is no good way
  # to script that generically. Nodes should not have password-less 
  # access to brokers to copy the .pub key, but this can be performed
  # manually:
  #   # scp root@broker:/etc/openshift/rsync_id_rsa.pub /root/.ssh/
  # the above step will ask for the root password of the broker machine
  #   # cat /root/.ssh/rsync_id_rsa.pub >> /root/.ssh/authorized_keys
  #   # rm /root/.ssh/rsync_id_rsa.pub
}

configure_wildcard_ssl_cert_on_node()
{
  # Generate a 2048 bit key and self-signed cert
  cat << EOF | openssl req -new -rand /dev/urandom \
	-newkey rsa:2048 -nodes -keyout /etc/pki/tls/private/localhost.key \
	-x509 -days 3650 -extensions v3_req \
	-out /etc/pki/tls/certs/localhost.crt 2> /dev/null
XX
SomeState
SomeCity
SomeOrganization
SomeOrganizationalUnit
*.${domain}
root@${domain}
EOF

  # Generate a cert signing request (example)
  #openssl req -new -in /etc/pki/tls/private/localhost.key -out /etc/pki/tls/certs/localhost.csr
}

configure_broker_ssl_cert()
{
  # Generate a 2048 bit key and self-signed cert
  cat << EOF | openssl req -new -rand /dev/urandom \
	-newkey rsa:2048 -nodes -keyout /etc/pki/tls/private/localhost.key \
	-x509 -days 3650 -extensions v3_req \
	-out /etc/pki/tls/certs/localhost.crt 2> /dev/null
XX
SomeState
SomeCity
SomeOrganization
SomeOrganizationalUnit
${broker_hostname}
root@${domain}
EOF
}

# Configure IP address and hostname.
configure_network()
{
  # Append some stuff to the DHCP configuration.
  cat <<EOF >> /etc/dhcp/dhclient-eth0.conf

prepend domain-name-servers ${named_ip_addr};
supersede host-name "${hostname%.${domain}}";
supersede domain-name "${domain}";
prepend domain-search "${domain}";
EOF
}

# Set the hostname
configure_hostname()
{
  sed -i -e "s/HOSTNAME=.*/HOSTNAME=${hostname}/" /etc/sysconfig/network
  hostname "${hostname}"
}

# Set some parameters in the OpenShift node configuration file.
configure_node()
{
  sed -i -e "s/^PUBLIC_IP=.*$/PUBLIC_IP=${node_ip_addr}/;
             s/^CLOUD_DOMAIN=.*$/CLOUD_DOMAIN=${domain}/;
             s/^PUBLIC_HOSTNAME=.*$/PUBLIC_HOSTNAME=${hostname}/;
             s/^BROKER_HOST=.*$/BROKER_HOST=${broker_hostname}/" \
      /etc/openshift/node.conf

  echo $broker_hostname > /etc/openshift/env/OPENSHIFT_BROKER_HOST
  echo $domain > /etc/openshift/env/OPENSHIFT_CLOUD_DOMAIN

  if is_true "$node_v2_enable"
  then
    mkdir -p /var/lib/openshift/.settings
    touch /var/lib/openshift/.settings/v2_cartridge_format
  fi
}

# Run the cronjob installed by openshift-origin-msg-node-mcollective immediately
# to regenerate facts.yaml.
update_openshift_facts_on_node()
{
  /etc/cron.minutely/openshift-facts
}

echo_installation_intentions()
{
  echo "The following components should be installed:"
  for component in $components
  do
    if eval $component
    then
      printf '\t%s.\n' $component
    fi
  done

  echo "Configuring with broker with hostname ${broker_hostname}."
  node && echo "Configuring node with hostname ${node_hostname}."
  echo "Configuring with named with IP address ${named_ip_addr}."
  broker && echo "Configuring with datastore with hostname ${datastore_hostname}."
  echo "Configuring with activemq with hostname ${activemq_hostname}."
}

# Modify console message to show install info
configure_console_msg()
{
  # add the IP to /etc/issue for convenience
  echo "Install-time IP address: ${cur_ip_addr}" >> /etc/issue
  echo_installation_intentions >> /etc/issue
  echo "Check /root/anaconda-post.log to see the %post output." >> /etc/issue
  echo >> /etc/issue
}



########################################################################

#
# Parse the kernel command-line, define variables with the parameters
# specified on it, and define functions broker() and node(), which
# return true or false as appropriate based on whether we are
# configuring the host as a broker or as a node.
#

# Parse /proc/cmdline so that from, e.g., "foo=bar baz" we get
# CONF_FOO=bar and CONF_BAZ=true in the environment.
parse_cmdline()
{
  for word in $(cat /proc/cmdline)
  do
    key="${word%%\=*}"
    case "$word" in
      (*=*) val="${word#*\=}" ;;
      (*) val=true ;;
    esac
    eval "CONF_${key^^}"'="$val"'
  done
}

is_true()
{
  for arg
  do
    [[ x$arg =~ x(1|true) ]] || return 1
  done

  return 0
}

is_false()
{
  for arg
  do
    [[ x$arg =~ x(1|true) ]] || return 0
  done

  return 1
}

# For each component, this function defines a constant function that
# returns either true or false.  For example, there will be a named
# function indicating whether we are currently installing the named
# service.  We can use 'if named; then ...; fi' or just 'named && ...'
# to run the given commands if, and only if, named is being installed
# on this host.
#
# The following functions will be defined:
#
#   activemq
#   broker
#   datastore
#   named
#   node
#
# For each component foo, we also set a $foo_hostname variable with the
# hostname for that logical host.  We use hostnames in configuration
# files wherever possible.  The only places where this is not possible
# is where we are referencing the named service; in such places, we use
# $named_ip_addr, which is also set by this function.  It is possible
# that one host runs multiple services, in which case more than one
# hostname will resolve to the same IP address.
#
# We also set the $domain variable, which is the domain that will be
# used when configuring BIND and assigning hostnames for the various
# hosts in the OpenShift PaaS.
#
# We also set the $repos_base variable with the base URL for the yum
# repositories that will be used to download OpenShift RPMs.  The value
# of this variable can be changed to use a custom repository or puddle.
#
# We also set the $cur_ip_addr variable to the IP address of the host
# running this script, based on the output of the `ip addr show` command
#
# In addition, the $nameservers variable will be set to
# a semicolon-delimited list of nameservers, suitable for use in
# named.conf, based on the existing contents of /etc/resolv.conf, and
# the $bind_key variable will be set to the value of CONF_BIND_KEY.
#
# The following variables will be defined:
#
#   activemq_hostname
#   bind_key
#   broker_hostname
#   cur_ip_addr
#   domain
#   datastore_hostname
#   named_hostname
#   named_ip_addr
#   nameservers
#   node_hostname
#   repos_base
#
# This function makes use of variables that may be set by parse_cmdline
# based on the content of /proc/cmdline or may be hardcoded by modifying
# this file.  All of these variables are optional; best attempts are
# made at determining reasonable defaults.
#
# The following variables are used:
#
#   CONF_ACTIVEMQ_HOSTNAME
#   CONF_BIND_KEY
#   CONF_BROKER_HOSTNAME
#   CONF_BROKER_IP_ADDR
#   CONF_DATASTORE_HOSTNAME
#   CONF_DOMAIN
#   CONF_INSTALL_COMPONENTS
#   CONF_NAMED_HOSTNAME
#   CONF_NAMED_IP_ADDR
#   CONF_NODE_HOSTNAME
#   CONF_NODE_IP_ADDR
#   CONF_NODE_V2_ENABLE
#   CONF_REPOS_BASE
set_defaults()
{
  # Following are the different components that can be installed:
  components='broker node named activemq datastore'

  # By default, each component is _not_ installed.
  for component in $components
  do
    eval "$component() { false; }"
  done

  # But any or all components may be explicity enabled.
  for component in ${CONF_INSTALL_COMPONENTS//,/ }
  do
    eval "$component() { :; }"
  done

  # If nothing is explicitly enabled, enable everything.
  installing_something=0
  for component in $components
  do
    if eval $component
    then
      installing_something=1
      break
    fi
  done
  if [ $installing_something = 0 ]
  then
    for component in $components
    do
      eval "$component() { :; }"
    done
  fi

  # Following are some settings used in subsequent steps.

  # Where to find the OpenShift repositories; just the base part before
  # splitting out into Infrastructure/Node/etc.
  repos_base_default='https://mirror.openshift.com/pub/origin-server/nightly/enterprise/2012-11-15'
  repos_base="${CONF_REPOS_BASE:-${repos_base_default}}"

  # There a no defaults for these. Customers should be using 
  # subscriptions via RHN. Internally we use private systems.
  rhel_repo="$CONF_RHEL_REPO"
  jboss_repo_base="$CONF_JBOSS_REPO_BASE"
  rhel_optional_repo="$CONF_RHEL_OPTIONAL_REPO"

  # The domain name for the OpenShift Enterprise installation.
  domain="${CONF_DOMAIN:-example.com}"

  # hostnames to use for the components (could all resolve to same host)
  broker_hostname="${CONF_BROKER_HOSTNAME:-broker.${domain}}"
  node_hostname="${CONF_NODE_HOSTNAME:-node.${domain}}"
  named_hostname="${CONF_NAMED_HOSTNAME:-ns1.${domain}}"
  activemq_hostname="${CONF_ACTIVEMQ_HOSTNAME:-activemq.${domain}}"
  datastore_hostname="${CONF_DATASTORE_HOSTNAME:-datastore.${domain}}"

  # The hostname name for this host.
  # Note: If this host is, e.g., both a broker and a datastore, we want
  # to go with the broker hostname and not the datastore hostname.
  if broker
  then hostname="$broker_hostname"
  elif node
  then hostname="$node_hostname"
  elif named
  then hostname="$named_hostname"
  elif activemq
  then hostname="$activemq_hostname"
  elif datastore
  then hostname="$datastore_hostname"
  fi

  # Grab the IP address set during installation.
  cur_ip_addr="$(/sbin/ip addr show dev eth0 | awk '/inet / { split($2,a,"/"); print a[1]; }')"

  # Unless otherwise specified, the broker is assumed to be the current
  # host.
  broker_ip_addr="${CONF_BROKER_IP_ADDR:-$cur_ip_addr}"

  # Unless otherwise specified, the node is assumed to be the current
  # host.
  node_ip_addr="${CONF_NODE_IP_ADDR:-$cur_ip_addr}"

  node_v2_enable="${CONF_NODE_V2_ENABLE:-false}"

  # Unless otherwise specified, the named service, data store, and
  # ActiveMQ service are assumed to be the current host if we are
  # installing the component now or the broker host otherwise.
  if named
  then
    named_ip_addr="${CONF_NAMED_IP_ADDR:-$cur_ip_addr}"
  else
    named_ip_addr="${CONF_NAMED_IP_ADDR:-$broker_ip_addr}"
  fi

  # The nameservers to which named on the broker will forward requests.
  # This should be a list of IP addresses with a semicolon after each.
  nameservers="$(awk '/nameserver/ { printf "%s; ", $2 }' /etc/resolv.conf)"

  # Set $bind_key to the value of $CONF_BIND_KEY if the latter is
  # non-empty.
  [ "x$CONF_BIND_KEY" != x ] && bind_key="$CONF_BIND_KEY"

  # Generate a random salt for the broker authentication.
  randomized=$(openssl rand -base64 20)
  broker && broker_auth_salt="${CONF_BROKER_AUTH_SALT:-${randomized}}"

  # Generate a random session secret for broker sessions.
  randomized=$(openssl rand -hex 64)
  broker && broker_session_secret="${CONF_BROKER_SESSION_SECRET:-${randomized}}"

  # Generate a random session secret for console sessions.
  broker && console_session_secret="${CONF_CONSOLE_SESSION_SECRET:-${randomized}}"

  # Set default passwords
  #
  #   This is the admin password for the ActiveMQ admin console, which 
  #   is not needed by OpenShift but might be useful in troubleshooting.
  activemq && activemq_admin_password="${CONF_ACTIVEMQ_ADMIN_PASSWORD:-${randomized//[![:alnum:]]}}"

  #   This is the user and password shared between broker and node for
  #   communicating over the mcollective topic channels in ActiveMQ. 
  #   Must be the same on all broker and node hosts.
  mcollective_user="${CONF_MCOLLECTIVE_USER:-mcollective}"
  mcollective_password="${CONF_MCOLLECTIVE_PASSWORD:-marionette}"

  #   These are the username and password of the administrative user 
  #   that will be created in the MongoDB datastore. These credentials
  #   are not used by in this script or by OpenShift, but an
  #   administrative user must be added to MongoDB in order for it to
  #   enforce authentication.
  mongodb_admin_user="${CONF_MONGODB_ADMIN_USER:-admin}"
  mongodb_admin_password="${CONF_MONGODB_ADMIN_PASSWORD:-${CONF_MONGODB_PASSWORD:-mongopass}}"

  #   These are the username and password of the normal user that will
  #   be created for the broker to connect to the MongoDB datastore. The
  #   broker application's MongoDB plugin is also configured with these
  #   values.
  mongodb_broker_user="${CONF_MONGODB_BROKER_USER:-openshift}"
  mongodb_broker_password="${CONF_MONGODB_BROKER_PASSWORD:-${CONF_MONGODB_PASSWORD:-mongopass}}"

  #   This is the name of the database in MongoDB in which the broker
  #   will store data.
  mongodb_name="${CONF_MONGODB_NAME:-openshift_broker}"

  #   This user and password are entered in the /etc/openshift/htpasswd
  #   file as a demo/test user. You will likely want to remove it after
  #   installation (or just use a different auth method).
  broker && openshift_user1="${CONF_OPENSHIFT_USER1:-demo}"
  broker && openshift_password1="${CONF_OPENSHIFT_PASSWORD1:-changeme}"
}


########################################################################

# Note: parse_cmdline is only needed for kickstart and not if this %post
# section is extracted and executed on a running system.
parse_cmdline

set_defaults

echo_installation_intentions
#configure_console_msg

is_false "$CONF_NO_NTP" && synchronize_clock
is_false "$CONF_NO_SSH_KEYS" && install_ssh_keys


# enable subscriptions / repositories according to requested method
case "$CONF_INSTALL_METHOD" in
  (yum)
    configure_rhel_repo
    if is_true "$CONF_OPTIONAL_REPO"
    then
      configure_optional_repo
    fi

    if activemq || broker || datastore
    then
      configure_broker_repo
    fi
    node && configure_node_repo
    node && configure_jbosseap_cartridge_repo
    node && configure_jbosseap_repo
    node && configure_jbossews_repo
    broker && configure_client_tools_repo
    ;;
  (rhn)
     echo "Register with RHN using an activation key"
     rhnreg_ks --activationkey=${CONF_RHN_REG_ACTKEY} --profilename=${hostname}
     yum-config-manager --setopt=rhel-x86_64-server-6.priority=2 rhel-x86_64-server-6 --save
     yum-config-manager --setopt="rhel-x86_64-server-6.exclude=tomcat6*" rhel-x86_64-server-6 --save

     for channel in rhel-x86_64-server-6-osop-1-rhc rhel-x86_64-server-6-osop-1-infrastructure
     do
       broker && rhn-channel --add --channel ${channel} --user ${CONF_RHN_REG_NAME} --password ${CONF_RHN_REG_PASS}
       yum-config-manager --setopt=${channel}.priority=1 ${channel} --save
     done
     for channel in rhel-x86_64-server-6-osop-1-node rhel-x86_64-server-6-osop-1-jbosseap
     do
       node && rhn-channel --add --channel ${channel} --user ${CONF_RHN_REG_NAME} --password ${CONF_RHN_REG_PASS}
       yum-config-manager --setopt=${channel}.priority=1 ${channel} --save
     done
     for channel in jbappplatform-6-x86_64-server-6-rpm jb-ews-1-x86_64-server-6-rpm
     do
       node && rhn-channel --add --channel ${channel} --user ${CONF_RHN_REG_NAME} --password ${CONF_RHN_REG_PASS}
       yum-config-manager --setopt=${channel}.priority=3 ${channel} --save
     done

     if is_true "$CONF_OPTIONAL_REPO"
     then
       rhn-channel --add --channel rhel-x86_64-server-optional-6 --user ${CONF_RHN_REG_NAME} --password ${CONF_RHN_REG_PASS}
     fi
     ;;
  (sm)
     #sm_reg_name / CONF_SM_REG_NAME
     #sm_reg_pass / CONF_SM_REG_PASS
     #sm_reg_pool / CONF_SM_REG_POOL
     echo "sam"
     ;;
esac

# Install yum-plugin-priorities
yum clean all; yum install -y yum-plugin-priorities

yum update -y

# Note: configure_named must run before configure_controller if we are
# installing both named and broker on the same host.
named && configure_named

#update_resolv_conf

configure_network
#configure_hostname

datastore && configure_datastore

#broker && configure_qpid
activemq && configure_activemq

#broker && configure_mcollective_for_qpid_on_broker
broker && configure_mcollective_for_activemq_on_broker

#node && configure_mcollective_for_qpid_on_node
node && configure_mcollective_for_activemq_on_node

broker && install_broker_pkgs
broker && fix_passenger
node && install_node_pkgs
node && install_cartridges
broker && install_rhc_pkg

broker && enable_services_on_broker
node && enable_services_on_node

node && configure_pam_on_node
node && configure_cgroups_on_node
node && configure_quotas_on_node

broker && configure_selinux_policy_on_broker
node && configure_selinux_policy_on_node

node && configure_sysctl_on_node
node && configure_sshd_on_node

broker && configure_controller
broker && configure_remote_user_auth_plugin
broker && configure_access_keys_on_broker
#broker && configure_mongo_auth_plugin
broker && configure_messaging_plugin
broker && configure_dns_plugin
broker && configure_httpd_auth
broker && configure_broker_ssl_cert

node && configure_port_proxy
node && configure_gears
node && configure_node
node && configure_wildcard_ssl_cert_on_node
node && update_openshift_facts_on_node

node && broker && fix_broker_routing

echo "Installation and configuration is complete;"
echo "please reboot to start all services properly."


# Configure an authorized key to provide the broker access
configure_authorized_key()
{
cat <<EOF >> /root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDj4ywobxQXlb4ey+2NufOh9+W2BH5NS9a4+D4X7AaKSrgMfTr8P2YFsioFOXXcpjKZrC3HLb6T8ZBxbO5mnTfl9SVv9/gAZZulxXWH/+1P0OLmZQ6u/D0GK4zosRS278Benm6FgiRZSrJZlo+h4Lf4HxAogdiwCDVJs44HnwMWuEjgkOgI0RyQ7txdaZDrwqn8vZ1yh+9bW0HlJWm374lyoNbCJzTH0IQQCLMEnb7QsWzD7lgaNpnKoZeJjQFi0HDGluJt/P9NjyJg3pqnMrGOCkxPU1zT90s0yCGkSUQ1xTJciBQOdffSQj7BAKGSqZxpM2iH8fZUPrpnUxQaXTRh
EOF
}

# Configure the private key on the broker to have named access
configure_private_key()
{
cat <<EOF > /root/.ssh/named_rsa
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA4+MsKG8UF5W+HsvtjbnzoffltgR+TUvWuPg+F+wGikq4DH06
/D9mBbIqBTl13KYymawtxy2+k/GQcWzuZp035fUlb/f4AGWbpcV1h//tT9Di5mUO
rvw9BiuM6LEUtu/AXp5uhYIkWUqyWZaPoeC3+B8QKIHYsAg1SbOOB58DFrhI4JDo
CNEckO7cXWmQ68Kp/L2dcofvW1tB5SVpt++JcqDWwic0x9CEEAizBJ2+0LFsw+5Y
GjaZyqGXiY0BYtBwxpbibfz/TY8iYN6apzKxjgpMT1Nc0/dLNMghpElENcUyXIgU
DnX30kI+wQChkqmcaTNoh/H2VD66Z1MUGl00YQIDAQABAoIBAQCkAAz7XFUdVApq
p1/iKvyGh5ytDTbH8dgpbZ1iId3jEDq74jPc7NNDLiDHeb60eHbZ2Oto+Ca62ZGV
z0sSVfqwZ2f12IKF5pnJBv26Thg+5JkmLXwPuj9AfX7+xtGdhZTvgx0Ov8Xg7LzF
dHERkmNTESfTvv5uULnovGtuWKUkZ0d1OJRY4uRFtilEawzeDcs6VCBUSxAKdTgI
p+wH3h2+IOqdMCle7mKt/k3pHDvjVkity3JE1G++m117C5ndUUEoizl9jHzVB0O+
sQaHVLDYZjeLmLS6mHv3EuAK86ZKiZ+kwRehnTnZnrj4tp8l3bZaFLa+thZdCI/E
QD7LoGCxAoGBAPYj8809V/w7mHZ9S7nDcKxvDbQU/Cm3tBW8JVCvFOBPnJbTUaGA
+lKM0Mob2lai6LyvG4RnqpZorQua4Ikb4H5kEti6I0MuVDadOCxLIi6iVSgjX185
hKsvszLEOHXf8BiqkOYbzUCXLdznMVlATNvyzAinJnOyrdaTGziXybfzAoGBAO0E
C1NHtdjVjWB/rCb2f+zKooBNIqo7K6oC6y+YDScgjHw2255w+uCG1sBgiKwHj1kE
lSp/mN0Af03eKshB1wIz5i83PNW2KvV1a2QWkf9ojbw6oPFGZWOOSGpycjJpzrSS
ai7d5fHsVDi7eyEsXNDVht+WjxTXSTdOIMiI8StbAoGBAKfIxi6HvGxiK4HJ007j
3PCOGydAjsvZP9b5E+62CmMFodZmYmTXSMvw1XqQFfusvT2xl+5fxDcXT65zes+7
wwIlMXuvFs56zEkWTu5SoRBs8+OSiTaePMN8lojqnRos9ru5uWBCX13CMC8/IbKX
VE0yascTOfDwQfPc/1dKkOTlAoGBAJxxgPA1cyhuvOSnIQCO0B2CGwTI5Uqrx8Ru
LMK7gGMFLvWGWCwast2k4vcUQOIcE1hUmAj3M/UcMOs6685G9x5zF0qvES6XEX/3
Qy1LYI7Pek51/GmFZ8Lw1Ye9hvcTs+aohgHtYavvrB/OUBWzbIhDiMToYgUFnUQu
A6GaEmXlAoGAJEJ7t+7joQ9TeIoSWlifTWz63biX5B2QLLQeI7ObAjrdj3iDo4De
UAhplvCUbVcZ3aVFYbofhd6Fyh7eR2RdPD/uWcsWeDkaO1lRXLrvTEgvlpFD//SU
EWGodSkqrF8f+Gdj1c7fZdc4XRygiOs/596K118fkehXXYtqs3JyXGs=
-----END RSA PRIVATE KEY-----
EOF

chmod 600 /root/.ssh/named_rsa
}

# Keeps the broker from getting SSH warnings when running the client
configure_permissive_ssh()
{
cat <<EOF >> /etc/ssh/ssh_config

Host *.cloudydemo.com
   CheckHostIP no
   StrictHostKeyChecking no
EOF
}

# Copy the DNS key from the named host to the broker
set_dns_key()
{
  SSH_CMD="ssh -n -o TCPKeepAlive=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -i /root/.ssh/named_rsa"
  KEY=$(${SSH_CMD} ${named_hostname} "grep Key: /var/named/K${domain}*.private | cut -d ' ' -f 2")
}

# Fix the node configuration to just use the hostname
# Amazon machines have fully qualified hostnames
configure_node_amz()
{
  sed -i -e "s/^PUBLIC_HOSTNAME=.*$/PUBLIC_HOSTNAME=${hostname}/" /etc/openshift/node.conf
}

# Configures named with the correct public IP
configure_named_amz()
{
  # Get the public ip address
  IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

  # Replace the bind configuration with the public ip address
  sed -i -e "s/A 127.0.0.1/A ${IP}/" /var/named/dynamic/${domain}.db
}

# Configures the LIBRA_SERVER variable for convenience
configure_libra_server()
{
  echo "export LIBRA_SERVER='${broker_hostname}'" >> /root/.bashrc
}

# This configures an authorized key to allow the broker to be
# able to obtain the DNS key
named && configure_authorized_key

# This fixes the BIND configuration on the named server by
# setting up the public IP address instead of 127.0.0.1
named && configure_named_amz

# If named was installed on this host, then have the DNSSEC key still
# that we used when configuring named.  Otherwise, we must grab the key
# from the host running named, copy it here (onto the broker), and
# re-run the DNS plug-in configuration on the broker once we have that
# key so that the broker can perform updates.
broker && configure_private_key
broker && ! named && set_dns_key
broker && configure_dns_plugin

# This will keep you from getting SSH warnings if you
# are running the client on the broker
broker && configure_permissive_ssh

# This sets up the LIBRA_SERVER on the broker machine
# for convenience of running 'rhc' on it
broker && configure_libra_server

# Re-configure the node hostname for Amazon hosts
node && configure_node_amz

if [ "x$2" != "x" ]
then
  # Important - the callback is only working
  # if the file data is sent up.  Probably related
  # to the newlines after the initial brace.
  cat <<EOF > /tmp/success_data
{
  "Status" : "SUCCESS",
  "Reason" : "Configuration Complete",
  "UniqueId" : "$1",
  "Data" : "Component has completed configuration."
}
EOF

  # This calls the verification URL for the CloudFormation
  # wait condition.  Again, it's really important to use
  # the file format or you will never unblock the wait state.
  echo "Calling wait URL..."
  curl -T /tmp/success_data $2
  echo "Done"
fi

# The kickstart requires the machines to be restarted
# in order to properly start the right services, firewalls,
# etc.  The restart does not re-IP the Amazon machines.
echo "Restarting VM"
reboot
