#!/bin/bash
clear
while true; do
echo -e "\e[32m0.exit       :退出本脚本
1.ustc      :切换中科大源并更新索引
2.aliyun    :切换阿里云源并更新索引 (谨慎选择，目前限速)
3.mirrors   :自定义源替换
4.docker-ce :使用中科大源安装docker
5.minio     :docker导入minio镜像到imges
6.images    :导入自定义docker镜像
7.network   :修改netplan配置为静态地址
8.ssh       :允许root登录

10.java-mysql-nginx-redis\n"

catmirror=$(grep -v -E "^\s*(#|$)|\[" /etc/apt/sources.list $(find /etc/apt/sources.list.d/ -type f) | awk '{print $2}' | grep "^http" | sort | uniq -c)
catmirror1=$(grep  "\[" /etc/apt/sources.list $(find /etc/apt/sources.list.d/ -type f) | awk '{print $3}' | sort | uniq -c)

echo -e "你目前正在使用的源是\n$catmirror\n$catmirror1"

echo -e "\e[0m"

change-mirrors(){
    echo -e "\e[31m\n确定要更改为？$1\n确定输入 y 取消输入 n 默认y\n\e[0m"
    read -p "输入选项: " yorn
    if [[ "$yorn" = "n" ]]; then
        echo "再见"
    else
        sed -i "s|http.*ubuntu|$1|g" /etc/apt/sources.list
        sed -i "s|http.*ubuntu|$1|g" /etc/apt/sources.list.d/ubuntu.sources
        apt update
    fi
}

load-images(){
    wget $1
    file=$(echo $1 | sed 's|.*/||')
    docker load < $file
    rm $file
}

read -p "输入选项：" op

case $op in

1)
change-mirrors "https://mirrors.ustc.edu.cn/ubuntu"
;;

2)
change-mirrors "https://mirrors.aliyun.com/ubuntu"
;;

3)
echo -e "\e[33m输入你要替换的源地址，要确保该地址下有 dists 文件夹\n\e[0m"
read -p "输入需要替换的源URL：" mirrors
change-mirrors "$mirrors"
;;

4)
sed -i '/docker-ce/d' /etc/apt/sources.list
curl -Ls https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | gpg --dearmor --yes -o  /etc/apt/trusted.gpg.d/docker-ce.gpg
if [[ $? -ne 0 ]]; then
    curl -Ls https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o  /etc/apt/trusted.gpg.d/docker-ce.gpg
fi
echo "deb https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable" >> /etc/apt/sources.list
apt update
apt install docker-ce -y
;;

5)
load-images "https://download.qijds.top/minio.tar"
;;

6)
echo -e "\e[33m输入你要导入的docker镜像，要确保该地址可以直接下载\n\e[0m"
read -p "输入导入的镜像URL：" images
load-images "$images"
;;

7)
wk=$(ip r | grep via | cut -d ' ' -f 5)
ip=$(ip a | grep $wk | sed -n "2p" | awk '{print $2}')
wg=$(ip r | grep via | head -n 1 | cut -d ' ' -f 3)
file=$(find /etc/netplan/ -name *.yaml | head -n 1)
cat << EOF > $file
network:
    ethernets:
        $wk:
            dhcp4: false
            dhcp6: true
            addresses:
            -   $ip
            nameservers:
                addresses: 
                -   223.5.5.5
                -   223.6.6.6
                -   2400:3200::1
                -   2400:3200:baba::1
            routes: 
            -   to: default
                via: $wg
    version: 2
EOF
netplan apply
;;

8)
sed -i "s|^#\?PermitRootLogin .*|PermitRootLogin yes|" /etc/ssh/sshd_config
systemctl daemon-reload
systemctl restart ssh*
;;

10)
echo -e "\e[33m\n安装 redis-server ？ \n确定输入 y 取消输入 n 默认n\n\e[0m"
read -p "输入选项：" redisyorn

echo -e "\e[33m\n安装 nginx ？ \n确定输入 y 取消输入 n 默认n\n\e[0m"
read -p "输入选项：" nginxyorn

echo -e "\e[33m\n安装 mysql-server ？ \n确定输入 y 取消输入 n 默认n\n\e[0m"
read -p "输入选项：" mysqlyorn

if [[ $mysqlyorn = y ]]; then
    while [[ -z "$mydbpass" ]]; do
        echo -e "\e[31m\n设置mysql root用户密码\e[0m"
        echo -e "\e[33m\n若已执行过本项再次执行会报 CREATE USER failed 忽略即可，新设置的密码依然可以生效\n\e[0m"
        read -p "牢记此密码：" mydbpass
    done
fi

echo -e "\e[33m\n安装 JAVA ？ \n确定输入 y 取消输入 n 默认n\n\e[0m"
read -p "输入选项" javayorn

if [[ $javayorn = y ]]; then
    echo -e "\e[33m\n选择java版本，可选版本：8 11 17 18 19 21\n\e[0m"
    read -p "java版本：" java
    apt install -y openjdk-${java}-jdk
fi

if [[ $mysqlyorn = y ]]; then
    apt install -y mysql-server
    sed -i "s|127.0.0.1|::|" /etc/mysql/mysql.conf.d/mysqld.cnf
    systemctl restart mysql
    mysql -uroot << EOF
    CREATE USER 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${mydbpass}';
    ALTER USER 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${mydbpass}';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
EOF
fi

if [[ $redisyorn = y ]]; then
    apt install -y redis-server
fi

if [[ $nginxyorn = y ]]; then
    apt install -y nginx
fi
;;

0)
echo -e "\e[31m已退出\e[0m"
break
;;

*)
echo "输入不正确，程序已退出，请输入选项序号"
;;
esac
done
