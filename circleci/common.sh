#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -ex

GRPCCURL_ARCH="x86_64"
VAULT_ARCH="amd64"
NODEJS_ARCH="x64"
COREDNS_ARCH="amd64"
ARCH=${ARCH:-`(uname -m | tr '[:upper:]' '[:lower:]')`}

if [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
    GRPCCURL_ARCH="arm64"
    VAULT_ARCH="arm64"
    NODEJS_ARCH="arm64"
    COREDNS_ARCH="arm64"
fi

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
    export APISIX_MAIN="https://raw.githubusercontent.com/apache/incubator-apisix/master/rockspec/apisix-master-0.rockspec"
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
}

create_lua_deps() {
    echo "Create lua deps"

    make deps
    # maybe reopen this feature later
    # luarocks install luacov-coveralls --tree=deps --local > build.log 2>&1 || (cat build.log && exit 1)
}

rerun_flaky_tests() {
    if tail -1 "$1" | grep "Result: PASS"; then
        exit 0
    fi

    if ! tail -1 "$1" | grep "Result: FAIL"; then
        # CI failure not caused by failed test
        exit 1
    fi

    local tests
    local n_test
    tests="$(awk '/^t\/.*.t\s+\(.+ Failed: .+\)/{ print $1 }' "$1")"
    n_test="$(echo "$tests" | wc -l)"
    if [ "$n_test" -gt 3 ]; then
        # too many tests failed
        exit 1
    fi

    echo "Rerun $(echo "$tests" | xargs)"
    FLUSH_ETCD=1 prove -I./test-nginx/lib -I./ $(echo "$tests" | xargs)
}

install_grpcurl () {
    # For more versions, visit https://github.com/fullstorydev/grpcurl/releases
    GRPCURL_VERSION="1.8.5"
    wget https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_${GRPCCURL_ARCH}.tar.gz
    tar -xvf grpcurl_${GRPCURL_VERSION}_linux_${GRPCCURL_ARCH}.tar.gz -C /usr/local/bin
}

install_vault_cli () {
    VAULT_VERSION="1.9.0"
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${VAULT_ARCH}.zip
    unzip vault_${VAULT_VERSION}_linux_${VAULT_ARCH}.zip && mv ./vault /usr/local/bin
}

install_nodejs () {
    NODEJS_PREFIX="/usr/local/node"
    NODEJS_VERSION="16.13.1"
    wget https://nodejs.org/dist/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-${NODEJS_ARCH}.tar.xz
    tar -xvf node-v${NODEJS_VERSION}-linux-${NODEJS_ARCH}.tar.xz
    rm -f /usr/local/bin/node
    rm -f /usr/local/bin/npm
    mv node-v${NODEJS_VERSION}-linux-${NODEJS_ARCH} ${NODEJS_PREFIX}
    ln -s ${NODEJS_PREFIX}/bin/node /usr/local/bin/node
    ln -s ${NODEJS_PREFIX}/bin/npm /usr/local/bin/npm
}

set_coredns() {
    # test a domain name is configured as upstream
    echo "127.0.0.1 test.com" | sudo tee -a /etc/hosts
    echo "::1 ipv6.local" | sudo tee -a /etc/hosts
    # test certificate verification
    echo "127.0.0.1 admin.apisix.dev" | sudo tee -a /etc/hosts
    cat /etc/hosts # check GitHub Action's configuration

    # override DNS configures
    if [ -f "/etc/netplan/50-cloud-init.yaml" ]; then
        sudo pip3 install yq

        tmp=$(mktemp)
        # Github Action default Nic: eht0
        # CircleCi default Nic: ens5
        yq -y '.network.ethernets.ens5."dhcp4-overrides"."use-dns"=false' /etc/netplan/50-cloud-init.yaml | \
        yq -y '.network.ethernets.ens5."dhcp4-overrides"."use-domains"=false' | \
        yq -y '.network.ethernets.ens5.nameservers.addresses[0]="8.8.8.8"' | \
        yq -y '.network.ethernets.ens5.nameservers.search[0]="apache.org"' > $tmp
        mv $tmp /etc/netplan/50-cloud-init.yaml
        cat /etc/netplan/50-cloud-init.yaml
        sudo netplan apply
        sleep 3

        sudo mv /etc/resolv.conf /etc/resolv.conf.bak
        sudo ln -s /run/systemd/resolve/resolv.conf /etc/
    fi
    cat /etc/resolv.conf

    mkdir -p build-cache

    if [ ! -f "build-cache/coredns_1_8_1" ]; then
        wget https://github.com/coredns/coredns/releases/download/v1.8.1/coredns_1.8.1_linux_${COREDNS_ARCH}.tgz
        tar -xvf coredns_1.8.1_linux_${COREDNS_ARCH}.tgz
        mv coredns build-cache/

        touch build-cache/coredns_1_8_1
    fi

    pushd t/coredns || exit 1
    ../../build-cache/coredns -dns.port=1053 &
    popd || exit 1
}

build_nacos_image() {
    cd ./circleci/pod/nacos/
    wget https://github.com/nacos-group/nacos-docker/archive/refs/tags/v2.1.0.tar.gz \
        -O nacos-docker-v2.1.0.tar.gz
    tar -zxvf nacos-docker-v2.1.0.tar.gz
    cd nacos-docker-2.1.0/build
    docker build --build-arg NACOS_VERSION=1.4.1 -t api7/nacos-server:1.4.1 .

    cd ~/project
}

build_rocketmq_image() {
    git clone --depth=1 git@github.com:apache/rocketmq-docker.git

    cd rocketmq-docker/image-build
    docker build --build-arg version=4.6.0 -f Dockerfile-alpine -t api7/rocketmq:4.6.0 .

    cd ~/project
}

skip_test_cases() {
    files=(
        "t/plugin/ldap-auth.t"
        "t/plugin/opa.t" "t/plugin/opa2.t"
        "t/plugin/openwhisk.t"
        "t/plugin/splunk-hec-logging.t"
        "t/discovery/eureka.t"
        "t/tars/discovery/tars.t"
    )

    for file in ${files[@]}; do
    rm -f $file
    done
}

GRPC_SERVER_EXAMPLE_VER=20210819
