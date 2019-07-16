#!/bin/bash
# Author: Jrohy
# Github: https://github.com/Jrohy/k8s-install

# cancel centos alias
[[ -f /etc/redhat-release ]] && unalias -a

#######color code########
RED="31m"      
GREEN="32m"  
YELLOW="33m" 
BLUE="36m"
FUCHSIA="35m"

GOOGLE_URLS=(
    packages.cloud.google.com
    k8s.gcr.io
)

CAN_GOOGLE=1

IS_MASTER=0

HELM=0

NETWORK=""

K8S_VERSION=""

colorEcho(){
    COLOR=$1
    echo -e "\033[${COLOR}${@:2}\033[0m"
}

ipIsConnect(){
    ping -c2 -i0.3 -W1 $1 &>/dev/null
    if [ $? -eq 0 ];then
        return 0
    else
        return 1
    fi
}

runCommand(){
    echo ""
    COMMAND=$1
    colorEcho $GREEN $1
    eval $1
}

#######get params#########
while [[ $# > 0 ]];do
    KEY="$1"
    case $KEY in
        --hostname)
        HOST_NAME="$2"
        echo "本机设置的主机名为: `colorEcho $BLUE $HOST_NAME`"
        runCommand "hostnamectl --static set-hostname $HOST_NAME"
        shift
        ;;
        --flannel)
        echo "当前节点设置为master节点,使用flannel网络"
        NETWORK="flannel"
        IS_MASTER=1
        ;;
        --calico)
        echo "当前节点设置为master节点,使用calico网络"
        NETWORK="calico"
        IS_MASTER=1
        ;;
        --helm)
        echo "安装Helm"
        HELM=1
        IS_MASTER=1
        ;;
        -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "   -f [file_path], --file=[file_path]:  offline tgz file path"
        echo "   -h, --help:                          find help"
        echo ""
        echo "Docker binary download link:  $(colorEcho $FUCHSIA $DOWNLOAD_URL)"
        exit 0
        shift # past argument
        ;; 
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done
#############################

