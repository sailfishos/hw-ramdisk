TOOLS_PATH=./initfs/tools

tools: gen_init_cpio reboot2 evkey rtc-clear install_util

install_util:
	install -d ./sbin
	install -d ./bin
	install -d ./tools
	install -m 755 $(TOOLS_PATH)/reboot2 ./sbin
	install -m 755 $(TOOLS_PATH)/evkey ./sbin
	install -m 755 $(TOOLS_PATH)/gen_init_cpio ./tools
	install -m 755 $(TOOLS_PATH)/rtc-clear ./sbin

gen_init_cpio: $(TOOLS_PATH)/gen_init_cpio.c
	gcc -Wall -O2 -D_FILE_OFFSET_BITS=64 $(TOOLS_PATH)/gen_init_cpio.c -o $(TOOLS_PATH)/gen_init_cpio -Wl,--no-as-needed
	strip $(TOOLS_PATH)/gen_init_cpio

reboot2: $(TOOLS_PATH)/reboot2.c
	gcc -Wall -O2 $(TOOLS_PATH)/reboot2.c -o $(TOOLS_PATH)/reboot2 -Wl,--no-as-needed
	strip $(TOOLS_PATH)/reboot2

evkey: $(TOOLS_PATH)/evkey.c
	gcc -Wall -O2 $(TOOLS_PATH)/evkey.c -o $(TOOLS_PATH)/evkey -Wl,--no-as-needed
	strip $(TOOLS_PATH)/evkey

rtc-clear:
	gcc -Wall -O2 $(TOOLS_PATH)/rtc-clear.c -o $(TOOLS_PATH)/rtc-clear -Wl,--no-as-needed
	strip $(TOOLS_PATH)/rtc-clear

tools_clean:
	rm -f $(TOOLS_PATH)/gen_init_cpio $(TOOLS_PATH)/reboot2 $(TOOLS_PATH)/evkey $(TOOLS_PATH)/rtc-clear *~
	rm -rf tools
