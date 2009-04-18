all: clean html

clean:
	rm 0* index.html

html:
	cp ../html/* .
	rm -fr ../html

publish: html
	git add .
	git commit -a -m 'new content'
	git push