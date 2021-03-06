#
# in order to use a private copy of openssl instead of the installed one,
# set OPENSSL to the path to the source directory that you built openssl in
#
# OPENSSL := ../openssl-0.9.8i

#
# don't build nm-openconnect-auth-dialog and the ssl UI on a Mac
#
OS=$(shell uname -s)

# Only build the NetworkManager part on Linux
ifeq ($(OS),Linux)
	NMAUTHDIALOG := nm-openconnect-auth-dialog
endif

ifdef RPM_OPT_FLAGS
OPT_FLAGS := $(RPM_OPT_FLAGS)
else
OPT_FLAGS := -O2 -g -Wall
endif

# Allow people to override OpenSSL and build it statically, if they need
# a special build for the DTLS support. $(OPENSSL) points to the build 
# dir; there's no need to install it anywhere (we link it statically).
ifdef OPENSSL
SSL_CFLAGS += -I$(OPENSSL)/include
SSL_LDFLAGS += -lz $(OPENSSL)/libssl.a $(OPENSSL)/libcrypto.a -ldl
else
SSL_CFLAGS += -I/usr/include/openssl
SSL_LDFLAGS += -lssl
endif

XML2_CFLAGS += $(shell xml2-config --cflags) 
XML2_LDFLAGS += $(shell xml2-config --libs)

GTK_CFLAGS += $(shell pkg-config --cflags gtk+-x11-2.0)
GTK_LDFLAGS += $(shell pkg-config --libs gtk+-x11-2.0)

GCONF_CFLAGS += $(shell pkg-config --cflags gconf-2.0)
GCONF_LDFLAGS += $(shell pkg-config --libs gconf-2.0)

CFLAGS := $(OPT_FLAGS) $(SSL_CFLAGS) $(XML2_CFLAGS) $(EXTRA_CFLAGS)
LDFLAGS := $(SSL_LDFLAGS) $(XML2_LDFLAGS) $(EXTRA_LDFLAGS)

ifdef SSL_UI
CFLAGS += -DSSL_UI
endif

ifeq ($(SSL_UI),ssl_ui_gtk.o)
LDFLAGS += $(GTK_LDFLAGS)
endif
CFLAGS_ssl_ui_gtk.o += $(GTK_CFLAGS)	
CFLAGS_nm-auth-dialog.o += $(GTK_CFLAGS) $(GCONF_CFLAGS) $(XML2_CFLAGS)

OPENCONNECT_OBJS := main.o $(SSL_UI) xml.o
CONNECTION_OBJS := dtls.o cstp.o mainloop.o tun.o 
AUTH_OBJECTS := ssl.o http.o version.o securid.o

all: openconnect $(NMAUTHDIALOG)

version.c: $(patsubst %.o,%.c,$(OBJECTS)) openconnect.h $(wildcard .git/index .git/refs/tags) version.sh
	@./version.sh
	@echo -en "New version.c: "
	@cut -f2 -d\" version.c

libopenconnect.a: $(AUTH_OBJECTS)
	$(AR) rcs $@ $^

openconnect: $(OPENCONNECT_OBJS) $(CONNECTION_OBJS) libopenconnect.a
	$(CC) -o $@ $^ $(LDFLAGS)

nm-openconnect-auth-dialog: nm-auth-dialog.o ssl_ui_gtk.o libopenconnect.a 
	$(CC) -o $@ $^ $(LDFLAGS) $(GTK_LDFLAGS) $(GCONF_LDFLAGS) $(XML2_LDFLAGS)

%.o: %.c
	$(CC) -c -o $@ $(CFLAGS) $(CFLAGS_$@) $< -MD -MF .$@.dep

clean:
	rm -f *.o *.a openconnect $(wildcard .*.o.dep)

install:
	mkdir -p $(DESTDIR)/usr/bin $(DESTDIR)/usr/libexec
	install -m0755 openconnect $(DESTDIR)/usr/bin
	install -m0755 nm-openconnect-auth-dialog $(DESTDIR)/usr/libexec

include /dev/null $(wildcard .*.o.dep)

ifdef VERSION
tag:
	@if git diff-index --name-only HEAD | grep ^ ; then \
		echo Uncommitted changes in above files; exit 1; fi
	sed 's/^v=.*/v="v$(VERSION)"/' -i version.sh
	git commit -s -m "Tag version $(VERSION)" version.sh
	git tag v$(VERSION)

tarball:
	git archive --format=tar --prefix=openconnect-$(VERSION)/ v$(VERSION) | gzip -9 > openconnect-$(VERSION).tar.gz
endif

