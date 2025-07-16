#!/bin/bash
clear
while true; do
echo -e "\e[32m
0.exit           :退出本脚本
1.ustc           :切换中科大源并更新索引
2.aliyun         :切换阿里云源并更新索引 (谨慎选择，目前限速)
3.mirrors        :自定义源替换
4.docker-ce      :使用中科大源安装docker
5.docker-mirror  :修改docker默认镜像源
6.images         :导入自定义docker镜像
7.network        :修改netplan配置为静态地址
8.ssh            :允许root登录
9.kubectl        :安装kubernetes集群

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
jq -n '."registry-mirrors" = ["https://docker.edudmt.com"]' | tee /etc/docker/daemon.json
apt install docker-ce -y
;;

5)
apt install -y jq
if [[ -f /etc/docker/daemon.json ]]; then
#sed -i 's|"registry-mirrors": \["[^"]*"\]|"registry-mirrors": ["https://docker.edudmt.com"]|g' /etc/docker/daemon.json
jq '."registry-mirrors" = ["https://docker.edudmt.com"]' /etc/docker/daemon.json | tee /etc/docker/daemon.json
else
# tee  /etc/docker/daemon.json <<-'EOF'
# {
#     "registry-mirrors": ["https://docker.edudmt.com"]
# }
# EOF
jq -n '."registry-mirrors" = ["https://docker.edudmt.com"]' | tee /etc/docker/daemon.json
fi
systemctl restart docker
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

9)
if ! systemctl is-active --quiet docker;  then
    echo "当前未安装或运行Docker,请先安装或运行Docker"
    echo "bash <(curl -Ls https://shell.qijds.top/ubuntu.sh)"               
    exit
fi
if [[ ! -f "hosts" ]]; then
apt install sshpass -y
echo "输入ip+空格+主机名+root用户密码,一行一个条目,输入完毕后按Ctrl+D结束输入,第一行为控制节点且主机名要与实际一致"
cat > "hosts" <<EOF
$(cat)
EOF
#cat hosts >> /etc/hosts
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q
#echo "接下来你需要按照上面条目的顺序输入主机root用户的密码"
while read -r ipadd hostname password; do
    #ead -p "输入 $hostname 的 root 密码" -s password
    sshpass -p "$password" ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519.pub root@$ipadd
    sshpass -p "$password" scp -o StrictHostKeyChecking=no ~/.ssh/id_ed25519 root@$ipadd:/root/.ssh/id_ed25519
    sshpass -p "$password" scp -o StrictHostKeyChecking=no hosts root@$ipadd:/root/hosts
    echo "$ipadd $hostname" >> /etc/hosts
    #sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@$ipadd "sed -ri 's/^#(.*PermitRootLogin).*/\1 yes/' /etc/ssh/sshd_config && systemctl restart sshd"
    #sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@$ipadd "sed -ri 's/^#(.*PasswordAuthentication).*/\1 yes/' /etc/ssh/sshd_config && systemctl restart sshd"
done < hosts    
else
while read -r ipadd hostname; do
    echo "$ipadd $hostname" >> /etc/hosts
