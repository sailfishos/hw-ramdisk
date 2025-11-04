#!/bin/bash
#
# Script to build MOSLO as a kernel and initrd combination which can be loaded
# to RAM
#
# Copyright 2010, Nokia Corporation
#
# Janne Lääkkö <janne.laakko@nokia.com>
# 08/2010
# Peter Antoniac <peter.antoniac@nokia.com>
#       * Fix the ldd issues in OBS transcoding
# 05/2011
#
# 12/2013
# Andrea Bernabei <andrea.bernabei@jollamobile.com>
#       * Jolla recovery for SBJ device


print_usage()
{
echo    "Usage: $0 -w <build-dir> -m <modules-dir>" \
        "-v <software version> [-t <tar-archive-name>] [-a <module-names>] [-l]"
}


#TODO find a way to automatically detect dlopen library dependencies

is_elf()
{
        local FILE_INFO=$(file -L $1)

        if [ "ELF" == "$(echo $FILE_INFO | \
                sed 's/.*\(ELF\)\(.*\)/\1/')" ] ; then
                return 1
        else
                return 0
        fi
}

is_dynamic()
{
        local FILE_INFO=$(file -L $1)

        if [ "dynamically" == "$(echo $FILE_INFO | \
                sed 's/.*\(dynamically\)\(.*\)/\1/')" ] ; then
                return 1
        else
                return 0
        fi
}

DEBUG=0

debug()
{
        if [ $DEBUG -eq 1 ] ; then
                echo -e "DEBUG: $@"
        fi
}

raw_find_libpath()
{
        if test -z "$1"; then
                echo "$0: Error: Empty library name!" 1>&2
                exit 1
        fi

        for path in /usr/lib /lib; do
                if find $path | grep -q -m 1 "$1"; then
                        echo $path/$1
                        return 0
                fi
        done
        return 1
}

# Recursive function to find all lib dependencies for a binary using objdump
# $1 path of library / executable to search deps for
# $2 temporary search file to store intermediate results, rm -f after call.
objdump_find_lib_paths()
{
        local RECURSED_LIBS=""
        local LIB_LIST=""
        local FOUND_LIB=""
        local FOUND_LIBS=""

        if test -z $1; then
                echo "$0: Error: Empty executable name!" 1>&2
                exit 1
        fi

        if ! test -f $2; then
                echo "$0: Error: No temporary list file provided!" 1>&2
                exit 1
        fi

        if cat $2 | grep -w $1; then
                # This library is already in the list, skipping.
                return
        else
                # Clean up temp file from duplicates
                SORTED_FILE=$(cat $2 | sort -u)
                echo $SORTED_FILE > $2
                # Add the given lib / binary to list file
                echo $1 >> $2
        fi

        if [ $DEBUG -eq 1 ] ; then
                echo "DEBUG: resolving $1, FILE LIST:" 1>&2
                cat $2 1>&2
                echo "***************************************" 1>&2
        fi

        LIB_LIST=$(objdump -p "$1" | grep NEEDED | sed -e 's/\NEEDED//g')
        for lib in $LIB_LIST; do
                # Get the library path from ldconfig's library cache list
                FOUND_LIB=$(ldconfig -p | grep $lib | cut -d ">" -f 2)
                if test -z "$FOUND_LIB"; then
                        # Fall back to find | grep based raw search
                        FOUND_LIB=$(raw_find_libpath $lib)
                        if test -z "$FOUND_LIB"; then
                                echo "Error: Could not find $lib from ldconfig -p" 1>&2
                                exit 1
                        fi
                fi
                FOUND_LIBS="$FOUND_LIBS $FOUND_LIB"
        done

        RECURSED_LIBS="$FOUND_LIBS"

        for recursed_lib in $RECURSED_LIBS; do
                if cat $2 | grep -w $recursed_lib; then
                        continue
                else
                        FOUND_LIBS="$FOUND_LIBS $(objdump_find_lib_paths $recursed_lib $2)"
                fi
        done

        # Sort out duplicates to reduce amount of recursion.
        FOUND_LIBS=$(echo $FOUND_LIBS | sed -e "s/ /\n/g" | sort -u)

        echo "$FOUND_LIBS"
}

