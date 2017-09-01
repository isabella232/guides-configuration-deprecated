#!/bin/bash

# This script includes a set of generic CI functions to test Packer Builds.
prepare () {
  rm -rf /tmp/packer
  curl -o /tmp/packer.zip https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip
  unzip /tmp/packer.zip -d /tmp
  chmod +x /tmp/packer
  rm -rf /tmp/terraform
  curl -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
  unzip /tmp/terraform.zip -d /tmp
  chmod +x /tmp/terraform
}

validate () {
  for PRODUCT in $*; do
    echo "Reviewing ${PRODUCT}.json template..."
    cd "${BUILDDIR}/${PRODUCT}"

    if /tmp/packer validate ${PRODUCT}.json; then
      echo -e "\033[32m\033[1m[PASS]\033[0m"
    else
      echo -e "\033[31m\033[1m[FAIL]\033[0m"
      return 1
    fi

    cd -
  done

  echo "Reviewing shell scripts..."
  if find . -iname \*.sh -exec bash -n {} \; > /dev/null; then
    echo -e "\033[32m\033[1m[PASS]\033[0m"
  else
    echo -e "\033[31m\033[1m[FAIL]\033[0m"
    return 1
  fi
}

packer_build () {
  echo ${PGP_SECRET_KEY} | base64 -d | gpg --import
  echo "Building Consul version: ${CONSUL_VERSION}"
  echo "Building Vault version: ${VAULT_VERSION}"
  echo "Building Nomad version: ${NOMAD_VERSION}"

  if [[ ${CONSUL_VERSION} == *"ent"* ]]; then
    export CONSUL_VERSION_STRIPPED=${CONSUL_VERSION/"+ent"/}
    export CONSUL_ENT_URL=$(AWS_SECRET_ACCESS_KEY=$(echo $AWS_SECRET_ACCESS_KEY_BINARY | base64 -d | gpg -d -) AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_BINARY} aws s3 presign --region="us-east-1" s3://${S3BUCKET}/consul-enterprise/${CONSUL_VERSION_STRIPPED}/consul-enterprise_${CONSUL_VERSION}_linux_amd64.zip --expires-in 3600)

    # Replacing '+' with '-' as '+' is an invalid character for the AMI name and
    # the version isn't used during the install when 'CONSUL_ENT_URL' is populated
    export CONSUL_VERSION=${CONSUL_VERSION/'+'/'-'}

     # TODO: Remove these echos when merging to master
    echo "CONSUL_VERSION: ${CONSUL_VERSION}"
    echo "CONSUL_VERSION_STRIPPED: ${CONSUL_VERSION_STRIPPED}"
    echo "CONSUL_ENT_URL: ${CONSUL_ENT_URL}"
  fi

  if [[ ${VAULT_VERSION} == *"ent"* ]]; then
    export VAULT_VERSION_STRIPPED=${VAULT_VERSION/"+ent"/}
    export VAULT_ENT_URL=$(AWS_SECRET_ACCESS_KEY=$(echo $AWS_SECRET_ACCESS_KEY_BINARY | base64 -d | gpg -d -) AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_BINARY} aws s3 presign --region="us-east-1" s3://${S3BUCKET}/vault-enterprise/${VAULT_VERSION_STRIPPED}/vault-enterprise_${VAULT_VERSION_STRIPPED}_linux_amd64.zip --expires-in 3600)

    # Replacing '+' with '-' as '+' is an invalid character for the AMI name and
    # the version isn't used during the install when 'VAULT_ENT_URL' is populated
    export VAULT_VERSION=${VAULT_VERSION/'+'/'-'}

     # TODO: Remove these echos when merging to master
    echo "VAULT_VERSION: ${VAULT_VERSION}"
    echo "VAULT_VERSION_STRIPPED: ${VAULT_VERSION_STRIPPED}"
    echo "VAULT_ENT_URL: ${CONSUL_ENT_URL}"
  fi

  for PRODUCT in $*; do
    echo "Building ${PRODUCT}.json Packer template..."
    cd "${BUILDDIR}/${PRODUCT}"

    if /tmp/packer build ${PRODUCT}.json ; then
      echo -e "\033[32m${PRODUCT} \033[1m[PASS]\033[0m"
    else
      echo -e "\033[31m${PRODUCT} \033[1m[FAIL]\033[0m"
      return 1
    fi

    cd -
  done

  echo "Cleaning up GPG Keyring..."
  gpg --fingerprint --with-colons ${PGP_SECRET_ID} |\
    grep "^fpr" |\
    sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' |\
    xargs gpg --batch --delete-secret-keys
}

# TODO: Remove when merging into master
build_ent () {
  echo "built_ent is DEPRECATED: Remove this function when merging to master"
}

build () {
  if [ -z ${RELEASE_VERSION} ]; then
    # Set RELEASE_VERSION to the current git branch if not specified so it's not empty
    export RELEASE_VERSION = ${GIT_BRANCH}
  fi

  if [ -z ${USER_TRIGGER+x} ]; then
    export VCS_NAME = ${USER_TRIGGER}
  fi

  echo "Starting build from ${GIT_BRANCH}"
  echo "RELEASE_VERSION: ${RELEASE_VERSION}"
  echo "VCS_NAME: ${VCS_NAME}"

  if [[ ${GIT_BRANCH} == *"master"* ]]; then
    echo "Building ${RELEASE_VERSION} images from ${GIT_BRANCH}"
    packer_build consul vault nomad hashistack
  else
    echo "FORCE_BUILD: ${FORCE_BUILD}"

    if ! [ -z ${FORCE_BUILD} ]; then
      echo "Building ${RELEASE_VERSION} images from ${GIT_BRANCH}"
      packer_build consul vault nomad hashistack
    else
      echo "Skip building ${RELEASE_VERSION} images from ${GIT_BRANCH}"
    fi
  fi

  echo "Completed build from ${GIT_BRANCH}"
}

publish () {
  git clone https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/hashicorp-modules/image-permission-aws
  cd image-permission-aws
  /tmp/terraform init
  /tmp/terraform push -var "consul_version=${CONSUL_VERSION}" -var "vault_version=${VAULT_VERSION}" -var "nomad_version=${NOMAD_VERSION}" -overwrite=consul_version -overwrite=vault_version -overwrite=nomad_version -name=atlas-demo/image-permission-aws .
}
