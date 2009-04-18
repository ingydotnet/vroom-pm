all:
	echo 'No default'

publish:
	(cd ..; perl Makefile.PL; make purge)
	vroom -html
	rm -fr ../../html
	mv html ../../
	git stash
	(cd ..; git co gh-pages; make publish; git co master)
	git stash apply