add_dependencies()
{
        local INPUT_FILE=$1
        local OUTPUT_FILE=$2

        local CHECK=$(cat $INPUT_FILE | sort | uniq)
        local DEP_FILE=$(mktemp -t ldout.XXXX)
        local SEARCH_FILE=$(mktemp -t objdump-out.XXXX)
        local LIBC=$(find /lib/ -name "libc.*")
        local DEP=""

        #Loop through all files in input list
        for i in $CHECK ; do
                debug "CHECKING FILE $i"
                #Check that the file is ELF
                if is_elf $i ; then
                        debug "Not an ELF file!"
                        continue
                else
                        debug "Is ELF file!"
                fi

                #Check that the file exist
                if [ ! -f $i ] ; then
                        echo "ERROR: $i does not exist!"
                        echo "Check build dependencies!"
                        exit 1
                fi

                #Check that the file is dynamically linked
                if is_dynamic $i ; then
                        debug "Not a dynamically linked file!"
                        continue
                else
                        debug "Is dynamically linked file!"
                fi

                DEP=$(objdump_find_lib_paths $i $SEARCH_FILE)

                debug "Dependencies:"
                if [ "$DEBUG" -eq "1" ] ; then
                        echo "$DEP" | sed -e "s/ /\n/g"
                fi

                echo $DEP | sed -e "s/ /\n/g"  >> $DEP_FILE
        done

        #Add input file content and their dependencies to output file
        cat $DEP_FILE $INPUT_FILE | sort | uniq > $OUTPUT_FILE
        rm -f $DEP_FILE
        rm -f $SEARCH_FILE
}

#
# get commandline parameters
#
echo
echo "Options:"
while getopts "w:k:m:v:t:a:l" opt; do
    case $opt in
        w)
            WORK_DIR=$OPTARG
            echo "Working directory: $WORK_DIR"
            ;;
        m)
            KERNEL_MOD_DIR=$OPTARG
            echo "Modules directory: $KERNEL_MOD_DIR"
            ;;
        v)
            BUILD_VERSION=$OPTARG
            echo "Version $BUILD_VERSION"
            ;;
        t)
            TAR_FILE=$OPTARG
            echo "Output tar file $TAR_FILE"
            ;;
        a)
            USER_MODULES=$OPTARG
            echo "Additional modules: $USER_MODULES"
            ;;
        l)
            USE_LZ4=true
            echo "Use lz4 compression"
            ;;
        \?)
            print_usage
            exit 1
            ;;
    esac
done
echo

[ -z "$WORK_DIR" ] && {
        print_usage
        exit 1
}

[ -d "$WORK_DIR" ] || {
        echo Working directory must exist
        exit 1
}

# Make sure sbin is in path in the build env.
export PATH="/sbin:$PATH"

#
# check and cleanup
#
BUILD_SRC=$WORK_DIR/initfs/skeleton
SCRIPTS_PATH=$WORK_DIR/initfs/scripts
TOOLS_PATH=$WORK_DIR/initfs/tools
PATH=$PATH:$SCRIPTS_PATH:$WORK_DIR/usr/bin:$TOOLS_PATH
ROOT_DIR=$WORK_DIR/rootfs
BUILD_VERSION_DIR=$ROOT_DIR/etc

KERNEL_MODS="g_nokia g_file_storage sep_driver twl4030_keypad g_multi $USER_MODULES" 
KERNEL_MOD_DEP=$KERNEL_MOD_DIR/modules.dep

UTIL_LIST=$BUILD_SRC/util-list
DIR_LIST=$BUILD_SRC/dir-list

if [ ! -z "$KERNEL_MOD_DIR" ]; then

        [ -d "$KERNEL_MOD_DIR" ] || {
                echo Cannot find kernel modules directory $KERNEL_MOD_DIR
                exit 1
        }

        ( [ -h "$KERNEL_MOD_DIR" ] && {
                KERNEL_MOD_DIR_NAME=$(basename $(readlink $KERNEL_MOD_DIR))
        } ) || {
                KERNEL_MOD_DIR_NAME=$(basename $KERNEL_MOD_DIR)
        }
fi

rm -rf $ROOT_DIR $WORK_DIR/rootfs.cpio

# Create directory skeleton
mkdir -p $ROOT_DIR
mkdir -p -m755 $(cat $DIR_LIST | sed s!^!$ROOT_DIR!)

#install init
install -m 755 $BUILD_SRC/init $ROOT_DIR/init || exit 1

mkdir -p $BUILD_VERSION_DIR
echo "$BUILD_VERSION" > $BUILD_VERSION_DIR/moslo-version

# Install other files
install -m644 $BUILD_SRC/fstab $ROOT_DIR/etc/fstab || exit 1

# Install moslo (taking it from the host system, which is usually an sb2 target)
install -m755 /bin/busybox-static $ROOT_DIR/sbin/busybox-static || exit 1

#
# Fix Harmattan preinit
#
ln -s /init $ROOT_DIR/sbin/preinit

#
# check library dependencies
#
rm -f /tmp/build-tmp-*
TMPFILE=$(mktemp /tmp/build-tmp-XXXXXX) || exit 1
add_dependencies $UTIL_LIST $TMPFILE
LIBS=$(cat $TMPFILE)

