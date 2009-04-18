all: clean html

clean:
	rm 0* index.html

html:
	cp ../html/* .
	rm -fr ../html
	git add .
	git status
