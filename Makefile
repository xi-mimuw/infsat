SOURCE = flags.ml profiling.ml utilities.ml sortedList.ml setQueue.ml twoLayerQueue.ml batchQueue.ml syntax.ml infSatParser.mli infSatParser.ml infSatLexer.ml grammarCommon.ml grammar.ml conversion.ml stype.ml hGrammar.ml cfa.ml type.ml typing.ml main.ml

all: infsat-debug TAGS

infSatParser.mli infSatParser.ml: infSatParser.mly
	ocamlyacc infSatParser.mly
infSatLexer.ml: infSatLexer.mll
	ocamllex infSatLexer.mll

infsat: $(SOURCE) wrapper.ml
# -unsafe can be considered
	ocamlopt -inline 1000 -o infsat unix.cmxa $^

top: $(SOURCE)
	ocamlmktop -o top unix.cma $(SOURCE)

 infsat-debug: $(SOURCE) wrapper.ml
	ocamlc -g -o infsat-debug unix.cma $^

test: $(SOURCE) test.ml
	ocamlfind ocamlc -o test -package oUnit -linkpkg -g $^

run-test: test
	./test -runner sequential -no-cache-filename -no-output-file

TAGS: $(SOURCE)
	ctags -e $(SOURCE)

doc: $(SOURCE)
	ocamldoc -html -d doc $(SOURCE)

.SUFFIXES:
	.ml .cmo .mli .cmi

.PHONY:
	all clean run-test

clean:
	rm -f *.cmi *.cmx *.o *.cmo *.cmt *.cmti *.exe infsat top infSatParser.ml infSatParser.mli infSatLexer.ml TAGS infsat-debug test oUnit-*
