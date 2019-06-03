#!/bin/bash

# Description: system init script
# Date: 2019-04-23
# Author: wangchao
# Blog: https://blog.csdn.net/wc1695040842

# Network
ping -c 1 -W 3 114.114.114.114 &> /dev/null
if [ ! $? = 0 ];then
  echo "Cannot be networked"
  exit 1
fi


# Set PATH Variables
export PATH=/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin:/root/bin
export LANG="en_US.UTF-8"

# Set output color
COLUMENS=80
SPACE_COL=$[ $COLUMENS-15 ]
#VERSION=`uname -r | awk -F'.' '{print $1}'`
VERSION=`uname -r | awk -F'.' '{print $4}' | awk -F 'l' '{print $2}'`  #根据是6还是7来判断
 
RED='\033[1;5;31m'
GREEN='\033[1;32m'
NORMAL='\033[0m'


success() {
  REAL_SPACE=$[ $SPACE_COL - ${#1} ]
  for i in `seq 1 $REAL_SPACE`; do
      echo -n " "
  done
  echo -e "[ ${GREEN}SUCCESS${NORMAL} ]"
}

failure() {
  REAL_SPACE=$[ $SPACE_COL - ${#1} ]
  for i in `seq 1 $REAL_SPACE`; do
      echo -n " "
  done
  echo -e "[ ${RED}FAILURE${NORMAL} ]"
  exit 1
}


# 01
Data="01) 关闭selinux..."
echo -n $Data
setenforce 0
/bin/cp /etc/selinux/config /etc/selinux/config.bak
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config &> /dev/null
[ `grep "SELINUX=enforcing" /etc/selinux/config|wc -l` -eq 0 ] && success "$Data" || failure "$Data"


# 02
Data="02) 关闭iptables或者firewalld..."
echo -n $Data
if [ $VERSION = 6 ];then
    service iptables stop &> /dev/null
	chkconfig iptables off &> /dev/null
	[ `chkconfig --list | grep iptables| grep 3:on | wc -l` -eq 0 ] && success "$Data" || failure "$Data"
else
    systemctl stop firewalld &> /dev/null
	systemctl disable firewalld &> /dev/null
	[ `systemctl list-unit-files | grep firewalld | grep enabled | wc -l` -eq 0 ] && success "$Data" || failure "$Data"
fi


# 03
Data="03) 设置公网DNS..."
echo -n $Data
cat << EOF >> /etc/resolv.conf
options timeout:1 attempts:1 rotate single-request-reopen
nameserver 114.114.114.114
nameserver 114.114.114.115
EOF
[ `grep '114.114.114.114' /etc/resolv.conf | wc -l` -ne 0 ] && success "$Data" || failure "$Data"


# 04
Data="04) 安装常用基础命令..."
echo -n $Data
yum -y install vim screen lrzsz tree openssl telnet iftop iotop sysstat wget ntpdate dos2unix lsof net-tools mtr gcc gcc-c++ &> /dev/null
if [ ! $? = 0 ];then
    failure "$Data"
else
    success "$Data"
fi


# 05
Data="05) 配置阿里云yum源..."
echo -n $Data
cd /etc/yum.repos.d
mkdir -p /etc/yum.repos.d/repo_bak
mv *.repo /etc/yum.repos.d/repo_bak/
wget http://mirrors.aliyun.com/repo/Centos-$VERSION.repo &> /dev/null 
yum clean all &> /dev/null && yum makecache &> /dev/null
[ `grep aliyun.com /etc/yum.repos.d/Centos-$VERSION.repo | wc -l` -ne 0 ] && success "$Data" || failure "$Data"


# 06
Data="06) 与阿里云时间同步服务器进行时间同步..."
echo -n $Data
/usr/sbin/ntpdate ntp1.aliyun.com &> /dev/null &&  hwclock --systohc &> /dev/null
echo "*/5 * * * * /usr/sbin/ntpdate ntp1.aliyun.com &&  hwclock --systohc" >> /var/spool/cron/root
if [ $VERSION = 6 ];then
    service crond restart &> /dev/null
else
    systemctl restart crond &> /dev/null
fi
[ `grep ntpdate /var/spool/cron/root |wc -l` -ne 0 ] && success "$Data" || failure "$Data"


# 07
Data="07) 调整文件描述符数量..."
echo -n $Data
/bin/cp /etc/security/limits.conf /etc/security/limits.conf.bak
echo "* - nofile 65535">> /etc/security/limits.conf
[ `grep nofile /etc/security/limits.conf | grep -v ^# | awk -F 'nofile' '{print $2}'` -ge  60000 ] && success "$Data" || failure "$Data"


# 08
Data="08) 修改字符集..."
echo -n $Data
if [ $VERSION = 6 ];then
    /bin/cp /etc/sysconfig/i18n /etc/sysconfig/i18n.bak
    echo 'LANG="en_US.UTF-8"' > /etc/sysconfig/i18n
    source /etc/sysconfig/i18n
    [ `echo $LANG | grep 'en_US.UTF-8' | wc -l` -ne 0 ] && success "$Data" || failure "$Data"
else
    /bin/cp /etc/locale.conf /etc/locale.conf.bak
    echo 'LANG="en_US.UTF-8"' > /etc/locale.conf
    source /etc/locale.conf
    [ `echo $LANG | grep 'en_US.UTF-8' | wc -l` -ne 0 ] && success "$Data" || failure "$Data"
fi


# 09
Data="09) 精简开机自启服务..."
echo -n $Data
if [ $VERSION = 6 ];then
    for cgt in `chkconfig --list | grep 3:on | awk '{print $1}'`;do chkconfig --level 3 $cgt off &> /dev/null;done
	for cgt in {crond,sshd,network,rsyslog};do chkconfig --level 3 $cgt on &>/dev/null;done
	[ `chkconfig --list|grep 3:on|wc -l` -eq 4 ] && success "$Data" || failure "$Data"
else
    systemctl list-unit-files|grep service| grep enable | awk '{print $1}'|xargs -i systemctl disable {} &> /dev/null
	for cgt in {crond,sshd,network,rsyslog,NetworkManager};do systemctl enable $cgt &>/dev/null;done
	[ `systemctl list-unit-files | grep enabled | wc -l` -lt 20 ] && success "$Data" || failure "$Data"
fi

# 10
Data="10) 内核参数优化..."
echo -n $Data
[ -f /etc/sysctl.conf.bak ] && /bin/cp /etc/sysctl.conf.bak /etc/sysctl.conf.bak.$(date +%F-%H%M%S) || /bin/cp /etc/sysctl.conf /etc/sysctl.conf.bak
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 1   
net.ipv4.conf.all.rp_filter = 1  
net.ipv4.conf.default.rp_filter = 1 
net.ipv4.conf.all.accept_source_route = 0  
net.ipv4.conf.default.accept_source_route = 0   
kernel.sysrq = 0   
kernel.core_uses_pid = 1  
kernel.msgmnb = 65536 
kernel.msgmax = 65536  
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
fs.file-max = 65535   
###内存资源使用相关设定
vm.vfs_cache_pressure = 100000
vm.swappiness = 0
net.core.wmem_default = 8388608   
net.core.rmem_default = 8388608  
net.core.rmem_max = 16777216 
net.core.wmem_max = 16777216 
net.ipv4.tcp_rmem = 4096 8192 4194304 
net.ipv4.tcp_wmem = 4096 8192 4194304    
##应对DDOS攻击,TCP连接建立设置
net.ipv4.tcp_syncookies = 1 
net.ipv4.tcp_synack_retries = 1  
net.ipv4.tcp_syn_retries = 1   
net.ipv4.tcp_max_syn_backlog = 262144 
##应对timewait过高,TCP连接断开设置
net.ipv4.tcp_max_tw_buckets = 6000  
net.ipv4.tcp_tw_recycle = 1  
net.ipv4.tcp_tw_reuse = 1 
net.ipv4.tcp_timestamps = 0   
net.ipv4.tcp_fin_timeout = 30 
net.ipv4.ip_local_port_range = 1024 65000
###TCP keepalived 连接保鲜设置
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 15 
net.ipv4.tcp_keepalive_probes = 5
###其他TCP相关调节
net.core.somaxconn = 8192 
net.core.netdev_max_backlog = 262144  
net.ipv4.tcp_max_orphans = 3276800    
net.ipv4.tcp_sack = 1  
net.ipv4.tcp_window_scaling = 1
EOF
sysctl -p &> /dev/null
[ `grep "net.ipv4.ip_forward = 1" /etc/sysctl.conf|wc -l` -ne 0 ] && success "$Data" || failure "$Data"


# 11
Data="11) 禁止空密码连接..."
echo -n $Data
/bin/cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
#sed -i 's/\#Port 22/Port 13888/' /etc/ssh/sshd_config
#sed -i 's/\#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/\#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/\#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
[ `grep "PermitEmptyPasswords no" /etc/ssh/sshd_config | wc -l` -ne 0 -a `grep "UseDNS no" /etc/ssh/sshd_config|wc -l` -ne 0 ] && success "$Data" || failure "$Data"


# 12
Data="12) 优化history记录..."
echo -n $Data
cat << EOF >> /etc/profile
export HISTSIZE=10000
USER_IP=\`who -u am i | awk '{print \$NF}'|sed -e 's/[()]//g'\`
if [ -z \$USER_IP  ]
then
  USER_IP="NO_client_IP"
fi
export HISTTIMEFORMAT="[%Y.%m.%d %H:%M:%S-\$USER_IP-\$USER]"
EOF
source /etc/profile
[ `grep "HISTTIMEFORMAT" /etc/profile | wc -l` -ne 0 ] && success "$Data" || failure "$Data"
