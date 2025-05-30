#
# License-Identifier: GPL
#
# Copyright (C) 2020 The Yambo Team
#
# Authors (see AUTHORS file for details): AM
#
define mk_exe
 LLIBS="";for lib in $$XLIBS; do if test -f $(compdir)/lib/lib_Y_$$lib.a; then LLIBS="$$LLIBS -l_Y_$$lib" ; fi; done ; \
 for lib in $$X_ypp_LIBS; do if test -f $(compdir)/lib/lib_YPP_$$lib.a; then LLIBS="$$LLIBS -l_YPP_$$lib" ; fi ; done ; \
 for exe in $$X2DO; do \
  if test ! -f $(compdir)/config/stamps_and_lists/$$exe.stamp && test ! -f  $(compdir)/config/stamps_and_lists/compilation_stop_$$exe.stamp; then \
   ./sbin/compilation/helper.sh -d $$BASE -t $$exe -o .objects -m x -g $@ -- "$$LLIBS $(xcpp) $$ADF"; \
   cd $$BASE ; $(MAKE) $(MAKEFLAGS) VPATH=$(srcdir)/$$BASE exe || { grep Error $(compdir)/log/compile_$@.log ; exit "$$?"; } ; cd $(compdir); \
  fi;\
  if test ! -f $(compdir)/config/stamps_and_lists/$$exe.stamp; then \
   echo "$$exe linking failed. Check log/compile_$$exe.log";\
   grep Error $(compdir)/log/compile_$$exe.log;\
   exit 1;\
  fi;\
 done
endef
