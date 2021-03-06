OPTS= -use-ocamlfind
BUILD=build
OCAMLBUILD := $(shell ocamlbuild -where 2> /dev/null)
S=$(abspath .)

all: alt-codept

ifdef OCAMLBUILD
all:codept_ocamlbuild
endif

alternative: lib/*.ml lib/*.mli full/*.ml full/*.mli precomputed/*.ml tests/*.ml
	make -C $(BUILD) -j

alt-%:
	make -C build -j $S/$*

alt2-%:
	make -C build -j $*


codept: lib/*.ml lib/*.mli full/*.ml full/*.mli precomputed/*.ml
	ocamlbuild $(OPTS) codept.native\
		&& mv codept.native codept

codept_ocamlbuild: ocamlbuild_plugin/*.ml
	ocamlbuild -no-ocamlfind -cflags -I,$(OCAMLBUILD) codept_ocamlbuild.otarget

clean:
	ocamlbuild -clean && cd build && make clean

tests: tests/**/*.ml test-run test-serialization codept
	./test-run && ./test-serialization

test-%: tests/%.ml codept
	ocamlbuild $(OPTS) $*.native && mv $*.native $@ 

%.native: full/%.ml
	ocamlbuild $(OPTS) $*.native 

codept-server: codept_server.native
	mv codept_server.native codept-server

codept-client: codept_client.native
	mv codept_client.native codept-client

doc: codept
	ocamlbuild $(OPTS) -docflags -charset,utf-8 codept.docdir/index.html

self_test:
	ln -s ocamlbuild/myocamlbuild_cs.ml myocamlbuild.ml; \
	ocamlbuild $(OPTS) -use-ocamldep codept.native; \
	rm myocamlbuild.ml

self_ref: OPTS = -use-ocamlfind -use-ocamldep

self_ref:codept

self_clean:
	ocamlbuild -clean
