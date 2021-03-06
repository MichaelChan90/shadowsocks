#安装yum工具
yum -y install yum-utils
#添加shadowssocks源
yum-config-manager --add-repo https://copr.fedorainfracloud.org/coprs/librehat/shadowsocks/repo/epel-7/librehat-shadowsocks-epel-7.repo
#更新系统
yum -y  update 
yum -y upgrade 
#安装开发必要的包
yum -y groupinstall "Development Libraries" 
yum -y groupinstall "Development Tools"
yum install epel-release -y
yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel  -y
#安装jq
yum -y install jq
#安装ifconfig
yum -y install net-tools.x86_64 
#修改root禁止远程，关闭22端口登录
echo "设置端口登录端口以及禁止root远程登录==============================="
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/'  /etc/ssh/sshd_config
read -p "请输入ssh登录端口（默认使用22）:" SSH_PORT
if [ ! -z "${SSH_PORT}" ]; then
	sed -i "s/#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
	firewall-cmd --zone=public --add-port=${SSH_PORT}/tcp --permanent
	firewall-cmd --reload
fi
semanage port -a -t ssh_port_t -p tcp ${SSH_PORT}
service sshd restart

#创建用户并设置密码
echo "开始创建系统管理用户=============================================="
read -p "请输入管理用户名:" USER
while [ -z "${USER}" ]
do
	read -p "请重新输入管理用户名: " USER
done

#密码隐藏显示
read -p  "用户密码: " -s PASSWD
echo ""
read -p  "确认密码: " -s REPASSWD
echo ""
while [[ -z "${PASSWD}" ]] || [[ -z "${REPASSWD}"  ]] || [[ ! "${PASSWD}"x = "${REPASSWD}"x ]]
do
	echo "输入密码不一致或为空"
	read -p  "请输入使用者密码: " -s PASSWD
	echo ""
	read -p  "确认密码: " -s REPASSWD
	echo ""
done

#增加管理用户
groupadd -g 2000 ${USER}
useradd -g 2000 -G root -d /home/${USER} ${USER}
echo ${USER}:${PASSWD} | chpasswd


echo "安装加密包========================================================="
#创建软件下载目录
SOFT_DIR="/home/${USER}/software"
rm -rf $SOFT_DIR
mkdir $SOFT_DIR
#下载最新稳定版本libsodium
wget -P $SOFT_DIR/ https://download.libsodium.org/libsodium/releases/LATEST.tar.gz
#解压
tar -zxvf $SOFT_DIR/LATEST.tar.gz -C $SOFT_DIR/ && cd $SOFT_DIR/libsodium*
#编译
./configure && make -j4 && make install
echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
ldconfig



echo "安装python========================================================="
#安装pip
yum -y install python-setuptools && easy_install pip
#更新pip到最新版本
pip install --upgrade pip
echo "安装并配置shadowcoks================================================"
#安装shadowsocks
pip install git+https://github.com/shadowsocks/shadowsocks.git@master



#获取本机ip地址
HOST_IP=$(ifconfig| grep "broadcast"|awk '{ print $2}')
#创建shaodowsock目录结构
SHADOW_HOME="/home/${USER}/shadowsocks"
rm -rf ${SHADOW_HOME}
mkdir ${SHADOW_HOME}
mkdir ${SHADOW_HOME}/bin
mkdir ${SHADOW_HOME}/conf
mkdir ${SHADOW_HOME}/logs
mkdir ${SHADOW_HOME}/pid
#输入shadowsocks配置信息
read -p "请输入shadowsocks开放端口以及密码（可多组参数[端口：密码;端口：密码]）: " PORT_PASS
PORT_PASS=${PORT_PASS//' '/''}
#校验输入信息
PATTERN="^([1-9]{1}[0-9]{0,4}:(\w)+){1}(;[1-9]{1}[0-9]{0,4}:(\w)+)*$"
while [[ ! ${PORT_PASS} =~ ${PATTERN} ]]
do
	read -p "请重新输入shadowsocks开放端口以及密码（可多组参数[端口：密码;端口：密码]）: " PORT_PASS
	PORT_PASS=${PORT_PASS//' '/''}
done
#打开系统端口
PORTS=(${PORT_PASS//;/ })
for PORT in ${PORTS[@]}
do
   PORT_PARAM=(${PORT//:/ })
   firewall-cmd --zone=public --add-port=${PORT_PARAM[0]}/tcp --permanent
done
firewall-cmd --reload
PORT_PASS=${PORT_PASS//:/'":"'}
PORT_PASS=${PORT_PASS//;/'","'}
PORT_PASS='"'${PORT_PASS}'"'
ENCRYPT="xchacha20-ietf-poly1305|chacha20-ietf-poly1305|aes-256-gcm|aes-192-gcm|aes-128-gcm|rc4"
#输入shadowsocks加密方式
read -p "请输入shadowsocks加密方式[${ENCRYPT}]: " METHOD
METHOD=${METHOD//' '/''}
PATTERN="^(${ENCRYPT})$"
while [[ ! ${METHOD} =~ ${PATTERN} ]]
do
	read -p "请重新输入shadowsocks加密方式[${ENCRYPT}]: " METHOD
	METHOD=${METHOD//' '/''}
done
#配置shadowsocks配置文件
CONF_FILE="$SHADOW_HOME/conf/shadowsocks.json"
cat > ${CONF_FILE}<<EOF
{
    "server":"${HOST_IP}",
    "local_address": "127.0.0.1",
    "local_port":1080,
    "port_password":{
    	${PORT_PASS}
    },
    "timeout":300,
    "method":"${METHOD}",
    "fast_open": false
}
EOF

#配置shadowsocks启动脚本
START_SH=${SHADOW_HOME}/bin/startup.sh
cat > ${START_SH}<<EOF
#!/bin/sh

basepath=\$(cd \`dirname \$0\`; pwd)
HOST_IP=\$(ifconfig| grep "broadcast"|awk '{print \$2}')
NOW_IP=\`cat \${basepath}/../conf/shadowsocks.json |jq ".server"\`
sed -i "s/\${NOW_IP}/\"\${HOST_IP}\"/g" \${basepath}/../conf/shadowsocks.json

ssserver -c \${basepath}/../conf/shadowsocks.json --pid-file \${basepath}/../pid/pid --log-file \${basepath}/../logs/ssserver.log -d start

EOF


chmod +x ${START_SH}

#配置服务停止脚本
STOP_SH=${SHADOW_HOME}/bin/shutdown.sh
cat > ${STOP_SH}<<EOF
#!/bin/sh

basepath=\$(cd \`dirname \$0\`; pwd)
pid=\`cat \${basepath}/../pid/pid\`
kill -9 \${pid}

EOF

chmod +x ${STOP_SH}
#修改文件属组
chown -R ${USER}:${USER} /home/${USER}/software
chown -R ${USER}:${USER} /home/${USER}/shadowsocks
