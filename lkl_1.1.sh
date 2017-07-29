#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
Green_font="\033[32m" && Yellow_font="\033[33m" && Red_font="\033[31m" && Font_suffix="\033[0m"
Info="${Green_font}[Info]${Font_suffix}"
Error="${Red_font}[Error]${Font_suffix}"
reboot="${Yellow_font}reboot${Font_suffix}"
echo -e "${Green_font}
#======================================
# Project: lkl-bbr
# Version: 1.1
# Author: nanqinlang
# Blog:   https://www.nanqinlang.com
# Github: https://github.com/nanqinlang
#======================================${Font_suffix}"

#check system
check_system(){
	cat /etc/issue | grep -q -E -i "debian" && release="debian" 
	cat /etc/issue | grep -q -E -i "ubuntu" && release="ubuntu"
    if [[ "${release}" = "debian" || "${release}" != "ubuntu" ]]; then 
	echo -e "${Info} system is ${release}"
	else echo -e "${Error} not support!" && exit 1
	fi
}

#check root
check_root(){
    if [[ "`id -u`" = "0" ]]; then
    echo -e "${Info} user is root"
	else echo -e "${Error} must be root user" && exit 1
    fi
}

#check ovz
check_ovz(){
	[[ "`virt-what`" = "" ]] && apt-get -y install virt-what
	virt=`virt-what`
	if [[ "${virt}" = "openvz" ]]; then 
	echo -e "${Info} virt is OpenVZ" 
	else echo -e "${Error} only support OpenVZ!" && exit 1
	fi
}

#determine workplace directory
directory(){
    [[ ! -d /home/lkl ]] && mkdir -p /home/lkl
	cd /home/lkl
}

#check ldd
check_ldd(){
    ldd=`ldd --version | grep ldd | awk '{print $NF}'`
    if [[ "${ldd}" < "2.14" ]]; then 
    echo -e "${Error} ldd version < 2.14, not support" && exit 1
	else echo -e "${Info} ldd version is ${ldd}"
    fi
}

#check bit
check_bit(){
    bit=`uname -m`
    if [[ "${bit}" != "x64_64" ]]; then
    echo -e "${Error} only support 64 bit" && exit 1
    else echo -e "${Info} bit is 64"
    fi
}

#install
install(){
    #preparatory
	check_system
	check_root
    echo "deb http://ftp.debian.org/debian wheezy-backports main" >> /etc/apt/sources.list
    apt-get update && apt-get install debian-keyring debian-archive-keyring -y && apt-key update && apt-get update
	check_ovz
	check_bit
	check_ldd
	apt-get install -y bc haproxy
	directory
    wget --no-check-certificate https://raw.githubusercontent.com/nanqinlang/lkl/master/liblkl-hijack.so
	[[ ! -e liblkl-hijack.so ]] && echo -e "${Error} downloading lkl mod failed, please check!" && exit 1

    #haproxy config
    cat > /home/lkl/haproxy.cfg<<-EOF
global

defaults
log global
mode tcp
option dontlognull
timeout connect 5000
timeout client 50000
timeout server 50000

frontend proxy-in
bind *:8080-9090
default_backend proxy-out

backend proxy-out
server server1 10.0.0.1 maxconn 20480

EOF
    [[ -e haproxy.cfg ]] && chmod +x haproxy.cfg && echo -e "${Info} configing haproxy successfully, continuing"

    #load lkl
    cat > /home/lkl/bbr.sh<<-EOF
LD_PRELOAD=/home/lkl/liblkl-hijack.so LKL_HIJACK_NET_QDISC="root|fq_codel" LKL_HIJACK_SYSCTL="net.ipv4.tcp_congestion_control=bbr;net.ipv4.tcp_fastopen=3" LKL_HIJACK_OFFLOAD="0x9983" LKL_HIJACK_NET_IFTYPE=tap LKL_HIJACK_NET_IFPARAMS=lkl-tap LKL_HIJACK_NET_IP=10.0.0.2 LKL_HIJACK_NET_NETMASK_LEN=24 LKL_HIJACK_NET_GATEWAY=10.0.0.1 haproxy -f /home/lkl/haproxy.cfg
EOF
    [[ -e bbr.sh ]] && chmod +x bbr.sh && echo -e "${Info} configing bbr successfully, continuing"

    #apply redirect
    cat > /home/lkl/enable.sh<<-EOF
ip tuntap add lkl-tap mode tap && ip addr add 10.0.0.1/24 dev lkl-tap && ip link set lkl-tap up
sysctl -w net.ipv4.ip_forward=1
iptables -P FORWARD ACCEPT && iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE && iptables -t nat -A PREROUTING -i venet0 -p tcp --dport 8080:9090 -j DNAT --to-destination 10.0.0.2
nohup /home/lkl/bbr.sh &
EOF
    [[ -e enable.sh ]] && chmod +x enable.sh && echo -e "${Info} configing run successfully, continuing"

    #self start
    sed -i 's/exit 0/ /ig' /etc/rc.local
    echo "/home/lkl/enable.sh" >> /etc/rc.local
    
	#run lkl-bbr
    bash /home/lkl/enable.sh
	status
}

status(){
    ping=`ping 10.0.0.2 -c 3 | grep ttl`
    if [[ "${ping}" = "" ]]; then
	echo -e "${Info} lkl-bbr is running" && exit 0
    else echo -e "${Error} lkl-bbr is not running" && exit 0
    fi
}

uninstall(){
    check_system
	check_root
	apt-get remove -y haproxy
	rm -rf /home/lkl
	sed -i '/home/lkl/enable.sh' /etc/rc.local
	echo -e "${Info} please remember ${reboot} to stop lkl-bbr"
	exit 0
}

command=$1
if [[ "${command}" = "" ]]; then
    echo -e "${Info}command not found, usage: ${Green_font}{ install | start | status | uninstall }${Font_suffix}" && exit 0
else
    command=$1
fi
case "${command}" in
	 install)
     install 2>&1 | tee -i /home/lkl-install.log
	 ;;
	 status)
     status 2>&1 | tee -i /home/lkl-status.log
	 ;;
	 uninstall)
     uninstall 2>&1 | tee -i /home/lkl-uninstall.log
	 ;;
esac