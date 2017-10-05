#!/bin/bash

# PLEASE EDIT NEXT LINES TO DEFINE YOUR OWN CONFIGURATION

LOGNAME="opihotspot.log" # Name of the log file
LOGPATH="/var/log/" # Path where the logfile will be stored be sure to add a / at the end of the path
MYSQL_PASSWORD="orangepi" # Password for user root (MySql/MariaDB not system)
AP_PASSPHRASE="orangepi" # Password for user AP
HOTSPOT_NAME="OPIhotspot" # Name of the hotspot that will be visible for users/customers
WAN_INTERFACE=`ip link show | grep '^[1-9]' | awk -F ':' '{print $2}' | awk '{$1=$1};1' | grep '^e'` # WAN interface (the one with Internet - default 'eth0' or long name for Debian 9+)
LAN_INTERFACE=`ip link show | grep '^[1-9]' | awk -F ':' '{print $2}' | awk '{$1=$1};1' | grep '^w'` # LAN interface (the one for the hotspot)
HOTSPOT_IP="192.168.12.1" # IP of the hotspot
HOTSPOT_NETWORK="192.168.12.0" # Network where the hotspot is located
HOTSPOT_HTTPS="N" # Use HTTPS to connect to web portal Set value to Y or N
COOVACHILLI_SECRETKEY="change-me" # Secret word for CoovaChilli
FREERADIUS_SECRETKEY="testing123" # Secret word for FreeRadius
LAN_WIFI_DRIVER="nl80211" # Wifi driver
HASERL_INSTALL="Y" # Install Haserl (required if you want to use the default Coova Portal) Set value to Y or N
AVAHI_INSTALL="Y" # Make Avahi optional Set value to Y or N

# *************************************
#
# PLEASE DO NOT MODIFY THE LINES BELOW
#
# *************************************

# Default Portal port
HOTSPOT_PORT="80"
HOTSPOT_PROTOCOL="http:\/\/"
# If we need HTTPS support, change port and protocol
if [ $HOTSPOT_HTTPS = "Y" ]; then
    HOTSPOT_PORT="443"
    HOTSPOT_PROTOCOL="https:\/\/"
fi


# CoovaChilli GIT URL
COOVACHILLI_ARCHIVE="https://github.com/coova/coova-chilli.git"
# Daloradius URL
DALORADIUS_ARCHIVE="https://github.com/lirantal/daloradius.git"
# Haserl URL
HASERL_URL="http://downloads.sourceforge.net/project/haserl/haserl-devel/haserl-0.9.35.tar.gz"
# Haserl archive name based on the URL (keep the same version)
HASERL_ARCHIVE="haserl-0.9.35"

### PKG Vars ###
PKG_MANAGER="apt-get"
PKG_CACHE="/var/lib/apt/lists/"
UPDATE_PKG_CACHE="${PKG_MANAGER} update"
PKG_INSTALL="${PKG_MANAGER} --yes install"
PKG_UPGRADE="${PKG_MANAGER} --yes upgrade"
PKG_DIST_UPGRADE="apt dist-upgrade -y --force-yes"
PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
#COLORS
# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan

#################################################
# Set variables
#################################################


TIME_START=$(date +%s)
TIME_STAMP_START=(`date +"%T"`)

DATE_LONG=$(date +"%a, %d %b %Y %H:%M:%S %z")
DATE_SHORT=$(date +%Y%m%d)

check_returned_code() {
    RETURNED_CODE=$@
    if [ $RETURNED_CODE -ne 0 ]; then
        display_message ""
        display_message "Something went wrong with the last command. Please check the log file"
        display_message ""
        exit 1
    fi
}

display_message() {
    MESSAGE=$@
    # Display on console
    echo "::: $MESSAGE"
    # Save it to log file
    echo "::: $MESSAGE" >> $LOGPATH$LOGNAME
}

execute_command() {
    display_message "$3"
    COMMAND="$1 >> $LOGPATH$LOGNAME 2>&1"
    eval $COMMAND
    COMMAND_RESULT=$?
    if [ "$2" != "false" ]; then
        check_returned_code $COMMAND_RESULT
    fi
}

