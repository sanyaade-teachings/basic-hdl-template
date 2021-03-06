# This file oritinally came from excamera's build example:
# http://excamera.com/sphinx/fpga-makefile.html
#
# That file contains no licensing or copyright claims, and neither does this.
#
# The top level module should define the variables below then include
# this file.  The files listed should be in the same directory as the
# root Makefile.  
#
#   variable      description
#   ----------    -------------
#   board         board target short-name
#   project       project name
#   top_module    top level module of the project
#   libdir        path to library directory
#   libs          library modules used
#   vendor        vendor of FPGA (xilinx, lattice, altera, etc.)
#   family        FPGA device family (spartan3e) 
#   part          FPGA part name (xc4vfx12-10-sf363)
#   flashsize     size of flash for mcs file (16384)
#   vgenerics     verilog parameters to be passed into top-level module
#   map_opts      (optional) options to give to map
#   par_opts      (optional) options to give to par
#   intstyle      (optional) intstyle option to all tools
#
#   files              description
#   ----------         ------------
#   opt_file           xst extra opttions file to put in .scr
#   ucf_file           .ucf file specifying FPGA constraints
#   bitconf_file       bitfile generation flags
#   bmm_file           BRAM default memory
#   verilog_files      all local non-testbench .v files
#   vhdl_files         all local .vhd files
#   tbfile		       all local .v testbench files
#   end_vhdl_files     all local encrypted .vhd files
#   xilinx_cores       all local .xco files
#
# Library modules should have a modules.mk in their root directory,
# namely $(libdir)/<libname>/module.mk, that simply adds to the verilog_files
# and xilinx_cores variable.
#
# All the .xco files listed in xilinx_cores will be generated with core, with
# the resulting .v and .ngc files placed back in the same directory as
# the .xco file.
#
# NOTE: DO NOT edit this file to change settings; instead edit Makefile

# These dot-targets must come first in the file
.PHONY: default xilinx_cores clean twr_map twr_par ise isim coregen \
	impact ldimpact lint planahead partial_fpga_editor final_fpga_editor \
	map_timing par_timing tests all bit mcs xreport

# "PRECIOUS" files will not be deleted by make as casually
.PRECIOUS: tb/%.isim tb/isim/unenclib/%.sdb

# Setup default targets
default: bitfiles
all: bitfiles
.DEFAULT: bitfiles

# This file only works with Xilinx stuff
vendor = xilinx

# Defaults; these should all be overriden though
hostbits ?= 64
iseenv ?= /opt/Xilinx/14.3/ISE_DS
opt_file ?= ./contrib/default.opt
vgenerics ?=
extra_prj ?=
verilog_files ?=
vhdl_files ?=
enc_vhdl_files ?=
tbfiles ?=

# The tb_ version of these variables allows overriding; eg if there are large
# synth-only HDL libraries you don't want imported
tb_verilog_files ?= $(verilog_files)
tb_vhdl_files ?= $(vhdl_files)
tb_enc_vhdl_files ?= $(enc_vhdl_files)

# Low-level Tunables (override in top-level Makefile)
synth_effort ?= high
unconst_timing ?= -u 50
const_timing_limit ?= 50
flashsize ?= 8192
mcs_datawidth ?= 8
map_opts ?= -timing -ol $(synth_effort) -detail -pr b -register_duplication -w
par_opts ?= -ol $(synth_effort)
intstyle ?= -intstyle xflow
multithreading ?= -mt 4

# Minimal list of bitfiles to be generated
bitfile_list += build/$(project).bit
bitfile_list += build/$(project).mcs

# Build Environment
iseenvfile?= $(iseenv)/settings$(hostbits).sh
xil_env ?= mkdir -p build/; cd ./build; source $(iseenvfile) > /dev/null
sim_env ?= cd ./tb; source $(iseenvfile) > /dev/null
coregen_work_dir ?= ./coregen-tmp
PWD := $(shell pwd)

# The following are used to color-code console build output
colorize ?= 2>&1 | python $(PWD)/contrib/colorize.py red ERROR: yellow WARNING: green \"Number of error messages: 0\" green \"Number of error messages:\t0\" green \"Number of errors:     0\"
colorizetest ?= 2>&1 | python $(PWD)/contrib/colorize.py red FAIL green PASS