done < hosts
fi
mastip=$(cat hosts | sed -n '1p' | cut -d " " -f 1)
wk=$(ip r | grep via | cut -d ' ' -f 5)
ip=$(ip a | grep $wk | sed -n "2p" | awk '{print $2}' | cut -d '/' -f 1)
sed -ri 's/^([^#].*swap.*)$/#\1/' /etc/fstab  && swapoff -a
cat >> /etc/sysctl.conf <<EOF
vm.swappiness = 0
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
cat >> /etc/modules-load.d/neutron.conf <<EOF
br_netfilter
EOF
modprobe  br_netfilter
sysctl -p > /dev/null
curl -fsSL https://mirrors.ustc.edu.cn/kubernetes/core%3A/stable%3A/v1.33/deb/Release.key | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg] https://mirrors.ustc.edu.cn/kubernetes/core%3A/stable%3A/v1.33/deb/ /" >> /etc/apt/sources.list
apt update 
apt install kubelet kubeadm kubectl -y
systemctl enable kubelet
wget https://download.chatyigo.com/cri-dockerd_0.4.0.3-0.ubuntu-jammy_amd64.deb
apt install ./cri-dockerd_0.4.0.3-0.ubuntu-jammy_amd64.deb -y
#sed -ri 's@^(.*fd://).*$@\1 --pod-infra-container-image crpi-0y43z4nwadql66kt.cn-shanghai.personal.cr.aliyuncs.com/qjds/k8s-pause:3.9@' /usr/lib/systemd/system/cri-docker.service
sed -ri 's@^(.*fd://).*$@\1 --pod-infra-container-image registry.aliyuncs.com/google_containers/pause@' /usr/lib/systemd/system/cri-docker.service
systemctl daemon-reload && systemctl restart cri-docker && systemctl enable cri-docker
if [[ $mastip == $ip ]]; then
kubeadm config print init-defaults > kubeadm.yaml
sed -ri "s@^(.*advertiseAddress: ).*@\1$ip@" kubeadm.yaml
sed -ri "s@^(.*criSocket: ).*@\1unix:///run/cri-dockerd.sock@" kubeadm.yaml
sed -ri "s@^(.*name: ).*@\1$(hostname)@" kubeadm.yaml
sed -ri "s@^(imageRepository: ).*@\1registry.aliyuncs.com/google_containers@" kubeadm.yaml
sed -ri "s@^(.*serviceSubnet: ).*@\1 10.255.250.0/24\n  podSubnet:  10.255.251.0/24@" kubeadm.yaml
tee -a kubeadm.yaml <<EOF
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
kubeadm init --config=kubeadm.yaml --upload-certs --ignore-preflight-errors=all
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
echo "$(kubeadm token create --print-join-command) --cri-socket unix:///run/cri-dockerd.sock" > join-command
while read -r ipadd hostname; do
    sshpass -p "$password" scp -o StrictHostKeyChecking=no join-command root@$ipadd:/root/join-command
done < hosts
echo -e "\e[32m\nKubernetes集群主节点初始化完成，等待从节点加入集群后在主节点安装calico （本脚本91选项）\n\e[0m"
fi
if [[ ! $mastip == $ip ]]; then
    if [[ -f join-command ]]; then
        cat join-command | bash
    else
        echo -e "\e[31m\n等待主节点初始化完成后执行 cat join-command | bash \n\e[0m"
    fi
fi
;;

91)
#安装calico
wget https://docs.projectcalico.org/manifests/calico.yaml
wk=$(ip r | grep via | cut -d ' ' -f 5)
sed -i "/- name: CALICO_IPV4POOL_IPIP/{n;a\\
            - name: IP_AUTODETECTION_METHOD\\
              value: \"interface=$wk\"
}" calico.yaml
sed -i "/- name: CALICO_IPV4POOL_CIDR/{s/# //;n;s/# //;s/192.168.0.0\/16/10.255.251.0\/24/}" calico.yaml
sed -i "s/docker.io/docker.edudmt.com/g" calico.yaml
kubectl apply -f calico.yaml
#bash <(curl -Ls https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3)
wget https://download.chatyigo.com/helm-3.18.4 -o /usr/local/bin/helm
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard --set web.service.type=NodePort
kubectl -n kubernetes-dashboard get svc | grep kubernetes-dashboard-web
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
        read -sp "牢记此密码：" mydbpass
    done
fi

echo -e "\e[33m\n安装 JAVA ？ \n确定输入 y 取消输入 n 默认n\n\e[0m"
read -p "输入选项" javayorn

if [[ $javayorn = y ]]; then
    echo -e "\e[33m\n选择java版本，可选版本：$(apt-cache search openjdk- | grep "^open" |awk -F- '{print $2}'| sort | uniq | tr '\n' ' ')\n\e[0m"
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