#
# Show to be installed binaries
#
echo "All needed binaries and libraries:"
for i in $LIBS ; do
        echo $i
done

#
# Store libraries information for debugging purposes
#
cp $TMPFILE libraries.txt

#
# install binaries from util-list and needed libraries
#
echo "Copying files to initrd root..."
for i in $(cat $TMPFILE) ; do
        if [ -f "$i" ] ; then
                debug "adding $i"
                DEST_DIR=$(dirname "$i" | sed  "s/^\///")
                d="$ROOT_DIR/$DEST_DIR"
                [ -d "$d" ] || mkdir -p "$d" || ( echo Fail to create dir $d;\
                        exit 1 ) # We exit if we fail
                debug cp -rL "$i" "$d"
                cp -rL "$i" "$d" || ( echo Fail to copy $i to $d; exit 1 )
        else
                echo "ERROR: file $i is missing!"
                exit 1
        fi
done
echo "done"
rm -f $TMPFILE

# Create (and fix) busybox links
BUSYBOX_BINARY=`find $ROOT_DIR -name "busybox*"`
echo "$BUSYBOX_BINARY"
${BUSYBOX_BINARY} --install -s $ROOT_DIR/bin/
for l in $ROOT_DIR/bin/*; do
  ln -sf /sbin/busybox-static $l
done

#
# install kernel modules
#

if [ ! -z "$KERNEL_MOD_DIR_NAME" ]; then
        echo
        echo "Installing Kernel modules"

        TMPFILE=$(mktemp /tmp/build-tmp-XXXXXX) || exit 1

        TARGET_KERNEL_MOD_DIR=$ROOT_DIR/lib/modules/$KERNEL_MOD_DIR_NAME

        mkdir -p $TARGET_KERNEL_MOD_DIR

        [ -a $KERNEL_MOD_DEP ] && {
                cp -p $KERNEL_MOD_DEP $TARGET_KERNEL_MOD_DIR/
        } || {
            KERNEL_MOD_DEP="$TARGET_KERNEL_MOD_DIR/modules.dep"
            depmod -an $KERNEL_VERSION > $KERNEL_MOD_DEP
        }
        {
                for i in $KERNEL_MODS ; do \
                        KERNEL_MOD=$(sed -n "s/\(.*$i.ko\)\(:.*\)/\1/p" < \
                        $KERNEL_MOD_DEP)
                [ -n "$KERNEL_MOD" ] && {
                        echo $KERNEL_MOD >> $TMPFILE
                }
                done
                LOOP=1

                while [ "$LOOP" -eq "1" ] ; do
                LOOP=0
                CHECK=$(cat $TMPFILE | sort | uniq)
                for d in $CHECK ; do
                AUX_MOD=$(sed -n "s/^$(echo $d | sed 's:/:\\/:g'): //p" \
                    < $KERNEL_MOD_DEP)
                [ -z "$AUX_MOD" ] || {
                        for m in $AUX_MOD ; do
                                grep $m $TMPFILE > /dev/null
                                [ "$?" -eq "1" ] && {
                                echo $m >> $TMPFILE
                                LOOP=1
                                }
                        done
                        }
                done
                done

                MODULES=$(cat $TMPFILE)
                for m in $MODULES ; do
                        BASENAME_TMP=$(basename $m)
                        TEMP_MOD_DIR=$(echo $m | sed "s/$BASENAME_TMP//")
                        install -d $TARGET_KERNEL_MOD_DIR/$TEMP_MOD_DIR
                        cp -p $KERNEL_MOD_DIR/$m $TARGET_KERNEL_MOD_DIR/$TEMP_MOD_DIR
                done
        }
fi

#
# create tar of rootfs
#
if [ ! -z $TAR_FILE ]; then
        tar -cf $WORK_DIR/$TAR_FILE $ROOT_DIR
        debug "$(tar -tf $WORK_DIR/$TAR_FILE)"
fi

#
# create bootable image with cmdline, bootstub, kernel image and initrd
#

gen_initramfs_list.sh -o $WORK_DIR/rootfs.cpio \
    -u squash -g squash $ROOT_DIR
if [ ! -z $USE_LZ4 ]; then
	lz4 -f -l -12 --favor-decSpeed $WORK_DIR/rootfs.cpio $WORK_DIR/rootfs.cpio.lz4
	echo Build is ready at $WORK_DIR/rootfs.cpio.lz4
else
	gzip -n -f $WORK_DIR/rootfs.cpio
	echo Build is ready at $WORK_DIR/rootfs.cpio.gz
fi