checkSys() {
    #检查是否为Root
    [ $(id -u) != "0" ] && { colorEcho ${RED} "Error: You must be root to run this script"; exit 1; }

    #检查CPU核数
    [[ `cat /proc/cpuinfo |grep "processor"|wc -l` == 1 && $IS_MASTER == 1 ]] && { colorEcho ${RED} "主节点CPU核数必须大于等于2!"; exit 1;}

    #检查系统信息
    if [[ -e /etc/redhat-release ]];then
        if [[ $(cat /etc/redhat-release | grep Fedora) ]];then
            OS='Fedora'
            PACKAGE_MANAGER='dnf'
        else
            OS='CentOS'
            PACKAGE_MANAGER='yum'
        fi
    elif [[ $(cat /etc/issue | grep Debian) ]];then
        OS='Debian'
        PACKAGE_MANAGER='apt-get'
    elif [[ $(cat /etc/issue | grep Ubuntu) ]];then
        OS='Ubuntu'
        PACKAGE_MANAGER='apt-get'
    else
        colorEcho ${RED} "Not support OS, Please reinstall OS and retry!"
        exit 1
    fi

    echo "正在检测当前服务器网络情况..."
    for ((i=0;i<${#GOOGLE_URLS[*]};i++))
    do
        ipIsConnect ${GOOGLE_URLS[$i]}
        if [[ ! $? -eq 0 ]]; then
            colorEcho ${YELLOW} " 当前服务器无法访问谷歌, 切换为国内的镜像源.."
            CAN_GOOGLE=0
            break	
        fi
    done

}

#安装依赖
installDependent(){
    if [[ ${OS} == 'CentOS' || ${OS} == 'Fedora' ]];then
        ${PACKAGE_MANAGER} install bash-completion -y
    else
        ${PACKAGE_MANAGER} update
        ${PACKAGE_MANAGER} install bash-completion apt-transport-https gpg -y
    fi
}

prepareWork() {
    ## 安装最新版docker
    if [[ ! $(type docker 2>/dev/null) ]];then
        colorEcho ${YELLOW} "本机docker未安装, 正在自动安装最新版..."
        source <(curl -sL https://git.io/fj8OJ)
    fi
    ## Centos关闭防火墙
    [[ ${OS} == 'CentOS' || ${OS} == 'Fedora' ]] && { systemctl disable firewalld.service; systemctl stop firewalld.service; }
    ## 禁用SELinux
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    ## 关闭swap
    swapoff -a
    sed -i 's/.*swap.*/#&/' /etc/fstab
}

installK8sBase() {
    if [[ $CAN_GOOGLE == 1 ]];then
        if [[ $OS == 'Fedora' || $OS == 'CentOS' ]];then
            cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
            yum install -y kubelet kubeadm kubectl
        else
            curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
            echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
            apt-get update
            apt-get install -y kubelet kubeadm kubectl
        fi
    else
        if [[ $OS == 'Fedora' || $OS == 'CentOS' ]];then
            cat>>/etc/yum.repos.d/kubrenetes.repo<<EOF
[kubernetes]
name=Kubernetes Repo
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
EOF
            yum install -y kubelet kubeadm kubectl
        else
            cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main
EOF
            gpg --keyserver keyserver.ubuntu.com --recv-keys BA07F4FB
            gpg --export --armor BA07F4FB | apt-key add -
            apt-get update
            apt-get install -y kubelet kubeadm kubectl
        fi
    fi
    systemctl enable kubelet && systemctl start kubelet

    #命令行补全
    [[ -z $(grep kubectl ~/.bashrc) ]] && echo "source <(kubectl completion bash)" >> ~/.bashrc
    [[ -z $(grep kubeadm ~/.bashrc) ]] && echo "source <(kubeadm completion bash)" >> ~/.bashrc
    source ~/.bashrc
    K8S_VERSION=$(kubectl version --short=true|awk 'NR==1{print $3}')
    echo "当前安装的k8s版本: $(colorEcho $GREEN $K8S_VERSION)"
}

runK8s(){
    if [[ $IS_MASTER == 1 ]];then
        if [[ $NETWORK == "flannel" ]];then
            runCommand "kubeadm init --pod-network-cidr=10.244.0.0/16 --kubernetes-version=`echo $K8S_VERSION|sed "s/v//g"`"
            runCommand "mkdir -p $HOME/.kube"
            runCommand "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
            runCommand "chown $(id -u):$(id -g) $HOME/.kube/config"
            runCommand "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
        elif [[ $NETWORK == "calico" ]];then
            runCommand "kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=`echo $K8S_VERSION|sed "s/v//g"`"
            runCommand "mkdir -p $HOME/.kube"
            runCommand "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
            runCommand "chown $(id -u):$(id -g) $HOME/.kube/config"
            CALIO_VERSION=$(curl -s https://docs.projectcalico.org/latest/getting-started/|grep Click|egrep 'v[0-9].[0-9]' -o)
            runCommand "kubectl apply -f https://docs.projectcalico.org/$CALIO_VERSION/manifests/calico.yaml"
        fi
    else
        echo "当前为从节点,请手动拷贝运行主节点运行kubeadm init后生成的kubeadm join命令, 如果丢失了join命令, 请在主节点运行`colorEcho $GREEN "kubeadm token create --print-join-command"`"
    fi
    colorEcho $YELLOW "kubectl和kubeadm命令补全重开终端生效!"
}

installHelm(){
    if [[ $IS_MASTER == 1 && $HELM == 1 ]];then
        curl -L https://git.io/get_helm.sh | bash
        helm init
        #命令行补全
        [[ -z $(grep helm ~/.bashrc) ]] && { echo "source <(helm completion bash)" >> ~/.bashrc; source ~/.bashrc; }
    fi
}

main() {
    checkSys
    prepareWork
    installDependent
    installK8sBase
    runK8s
    installHelm
}

main