#!/bin/bash

DISTRO=$(hostnamectl | cut -f 5 -d " " | sed '7!d')
IP=$(hostname -I | awk '{print $1}')

# TODO - configure below variables to your liking
ZONE="hogwarts.hp.com."
SLAVE=10.9.1.91
MASTER_IP=10.9.0.254
TO_MOVE_ZONE="examen.griffindor.hp.com."

add_to_hosts () {
	echo " 
$MASTER master
$SLAVE slave
" >> /etc/hosts
}

create_zone () {
        CONF_FILE="/etc/bind/named.conf.local"
        LZONE=$1

        echo "
zone \"$LZONE\" {
        type master;
        file \"/etc/bind/db.${LZONE::-1}\";
        allow-transfer { $SLAVE; };
};
" >> $CONF_FILE


echo ";
; BIND data file for local loopback interface
;
\$TTL    604800
@       IN      SOA     $LZONE root.$LZONE (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;

; name servers - NS records
        IN      NS      ns1.$LZONE

; name servers - A records
ns1.$LZONE    IN      A       $IP
www.$LZONE    IN      A       $IP

$LZONE   1936    IN      MX      10      mail.$LZONE
" > /etc/bind/db.${LZONE::-1}

    named-checkzone ${LZONE::-1} /etc/bind/db.${LZONE::-1}
}

set_options () {

echo "acl goodguys { $SLAVE; 127.0.0.1; };

options {
        directory \"/var/cache/bind\";

        dnssec-validation auto;

        auth-nxdomain no;    # conform to RFC1035
        listen-on-v6 { any; };

        listen-on { $IP; localhost; };

        allow-query { goodguys; };
        allow-recursion { goodguys; };
        recursion yes;
};" > /etc/bind/named.conf.options

}

debian_dns () {
        apt update && apt install -y host dnsutils && apt install -y bind9 bind9utils

        set_options

        create_zone $ZONE
        create_zone $TO_MOVE_ZONE

        named-checkconf

		sleep 1

        service bind9 restart
}

centos_dns () {
        CONF_FILE="/etc/named.conf"
        yum install -y bind-utils && yum install -y bind

        echo "
zone \"$TO_MOVE_ZONE\" {
        type slave;
        file \"/var/named/slaves/db.${TO_MOVE_ZONE::-1}\";
        masters { $MASTER_IP; };
};
" >> /etc/named.conf
		
		sleep 1

        systemctl restart named.service
}

check_root () {
	if [[ $EUID -ne 0 ]]; then
	   echo "This script must be run as root" 
	   exit 1
	fi
}

# ===== main =====
check_root
add_to_hosts
if [ $DISTRO == "Debian" ]; then
        debian_dns 
elif [ $DISTRO == "CentOS" ]; then
        centos_dns
else
        echo "Unknown dsitro, fallback to manual configuration"
fi
