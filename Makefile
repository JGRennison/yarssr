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
				$(DESTDIR)/$(DATADIR) \
				$(DESTDIR)/$(LIBDIR) \
				$(DESTDIR)/$(LOCALEDIR)/en/$(LC_CATEGORY) \
				$(DESTDIR)/$(LOCALEDIR)/de/$(LC_CATEGORY)
			
	@echo Copying lib files to $(DESTDIR)/$(DATADIR):
	@cp -Rp lib/* $(DESTDIR)/$(LIBDIR)/
	@echo Copying share files to $(DESTDIR)/$(DATADIR):
	@cp -Rp share/* $(DESTDIR)/$(DATADIR)/

	find $(DESTDIR)/$(DATADIR) -type f -exec chmod 644 "{}" \;
	find $(DESTDIR)/$(LIBDIR) -type f -exec chmod 644 "{}" \;

	install -m 0644 build/locale/en/$(LC_CATEGORY)/yarssr.mo $(DESTDIR)/$(LOCALEDIR)/en/$(LC_CATEGORY)/
	install -m 0644 build/locale/de/$(LC_CATEGORY)/yarssr.mo $(DESTDIR)/$(LOCALEDIR)/de/$(LC_CATEGORY)/
	install -m 0755 build/yarssr	$(DESTDIR)/$(BINDIR)

clean:
	rm -rf build

cleancvs:
	find . -name CVS -type d -exec rm -rf '{}' \;

uninstall:
	rm -rf	$(BINDIR)/yarssr \
		$(LIBDIR) \
		$(DATADIR)/yarssr
		
.PHONY: all yarssr clean install uninstall
