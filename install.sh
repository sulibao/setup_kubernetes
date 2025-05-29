#!/bin/bash
set -e
export path=`pwd`
export containerd_data="/app/containerd"
export nerdctl_data="/app/nerdctl"
export image_registry="registry.cn-chengdu.aliyuncs.com/su03"
export ansible_log_dir="$path/log"
export ansible_image_url_x86="registry.cn-chengdu.aliyuncs.com/su03/ansible:latest"
export ansible_image_url_arm="registry.cn-chengdu.aliyuncs.com/su03/ansible-arm:latest"
export ssh_pass="sulibao"
export global_data_dir=$(awk -F': ' '/global_data_dir:/ {print $2}' ./group_vars/all.yml)
export target_yum_repo_x86="$path/packages/yum-repo/x86/yum-repo.tgz"
export target_yum_repo_arm="$path/packages/yum-repo/arm/yum-repo.tgz"
export yum_repo_url_x86="https://sulibao.oss-cn-chengdu.aliyuncs.com/yum-repo/amd/yum-repo.tgz"
export yum_repo_url_arm="https://sulibao.oss-cn-chengdu.aliyuncs.com/yum-repo/arm/yum-repo.tgz"
export nginx_image_url_x86="https://sulibao.oss-cn-chengdu.aliyuncs.com/nginx-image/amd/nginx.tgz"
export nginx_image_url_arm="https://sulibao.oss-cn-chengdu.aliyuncs.com/nginx-image/arm/nginx.tgz"
export target_nginx_image_x86="$path/image/x86/nginx.tgz"
export target_nginx_image_arm="$path/image/arm/nginx.tgz"
export target_containerd_file_x86="$path/packages/containerd/x86/containerd-x86.tgz"
export target_containerd_file_arm="$path/packages/containerd/arm64/containerd-arm.tgz"
export containerd_url_x86="https://sulibao.oss-cn-chengdu.aliyuncs.com/containerd/amd/containerd-x86.tgz"
export containerd_url_arm="https://sulibao.oss-cn-chengdu.aliyuncs.com/containerd/arm/containerd-arm.tgz"

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
    mkdir -p {$ansible_log_dir,$nginx_imagedir_x86}
    if [ -f "$target_yum_repo_x86" ]; then
      echo "The file $target_yum_repo_x86 already exists, skip download."
    else
      mkdir -p "$(dirname "$target_yum_repo_x86")"
      curl -C - -o "$target_yum_repo_x86" "$yum_repo_url_x86"
      if [ $? -eq 0 ]; then
        echo "The file downloaded successfully."
      else
        echo "Failed to download the file."
      fi
    fi
    if [ -f "$target_nginx_image_x86" ]; then
      echo "The file $target_nginx_image_x86 already exists, skip download."
    else
      mkdir -p "$(dirname "$target_nginx_image_x86")"
      curl -C - -o "$target_nginx_image_x86" "$nginx_image_url_x86"
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
    mkdir -p {$ansible_log_dir,$nginx_imagedir_arm}
    if [ -f "$target_yum_repo_arm" ]; then
      echo "The file $target_yum_repo_arm already exists, skip download."
    else
      mkdir -p "$(dirname "$target_yum_repo_arm")"
      curl -C - -o "$target_yum_repo_arm" "$yum_repo_url_arm"
      if [ $? -eq 0 ]; then
        echo "The file downloaded successfully."
      else
        echo "Failed to download the file."
      fi
    fi
    if [ -f "$target_nginx_image_arm" ]; then
      echo "The file $target_nginx_image_arm already exists, skip download."
    else
      mkdir -p "$(dirname "$target_nginx_image_arm")"
      curl -C - -o "$target_nginx_image_arm" "$nginx_image_url_arm"
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
    if [ -f "$target_containerd_file_x86" ]; then
      echo "The file $target_containerd_file_x86 already exists, skip download."
    else
      mkdir -p "$(dirname "$target_containerd_file_x86")"
      curl -C - -o "$target_containerd_file_x86" "$containerd_url_x86"
      tar -xf "$target_containerd_file_x86" -C "$path/packages/containerd/x86/"
      if [ $? -eq 0 ]; then
        echo "The file downloaded successfully."
      else
        echo "Failed to download the file."
      fi
    fi 
    export CONTAINERD_PACKAGE=$path/packages/containerd/x86/containerd-1.7.6.tgz
    export LIBSECCOMP_PACKAGE=$path/packages/containerd/x86/libseccomp-2.5.2-1.el8.x86_64.rpm
  else
    if [ -f "$target_containerd_file_arm" ]; then
      echo "The file $target_containerd_file_arm already exists, skip download."
    else
      mkdir -p "$(dirname "$target_containerd_file_arm")"
      curl -C - -o "$target_containerd_file_arm" "$containerd_url_arm"
      tar -xf "$target_containerd_file_arm" -C "$path/packages/containerd/arm64/"
      if [ $? -eq 0 ]; then
        echo "The file downloaded successfully."
      else
        echo "Failed to download the file."
      fi
    fi
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
  nerdctl exec -i ansible_sulibao /bin/sh -c "cd $global_data_dir/setup_kubernetes/ && ansible-playbook offline-installed.yml"
  echo -e "Install offline yum repository"
}

function main() {
  check_arch
  #check_containerd  
  #ensure_ansible
  #create_ssh_key
  #copy_ssh_key 
  #copy_cert
  run_offline_repo
  
}

main
