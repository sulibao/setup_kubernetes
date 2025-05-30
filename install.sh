#!/bin/bash
set -e
export path=`pwd`
export install_ha=false
export install_nfs=true
export install_local_path=true
export global_data_dir=$(awk -F': ' '/global_data_dir:/ {print $2}' ./group_vars/all.yml)
export containerd_data="$global_data_dir/containerd"
export nerdctl_data="$global_data_dir/nerdctl"
export image_registry="registry.cn-chengdu.aliyuncs.com/su03"
export ansible_log_dir="$path/log"
export ansible_image_url_x86="$image_registry/ansible:latest"
export ansible_image_url_arm="$image_registry/ansible-arm:latest"
export ssh_pass="sulibao"
export target_containerd_file_x86="$path/packages/containerd/x86/containerd-x86.tgz"
export target_containerd_file_arm="$path/packages/containerd/arm/containerd-arm.tgz"
export packages_url_x86="https://sulibao.oss-cn-chengdu.aliyuncs.com/k8s-packages/packages_x86.tgz"
export packages_file_x86="$path/packages_x86.tgz"
export packages_url_arm="https://sulibao.oss-cn-chengdu.aliyuncs.com/k8s-packages/packages_arm.tgz"
export packages_file_arm="$path/packages_arm.tgz"

function check_arch() {
  if [ -f /etc/redhat-release ]; then
    OS="RedHat"
  elif [ -f /etc/kylin-release ]; then
    OS="kylin"
  else
    echo "Unknow linux distribution."
  fi
  OS_ARCH=$(uname -a)
  if [[ "$OS_ARCH" =~ "x86" ]]
  then
    ARCH="x86"
    echo -e  "The operating system is $OS,the architecture is X86."
    mkdir -p $ansible_log_dir
    if [ -f "$packages_file_x86" ]; then
      echo "The file $packages_file_x86 already exists, skip download."
    else
      curl -C - -o "$packages_file_x86" "$packages_url_x86"
      tar -xf "$packages_file_x86" -C "$path"
      if [ $? -eq 0 ]; then
        echo "The file downloaded successfully."
      else
        echo "Failed to download the file."
      fi
    fi
  elif [[ "$OS_ARCH" =~ "aarch" ]]
  then
    ARCH="arm64"
    echo -e  "The operating system is $OS,the architecture is Arm."
    mkdir -p $ansible_log_dir
    if [ -f "$packages_file_arm" ]; then
      echo "The file $packages_file_arm already exists, skip download."
    else
      curl -C - -o "$packages_file_arm" "$packages_url_arm"
      tar -xf "$packages_file_x86" -C "$path"
      if [ $? -eq 0 ]; then
        echo "The file downloaded successfully."
      else
        echo "Failed to download the file."
      fi
    fi
  fi
}

function check_containerd() {
  echo -e "Make sure docker is installed and running."
  if ! [ -x "$(command -v nerdctl)" ]; then
    echo "Command nerdctl not find,will install."
    install_containerd
  fi
  if ! systemctl is-active --quiet containerd; then
    echo "Containerd status is not running,will install."
    install_containerd
  fi
}