prepare_logfile() {
    echo "::: Preparing log file"
    if [ -f $LOGPATH$LOGNAME ]; then
        echo "::: Log file already exists. Creating a backup."
        execute_command "mv $LOGPATH$LOGNAME $LOGPATH$LOGNAME.`date +%Y%m%d.%H%M%S`"
    fi
    echo "::: Creating the log file"
    execute_command "touch $LOGPATH$LOGNAME"
    display_message "Log file created : $LOGPATH$LOGNAME"
    display_message "'sudo tail -f $LOGPATH$LOGNAME' in a new console to get installation details"
echo -e "$Cyan \n sudo tail -f $LOGPATH$LOGNAME $Color_Off \n"
}


prepare_install() {
    # Prepare the log file
    prepare_logfile
    #systemctl stop bluez
    apt-get remove bluez -y  > /dev/null 2>&1

}

check_root() {
    # Must be root to install the hotspot
    echo ":::"
    if [[ $EUID -eq 0 ]];then
        echo "::: You are root - OK"
    else
        echo "::: sudo will be used for the install."
        # Check if it is actually installed
        # If it isn't, exit because the install cannot complete
        if [[ $(dpkg-query -s sudo) ]];then
            export SUDO="sudo"
            export SUDOE="sudo -E"
        else
            echo "::: Please install sudo or run this as root."
            exit 1
        fi
    fi
}

jumpto() {
    label=$1
    cmd=$(sed -n "/$label:/{:a;n;p;ba};" $0 | grep -v ':$')
    eval "$cmd"
    exit
}

verifyFreeDiskSpace() {
    # Needed free space
    local required_free_megabytes=500
    # If user installs unattended-upgrades we will check for 500MB free
    echo ":::"
    echo -n "::: Verifying free disk space ($required_free_megabytes Kb)"
    local existing_free_megabytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

    # - Unknown free disk space , not a integer
    if ! [[ "${existing_free_megabytes}" =~ ^([0-9])+$ ]]; then
        echo ""
        echo "::: Unknown free disk space!"
        echo "::: We were unable to determine available free disk space on this system."
        echo "::: You may continue with the installation, however, it is not recommended."
        read -r -p "::: If you are sure you want to continue, type YES and press enter :: " response
        case $response in
            [Y][E][S])
                ;;
            *)
                echo "::: Confirmation not received, exiting..."
                exit 1
                ;;
        esac
    # - Insufficient free disk space
    elif [[ ${existing_free_megabytes} -lt ${required_free_megabytes} ]]; then
        echo ""
        echo "::: Insufficient Disk Space!"
        echo "::: Your system appears to be low on disk space. Pi-HotSpot recommends a minimum of $required_free_megabytes MegaBytes."
        echo "::: You only have ${existing_free_megabytes} MegaBytes free."
        echo ":::"
        echo "::: If this is a new install on a Raspberry Pi you may need to expand your disk."
        echo "::: Try running 'sudo raspi-config', and choose the 'expand file system option'"
        echo ":::"
        echo "::: After rebooting, run this installation again."

        echo "Insufficient free space, exiting..."
        exit 1
    else
        echo " - OK"
    fi
}

update_package_cache() {
  timestamp=$(stat -c %Y ${PKG_CACHE})
  timestampAsDate=$(date -d @"${timestamp}" "+%b %e")
  today=$(date "+%b %e")

  if [ ! "${today}" == "${timestampAsDate}" ]; then
    #update package lists
    echo ":::"
    if command -v debconf-apt-progress &> /dev/null; then
        $SUDO debconf-apt-progress -- ${UPDATE_PKG_CACHE}
    else
        $SUDO ${UPDATE_PKG_CACHE} &> /dev/null
    fi
  fi
}

notify_package_updates_available() {
  echo ":::"
  echo -n "::: Checking ${PKG_MANAGER} for upgraded packages...."
  updatesToInstall=$(eval "${PKG_COUNT}")
  echo " done!"
  echo ":::"
  if [[ ${updatesToInstall} -eq "0" ]]; then
    echo "::: Your system is up to date! Continuing with OPi-Hotspot installation..."
  else
    echo "::: There are ${updatesToInstall} updates available for your system!"
    echo ":::"
execute_command "apt-get upgrade -y --force-yes" true "Upgrading the packages. Please be patient. 'sudo tail -f $LOGPATH$LOGNAME' in a new console to get installation details"
    display_message "Please reboot and run the script again"
    exit 1
  fi
}

