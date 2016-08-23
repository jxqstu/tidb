### Makefile for tidb

# Ensure GOPATH is set before running build process.
ifeq "$(GOPATH)" ""
  $(error Please set the environment variable GOPATH before running `make`)
endif

path_to_add := $(addsuffix /bin,$(subst :,/bin:,$(GOPATH)))
export PATH := $(path_to_add):$(PATH)

GO        := GO15VENDOREXPERIMENT="1" go
ARCH      := "`uname -s`"
LINUX     := "Linux"
MAC       := "Darwin"
PACKAGES  := $$(go list ./...| grep -vE 'vendor')
FILES     := $$(find . | grep -vE 'vendor'| grep '\.go')

LDFLAGS += -X "github.com/pingcap/tidb/util/printer.TiDBBuildTS=$(shell date -u '+%Y-%m-%d %I:%M:%S')"
LDFLAGS += -X "github.com/pingcap/tidb/util/printer.TiDBGitHash=$(shell git rev-parse HEAD)"

TARGET = ""

.PHONY: all build install update parser clean todo test gotest interpreter server goyacc dev

default: server buildsucc

buildsucc:
	@echo Build TiDB Server successfully!

all: dev server install

dev: parser build test check

build:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) build
	rm -rf vendor

install:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) install ./...
	rm -rf vendor

TEMP_FILE = temp_parser_file

goyacc:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) build -o bin/goyacc github.com/pingcap/tidb/parser/goyacc
	rm -rf vendor

parser: goyacc
	rm -rf parser/scanner.go
	bin/goyacc -o /dev/null -xegen $(TEMP_FILE) parser/parser.y
	bin/goyacc -o parser/parser.go -xe $(TEMP_FILE) parser/parser.y 2>&1 | egrep "(shift|reduce)/reduce" | awk '{print} END {if (NR > 0) {print "Find conflict in parser.y. Please check y.output for more information."; system("rm -f $(TEMP_FILE)"); exit 1;}}'
	rm -f $(TEMP_FILE)
	rm -f y.output

	@if [ $(ARCH) = $(LINUX) ]; \
	then \
		sed -i -e 's|//line.*||' -e 's/yyEofCode/yyEOFCode/' parser/parser.go; \
	elif [ $(ARCH) = $(MAC) ]; \
	then \
		/usr/bin/sed -i "" 's|//line.*||' parser/parser.go; \
		/usr/bin/sed -i "" 's/yyEofCode/yyEOFCode/' parser/parser.go; \
	fi

	@awk 'BEGIN{print "// Code generated by goyacc"} {print $0}' parser/parser.go > tmp_parser.go && mv tmp_parser.go parser/parser.go;

check:
	bash gitcookie.sh
	go get github.com/golang/lint/golint

	@echo "vet"
	@ go tool vet $(FILES) 2>&1 | awk '{print} END{if(NR>0) {exit 1}}'
	@echo "vet --shadow"
	@ go tool vet --shadow $(FILES) 2>&1 | awk '{print} END{if(NR>0) {exit 1}}'
	@echo "golint"
	@ golint $(PACKGES) 2>&1 | grep -vE 'LastInsertId|NewLexer|\.pb\.go' | awk '{print} END{if(NR>0) {exit 1}}'
	@echo "gofmt (simplify)"
	@ gofmt -s -l -w $(FILES) 2>&1 | awk '{print} END{if(NR>0) {exit 1}}'

errcheck:
	go get github.com/kisielk/errcheck
	errcheck -blank $(PACKAGES)

clean:
	$(GO) clean -i ./...
	rm -rf *.out

todo:
	@grep -n ^[[:space:]]*_[[:space:]]*=[[:space:]][[:alpha:]][[:alnum:]]* */*.go parser/parser.y || true
	@grep -n TODO */*.go parser/parser.y || true
	@grep -n BUG */*.go parser/parser.y || true
	@grep -n println */*.go parser/parser.y || true

test: gotest

gotest:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test -cover $(PACKAGES)
	rm -rf vendor

race:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test --race $(PACKAGES)
	rm -rf vendor

tikv_integration_test:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test ./store/tikv/. -with-tikv=true
	rm -rf vendor

interpreter:
	rm -rf vendor && ln -s _vendor/vendor vendor
	@cd interpreter && $(GO) build -ldflags '$(LDFLAGS)'
	rm -rf vendor

server: parser
ifeq ($(TARGET), "")
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) build -ldflags '$(LDFLAGS)' -o bin/tidb-server tidb-server/main.go
	rm -rf vendor
else
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) build -ldflags '$(LDFLAGS)' -o '$(TARGET)' tidb-server/main.go
	rm -rf vendor
endif
