PREFIX ?= /usr

default: all

include initfs/tools/Makefile

initfs.tar.bz2: tools
	tar -cjf initfs.tar.bz2 initfs/skeleton/ sbin/evkey \
		 sbin/reboot2 initfs/tools/gen_init_cpio

all: initfs.tar.bz2

install: all
	install -d $(DESTDIR)$(PREFIX)/sbin/
	install -m 755 initfs/scripts/*.sh $(DESTDIR)$(PREFIX)/sbin/
	install -D initfs.tar.bz2 $(DESTDIR)$(PREFIX)/share/hw-ramdisk/initfs.tar.bz2

clean: tools_clean
	rm -f initfs.tar.bz2