package_check_install() {
    dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -c "ok installed" || ${PKG_INSTALL} "${1}"
}

opihotspot_DEPS_START=( apt-transport-https debconf-utils)
opihotspot_DEPS_WIFI=( apt-utils  firmware-ralink firmware-realtek )
opihotspot_DEPS=(  libtool gengetopt libcurl3-dev dnsmasq dkms hostapd apache2 php5 php5-mysql mysql-server mysql-client phpmyadmin  libapache2-mod-php5 freeradius freeradius-mysql freeradius-utils php-pear php5-gd php-db curl libcurl3 libcurl3-dev php5-curl php5-mcrypt)

install_dependent_packages() {

  declare -a argArray1=("${!1}")

  if command -v debconf-apt-progress &> /dev/null; then
    $SUDO debconf-apt-progress -- ${PKG_INSTALL} "${argArray1[@]}"
  else
    for i in "${argArray1[@]}"; do
      echo -n ":::    Checking for $i..."
      $SUDO package_check_install "${i}" &> /dev/null
      echo " installed!"
    done
  fi
}

check_root
 
DEBIAN_VERSION=`cat /etc/*-release | grep VERSION_ID | awk -F= '{print $2}' | sed -e 's/^"//' -e 's/"$//'`
if [[ $DEBIAN_VERSION -ne 8 ]];then
        display_message ""
        display_message "This script is used to get installed on Debian GNU/Linux 8 (jessie)"
        display_message ""
    exit 1
fi

verifyFreeDiskSpace

prepare_install

update_package_cache

notify_package_updates_available

install_dependent_packages opihotspot_DEPS_START[@]

execute_command "dpkg --purge --force-all coova-chilli" true "Remove old configuration of Coova Chilli"
execute_command "dpkg --purge --force-all haserl" true "Remove old configuration of haserl"
execute_command "dpkg --purge --force-all hostapd" true "Remove old configuration of hostapd"


execute_command "/sbin/ifconfig -a | grep $LAN_INTERFACE" false "Checking if wlan0 interface already exists"
if [ $COMMAND_RESULT -ne 0 ]; then
    display_message "Wifi interface not found. Upgrading the system first"

    execute_command "apt dist-upgrade -y --force-yes" true "Upgrading the distro. Be patient"

    install_dependent_packages opihotspot_DEPS_WIFI[@]

    display_message "Please reboot and run the script again"
    exit 1
fi


sudo debconf-set-selections <<EOF
mysql-server    mysql-server/root_password password $MYSQL_PASSWORD
mysql-server    mysql-server/root_password_again password $MYSQL_PASSWORD
dbconfig-common dbconfig-common/mysql/app-pass password $MYSQL_PASSWORD
dbconfig-common dbconfig-common/mysql/admin-pass password $MYSQL_PASSWORD
dbconfig-common dbconfig-common/password-confirm password $MYSQL_PASSWORD
dbconfig-common dbconfig-common/app-password-confirm password $MYSQL_PASSWORD
phpmyadmin      phpmyadmin/reconfigure-webserver multiselect apache2
phpmyadmin      phpmyadmin/dbconfig-install boolean true
phpmyadmin      phpmyadmin/app-password-confirm password $MYSQL_PASSWORD 
phpmyadmin      phpmyadmin/mysql/admin-pass     password $MYSQL_PASSWORD
phpmyadmin      phpmyadmin/password-confirm     password $MYSQL_PASSWORD
phpmyadmin      phpmyadmin/setup-password       password $MYSQL_PASSWORD
phpmyadmin      phpmyadmin/mysql/app-pass       password $MYSQL_PASSWORD
EOF

display_message "Getting WAN IP of the Orange Pi (for daloradius access)"
MY_IP=`ifconfig eth0 | grep "inet addr" | head -n 1 | cut -d : -f 2 | cut -d " " -f 1`

