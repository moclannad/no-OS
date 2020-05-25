comma = ,

addcommas = $(filter-out $(lastword $1$(comma), $(addsuffix $(comma),$1)),\
		$(addsuffix $(comma),$1)) $(lastword $1)

ifeq ($(OS), Windows_NT)
remove_fun = powershell Remove-Item -ErrorAction Ignore -cf:\$$false\
		 $(call addcommas, $1)
else
remove_fun = rm -rf $(1)
endif

CC ?= gcc

OBJS = source/ff.o source/ffsystem.o source/ffunicode.o adi_diskio.o

CFLAGS += -Isource

.PHONEY = all clean

all: libfatfs.a

libfatfs.a: $(OBJS)
	$(AR) $(ARFLAGS) $@ $(OBJS)

clean:
	-$(call remove_fun, $(OBJS) libfatfs.a)
