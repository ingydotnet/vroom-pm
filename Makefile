# The Zilla::Dist Makefile
#
# This is the shared Zilla::Dist Makefile. Most of the `zild` commands simply
# invoke this Makefile from the installed share directory for Zilla::Dist.
#
# For instance, both of these commands:
#
#   zild update
#   zild make update
#
# just invoke:
#
#   make -f `zild makefile` update

.PHONY: cpan test

SHELL := bash
MAKE_FILE := $(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
ROOT := $(shell dirname $(dir $(MAKE_FILE)))
BASE := $(shell pwd)
MAKE := make -f $(MAKE_FILE)
PERL ?= $(shell which perl)
ZILD := $(PERL) -S zild
LOG := $(PERL_ZILLA_DIST_RELEASE_LOG)
export PATH := $(BASE)/bin:$(PATH)

# XXX Change to `metaspec =zild libname`
NAMEPATH := $(shell $(ZILD) meta =zild/libname)
NAMEPATH := $(subst ::,/,$(NAMEPATH))
ifeq (,$(NAMEPATH))
NAMEPATH := $(shell $(ZILD) meta name)
endif
NAME := $(shell $(ZILD) meta name)
VERSION := $(shell $(ZILD) meta version)
RELEASE_BRANCH ?= $(shell $(ZILD) meta branch)

DISTDIR := $(NAME)-$(VERSION)
DIST := $(DISTDIR).tar.gz
NAMEPATH := $(subst -,/,$(NAMEPATH))
SUCCESS := "$(DIST) Released!!!"

README :=
ifeq (,$(shell zild meta =zild/no-readme))
  ifneq (,$(wildcard $(BASE)/ReadMe.pod))
    README := ReadMe.pod
  endif
  ifneq (,$(wildcard $(BASE)/ReadMe.md))
    README := ReadMe.md
  endif
endif

export TESTML_RUN := perl

default: help

help:
	@echo 'Makefile targets:'
	@echo ''
	@echo '    make test      - Run the repo tests'
	@echo '    make test-dev  - Run the developer only tests'
	@echo '    make test-all  - Run all tests'
	@echo '    make test-cpan - Make cpan/ dir and run tests in it'
	@echo '    make test-dist - Run the dist tests'
	@echo ''
	@echo '    make install   - Install the dist from this repo'
	@echo '    make prereqs   - Install the CPAN prereqs'
	@echo '    make update    - Update generated files'
	@echo '    make release   - Release the dist to CPAN'
	@echo ''
	@echo '    make cpan      - Make cpan/ dir with dist.ini'
	@echo '    make cpanshell - Open new shell into new cpan/'
	@echo ''
	@echo '    make dist      - Make CPAN distribution tarball'
	@echo '    make distdir   - Make CPAN distribution directory'
	@echo '    make distshell - Open new shell into new distdir'
	@echo ''
	@echo '    make upgrade   - Upgrade the build system (Makefile)'
	@echo '    make readme    - Make the ReadMe.pod file'
	@echo '    make travis    - Make a travis.yml file'
	@echo '    make uninstall - Uninstall the dist from this repo'
	@echo ''
	@echo '    make clean     - Clean up build files'
	@echo '    make help      - Show this help'
	@echo ''

#------------------------------------------------------------------------------
# Test Targets:
#------------------------------------------------------------------------------
test:
ifeq ($(wildcard pkg/no-test),)
ifneq ($(wildcard test),)
	$(PERL) -S prove -lv test
endif
else
	@echo "Testing not available. Use 'test-dist' instead."
endif

test-dev:
ifneq ($(wildcard test/devel),)
	$(PERL) -S prove -lv test/devel
endif

test-all: test test-dev

test-cpan cpantest: cpan
ifeq ($(wildcard pkg/no-test),)
	@echo '***** Running tests in `cpan/` directory'
	(cd cpan; $(PERL) -S prove -lv t) && make clean
else
	@echo "Testing not available. Use 'test-dist' instead."
endif

test-dist disttest: cpan
	@echo '***** Running tests in `$(DISTDIR)` directory'
	(cd cpan; dzil test) && $(MAKE) clean

#------------------------------------------------------------------------------
# Installation Targets:
#------------------------------------------------------------------------------
install: distdir
	@echo '***** Installing $(DISTDIR)'
	(cd $(DISTDIR); $(PERL) Makefile.PL; make install)
	$(MAKE) clean

prereqs:
	cpanm `$(ZILD) meta requires`

update:
	@echo '***** Updating/regenerating repo content'
	$(MAKE) readme about travis version webhooks

#------------------------------------------------------------------------------
# Release and Build Targets:
#------------------------------------------------------------------------------
release:
ifneq ($(LOG),)
	@echo "$$(date) - Release $(DIST) STARTED" >> $(LOG)
endif
	$(MAKE) clean
	$(MAKE) update
	$(MAKE) check-release
	$(MAKE) date
	$(MAKE) test-all
	RELEASE_TESTING=1 $(MAKE) test-dist
	@echo '***** Releasing $(DISTDIR)'
	$(MAKE) dist
ifneq ($(PERL_ZILLA_DIST_RELEASE_TIME),)
	@echo $$(( ( $$PERL_ZILLA_DIST_RELEASE_TIME - $$(date +%s) ) / 60 )) \
	minutes, \
	$$(( ( $$PERL_ZILLA_DIST_RELEASE_TIME - $$(date +%s) ) % 60 )) \
	seconds, until RELEASE TIME!
	@echo sleep $$(( $$PERL_ZILLA_DIST_RELEASE_TIME - $$(date +%s) ))
	@sleep $$(( $$PERL_ZILLA_DIST_RELEASE_TIME - $$(date +%s) ))
endif
	cpan-upload $(DIST)
ifneq ($(LOG),)
	@echo "$$(date) - Release $(DIST) UPLOADED" >> $(LOG)
endif
	$(MAKE) clean
	[ -z "$$(git status -s)" ] || zild-git-commit
	git push
	git tag $(VERSION)
	git push --tag
	$(MAKE) clean
ifneq ($(PERL_ZILLA_DIST_AUTO_INSTALL),)
	@echo "***** Installing after release"
	$(MAKE) install
endif
	@echo
	git status
	@echo
	@[ -n "$$(which cowsay)" ] && cowsay "$(SUCCESS)" || echo "$(SUCCESS)"
	@echo
ifneq ($(LOG),)
	@echo "$$(date) - Release $(DIST) COMPLETED" >> $(LOG)
endif

cpan:
	@echo '***** Creating the `cpan/` directory'
	zild-make-cpan

cpanshell: cpan
	@echo '***** Starting new shell in `cpan/` directory'
	(cd cpan; $$SHELL)
	$(MAKE) clean

dist: clean cpan
	@echo '***** Creating new dist: $(DIST)'
	(cd cpan; dzil build)
	mv cpan/$(DIST) .
	rm -fr cpan

distdir: clean cpan
	@echo '***** Creating new dist directory: $(DISTDIR)'
	(cd cpan; dzil build)
	mv cpan/$(DIST) .
	tar xzf $(DIST)
	rm -fr cpan $(DIST)

distshell: distdir
	@echo '***** Starting new shell in `$(DISTDIR)` directory'
	(cd $(DISTDIR); $$SHELL)
	$(MAKE) clean

upgrade:
	@echo '***** Checking that Zilla-Dist Makefile is up to date'
	cp `$(ZILD) sharedir`/Makefile ./

readme: $(README)

ReadMe.pod:
ifneq (,$(wildcard doc/$(NAMEPATH).md))
	cat doc/$(NAMEPATH).md | \
	  zild-markdown-plus \
	  pandoc --from=gfm --to=json | \
	  zild-pandoc-json-to-pod \
	  > $@
else
	swim --to=pod --complete --wrap --meta=Meta \
	  doc/$(NAMEPATH).swim > $@
endif

ReadMe.md: doc/$(NAMEPATH).md force
	zild-markdown-plus < $< > $@

about:
ifeq (,$(shell zild meta =zild/no-about))
	$(PERL) -S zild-render-template About
endif

travis:
ifeq (,$(shell zild meta =zild/no-travis))
	$(PERL) -S zild-render-template travis.yml .travis.yml
endif

uninstall: distdir
	(cd $(DISTDIR); $(PERL) Makefile.PL; make uninstall)
	$(MAKE) clean

clean:
	rm -fr blib cpan .build .inline $(DIST) $(DISTDIR)
	find . -type d | grep '\.testml' | xargs rm -fr

distclean purge: clean

force:
	true

#------------------------------------------------------------------------------
# Non-pulic-facing targets:
#------------------------------------------------------------------------------
check-release:
	@echo '***** Checking readiness to release $(DIST)'
	RELEASE_BRANCH=$(RELEASE_BRANCH) zild-check-release
	git stash
	rm -fr .git/rebase-apply
	git pull --rebase origin $(RELEASE_BRANCH)
	git stash pop

date:
	$(ZILD) changes date "`date`"

version:
	$(PERL) -S zild-version-update

webhooks:
	$(PERL) -S zild webhooks