if [ $AVAHI_INSTALL = "Y" ]; then
    display_message "DEPS INSTALL + Adding Avahi dependencies"
    opihotspot_DEPS+=( avahi-daemon libavahi-client-dev )

    #display_message "Updating the system hostname to $HOTSPOT_NAME"
    #echo $HOTSPOT_NAME > /etc/hostname
    #check_returned_code $?

    #execute_command "grep $HOTSPOT_NAME /etc/hosts" false "Updating /etc/hosts"
    #if [ $COMMAND_RESULT -ne 0 ]; then
    #    sed -i "s/raspberrypi/$HOTSPOT_NAME/" /etc/hosts
    #    check_returned_code $?
    #fi
fi
DEBIAN_FRONTEND=noninteractive
install_dependent_packages opihotspot_DEPS[@]
execute_command "git clone https://github.com/oblique/create_ap  > /dev/null 2>&1 && cd create_ap"  true "Clone create_ap"
make install > /dev/null 2>&1
cd ..
execute_command "mv /etc/create_ap.conf /etc/create_ap.conf.bak" true "Update create_ap"

display_message "Configuring hostapd"
echo "CHANNEL=4
GATEWAY=$HOTSPOT_IP
WPA_VERSION=1+2
ETC_HOSTS=0
DHCP_DNS=gateway
NO_DNS=0
HIDDEN=0
MAC_FILTER=0
MAC_FILTER_ACCEPT=/etc/hostapd/hostapd.accept
ISOLATE_CLIENTS=0
SHARE_METHOD=nat
IEEE80211N=0
IEEE80211AC=0
HT_CAPAB='[HT40+]'
VHT_CAPAB=
DRIVER=$LAN_WIFI_DRIVER
NO_VIRT=0
COUNTRY=
FREQ_BAND=2.4
NEW_MACADDR=
DAEMONIZE=0
NO_HAVEGED=0
WIFI_IFACE=$LAN_INTERFACE
INTERNET_IFACE=$WAN_INTERFACE
SSID=$HOTSPOT_NAME
PASSPHRASE=$AP_PASSPHRASE
USE_PSK=0" > /etc/create_ap.conf
check_returned_code $?

execute_command "systemctl daemon-reload && systemctl start create_ap.service && systemctl enable create_ap.service" true "Install ap"
execute_command "rm -r -f create_ap" true "Delete catalog create_ap"

echo -e "$Green \n Enable AP Service $Color_Off \n"

execute_command "cd /var/www/html/ && rm -rf daloradius && git clone $DALORADIUS_ARCHIVE daloradius" true "Cloning daloradius project"



#execute_command "service freeradius stop" true "Stopping freeradius service to update the configuration"



display_message "Creating freeradius database"
mysql -u root -porangepi -e 'drop database if exists radius'
mysql -u root -porangepi -e 'create database radius'
mysql -u root -porangepi -e 'GRANT ALL PRIVILEGES ON radius.* TO radius@localhost IDENTIFIED BY "radiuspassword"'
mysql -u root -porangepi -e 'flush privileges'
check_returned_code $?



display_message "Loading daloradius configuration into MySql"
mysql -u root -porangepi radius < /var/www/html/daloradius/contrib/db/fr2-mysql-daloradius-and-freeradius.sql
check_returned_code $?


execute_command "grep phpmyadmin /etc/apache2/apache2.conf" false "Update configuration Apache"
if [ $COMMAND_RESULT -ne 0 ]; then
cat >> /etc/apache2/apache2.conf << EOT

Include /etc/phpmyadmin/apache.conf
EOT
    check_returned_code $?
fi

#service apache2 restart
#echo -e "$Green \n Apache Restart $Color_Off \n"

display_message "Creating users privileges for localhost"
echo "GRANT ALL ON radius.* to 'radius'@'localhost';" > /tmp/grant.sql
check_returned_code $?

display_message "Granting users privileges"
mysql -u root -p$MYSQL_PASSWORD < /tmp/grant.sql
check_returned_code $?

