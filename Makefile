SHELL := /bin/bash
REPO	= github.com/da-moon/soil
BIN		= soil

TESTS	      = .
TEST_TAGS     =
TEST_ARGS     =
BENCH	      = .

TEST_PACKAGES ?= ./...

GO_IMAGE    = golang:1.16
CWD 		= $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

V           = $(shell git describe --always --tags --dirty)
GOOPTS      = -installsuffix cgo -ldflags '-s -w -X $(REPO)/proto.Version=$(V)'
GOBIN       ?= $(GOPATH)/bin


sources: 		## go fmt and vet
	go fmt ./...
	go vet ./...

deps:			## update vendor
	dep ensure -v

###
### Test
###

test: test-unit test-cluster test-systemd		## run all tests

clean-test: clean-test-systemd		## clean test artifacts
	-find . -name ".test_*" -exec rm -rf {} \;
	-find /tmp -name ".test_*" -exec rm -rf {} \;

test-unit: 		## run unit tests
	go test -race -run=$(TESTS) $(TEST_ARGS) -tags="test_unit $(TEST_TAGS)" $(TEST_PACKAGES)

test-cluster:
	go test -race -run=$(TESTS) -p=1 $(TEST_ARGS) -tags="test_cluster $(TEST_TAGS)" $(TEST_PACKAGES)

test-systemd: testdata/systemd/.vagrant-ok	## run SystemD tests
	docker -H 127.0.0.1:2475 run --net=host --rm --name=test \
	-v /run/soil:/run/soil \
	-v /var/lib/soil:/var/lib/soil \
	-v /run/systemd/system:/run/systemd/system \
	-v /etc/systemd/system:/etc/systemd/system \
	-v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v /vagrant:/go/src/github.com/da-moon/soil \
	-v /tmp:/tmp \
	$(GO_IMAGE) go test -race -run=$(TESTS) -p=1 $(TEST_ARGS) -tags="test_systemd $(TEST_TAGS)" $(TEST_PACKAGES)

testdata/systemd/.vagrant-ok: testdata/systemd/Vagrantfile
	cd testdata/systemd && vagrant up --parallel
	touch testdata/systemd/.vagrant-ok

clean-test-systemd:	## clean Systemd tests artifacts
	-cd testdata/systemd && vagrant destroy -f
	-rm -rf testdata/systemd/.vagrant*

coverage: testdata/systemd/.vagrant-ok	## run SystemD tests
	docker -H 127.0.0.1:2475 run --net=host --rm --name=test \
	-v /run/soil:/run/soil \
	-v /var/lib/soil:/var/lib/soil \
	-v /run/systemd/system:/run/systemd/system \
	-v /etc/systemd/system:/etc/systemd/system \
	-v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v /vagrant:/go/src/github.com/da-moon/soil \
	-v /tmp:/tmp \
	--workdir /go/src/github.com/da-moon/soil \
	$(GO_IMAGE) ./testdata/ci/run-coverage.sh


###
### Dist
###

#dist: \
#	dist/$(BIN)-$(V)-darwin-amd64.tar.gz \
#	dist/$(BIN)-$(V)-linux-amd64.tar.gz
#
#dist/$(BIN)-$(V)-%-amd64.tar.gz: dist/%/$(BIN) dist/%/$(BIN)-debug
#	tar -czf $@ -C ${<D} $(notdir $^)
#
#dist/%/$(BIN): $(SRC) $(ALL_SRC)
#	@mkdir -p $(@D)
#	GOPATH=$(GOPATH) CGO_ENABLED=0 GOOS=$* go build $(GOOPTS) -o $@ $(REPO)/cmd/$(BIN)
#
#dist/%/$(BIN)-debug: $(SRC) $(ALL_SRC)
#	@mkdir -p $(@D)
#	GOPATH=$(GOPATH) CGO_ENABLED=0 GOOS=$* go build $(GOOPTS) -tags debug -o $@ $(REPO)/cmd/$(BIN)
#
#docker-image: dist/$(BIN)-$(V)-linux-amd64.tar.gz
#	docker build --build-arg V=$(V) -t soil-local:$(V) -f Dockerfile.local .
#
#clean-dist:
#	rm -rf dist

###
###	Install
###

#install: $(GOBIN)/$(BIN)
#install-debug: $(GOBIN)/$(BIN)-debug
#
#$(GOBIN)/$(BIN): $(SRC) $(ALL_SRC)
#	GOPATH=$(GOPATH) CGO_ENABLED=0 go build $(GOOPTS) -o $@ $(REPO)/cmd/$(BIN)
#
#$(GOBIN)/$(BIN)-debug: $(SRC) $(ALL_SRC)
#	GOPATH=$(GOPATH) CGO_ENABLED=0 go build $(GOOPTS) -tags debug -o $@ $(REPO)/cmd/$(BIN)
#
#uninstall:
#	rm -rf $(GOBIN)/$(BIN)
#	rm -rf $(GOBIN)/$(BIN)-debug

###
### clean
###

clean: clean-docs clean-test

###
### docs
###

docs:
	docker run --rm -v $(CWD)/docs:/site -p 4000:4000 andredumas/github-pages serve --watch

clean-docs:
	rm -rf docs/_site


.SILENT: bootstrap
.PHONY: bootstrap
bootstrap:
	- go env -w "GO111MODULE=on"
	- go env -w "CGO_ENABLED=0"
	- go env -w "CGO_LDFLAGS=-s -w -extldflags '-static'"
	- go clean -modcache
	- go mod tidy
	- go generate -tags tools tools.go

build: bootstrap
	mage build

.PHONY: \
	docs \
	test test-unit \
	test-systemd \
	clean
