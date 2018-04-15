ZZPATH ?= $(HOME)/zz

.PHONY: install
install:
	@./zz.sh install

.PHONY: build
build:
	@./zz.sh build

.PHONY: clean
clean:
	@./zz.sh clean

.PHONY: distclean
distclean:
	@./zz.sh distclean

.PHONY: test
test: install
	@$(ZZPATH)/bin/zz test