display_message "Configuring daloradius DB user name"
sed -i "s/\$configValues\['CONFIG_DB_USER'\] = 'root';/\$configValues\['CONFIG_DB_USER'\] = 'radius';/g" /var/www/html/daloradius/library/daloradius.conf.php
check_returned_code $?
display_message "Configuring daloradius DB user password"
sed -i "s/\$configValues\['CONFIG_DB_PASS'\] = '';/\$configValues\['CONFIG_DB_PASS'\] = 'radiuspassword';/g" /var/www/html/daloradius/library/daloradius.conf.php
check_returned_code $?

display_message "Updating freeradius configuration - Activate SQL"
sed -i '/^#.*\$INCLUDE sql\.conf$/s/^#//g' /etc/freeradius/radiusd.conf
check_returned_code $?

display_message "Configuring daloradius DB user password"
sed -i 's/password = "radpass"$/password = "radiuspassword"/' /etc/freeradius/sql.conf
check_returned_code $?

display_message "Updating inner-tunnel configuration"
sed -i 's/^#[ \t]*sql$/sql/g' /etc/freeradius/sites-available/inner-tunnel
check_returned_code $?

display_message "Updating freeradius default configuration "
sed -i 's/^#[ \t]*sql$/sql/g' /etc/freeradius/sites-available/default
check_returned_code $?






if [ $HASERL_INSTALL = "Y" ]; then
    execute_command "rm -rf $HASERL_ARCHIVE.tar.gz && rm -rf $HASERL_ARCHIVE" true "Removing any previous sources of Haserl archive"

    execute_command "wget $HASERL_URL" true "Download Haserl"

    execute_command "tar zxvf $HASERL_ARCHIVE.tar.gz  > /dev/null 2>&1"  true "Uncompressing Haserl archive"

    execute_command "cd $HASERL_ARCHIVE && ./configure --prefix=/usr  > /dev/null 2>&1 && make   > /dev/null 2>&1 && make install"  true "Compiling and installing Haserl"

    execute_command "cd .. && rm -rf $HASERL_ARCHIVE.tar.gz && rm -rf $HASERL_ARCHIVE" true "Removing any previous sources of Haserl archive"
echo -e "$Green \n Compiling and installing Haserl $Color_Off \n"
    #display_message "Updating chilli configuration"
    #sed -i '/haserl=/s/^haserl=.*$/haserl=\/usr\/local\/bin\/haserl/g' /etc/chilli/wwwsh
    check_returned_code $?

fi



#  > /dev/null 2>&1

execute_command "rm -rf coova-chilli" true "Removing any previous sources of CoovaChilli project"

execute_command "git clone $COOVACHILLI_ARCHIVE coova-chilli" true "Cloning CoovaChilli project"

execute_command "cd coova-chilli && ./bootstrap  > /dev/null 2>&1 && ./configure --prefix=/usr --libdir=/usr/lib --localstatedir=/var --sysconfdir=/etc --enable-miniportal --with-openssl --enable-libjson --enable-useragent --enable-sessionstate --enable-sessionid --enable-chilliredir --enable-binstatusfile --enable-statusfile --disable-static --enable-shared --enable-largelimits --enable-proxyvsa --enable-chilliproxy --enable-chilliradsec --with-poll  --enable-dhcpopt --enable-sessgarden --enable-ipwhitelist --enable-redirdnsreq --enable-miniconfig --enable-layer3 --enable-chilliscript --enable-eapol --enable-uamdomainfile --enable-modules --enable-multiroute  > /dev/null 2>&1  " true "Configure CoovaChilli package"

execute_command "make > /dev/null 2>&1   && make install  > /dev/null 2>&1 " true "Installing CoovaChilli package"

echo -e "$Green \n Installing CoovaChilli package $Color_Off \n"
execute_command "cd .. && rm -rf coova-chilli" true "Removing any previous sources of CoovaChilli project"

execute_command "cp -f /etc/chilli/defaults /etc/chilli/defaults.backup" true "Backup of default configuration file"





display_message "Configuring CoovaChilli WAN interface"
sed -i "s/\# HS_WANIF=eth0/HS_WANIF=$WAN_INTERFACE/g" /etc/chilli/defaults
check_returned_code $?

