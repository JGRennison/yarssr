PREFIX=/usr
BINDIR=$(PREFIX)/bin
LIBDIR=$(PREFIX)/share/yarssr
DATADIR=$(PREFIX)/share
LOCALEDIR=$(DATADIR)/locale

LC_CATEGORY=LC_MESSAGES

all: yarssr

yarssr:
	@mkdir -p build

	perl -ne 's!\@PREFIX\@!$(PREFIX)!g ; s!\@LIBDIR\@!$(LIBDIR)!g ; print' < src/yarssr > build/yarssr

	mkdir -p build/locale/en/$(LC_CATEGORY)
	msgfmt -o build/locale/en/$(LC_CATEGORY)/yarssr.mo src/po/en.po
	mkdir -p build/locale/de/$(LC_CATEGORY)
	msgfmt -o build/locale/de/$(LC_CATEGORY)/yarssr.mo src/po/de.po

install:
	mkdir -p	$(DESTDIR)/$(BINDIR) \
				$(DESTDIR)/$(DATADIR)/yarssr/pixmaps \
				$(DESTDIR)/$(LIBDIR)/Yarssr \
				$(DESTDIR)/$(LOCALEDIR)/en/$(LC_CATEGORY) \
				$(DESTDIR)/$(LOCALEDIR)/de/$(LC_CATEGORY)

	@echo Copying lib files to $(DESTDIR)/$(DATADIR):
	install -m 0644 lib/Yarssr.pm $(DESTDIR)/$(LIBDIR)/
	install -m 0644 -t $(DESTDIR)/$(LIBDIR)/Yarssr/ lib/Yarssr/*.pm

	@echo Copying share files to $(DESTDIR)/$(DATADIR):
	install -m 0644 share/yarssr/yarssr.glade $(DESTDIR)/$(DATADIR)/yarssr/
	install -m 0644 -t $(DESTDIR)/$(DATADIR)/yarssr/pixmaps/ share/yarssr/pixmaps/*.png share/yarssr/pixmaps/*.xpm

	install -m 0644 build/locale/en/$(LC_CATEGORY)/yarssr.mo $(DESTDIR)/$(LOCALEDIR)/en/$(LC_CATEGORY)/
	install -m 0644 build/locale/de/$(LC_CATEGORY)/yarssr.mo $(DESTDIR)/$(LOCALEDIR)/de/$(LC_CATEGORY)/
	install -m 0755 build/yarssr	$(DESTDIR)/$(BINDIR)

clean:
	rm -rf build

uninstall:
	rm -rf	$(BINDIR)/yarssr \
		$(LIBDIR) \
		$(DATADIR)/yarssr

.PHONY: all yarssr clean install uninstall
