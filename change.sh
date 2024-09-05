#!/bin/bash
echo -e "\e[32m
1.ustc		:切换中科大源并更新索引
2.aliyun	:切换阿里云源并更新索引 (谨慎选择，目前限速)
3.docker-ce	:使用中科大源安装docker
4.minio		:docker导入minio镜像到imges

你目前正在使用的源是$(awk '$1 ~ /^deb/ {print $2}' /etc/apt/sources.list | head -n 1)
\e[0m"

change-mirror(){
    echo -e "\e[31m\n确定要更改为？$1\n确定输入 y 取消输入 n\n\e[0m"
    read -p "输入选项: " yorn
    if [[ "$yorn" = "n" ]]; then
        echo "再见"
    else
        sed -i "s|http.*ubuntu|$1|g" /etc/apt/sources.list
        apt update
    fi
}

read -p "输入选项:" op

case $op in

1)
change-mirror "https://mirrors.ustc.edu.cn/ubuntu"
;;

2)
change-mirror "https://mirrors.aliyun.com/ubuntu"
;;

3)
sed -i '/docker-ce/d' /etc/apt/sources.list
#curl -Ls https://download.qijds.top/docker-ce.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/docker-ce.gpg
curl -Ls https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor --yes -o  /etc/apt/trusted.gpg.d/docker-ce.gpg
lsb=$(lsb_release -cs)
echo "deb https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $lsb stable" >> /etc/apt/sources.list
apt update
apt install docker-ce -y
;;

4)
wget https://download.qijds.top/minio.tar 
docker load < minio.tar
rm minio.tar
;;

*)
echo "输入不正确，程序已退出，请输入选项序号"
;;
esac
