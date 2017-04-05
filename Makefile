HERE=$(shell pwd)
PREFIX=/usr/local
BINDIR=$(PREFIX)/bin
SHAREDIR=$(PREFIX)/share
RESOURCEDIR=$(SHAREDIR)/blablacar
RESOURCES=$(HERE)/lib/*
BINARIES=$(HERE)/blablacar.rb

all: help

help:
	@echo "Usage:"
	@echo "	 make install                     # install"
	@echo "	 make uninstall                   # uninstall"
	@echo

# May need to be run as root
install:
	install -d $(BINDIR) $(RESOURCEDIR)
	install -v $(BINARIES) $(BINDIR)
	install -v -m 644 $(RESOURCES) $(RESOURCEDIR)

# May need to be run as root
uninstall:
	test -d $(BINDIR) && \
	cd $(BINDIR) && \
	rm -f blablacar.rb
	test -d $(SHAREDIR) && \
	cd $(SHAREDIR) && \
	rm -rf blablacar

.PHONY: all help install uninstall
