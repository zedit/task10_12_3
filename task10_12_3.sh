#!/bin/bash

source config
CHECK_SUM="3d2b173212bb6f3c702df72e78fac3a7"
DIR_NAME="/var/lib/libvirt/images/"
UDVM1="templates/user-data_vm1.template"
UDVM2="templates/user-data_vm2.template"
MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`
vm1_conf="config-drives/vm1-config"
vm2_conf="config-drives/vm2-config"
path_to_workir=$(pwd)
def_img="${path_to_workir}/xenial-server-cloudimg-amd64-disk1.img"

function create_ext_net {
  if [ ! -e "networks/" ]; then
    mkdir networks
  fi
  local file_ext_net="networks/external.xml"
  cp templates/external.xml.template ${file_ext_net}
  sed -i "s/SED_EXTERNAL_NET_NAME/${EXTERNAL_NET_NAME}/" ${file_ext_net}
  sed -i "s/SED_EXTERNAL_NET_HOST_IP/${EXTERNAL_NET_HOST_IP}/" ${file_ext_net}
  sed -i "s/SED_EXTERNAL_NET_MASK/${EXTERNAL_NET_MASK}/" ${file_ext_net}
  sed -i "s/SED_EXTERNAL_NET/${EXTERNAL_NET}/g" ${file_ext_net}
  sed -i "s/SED_MAC/${MAC}/" ${file_ext_net}
  sed -i "s/SED_VM1_EXTERNAL_IP/${VM1_EXTERNAL_IP}/" ${file_ext_net}
  sed -i "s/SED_VM1_NAME/${VM1_NAME}/" ${file_ext_net}
  virsh net-define ${file_ext_net}
  virsh net-start ${EXTERNAL_NET_NAME}
}

function create_int_net {
  if [ ! -e "networks/" ]; then
    mkdir networks
  fi
  local file_int_net="networks/internal.xml"
  cp templates/internal.xml.template ${file_int_net}
  sed -i "s/SED_INTERNAL_NET_NAME/${INTERNAL_NET_NAME}/" ${file_int_net}
  virsh net-define ${file_int_net}
  virsh net-start ${INTERNAL_NET_NAME}
}

function create_man_net {
  if [ ! -e "networks/" ]; then
    mkdir networks
  fi
  local file_man_net="networks/management.xml"
  cp templates/management.xml.template ${file_man_net}
  sed -i "s/SED_MANAGEMENT_NET_NAME/${MANAGEMENT_NET_NAME}/" ${file_man_net}
  sed -i "s/SED_MANAGEMENT_HOST_IP/${MANAGEMENT_HOST_IP}/" ${file_man_net}
  sed -i "s/SED_MANAGEMENT_NET_MASK/${MANAGEMENT_NET_MASK}/" ${file_man_net}
  virsh net-define ${file_man_net}
  virsh net-start ${MANAGEMENT_NET_NAME}
}

function downloadImg {
  if [ ! -e "${DIR_NAME}/${1}" ]; then
    mkdir ${DIR_NAME}/${1}
  fi
  if [ -f "${def_img}" ]; then
    cp ${def_img} ${2}
  else
    if [ ! -f ${def_img} ]; then
      wget -O ${def_img} ${VM_BASE_IMAGE}
      cp ${def_img} ${2} 
    else
      local existing_file_check_sum="$(md5sum -b ${def_img} | awk '{print$1}')"
      if [[ "${CHECK_SUM}" != "${existing_file_check_sum}" ]]
        then
          wget -O ${def_img} ${VM_BASE_IMAGE}
          cp ${def_img} ${2}
      fi
    fi
  fi
}

function createNetworkVM1data {
  if [ ! -e "${vm1_conf}" ]; then
    mkdir -p ${vm1_conf}
  fi
cat << EOF > ${vm1_conf}/meta-data
version: 1
config:
  - type: nameserver
    address:
      - ${EXTERNAL_NET_HOST_IP}
      - ${VM_DNS}
  - type: physical
    name: ${VM1_EXTERNAL_IF}
    subnets:
     - control: auto
       type: ${EXTERNAL_NET_TYPE}
  - type: physical
    name: ${VM1_INTERNAL_IF}
    subnets:
     - control: auto
       type: static
       address: ${VM1_INTERNAL_IP}
       netmask: ${INTERNAL_NET_MASK}
  - type: physical
    name: ${VM1_MANAGEMENT_IF}
    subnets:
     - control: auto
       type: static
       address: ${VM1_MANAGEMENT_IP}
       netmask: ${MANAGEMENT_NET_MASK}
EOF
}

function createNetworkVM2data {
  if [ ! -e "${vm2_conf}" ]; then
    mkdir ${vm2_conf}
  fi
cat << EOF > ${vm2_conf}/meta-data
version: 1
config:
  - type: nameserver
    address:
      - ${EXTERNAL_NET_HOST_IP}
      - ${VM_DNS}
  - type: physical
    name: ${VM2_INTERNAL_IF}
    subnets:
     - control: auto
       type: static
       address: ${VM2_INTERNAL_IP}
       netmask: ${INTERNAL_NET_MASK}
       gateway: ${VM1_INTERNAL_IP}
  - type: physical
    name: ${VM2_MANAGEMENT_IF}
    subnets:
     - control: auto
       type: static
       address: ${VM2_MANAGEMENT_IP}
       netmask: ${MANAGEMENT_NET_MASK}
EOF
}

function createUserdataVM1 {
  local check_cu_inst=$(apt-cache policy cloud-utils | grep Installed | awk -F ': ' '{print $2}')
  local user_data_file="${vm1_conf}/user-data"
  if [ ! -e "${vm1_conf}" ]; then
    mkdir -p ${vm1_conf}
  fi
  if [ "${check_cu_inst}" == "(none)" ]; then
    apt-get update
    apt-get install -y cloud-utils
  fi 
  cp ${UDVM1} ${user_data_file}
  sed -i "s/sed_change_vm_name/${VM1_NAME}/" ${user_data_file}
  sed -i "s#sed_change_public_key#$(cat ${SSH_PUB_KEY})#" ${user_data_file}
  sed -i "s/SED_VM1_INTERNAL_IP/${VM1_INTERNAL_IP}/" ${user_data_file}
  sed -i "s/SED_VM2_INTERNAL_IP/${VM2_INTERNAL_IP}/" ${user_data_file}
  sed -i "s/SED_VXLAN_IF/${VXLAN_IF}/g" ${user_data_file}
  sed -i "s/SED_VXLAN_ID/${VID}/" ${user_data_file}
  sed -i "s/SED_VM1_VXLAN_IP/${VM1_VXLAN_IP}/" ${user_data_file}
  sed -i "s/SED_INT_IF/${VM1_INTERNAL_IF}/" ${user_data_file}
  sed -i "s/SED_EXT_IF/${VM1_EXTERNAL_IF}/g" ${user_data_file}
  sed -i "s#SED_INT_NET_IP#${INTERNAL_NET_IP}/${INTERNAL_NET_MASK}#" ${user_data_file}
  sed -i "s#SED_NGINX_LOG_DIR#${NGINX_LOG_DIR}#g" ${user_data_file}
  sed -i "s/SED_EXTERNAL_NET_HOST_IP/${EXTERNAL_NET_HOST_IP}/" ${user_data_file}
  sed -i "s#SED_PATH_TO_WORKDIR#${path_to_workir}#" ${user_data_file}
  sed -i "s/SED_NGINX_PORT/${NGINX_PORT}/" ${user_data_file}
  sed -i "s#SED_NGINX_IMAGE#${NGINX_IMAGE}#" ${user_data_file}
  cloud-localds -N ${vm1_conf}/meta-data ${VM1_CONFIG_ISO} ${user_data_file}
}

function createUserdataVM2 {
  if [ ! -e "${vm2_conf}" ]; then
    mkdir -p ${vm2_conf}
  fi
  local check_cu_inst=$(apt-cache policy cloud-utils | grep Installed | awk -F ': ' '{print $2}')
  local user_data_file="${vm2_conf}/user-data"
  if [ "${check_cu_inst}" == "(none)" ]; then
    apt-get update
    apt-get install -y cloud-utils
  fi 
  cp ${UDVM2} ${user_data_file}
  sed -i "s/sed_change_vm_name/${VM2_NAME}/" ${user_data_file}
  sed -i "s#sed_change_public_key#$(cat ${SSH_PUB_KEY})#" ${user_data_file}
  sed -i "s/SED_VM1_INTERNAL_IP/${VM1_INTERNAL_IP}/" ${user_data_file}
  sed -i "s/SED_VM2_INTERNAL_IP/${VM2_INTERNAL_IP}/" ${user_data_file}
  sed -i "s/SED_VXLAN_IF/${VXLAN_IF}/g" ${user_data_file}
  sed -i "s/SED_VM2_VXLAN_IP/${VM2_VXLAN_IP}/" ${user_data_file}
  sed -i "s/SED_VXLAN_ID/${VID}/" ${user_data_file}
  sed -i "s/SED_APACHE_PORT/${APACHE_PORT}/" ${user_data_file}
  sed -i "s/SED_APACHE_IMAGE/${APACHE_IMAGE}/" ${user_data_file}
  cloud-localds -N ${vm2_conf}/meta-data ${VM2_CONFIG_ISO} ${user_data_file}
}

function createVM1 {
  virt-install --virt-type=${VM_VIRT_TYPE} --name ${VM1_NAME} \
               --ram ${VM1_MB_RAM} \
               --vcpus=${VM1_NUM_CPU} \
               --noautoconsole \
               --${VM_TYPE} \
               --network network=${EXTERNAL_NET_NAME},model=virtio,mac=${MAC} \
               --network network=${INTERNAL_NET_NAME},model=virtio \
               --network network=${MANAGEMENT_NET_NAME},model=virtio \
               --cdrom=${VM1_CONFIG_ISO} \
               --disk path=${VM1_HDD},format=qcow2
}

function createVM2 {
  virt-install --virt-type=${VM_VIRT_TYPE} --name ${VM2_NAME} \
               --ram ${VM2_MB_RAM} \
               --vcpus=${VM2_NUM_CPU} \
               --noautoconsole \
               --${VM_TYPE} \
               --network network=${INTERNAL_NET_NAME},model=virtio \
               --network network=${MANAGEMENT_NET_NAME},model=virtio \
               --cdrom=${VM2_CONFIG_ISO} \
               --disk path=${VM2_HDD},format=qcow2
}

function get_ssl_certs {
  local certs_path=${path_to_workir}/docker/certs
  local ssl_cert="${certs_path}/web.crt"
  local ssl_cert_key="${certs_path}/web.key"
  local root_cert="${certs_path}/root-ca.crt"
  local root_cert_key="${certs_path}/root-ca.key"
  if [ ! -e "${certs_path}" ]; then
    mkdir -p ${certs_path}
  fi
  local ssl_conf="${certs_path}/opensll_san.cnf"
  local ssl_csr="${certs_path}/web.csr"
cat << EOF > ${ssl_conf}
[ v3_req ]
basicConstraints            = CA:FALSE
keyUsage                    = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName              = @alt_names
 
[alt_names]
IP.1   = ${VM1_EXTERNAL_IP}
DNS.1   = ${VM1_NAME}
EOF
  openssl genrsa -out "${root_cert_key}" 4096
  openssl req -x509 -new -nodes -key "${root_cert_key}" -sha256 -days 10000 -out "${root_cert}" -subj "/C=UA/ST=Kharkov/L=Kharkov/O=homework/OU=task10_12_3/CN=root_cert"
  openssl genrsa -out "${ssl_cert_key}" 2048
  openssl req -new -out "${ssl_csr}" -key "${ssl_cert_key}" -subj "/C=UA/ST=Kharkov/L=Kharkov/O=homework/OU=task6_7/CN=${VM1_NAME}/"
  openssl x509 -req -in "${ssl_csr}" -CA "${root_cert}" -CAkey "${root_cert_key}" -CAcreateserial -out "${ssl_cert}" -extensions v3_req -extfile "${ssl_conf}"
}

function nginx_conf {
  local nginx_conf_template="${path_to_workir}/templates/nginx.conf.template"
  if [ ! -e "${path_to_workir}/docker/etc" ]; then
    mkdir -p ${path_to_workir}/docker/etc
  fi
  cp ${nginx_conf_template} ${path_to_workir}/docker/etc/nginx.conf
  sed -i "s/SED_VM2_VXLAN_IP_APACHE_PORT/${VM2_VXLAN_IP}:${APACHE_PORT}/" ${path_to_workir}/docker/etc/nginx.conf
}

function nfs_setup {
  local check_nfs_inst=$(apt-cache policy nfs-kernel-server | grep Installed | awk -F ': ' '{print $2}')
  if [ "${check_nfs_inst}" == "(none)" ]; then
    apt-get update
    apt-get install -y nfs-kernel-server nfs-common
  fi
  echo "${path_to_workir}/docker ${VM1_EXTERNAL_IP}/${EXTERNAL_NET_MASK}(ro,insecure,nohide,all_squash,anonuid=1000,anongid=1000,no_subtree_check)" >> /etc/exports
  /etc/init.d/nfs-kernel-server restart
}

create_ext_net
create_int_net
create_man_net
downloadImg ${VM1_NAME} ${VM1_HDD}
downloadImg ${VM2_NAME} ${VM2_HDD}
createNetworkVM1data
createNetworkVM2data
createUserdataVM1
createUserdataVM2
createVM1
createVM2
get_ssl_certs
nginx_conf
nfs_setup
