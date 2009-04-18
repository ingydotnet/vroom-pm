all:
	echo 'No default'

publish:
	vroom -html
	mv html ../../
	git stash
	git co gh-pages
	make publish
	git co master
	git stash apply
