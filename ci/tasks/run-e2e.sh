#!/usr/bin/env bash

set -e

CURRENT_PATH=$(pwd)
SDK_SLB_BLOB_PATH=$CURRENT_PATH/slb-blob
SDK_CORE_BLOB_PATH=$CURRENT_PATH/core-blob
PYTHON_SETUP_TOOLS_BLOB_PATH=$CURRENT_PATH/python-setup-tools-blob
PYCRYPTO_BLOB_PATH=$CURRENT_PATH/pycrypto-blob
PIP_BLOB_PATH=$CURRENT_PATH/pip-blob
PYTHON_DEVEL_BLOB_PATH=$CURRENT_PATH/python-blob
LIBPQXX_DEVEL_BLOB_PATH=$CURRENT_PATH/libpqxx-blob
LIBFFI_DEVEL_BLOB_PATH=$CURRENT_PATH/libffi-blob
JQ_BLOB_PATH=$CURRENT_PATH/jq-blob

METADATA_FILE=$CURRENT_PATH/environment/metadata

bosh_cli=$(realpath bosh-cli/bosh-cli-*)
chmod +x $bosh_cli
cp "${bosh_cli}" /usr/local/bin/bosh2

source director-state/director.env

# add blobs for e2e test
# when e2e-test-release/config/final set to remote storage, this code can be removed
function addBlobs {
   bosh2 add-blob ${JQ_BLOB_PATH}/jq-linux64 jq/jq-linux64
   bosh2 add-blob ${PIP_BLOB_PATH}/pip-1.3.1.tar.gz pip/pip-1.3.1.tar.gz
   # python-dev
   bosh2 add-blob ${PYTHON_DEVEL_BLOB_PATH}/libexpat1-dev_2.1.0-4ubuntu1.4_amd64.deb python_devel/libexpat1-dev_2.1.0-4ubuntu1.4_amd64.deb
   bosh2 add-blob ${PYTHON_DEVEL_BLOB_PATH}/libpython2.7_2.7.6-8ubuntu0.3_amd64.deb python_devel/libpython2.7_2.7.6-8ubuntu0.3_amd64.deb
   bosh2 add-blob ${PYTHON_DEVEL_BLOB_PATH}/libpython2.7-dev_2.7.6-8ubuntu0.3_amd64.deb python_devel/libpython2.7-dev_2.7.6-8ubuntu0.3_amd64.deb
   bosh2 add-blob ${PYTHON_DEVEL_BLOB_PATH}/libpython-dev_2.7.5-5ubuntu3_amd64.deb python_devel/libpython-dev_2.7.5-5ubuntu3_amd64.deb
   bosh2 add-blob ${PYTHON_DEVEL_BLOB_PATH}/python2.7-dev_2.7.6-8ubuntu0.3_amd64.deb python_devel/python2.7-dev_2.7.6-8ubuntu0.3_amd64.deb
   bosh2 add-blob ${PYTHON_DEVEL_BLOB_PATH}/python-dev_2.7.5-5ubuntu3_amd64.deb python_devel/python-dev_2.7.5-5ubuntu3_amd64.deb

   bosh2 add-blob ${PYTHON_SETUP_TOOLS_BLOB_PATH}/setuptools-0.6c11.tar.gz setup_tools/setuptools-0.6c11.tar.gz
   bosh2 add-blob ${PYCRYPTO_BLOB_PATH}/pycrypto-2.6.1.tar.gz pycrypto/pycrypto-2.6.1.tar.gz
   bosh2 add-blob ${SDK_CORE_BLOB_PATH}/aliyun-python-sdk-core-2.5.2.tar.gz sdk_core/aliyun-python-sdk-core-2.5.2.tar.gz
   bosh2 add-blob ${SDK_SLB_BLOB_PATH}/aliyun-python-sdk-slb-3.2.1.tar.gz sdk_slb/aliyun-python-sdk-slb-3.2.1.tar.gz
}

# CREATE TEST RELEASE
pushd bosh-cpi-src/ci/assets/e2e-test-release
  addBlobs
  time bosh2 -n create-release --force --name e2e-test --version 1.0.0
  time bosh2 -n upload-release
popd

# UPLOAD STEMCELL
echo "upload light stemcell..."
time bosh2 -n upload-stemcell "$(realpath stemcell/*.tgz)"
#echo "upload heavy stemcell..."
#time bosh2 -n upload-stemcell "$(realpath heavy-stemcell/*.tgz)"

stemcell_name="$( bosh2 int <( tar xfO $(realpath stemcell/*.tgz) stemcell.MF ) --path /name )"
heavy_stemcell_name="$( bosh2 int <( tar xfO $(realpath heavy-stemcell/*.tgz) stemcell.MF ) --path /name )"
# alicloud_kms_key_arn="$(cat environment/metadata | jq --raw-output ".alicloud_kms_key_arn")"

# --cloud-properties "{\"encrypted\": true, \"kms_key_arn\": \"${alicloud_kms_key_arn}\"}" \
#time bosh2 repack-stemcell \
#  --name e2e-encrypted-heavy-stemcell \
#  --version 0.1 \
#  "$(realpath heavy-stemcell/*.tgz)" \
#  /tmp/e2e-encrypted-heavy-stemcell.tgz
#time bosh2 -n upload-stemcell /tmp/e2e-encrypted-heavy-stemcell.tgz
#encrypted_heavy_stemcell_img_id="$( bosh2 stemcells | grep e2e-encrypted-heavy-stemcell | awk '{print $NF;}' )"

#UPDATE CLOUD CONFIG
time bosh2 -n ucc \
  -l ${METADATA_FILE} \
  bosh-cpi-src/ci/assets/e2e-test-release/cloud-config.yml

echo "access key for e2e..."
echo ${ALICLOUD_ACCESS_KEY_ID}

# BOSH DEPLOY
#-v "heavy_stemcell_name=${heavy_stemcell_name}" \
#-v "encrypted_heavy_stemcell_img_id=${encrypted_heavy_stemcell_img_id}" \
time bosh2 -n deploy -d e2e-test \
  -v "stemcell_name=${stemcell_name}" \
  -v access_key=${ALICLOUD_ACCESS_KEY_ID} \
  -v secret_key=${ALICLOUD_SECRET_ACCESS_KEY} \
  -l ${METADATA_FILE} \
  bosh-cpi-src/ci/assets/e2e-test-release/manifest.yml

# RUN ERRANDS
#time bosh2 -n run-errand -d e2e-test iam-instance-profile-test
#time bosh2 -n run-errand -d e2e-test raw-ephemeral-disk-test
time bosh2 -n run-errand -d e2e-test slb-registration-test
#time bosh2 -n run-errand -d e2e-test heavy-stemcell-test
#time bosh2 -n run-errand -d e2e-test encrypted-heavy-stemcell-test