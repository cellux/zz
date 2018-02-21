.PHONY: install
install:
	@./zz.sh install

.PHONY: build
build:
	@./zz.sh build

.PHONY: test
test:
	@./zz.sh test

.PHONY: clean
clean:
	@./zz.sh clean

.PHONY: distclean
distclean:
	@./zz.sh distclean