function install_containerd() {
  echo -e "Installing containerd."
  if [[ "$ARCH" == "x86" ]]
  then
    tar -xf $target_containerd_file_x86 -C $path/packages/containerd/x86/ --strip-components=1
    export CONTAINERD_PACKAGE=$path/packages/containerd/x86/containerd-1.7.6.tgz
    export LIBSECCOMP_PACKAGE=$path/packages/containerd/x86/libseccomp-2.5.2-1.el8.x86_64.rpm
  else
    tar -xf $target_containerd_file_arm -C $path/packages/containerd/arm/ --strip-components=1
    export CONTAINERD_PACKAGE=$path/packages/containerd/arm64/containerd-1.7.6.tgz
    export LIBSECCOMP_PACKAGE=$path/packages/containerd/arm64/libseccomp-2.5.2-1.el8.aarch64.rpm
  fi

  if [[ "$OS" == "RedHat" || "$OS" == "CentOS" ]]; then
    rpm -Uvh "$LIBSECCOMP_PACKAGE" || :
  fi

  tar axvf "$CONTAINERD_PACKAGE" -C /tmp
  cp -arf /tmp/containerd/* /
  test -d /etc/containerd || mkdir -p /etc/containerd
  test -d /etc/nerdctl || mkdir -p /etc/nerdctl
  envsubst '${containerd_data},${image_registry}' < $path/packages/containerd/config.toml.template > /etc/containerd/config.toml
  envsubst '$nerdctl_data' < $path/packages/containerd/nerdctl.toml.template > /etc/nerdctl/nerdctl.toml
  setenforce 0 || :
  systemctl stop firewalld
  systemctl disable firewalld
  systemctl daemon-reload
  systemctl enable containerd.service --now
  systemctl restart containerd || :
  maxSecond=60
  for i in $(seq 1 $maxSecond); do
    if systemctl is-active --quiet containerd; then
      break
    fi
    sleep 1
  done
  if ((i == maxSecond)); then
    echo "Start containerd failed, please check containerd service."
    exit 1
  fi
  echo -e "Installed containerd"
}

function pull_ansible_image() {
  if [[ "$ARCH" == "x86" ]]
  then
    nerdctl pull "$ansible_image_url_x86"
  else
    nerdctl pull "$ansible_image_url_arm"
  fi
  echo -e "Pulled ansible image."
}

function ensure_ansible() {
  echo -e "Checking the status of the ansible."
  if test -z "$(docker ps -a | grep ansible_sulibao)"; then
    echo -e "Ansible is not running, will run."
    pull_ansible_image
    run_ansible
  else
    echo -e "Ansible is running, will restart."
    nerdctl restart ansible_sulibao
  fi
}

function run_ansible() {
  echo -e "Installing Ansible container."
  if [[ "$ARCH" == "x86" ]]
  then
    nerdctl run --name ansible_sulibao --network="host" --workdir=$path -d -e LANG=C.UTF-8 -e ssh_password=$ssh_pass --restart=always -v /etc/localtime:/etc/localtime:ro -v ~/.ssh:/root/.ssh -v $path:$path -v "$capath":"$capath" "$ansible_image_url_x86" sleep 31536000
  else
    nerdctl run --name ansible_sulibao --network="host" --workdir=$path -d -e LANG=C.UTF-8 -e ssh_password=$ssh_pass --restart=always -v /etc/localtime:/etc/localtime:ro -v ~/.ssh:/root/.ssh -v $path:$path -v "$capath":"$capath" "$ansible_image_url_arm" sleep 31536000
  fi
  echo -e "Installed Ansible container."
}

function  create_ssh_key(){
  echo -e "Create sshkey"
  nerdctl exec -i ansible_sulibao /bin/sh -c 'echo -e "y\n"|ssh-keygen -t rsa -N "" -C "deploy@ansible" -f ~/.ssh/id_rsa_ansible -q'
  echo -e "\nCreate sshkey"
}

function copy_ssh_key() {
  echo -e "Copy sshkey"
  nerdctl exec -i ansible_sulibao /bin/sh -c "cd $global_data_dir/setup_kubernetes/ && ansible-playbook  ssh-access.yml -e ansible_ssh_pass=$ssh_pass"
  echo -e "\nCopy sshkey"
}

function copy_cert() {
  echo -e "Copy ca cert"
  nerdctl exec -i ansible_sulibao /bin/sh -c "cd $global_data_dir/setup_kubernetes/ && ansible-playbook  runtime-ca-cert.yml"
  echo -e "Copy ca cert"
}

function run_offline_repo() {
  echo -e "Install offline yum repository"
  nerdctl exec -i ansible_sulibao /bin/sh -c "cd $global_data_dir/setup_kubernetes/ && ansible-playbook yum-repo.yml"
  echo -e "Install offline yum repository"
}

function run_chrony() {
  echo -e "Install Chrony Time Synchronization Service"
  nerdctl exec -i ansible_sulibao /bin/sh -c  "cd $global_data_dir/setup_kubernetes/ && ansible-playbook chrony.yml"
  echo -e "Installed Chrony Time Synchronization Service"
}

function ensure_kubernetes() {
  echo -e "Check the status of kubernetes"
  if test -z "$(kubectl get node  | grep Ready)"; then
    echo "Kubernetes is not ready go to install kubernetes"
    install_kubernetes
  fi
}

function install_kubernetes() {
  echo -e "Installing kubernetes"
  if [[ "$install_ha" == "true" ]]
  then
    nerdctl exec -i ansible_sulibao /bin/sh -c  "cd $global_data_dir/setup_kubernetes/ && ansible-playbook  runtime-k8s-v1.26-ha.yml"
  else
    nerdctl exec -i ansible_sulibao /bin/sh -c  "cd $global_data_dir/setup_kubernetes/ && ansible-playbook  runtime-k8s-v1.26.yml"
  fi
  echo -e "Installed kubernetes"
}

function install_istio() {
  echo -e "Installing istio"
  nerdctl exec -i ansible_sulibao /bin/sh -c  "cd $global_data_dir/setup_kubernetes/ && ansible-playbook  istio.yml"
  echo -e "Installed istio"
}

function install_chartmuseum() {
  echo -e "Installing helm"
  nerdctl exec -i ansible_sulibao /bin/sh -c  "cd $global_data_dir/setup_kubernetes/ && ansible-playbook  chartmuseum.yml"
  echo -e "Installed helm"
}

function install_nfs() {
  if [[ "$install_nfs" == "true" ]]
  then
    echo -e "Install NFS server"
    nerdctl exec -i ansible_sulibao /bin/sh -c  "cd $global_data_dir/setup_kubernetes/ && ansible-playbook nfs.yml"
    echo -e "Install NFS server"
  else
    echo -e "Skip install NFS"
  fi
}

function install_local_path() {
  if [[ "$install_local_path" == "true" ]]
  then
    echo -e "Install local storage"
    nerdctl exec -i ansible_sulibao /bin/sh -c "cd $global_data_dir/setup_kubernetes/ && ansible-playbook ./local-path.yml"
    echo -e "Install local storage"
  else
    echo -e "Skip install local storage"
  fi

}

function main() {
  check_arch
  check_containerd  
  ensure_ansible
  create_ssh_key
  copy_ssh_key 
  copy_cert
  run_offline_repo
  run_chrony  
  ensure_kubernetes
  #install_istio
  install_chartmuseum
  install_nfs
  install_local_path
}

main
