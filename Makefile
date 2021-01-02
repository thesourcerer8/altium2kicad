DESTDIR=/opt/altium2kicad

INSTALL=install

all:

install:
			$(INSTALL) -D -m 0755 unpack.pl $(DESTDIR)$(PREFIX)/bin/a2k-unpack
			$(INSTALL) -D -m 0755 convertschema.pl $(DESTDIR)$(PREFIX)/bin/a2k-convertschema
			$(INSTALL) -D -m 0755 convertpcb.pl $(DESTDIR)$(PREFIX)/bin/a2k-convertpcb
			$(INSTALL) -D -m 0755 altium2kicad $(DESTDIR)$(PREFIX)/bin/altium2kicad
			$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/lib/perl
			cp -fr Math $(DESTDIR)$(PREFIX)/lib/perl