display_message "Configuring CoovaChilli LAN interface"
sed -i "s/HS_LANIF=eth1/HS_LANIF=$LAN_INTERFACE/g" /etc/chilli/defaults
check_returned_code $?

display_message "Configuring CoovaChilli hotspot network"
sed -i "s/HS_NETWORK=10.1.0.0/HS_NETWORK=$HOTSPOT_NETWORK/g" /etc/chilli/defaults
check_returned_code $?

display_message "Configuring CoovaChilli hotspot IP"
sed -i "s/HS_UAMLISTEN=10.1.0.1/HS_UAMLISTEN=$HOTSPOT_IP/g" /etc/chilli/defaults
check_returned_code $?


    execute_command "rm -rf /etc/default/chilli" true "Removing any previous sources of default/chilli"



cat >> /etc/default/chilli << EOT

START_CHILLI=1
CONFFILE="/etc/chilli.conf"
HS_USER="chilli"

EOT
    check_returned_code $?





execute_command "rm -rf /etc/init.d/chilli" true "Removing any previous sources of /etc/init.d/chilli"


echo '#! /bin/sh
### BEGIN INIT INFO
# Provides:          chilli
# Required-Start:    $remote_fs $syslog $network
# Required-Stop:     $remote_fs $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start CoovaChilli daemon at boot time
# Description:       Enable CoovaChilli service provided by daemon.
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=/usr/sbin/chilli
NAME=chilli
DESC=chilli

START_CHILLI=1

if [ -f /etc/default/chilli ] ; then
   . /etc/default/chilli
fi

if [ "$START_CHILLI" != "1" ] ; then
   echo "Chilli default off. Look at /etc/default/chilli"
   exit 0
fi

test -f $DAEMON || exit 0

. /etc/chilli/functions

MULTI=$(ls /etc/chilli/*/chilli.conf 2>/dev/null)
[ -z "$DHCPIF" ] && [ -n "$MULTI" ] && {
    for c in $MULTI; 
    do
	echo "Found configuration $c"
	DHCPIF=$(basename $(echo $c|sed '\''s#/chilli.conf##'\''))
	export DHCPIF
	echo "Running DHCPIF=$DHCPIF $0 $*"
	sh $0 $*
    done
    exit
}

if [ -n "$DHCPIF" ]; then
    CONFIG=/etc/chilli/$DHCPIF/chilli.conf
else
    CONFIG=/etc/chilli.conf
fi

[ -f $CONFIG ] || {
    echo "$CONFIG Not found"
    exit 0
}

check_required

RETVAL=0
prog="chilli"

case "$1" in
  start)
	echo -n "Starting $DESC: "
	/sbin/modprobe tun >/dev/null 2>&1
	echo 1 > /proc/sys/net/ipv4/ip_forward
	
	writeconfig
	radiusconfig
	
	test ${HS_ADMINTERVAL:-0} -gt 0 && {	
            (crontab -l 2>&- | grep -v $0
		echo "*/$HS_ADMINTERVAL * * * * $0 radconfig"
		) | crontab - 2>&-
	}

	ifconfig $HS_LANIF 0.0.0.0

	start-stop-daemon --start --quiet --pidfile /var/run/$NAME.$HS_LANIF.pid \
		--exec $DAEMON -- -c $CONFIG
	RETVAL=$?
	echo "$NAME."
	;;
    
    checkrunning)
	check=`start-stop-daemon --start --exec $DAEMON --test`
	if [ x"$check" != x"$DAEMON already running." ] ; then
            $0 start
	fi
	;;
    
    radconfig)
	[ -e $MAIN_CONF ] || writeconfig
	radiusconfig
	;;
    
    restart)
	$0 stop
	sleep 1
	$0 start
	RETVAL=$?
	;;
    
    stop)
	echo -n "Stopping $DESC: "
	
	crontab -l 2>&- | grep -v $0 | crontab -
	
	
	start-stop-daemon --oknodo --stop --quiet --pidfile /var/run/$NAME.$HS_LANIF.pid \
	    --exec $DAEMON
	echo "$NAME."
	;;
    
    reload)
	echo "Reloading $DESC."
	start-stop-daemon --stop --signal 1 --quiet --pidfile \
	    /var/run/$NAME.$HS_LANIF.pid --exec $DAEMON
	;;
    
    condrestart)
	check=`start-stop-daemon --start --exec $DAEMON --test`
	if [ x"$check" != x"$DAEMON already running." ] ; then
            $0 restart
            RETVAL=$?
	fi
	;;
    
    status)
	status chilli
	RETVAL=$?
	;;
    
    *)
	N=/etc/init.d/$NAME
	echo "Usage: $N {start|stop|restart|condrestart|status|reload|radconfig}" >&2
	exit 1
	;;
