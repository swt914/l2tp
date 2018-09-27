#!/bin/bash


install_kubetool(){
apt-get update && apt-get install -y apt-transport-https
curl  http://mirrors.cloud.aliyuncs.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://mirrors.cloud.aliyuncs.com/kubernetes/apt/ kubernetes-xenial main
EOF
apt-get update && apt-get install -y kubelet kubeadm kubectl

}

set_docker_damon(){
    apt update && apt-get install -y docker.io
cat <<EOF >/etc/docker/daemon.json
{"insecure-registries":["$docker_mirror_server"]}
EOF
    systemctl restart docker.service

}

setup_kubelet_conf(){
    sed -i "3i\Environment='KUBELET_POD_INFRA_ARGS=--pod-infra-container-image=$docker_mirror_server/pause:3.1'" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    sed -i 's#$KUBELET_KUBECONFIG_ARGS#$KUBELET_KUBECONFIG_ARGS $KUBELET_POD_INFRA_ARGS#g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
}

down_k8s_image_from_dockerhub_and_store_local_mirror(){
docker login -u shiwt -p shiwt
docker pull shiwt/kube-proxy-amd64 -a && docker tag shiwt/kube-proxy-amd64:v1.11.3 $docker_mirror_server/kube-proxy-amd64:v1.11.3 && docker push $docker_mirror_server/kube-proxy-amd64:v1.11.3
docker pull shiwt/kube-apiserver-amd64 -a && docker tag shiwt/kube-apiserver-amd64:v1.11.3 $docker_mirror_server/kube-apiserver-amd64:v1.11.3 && docker push $docker_mirror_server/kube-apiserver-amd64:v1.11.3
docker pull shiwt/kube-controller-manager-amd64 -a && docker tag shiwt/kube-controller-manager-amd64:v1.11.3 $docker_mirror_server/kube-controller-manager-amd64:v1.11.3 && docker push $docker_mirror_server/kube-controller-manager-amd64:v1.11.3
docker pull shiwt/kube-scheduler-amd64 -a && docker tag shiwt/kube-scheduler-amd64:v1.11.3 $docker_mirror_server/kube-scheduler-amd64:v1.11.3 && docker push $docker_mirror_server/kube-scheduler-amd64:v1.11.3
docker pull shiwt/coredns -a && docker tag shiwt/coredns:1.1.3  $docker_mirror_server/coredns:1.1.3 && docker push $docker_mirror_server/coredns:1.1.3
docker pull shiwt/etcd-amd64 -a && docker tag shiwt/etcd-amd64:3.2.18 $docker_mirror_server/etcd-amd64:3.2.18 && docker push $docker_mirror_server/etcd-amd64:3.2.18
docker pull shiwt/pause -a && docker tag shiwt/pause:3.1  $docker_mirror_server/pause:3.1 && docker push $docker_mirror_server/pause:3.1
docker pull shiwt/flannel:v0.10.0-amd64 && docker tag shiwt/flannel:v0.10.0-amd64 $docker_mirror_server/flannel:v0.10.0-amd64  && docker push $docker_mirror_server/flannel:v0.10.0-amd64

}

setup_registry_server(){

set_docker_damon

dockerdata=$HOME/swt914/k8s/registry-data
mkdir $dockerdata -p
docker run -d -p 5000:5000 -v $dockerdata:/var/lib/registry registry:2

#down_k8s_image_from_dockerhub_and_store_local_mirror

newregistry_container_id=`docker ps | grep "registry:2" | awk '{print $1}'`
docker commit -m "save newregistry" $newregistry_container_id $docker_mirror_server/registry:2
docker push $docker_mirror_server/registry:2
#docker pull $docker_mirror_server/pause:3.1

curl -XGET $docker_mirror_server/v2/_catalog
du -slh $dockerdata/
docker logout

}


install_kubecluster(){

cat <<EOF > $HOME/kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
  advertiseAddress: "$k8s_master_ip"
networking:
  podSubnet: "10.244.0.0/16"
kubernetesVersion: "v1.11.3"
imageRepository: "$docker_mirror_server"

EOF

setup_kubelet_conf

kubeadm init --config $HOME/kubeadm.yaml

mkdir -p $HOME/.kube
cp -rf /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

sysctl net.bridge.bridge-nf-call-iptables=1
#kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
sed -i "s/MIRROR_SERVER/$docker_mirror_server/g" $HOME/kube-flannel.yml
kubectl apply -f $HOME/kube-flannel.yml
kubectl get node

}

if [ $# -eq 0 ];then
    echo -e "no found k8s mirror server ip， default use localhost host? [y/n]\n"
    read answer
    if [ $answer == "y" ];then
       k8s_docker_mirror_ip=`ifconfig eth0 | grep "inet addr:" | awk '{print $2}' | awk -F ":" '{print $2}'`
    else
       echo -e "please input k8s mirror server ip\n"
       read ip
       k8s_docker_mirror_ip="$ip"
    fi
else
   k8s_docker_mirror_ip=$1
fi

echo "k8s_docker_mirror_ip: $k8s_docker_mirror_ip"

docker_mirror_server="$k8s_docker_mirror_ip:5000"

k8s_master_ip=`ifconfig eth0 | grep "inet addr:" | awk '{print $2}' | awk -F ":" '{print $2}'`


ossfs swt914 /root/swt914/ -ourl=oss-cn-beijing-internal.aliyuncs.com

echo "install kubectl kubeadm kubelet"
install_kubetool 
echo "configure kubelet configure"
setup_kubelet_conf


echo "setup docker registry service" 
set_docker_damon
#setup_registry_server


echo "install kubecluster"
#install_kubecluster
