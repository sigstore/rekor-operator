# Copyright 2021 The Sigstore Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Current Operator version
VERSION ?= 0.0.1
# Default bundle image tag
BUNDLE_IMG ?= controller-bundle:$(VERSION)
# Options for 'bundle-build'
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# Allow overriding manifest generation destination directory
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
MANIFEST_ROOT ?= config
CRD_ROOT ?= $(MANIFEST_ROOT)/crd/bases
WEBHOOK_ROOT ?= $(MANIFEST_ROOT)/webhook
RBAC_ROOT ?= $(MANIFEST_ROOT)/rbac
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?=

# Image URL to use all building/pushing image targets
IMG ?= controller:latest

# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.22
KUBEBUILDER_ASSETS = $(shell go run sigs.k8s.io/controller-runtime/tools/setup-envtest@latest use $(ENVTEST_K8S_VERSION) -p path --bin-dir ${ROOT_DIR}/bin)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Build time versioning details.
LDFLAGS := $(shell hack/version.sh)

# Binaries.
CONTROLLER_GEN_VERSION := v0.8.0
CONVERSION_GEN_VERSION := v0.23.1
KUSTOMIZE_VERSION := v4.4.1
ENVSUBST_VERSION := v1.2.0

.PHONY: manager
manager: build

##@ Development

.PHONY: generate
generate: generate-go generate-manifests  ## Generate code and manifests.

.PHONY: generate-go
generate-go: controller-gen conversion-gen  ## Runs Go related generate targets.
	$(CONTROLLER_GEN) \
	paths="./api/..." \
	object:headerFile="hack/boilerplate.go.txt"

.PHONY: generate-manifests
generate-manifests: controller-gen  ## Generate manifests e.g. CRD, RBAC etc.
	$(CONTROLLER_GEN) \
		paths="./api/..." \
		rbac:roleName=manager-role \
		crd \
		webhook \
		output:crd:artifacts:config=$(CRD_ROOT) \
		output:webhook:dir=$(WEBHOOK_ROOT)
	$(CONTROLLER_GEN) \
		paths="./controllers/..." \
		output:rbac:dir=$(RBAC_ROOT) \
		rbac:roleName=manager-role

.PHONY: fmt
fmt:  ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet:  ## Run go vet against code.
	go vet ./...

.PHONY: test
test: generate fmt vet  ## Run tests.
	KUBEBUILDER_ASSETS="$(KUBEBUILDER_ASSETS)" go test -v ./...

.PHONY: coverage
coverage: generate fmt vet  ## Take a test coverage.
	KUBEBUILDER_ASSETS="$(KUBEBUILDER_ASSETS)" go test -v -covermode=atomic -coverpkg=./... -coverprofile=cover.out ./...

##@ Build

.PHONY: build
build: generate fmt vet  ## Build manager binary.
	go build -o bin/manager main.go

.PHONY: run
run: generate fmt vet  ## Run a controller from your host.
	go run ./main.go

.PHONY: bundle
bundle: generate kustomize  # Generate bundle manifests and metadata, then validate generated files.
	operator-sdk generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | operator-sdk generate bundle -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	operator-sdk bundle validate ./bundle

.PHONY: bundle-build
bundle-build:  # Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: docker-build
docker-build: test  ## Build docker image with the manager.
	docker build -t ${IMG} .

.PHONY: docker-push
docker-push:  ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: generate kustomize  ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: generate kustomize  ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: generate kustomize  ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy:  ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Tooling Binaries

CONTROLLER_GEN = $(shell pwd)/bin/controller-gen
controller-gen: ${CONTROLLER_GEN}  ## Install controller-gen locally if necessary.
${CONTROLLER_GEN}:
	$(call install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION})

CONVERSION_GEN = $(shell pwd)/bin/conversion-gen
conversion-gen: ${CONVERSION_GEN}  ## Install conversion-gen locally if necessary.
${CONVERSION_GEN}:
	$(call install-tool,$(CONVERSION_GEN),k8s.io/code-generator/cmd/conversion-gen@${CONVERSION_GEN_VERSION})

KUSTOMIZE = $(shell pwd)/bin/kustomize
kustomize: ${KUSTOMIZE}  ## Install kustomize locally if necessary.
${KUSTOMIZE}:
	$(call install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v4@${KUSTOMIZE_VERSION})

ENVTEST = $(shell pwd)/bin/setup-envtest
envtest: ${ENVTEST}  ## Install envtest-setup locally if necessary.
${ENVTEST}:
	$(call install-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest@latest)

# install-tool will 'go install' any package $2 and install it to $1.
define install-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp > /dev/null 2>&1 ;\
echo "Downloading $(2)" ;\
go get $(2) > /dev/null 2>&1 ;\
echo "package tmp\nimport (_ \"`echo $(2) | awk -F@ '{print $$1}'`\")" | tee tools.go > /dev/null 2>&1 ;\
go mod tidy ;\
GOBIN=${ROOT_DIR}/bin go install `echo $(2) | cut -d@ -f1` ;\
rm -rf $$TMP_DIR ;\
}
endef

##@ Cleanup

.PHONY: clean
clean: clean-bin clean-temporary  ## Remove all generated files.

.PHONY: clean-bin
clean-bin:  ## Remove all generated binaries.
	@chmod 755 $(shell find ./bin/k8s -type d)
	rm -rf bin
	rm -rf hack/tools/bin

.PHONY: clean-temporary
clean-temporary:  ## Remove all temporary files and folders.
	rm -f minikube.kubeconfig
	rm -f kubeconfig

##@ Help

.PHONY: help
help:  ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