esac

exit 0

' > /etc/init.d/chilli
check_returned_code $?

#execute_command "wget -O  /etc/init.d/chilli http://ua3nbw.ru/files/chilli.txt" true "Removing any previous sources of init.d/chilli"
#check_returned_code $?


echo "insert into radcheck (username, attribute, op, value) values ('test', 'Cleartext-Password', ':=', 'test');" | mysql -u radius -pradiuspassword radius

echo "insert into userinfo (id, username, firstname, lastname, email, department, company, workphone, homephone, mobilephone, address, city, state, country, zip, notes, changeuserinfo, portalloginpassword, enableportallogin, creationdate, creationby, updatedate, updateby)  values
(1, 'test', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '0', '', 0, '2017-10-01 22:04:51', 'administrator', NULL, NULL);" | mysql -u radius -pradiuspassword radius


service freeradius restart
    check_returned_code $?
echo -e " \n $Green Restarting freeradius service $Color_Off \n" 

service apache2 restart
    check_returned_code $?
echo -e "$Green  Apache Restart $Color_Off \n"

service hostapd restart
    check_returned_code $?
echo -e "$Green  Restarting hostapd $Color_Off \n"  


#sudo chmod +x /etc/init.d/chilli
#sudo update-rc.d chilli defaults
#systemctl enable chilli
#systemctl start chilli





chmod +x /etc/init.d/chilli > /dev/null 2>&1
execute_command "update-rc.d chilli defaults" true "update-rc.d chilli defaults"
    check_returned_code $? 
systemctl daemon-reload
execute_command "systemctl enable chilli" false "systemctl enable chilli" 
    check_returned_code $?
execute_command "systemctl start chilli" false "systemctl start chilli"
    check_returned_code $?


echo -e " \n $Green Starting CoovaChilli service $Color_Off \n" 


#execute_command "service chilli start" true "Starting CoovaChilli service" 

if [ $COMMAND_RESULT -ne 0 ]; then
    display_message "Unable to find chilli interface tun0"
    exit 1
fi
###execute_command "/etc/init.d/networking restart" true "Restarting network service to take IP forwarding into account"
# Last message to display once installation ended successfully



display_message ""
display_message ""
display_message "Congratulation ! You now have your hotspot ready !"
display_message ""
display_message "- Wifi Hotspot available : $HOTSPOT_NAME"
if [ $AVAHI_INSTALL = "Y" ]; then

echo -e "- For the user management, please connect to $Cyan http://$MY_IP/daloradius $Color_Off or $Cyan http://$HOTSPOT_NAME.local/daloradius $Color_Off \n"

else

echo -e "- For the user management, please connect to $Cyan http://$MY_IP/daloradius $Color_Off \n"

fi
echo -e "  (login :$Yellow administrator $Color_Off / password : $Yellow radius $Color_Off ) \n"

echo -e "- For phpmyadmin, please connect to $Cyan http://$MY_IP/phpmyadmin/ $Color_Off \n"
echo -e "  (login :$Yellow root $Color_Off / password : $Yellow $MYSQL_PASSWORD $Color_Off ) \n"






    #################################################
    # Cleanup
    #################################################

    # clean up dirs

    # note time ended
    time_end=$(date +%s)
    time_stamp_end=(`date +"%T"`)
    runtime=$(echo "scale=2; ($time_end-$TIME_START) / 60 " | bc)

    # output finish
    echo -e "\nTime started: ${TIME_STAMP_START}"
    echo -e "Time started: ${time_stamp_end}"
    echo -e "Total Runtime (minutes): $Red $runtime\n $Color_Off "

exit 0












