#!/bin/bash
# Released under the BSD-License, see LICENSE for more information

# This little script is used for simplifying the installation of SNMPD on new servers.
# Note that in this current state the community defaults to public (which might
# be insecure if snmpd-access isnt restricted by the firewall).
# The script also contains the distro.sh-file used by the Observium network
# monitor tool, which autoinstalls itself if you set $observium to 1.

# v1.5 - by devvis / Gustav Eklundh


#####################
## CONFIG
#####################

## What options should snmpd run with?
snmpdopts='-Lsd -Lf /dev/null -u snmp -I -p /var/run/snmpd.pid -c /etc/snmp/snmpd.conf'

## Do you (plan to) use observium, if so, set this to 1
observium=0

## Should we use input or variables defined below? (1 = input, 0 use values defined below)
input=0
community='public'
syslocation='"Some city, Some country"'
syscontact='some@email.com'

#####################
## END OF CONFIG
#####################


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [ "$input" == 1 ] ; then
	# We're just going to grab some input from the user, if the user wants to.
	echo "What community should snmpd answer to?"
	read community
	echo "Where is the system located?"
	read syslocation
	echo "Who is the system contact?"
	read syscontact
fi

snmpd=`dpkg --get-selections | awk '/\snmpd/{print $1}'`

if [ "$snmpd" != "snmpd" ]; then
        apt-get -y -qq install snmpd
fi

if [ -e "/etc/snmp/snmpd.conf" ]; then
        mv /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.org
fi
echo "rocommunity     $community" > /etc/snmp/snmpd.conf
echo "syslocation     $syslocation" >> /etc/snmp/snmpd.conf
echo "syscontact      $syscontact" >> /etc/snmp/snmpd.conf
echo "SNMPDOPTS=$snmpdopts" >> /etc/snmp/snmpd.conf

if [ "$observium" == 1 ] ; then
	echo "extend .1.3.6.1.4.1.2021.7890.1 distro /usr/bin/distro" >> /etc/snmp/snmpd.conf

# adding the distro-script from observium
cat > /usr/bin/distro <<'DISTRO'
#!/bin/sh
# Detects which OS and if it is Linux then it will detect which Linux Distribution.

OS=`uname -s`
REV=`uname -r`
MACH=`uname -m`

GetVersionFromFile()
{
  VERSION=`cat $1 | tr "\n" ' ' | sed s/.*VERSION.*=\ // `
}

if [ "${OS}" = "SunOS" ] ; then
  OS=Solaris
  ARCH=`uname -p`
  OSSTR="${OS} ${REV}(${ARCH} `uname -v`)"
elif [ "${OS}" = "AIX" ] ; then
  OSSTR="${OS} `oslevel` (`oslevel -r`)"
elif [ "${OS}" = "Linux" ] ; then
  KERNEL=`uname -r`
  if [ -f /etc/redhat-release ] ; then
    DIST=$(cat /etc/redhat-release | awk '{print $1}')
    if [ "${DIST}" = "CentOS" ]; then
      DIST="CentOS"
    else
      DIST="RedHat"
    fi

    PSUEDONAME=`cat /etc/redhat-release | sed s/.*\(// | sed s/\)//`
    REV=`cat /etc/redhat-release | sed s/.*release\ // | sed s/\ .*//`
  elif [ -f /etc/SuSE-release ] ; then
    DIST=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`
    REV=`cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //`
  elif [ -f /etc/mandrake-release ] ; then
    DIST='Mandrake'
    PSUEDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`
    REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`
  elif [ -f /etc/debian_version ] ; then
    DIST="Debian `cat /etc/debian_version`"
    REV=""
  fi

  if [ -f /etc/UnitedLinux-release ] ; then
    DIST="${DIST}[`cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//`]"
  fi

  if [ -f /etc/lsb-release ] ; then
    LSB_DIST="`cat /etc/lsb-release | grep DISTRIB_ID | cut -d "=" -f2`"
    LSB_REV="`cat /etc/lsb-release | grep DISTRIB_RELEASE | cut -d "=" -f2`"
    if [ "$LSB_DIST" != "" ] ; then
      DIST=$LSB_DIST
      REV=$LSB_REV
    fi
  fi

#  OSSTR="${OS} ${DIST} ${REV}(${PSUEDONAME} ${KERNEL} ${MACH})"
  OSSTR="${DIST} ${REV}"
elif [ "${OS}" = "Darwin" ] ; then
  if [ -f /usr/bin/sw_vers ] ; then
    OSSTR=`/usr/bin/sw_vers|grep -v Build|sed 's/^.*:.//'| tr "\n" ' '`
  fi
fi

echo ${OSSTR}

DISTRO
chmod +x /usr/bin/distro
/etc/init.d/snmpd restart

fi # end of observium-part

echo "SNMPD is now installed and should be ready to use."
if [ "$community" == "public" ] ; then
	echo "Note that SNMPD is configured with public as the default community."
	echo "This means that if udp access to 161 isn't restricted, anyone can access the information that SNMPD provides."
fi

