REPO	= github.com/akaspin/soil
BIN		= soil

BENCH	= .
TESTS	= .

CWD 		= $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
VENDOR 		= $(CWD)/vendor
SRC 		= $(shell find . -type f \( -iname '*.go' ! -iname "*_test.go" \) -not -path "./vendor/*")
SRC_TEST 	= $(shell find . -type f -name '*_test.go' -not -path "./vendor/*")
SRC_VENDOR 	= $(shell find ./vendor -type f \( -iname '*.go' ! -iname "*_test.go" \))
PACKAGES    = $(shell cd $(GOPATH)/src/$(REPO) && go list ./... | grep -v /vendor/)

V=$(shell git describe --always --tags --dirty)
GOOPTS=-installsuffix cgo -ldflags '-s -w -X $(REPO)/command.V=$(V)'


ifdef GOBIN
	INSTALL_DIR=$(GOBIN)
else
    INSTALL_DIR=$(GOPATH)/bin
endif


###
### Test
###

test:
	docker -H 127.0.0.1:2375 run --rm \
		-v /etc/systemd/system:/etc/systemd/system \
		-v /run/systemd/system:/run/systemd/system \
		-v /usr/lib/systemd/system:/usr/lib/systemd/system \
		-v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
		-v /vagrant:/go/src/github.com/akaspin/soil \
		golang:1.8 go test -run=$(TESTS) -p=1 $(PACKAGES)

test-debug:
	docker -H 127.0.0.1:2375 run --rm \
		-v /etc/systemd/system:/etc/systemd/system \
		-v /run/systemd/system:/run/systemd/system \
		-v /usr/lib/systemd/system:/usr/lib/systemd/system \
		-v /var/run/dbus:/var/run/dbus \
		-v /vagrant:/go/src/github.com/akaspin/soil \
		golang:1.8 go test -v -run=$(TESTS) -p=1 -tags="debug" $(PACKAGES)

###
### Dist
###



dist: \
	dist/$(BIN)-$(V)-darwin-amd64.tar.gz \
	dist/$(BIN)-$(V)-linux-amd64.tar.gz

dist-bin-linux: dist/linux/$(BIN) dist/linux/$(BIN)-debug

dist/$(BIN)-$(V)-%-amd64.tar.gz: dist/%/$(BIN) dist/%/$(BIN)-debug
	tar -czf $@ -C ${<D} $(notdir $^)

dist/%/$(BIN): $(SRC) $(SRC_VENDOR)
	@mkdir -p $(@D)
	GOPATH=$(GOPATH) CGO_ENABLED=0 GOOS=$* go build $(GOOPTS) -o $@ $(REPO)/command/$(BIN)

dist/%/$(BIN)-debug: $(SRC) $(SRC_VENDOR)
	@mkdir -p $(@D)
	GOPATH=$(GOPATH) CGO_ENABLED=0 GOOS=$* go build $(GOOPTS) -tags debug -o $@ $(REPO)/command/$(BIN)


###
###	Install
###

install: $(INSTALL_DIR)/$(BIN)
install-debug: $(INSTALL_DIR)/$(BIN)-debug

$(INSTALL_DIR)/$(BIN): $(SRC)
	GOPATH=$(GOPATH) CGO_ENABLED=0 go build $(GOOPTS) -o $@ $(REPO)/command/$(BIN)

$(INSTALL_DIR)/$(BIN)-debug: $(SRC)
	GOPATH=$(GOPATH) CGO_ENABLED=0 go build $(GOOPTS) -tags debug -o $@ $(REPO)/command/$(BIN)


###
### clean
###

clean: clean-dist uninstall

uninstall:
	rm -rf $(INSTALL_DIR)/$(BIN)
	rm -rf $(INSTALL_DIR)/$(BIN)-debug

clean-dist:
	rm -rf dist


.PHONY: test