# SPDX-FileCopyrightText: 2019-present Open Networking Foundation <info@opennetworking.org>
#
# SPDX-License-Identifier: Apache-2.0

export CGO_ENABLED=1
export GO111MODULE=on

.PHONY: build

ONOS_KPIMON_VERSION := 0.0.4
ONOS_PROTOC_VERSION := v0.6.6
BUF_VERSION := 0.27.1

build: # @HELP build the Go binaries and run all validations (default)
build:
	GOPRIVATE="github.com/markmeme/*" go build -o build/_output/onos-kpimon ./cmd/onos-kpimon

build-tools:=$(shell if [ ! -d "./build/build-tools" ]; then cd build && git clone https://github.com/onosproject/build-tools.git; fi)
include ./build/build-tools/make/onf-common.mk

test: # @HELP run the unit tests and source code validation
test: build deps linters license
	go test -race github.com/markmeme/onos-kpimon/pkg/...
	go test -race github.com/markmeme/onos-kpimon/cmd/...

jenkins-test:  # @HELP run the unit tests and source code validation producing a junit style report for Jenkins
jenkins-test: deps license linters
	TEST_PACKAGES=github.com/markmeme/onos-kpimon/... ./build/build-tools/build/jenkins/make-unit

buflint: #@HELP run the "buf check lint" command on the proto files in 'api'
	docker run -it -v `pwd`:/go/src/github.com/markmeme/onos-kpimon \
		-w /go/src/github.com/markmeme/onos-kpimon/api \
		bufbuild/buf:${BUF_VERSION} check lint

protos: # @HELP compile the protobuf files (using protoc-go Docker)
protos:
	docker run -it -v `pwd`:/go/src/github.com/markmeme/onos-kpimon \
		-w /go/src/github.com/markmeme/onos-kpimon \
		--entrypoint build/bin/compile-protos.sh \
		onosproject/protoc-go:${ONOS_PROTOC_VERSION}

helmit-kpm: integration-test-namespace # @HELP run MHO tests locally
	helmit test -n test ./cmd/onos-kpimon-test --timeout 30m --no-teardown --suite kpm

helmit-ha: integration-test-namespace # @HELP run MHO HA tests locally
	helmit test -n test ./cmd/onos-kpimon-test --timeout 30m --no-teardown --suite ha

integration-tests: helmit-kpm helmit-ha # @HELP run all MHO integration tests locally

onos-kpimon-docker: # @HELP build onos-kpimon Docker image
onos-kpimon-docker:
	@go mod vendor
	docker build . -f build/onos-kpimon/Dockerfile \
		-t markmimi/kpimon:${ONOS_KPIMON_VERSION}
	@rm -rf vendor

images: # @HELP build all Docker images
images: build onos-kpimon-docker

kind: # @HELP build Docker images and add them to the currently configured kind cluster
kind: images
	@if [ "`kind get clusters`" = '' ]; then echo "no kind cluster found" && exit 1; fi
	kind load docker-image markmimi/kpimon:${ONOS_KPIMON_VERSION}

all: build images

publish: # @HELP publish version on github and dockerhub
	./build/build-tools/publish-version ${VERSION} markmimi/kpimon

jenkins-publish: jenkins-tools # @HELP Jenkins calls this to publish artifacts
	./build/bin/push-images
	./build/build-tools/release-merge-commit

clean:: # @HELP remove all the build artifacts
	rm -rf ./build/_output ./vendor ./cmd/onos-kpimon/onos-kpimon ./cmd/onos/onos
	go clean -testcache github.com/markmeme/onos-kpimon/...