# Library stuff (TODO: untested)
libs ?=
libdir ?=
libmks = $(patsubst %,$(libdir)/%/module.mk,$(libs)) 
mkfiles = Makefile $(libmks) contrib/xilinx.mk
include $(libmks)

# Setup coregen'd includes
xilinx_cores: $(corengcs)

corengcs = $(foreach core,$(xilinx_cores),$(core:.xco=.ngc))
verilog_files += $(foreach core,$(xilinx_cores),$(core:.xco=.v))
tbmods = $(foreach tbm,$(tbfiles),unenclib.`basename $(tbm) .v`)
define cp_template
$(2): $(1)
	cp $(1) $(2)
endef
$(foreach ngc,$(corengcs),$(eval $(call cp_template,$(ngc),build/$(notdir $(ngc)))))

# Aliases
twr_map: build/$(project)_post_map.twr
twr_par: build/$(project)_post_par.twr
bit: build/$(project).bit
mcs: build/$(project).mcs
synth: build/$(project).bit

$(coregen_work_dir)/$(project).cgp: contrib/template.cgp
	@if [ -d $(coregen_work_dir) ]; then \
		rm -rf $(coregen_work_dir)/*; \
	else \
		mkdir -p $(coregen_work_dir); \
	fi
	@cp contrib/template.cgp $@
	@echo "SET designentry = Verilog " >> $@
	@echo "SET device = $(device)" >> $@
	@echo "SET devicefamily = $(family)" >> $@
	@echo "SET package = $(device_package)" >> $@
	@echo "SET speedgrade = $(speedgrade)" >> $@
	@echo "SET workingdirectory = ./tmp/" >> $@

untouchcores:
	@echo "Resetting .xco timestamps so that cores won't be rebuilt"
	./contrib/git_untouch.sh $(xilinx_cores)

%.ngc %.v: %.xco $(coregen_work_dir)/$(project).cgp
	@echo "=== rebuilding $@"
	@bash -c "$(xil_env); \
		cd ../$(coregen_work_dir); \
		coregen -b ../$< -p $(project).cgp;"
	@xcodir=`dirname $<`; \
	basename=`basename $< .xco`; \
	echo $(coregen_work_dir)/$$basename.v; \
	if [ ! -r $(coregen_work_dir)/$$basename.ngc ]; then \
		echo "'$@' wasn't created."; \
		exit 1; \
	else \
		cp $(coregen_work_dir)/$$basename.v $(coregen_work_dir)/$$basename.ngc $$xcodir; \
	fi


timestamp = $(shell date +%F-%H%M)

bitfiles: $(bitfile_list)
	@mkdir -p $@/$(timestamp)/logs
	@mkdir -p $@/latest/logs
	@# NB: _bd.bmm was listed below in the past...
	@for x in $(bitfile_list); do \
		cp $$x $@/$(timestamp)/$(project)$$x || true; \
	done;
	@for x in .cfi _par.ncd _post_par.twr _post_par.twx; do \
		cp build/$(project)$$x $@/$(timestamp)/$(project)$$x || true; \
		cp build/$(project)$$x $@/latest/$(project)$$x || true; \
	done;
	@cp -R build/_xmsgs/* $@/$(timestamp)/logs || true;
	@cp -R build/_xmsgs/* $@/latest/logs || true;
	@bash -c "$(xil_env); \
		cd ..; \
		xst -help | head -1 | sed 's/^/#/' | cat - build/$(project).scr > $@/$(timestamp)/$(project).scr"

build/$(project).mcs: build/$(project).bit
	@if [ ! -f build/$(project).bit ]; then false; fi
	@echo "Generating $@..."
	@bash -c "$(xil_env); \
		promgen -w -data_width $(mcs_datawidth) -s $(flashsize) -p mcs \
		        -o $(project).mcs -u 0 $(project).bit $(colorize)"
	@if [ ! -f $@ ]; then false; fi

build/$(project).bit: build/$(project)_par.ncd build/$(project)_post_par.twr $(bitconf_file)
	@echo "Generating $@..."
	@bash -c "$(xil_env); \
		bitgen $(intstyle) -f ../$(bitconf_file) -w $(project)_par.ncd \
		       $(project).bit $(project).pcf $(colorize)"
	@if [ ! -f $@ ]; then false; fi


build/$(project)_par.ncd: build/$(project).ncd build/$(project)_post_map.twr
	@bash -c "$(xil_env); \
	if par $(intstyle) $(par_opts) -w $(project).ncd $(project)_par.ncd $(multithreading) $(colorize); then \
		:; \
	else \
		false; \
	fi "
	@if [ ! -f $@ ]; then false; fi

build/$(project).ncd: build/$(project).ngd
	@if [ -r $(project)_par.ncd ]; then \
		cp $(project)_par.ncd smartguide.ncd; \
		smartguide="-smartguide smartguide.ncd"; \
	else \
		smartguide=""; \
	fi; \
	bash -c "$(xil_env); \
		map $(intstyle) $(map_opts) $$smartguide $(project).ngd $(multithreading) $(colorize)"
	@if [ ! -f $@ ]; then false; fi

build/$(project).ngd: build/$(project).ngc $(ucf_file) $(bmm_file)
	@rm -f $@
	@bash -c "$(xil_env); \
		ngdbuild $(intstyle) $(project).ngc -bm ../$(bmm_file) \
		         -sd ../cores -uc ../$(ucf_file) -aul $(colorize)"
	@if [ ! -f $@ ]; then false; fi

build/$(project).ngc: $(verilog_files) $(vhdl_files) $(corengcs) build/$(project).scr build/$(project).prj 
	@echo "HACK: Forcing re-build of .scr configuration file..."
	@bash -c "rm build/$(project).scr; make build/$(project).scr"
	# XST does not fail on error (!), so deleting the .ngc before building
	@rm -f $@
	@bash -c "$(xil_env); \
		xst $(intstyle) -ifn $(project).scr $(colorize)"
	@if [ ! -f $@ ]; then false; fi

build/$(project).prj: $(verilog_files) $(vhdl_files)
	@for src in $(verilog_files); do echo "verilog work ../$$src" >> $(project).tmpprj; done
	@for src in $(vhdl_files); do echo "vhdl work ../$$src" >> $(project).tmpprj; done
	@for stub in $(extra_prj); do cat $$stub >> $(project).tmpprj; done
	@sort -u $(project).tmpprj > $@
	@rm -f $(project).tmpprj

build/$(project).scr: $(opt_file)
	@mkdir -p build
	@echo "run" > $@
	@echo "-p $(part)" >> $@
	@echo "-top $(top_module)" >> $@
	@echo "-ifn $(project).prj" >> $@
	@echo "-ofn $(project).ngc" >> $@
	@echo '-generics {$(vgenerics)}' >> $@
	@cat $(opt_file) >> $@
	cp $@ build/$(project).xst

build/$(project)_post_map.twr: build/$(project).ncd
	@bash -c "$(xil_env); \
		trce $(unconst_timing) -e $(const_timing_limit) -l $(const_timing_limit) \
		     $(project).ncd $(project).pcf -o $(project)_post_map.twr $(colorize)"
	@echo "Read $@ for timing analysis details"

build/$(project)_post_par.twr: build/$(project)_par.ncd
	@bash -c "$(xil_env); \
		trce $(unconst_timing) -e $(const_timing_limit) -l $(const_timing_limit) \
		     $(project)_par.ncd $(project).pcf -o $(project)_post_par.twr $(colorize)"
	@echo "See $@ for timing analysis details"

tb/simulate_isim.prj: $(tbfiles) $(tb_verilog_files) $(tb_vhdl_files) $(tb_enc_vhdl_files)
	@rm -f $@
	@for f in $(tb_verilog_files); do \
		echo "verilog unenclib ../$$f" >> $@; \
	done
	@for f in $(tb_vhdl_files); do \
		echo "vhdl unenclib ../$$f" >> $@; \
	done
	@for f in $(tb_enc_vhdl_files); do \
		echo "vhdl enclib ../$$f" >> $@; \
	done
	@for f in $(tbfiles); do \
		echo "verilog unenclib ../$$f" >> $@; \
	done
	@echo "verilog unenclib $(iseenv)/ISE/verilog/src/glbl.v" >> $@

tb/isim/unenclib/%.sdb: tb/simulate_isim.prj $(tbfiles) $(verilog_files) $(vhdl_files)
	@rm -f $@
	@bash -c "$(sim_env); \
		cd ../tb/; \
		vlogcomp -prj simulate_isim.prj $(colorize)"
	@if [ ! -f $@ ]; then false; fi

tb/%.isim: tb/%.v tb/isim/unenclib/%.sdb
	@rm -f $@
	@uut=`basename $< .v`; \
	bash -c "$(sim_env); \
		cd ../tb/; \
		fuse -lib unisims_ver -lib secureip -lib xilinxcorelib_ver \
		     -lib unimacro_ver -lib iplib=./iplib -lib unenclib -o $$uut.isim \
			 unenclib.$$uut unenclib.glbl $(colorize)"
	@if [ ! -f $@ ]; then false; fi

isim/%: tb/%.isim tb/simulate_isim.prj
	@uut=`basename $@`; \
	bash -c "$(sim_env); \
		cd ../tb; \
		./$$uut.isim -gui -view $$uut.wcfg &"

isimcli/%: tb/%.isim tb/simulate_isim.prj
	@uut=`basename $@`; \
	bash -c "$(sim_env); \
		cd ../tb; \
		./$$uut.isim"

resim/%: tb/%.isim tb/simulate_isim.prj
	@true

test/%: tb/%.isim tb/simulate_isim.prj
	@echo "run all" > ./tb/test.tcl
	@uut=`basename $@`; \
	bash -c "$(sim_env); \
		cd ../tb/; \
		./$$uut.isim -tclbatch test.tcl $(colorizetest)"

tests: $(alltests)

isim: simulate
	@bash -c "$(sim_env); \
		cd ../tb/; \
		isimgui &"

coregen: $(coregen_work_dir)/$(project).cgp
	@bash -c "$(xil_env); \
		cd ../$(coregen_work_dir); \
		coregen -p $(project).cgp &"

impact:
	@bash -c "$(xil_env); \
		cd ../build; \
		impact &"

ldimpact:
	@bash -c "$(xil_env); \
		cd ../build; \
		LD_PRELOAD=/usr/local/lib/libusb-driver.so impact &"

autoimpact:
	@bash -c "$(xil_env); \
		cd ../build; \
		impact -mode bscan -b build/$(project).bit -port auto -autoassign &"

ise:
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "! WARNING: you might need to update ISE's project settings !"
	@echo "!          (see README)                                    !"
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@mkdir -p build
	@bash -c "$(xil_env); \
		cd ..; \
		XIL_MAP_LOCWARN=0 ise $(project).xise &"

planahead:
	@bash -c "$(xil_env); \
		cd ..; \
		planAhead &"

# DISPLAY variable (X Windows) should be inherited from environment
DISPLAY ?= :0

map_fpga_editor: build/$(project).ncd
	@echo "Starting fpga_editor in the background (can take a minute or two)..."
	@echo "IGNORE the RPC errors below."
	@echo
	@bash -c "$(xil_env); \
		DISPLAY=`echo $(DISPLAY) | sed s/'\.0'//` fpga_editor $(project).ncd &"

par_fpga_editor: build/$(project)_par.ncd
	@echo "Starting fpga_editor in the background (can take a minute or two)..."
	@echo "IGNORE the RPC errors below."
	@echo
	@bash -c "$(xil_env); \
		DISPLAY=`echo $(DISPLAY) | sed s/'\.0'//` fpga_editor $(project)_par.ncd &"

timingan:
	@bash -c "$(xil_env); \
		timingan &"

xreport:
	@bash -c "$(xil_env); \
		xreport &"

map_timingan: build/$(project)_post_map.twr
	@bash -c "$(xil_env); \
		timingan -ucf ../$(ucf_file) $(project).ncd $(project).pcf $(project)_post_map.twx &"

par_timingan: build/$(project)_post_par.twr
	@bash -c "$(xil_env); \
		timingan -ucf ../$(ucf_file) $(project)_par.ncd $(project).pcf $(project)_post_par.twx &"

lint:
	verilator --lint-only -I./hdl -I./cores -Wall -Wno-DECLFILENAME hdl/$(top_module)_$(board) || true

help:
	@cat ./contrib/README
	@echo
	@echo "See README for general help"

clean: clean_synth clean_sim clean_ise
	rm -rf coregen-tmp

mostlyclean: clean_synth clean_sim clean_ise

clean_ise:
	rm -rf iseconfig

clean_sim:
	rm -f tb/*.log
	rm -f tb/*.cmd
	rm -f tb/*.xmsgs
	rm -f tb/*.prj
	rm -f tb/*.isim
	rm -rf tb/isim

clean_synth:
	rm -rf build

