EXT_LIBS      = libxc lapack fftw fftqe yaml futile iotk hdf5 netcdf etsf_io blacs scalapack petsc slepc
INT_LIBS      = qe_pseudo slatec math77 local
YAMBO_INT_LIBS= Yio 
YAMBO_EXT_LIBS= Ydriver 
YLIBDRIVER    = interface main options 
YLIBDRIVER_LD = _driver_options _driver_interface _driver_main 
YLIBIO        = modules Yio
YLIBIO_LD     = $(YLIBIO_LD)
#
# Source code
#
BASIC_LIBS   = driver tools modules memory matrices linear_algebra parallel parser communicate common timing Yio io \
               xc_functionals interface stop_and_restart wf_and_fft bz_ops coulomb
BASIC_LIBS_LD= tools memory Yio communicate modules matrices linear_algebra bz_ops parallel parser communicate common timing Yio io \
               xc_functionals interface stop_and_restart wf_and_fft coulomb

MAIN_LIBS    = $(BASIC_LIBS) interpolate qp_control setup tddft dipoles pol_function qp acfdt bse
MAIN_LIBS_LD = $(BASIC_LIBS_LD) interpolate qp_control setup tddft dipoles pol_function qp acfdt bse

PJ_SCLIBS    = $(MAIN_LIBS) collisions hamiltonian sc
PJ_SCLIBS_LD = $(MAIN_LIBS_LD) hamiltonian collisions sc

PJ_RTLIBS    = $(BASIC_LIBS) interpolate real_time_control qp_control setup \
               tddft dipoles pol_function qp acfdt bse collisions hamiltonian \
               real_time_hamiltonian real_time_propagation real_time_el-ph real_time_lifetimes real_time_common
PJ_RTLIBS_LD = $(BASIC_LIBS_LD) interpolate real_time_control qp_control setup \
               tddft dipoles pol_function qp acfdt bse hamiltonian collisions \
               real_time_hamiltonian real_time_propagation real_time_el-ph real_time_lifetimes real_time_common

PJ_PLLIBS    = $(BASIC_LIBS) interpolate real_time_control qp_control setup \
               tddft dipoles pol_function qp acfdt bse collisions hamiltonian sc \
               real_time_hamiltonian real_time_propagation real_time_el-ph real_time_lifetimes real_time_common
PJ_PLLIBS_LD = $(BASIC_LIBS_LD) interpolate real_time_control qp_control setup \
               tddft dipoles pol_function qp acfdt bse hamiltonian collisions sc \
               real_time_hamiltonian real_time_propagation real_time_el-ph real_time_lifetimes real_time_common

PJ_NLLIBS    = $(PJ_RTLIBS) nloptics
PJ_NLLIBS_LD = $(PJ_RTLIBS_LD) nloptics
#
# Interfaces
#
2YLIBS       = driver tools modules memory matrices linear_algebra parallel parser communicate common timing Yio io setup interface stop_and_restart bz_ops
2YLIBS_LD    = tools memory communicate modules matrices linear_algebra parallel parser communicate common timing Yio io setup interface stop_and_restart bz_ops
#
# YPP
#
YPP_BASIC_LIBS     = modules interface qp plotting k-points symmetries bits electrons 
YPP_BASIC_LIBS_LD  = modules interface qp plotting k-points symmetries bits electrons 
YPP_LIBS           = $(YPP_BASIC_LIBS) excitons
YPP_LIBS_LD        = $(YPP_BASIC_LIBS_LD) excitons
YPPPH_LIBS         = $(YPP_BASIC_LIBS) elph excitons
YPPPH_LIBS_LD      = $(YPP_BASIC_LIBS_LD) elph excitons
YPPRT_LIBS         = $(YPP_BASIC_LIBS) elph real_time excitons
YPPRT_LIBS_LD      = $(YPP_BASIC_LIBS_LD) elph real_time excitons
#
YPP_MAIN_LIBS      = $(BASIC_LIBS) interpolate qp_control setup interface tddft dipoles pol_function qp bse
YPP_MAIN_LIBS_LD   = $(BASIC_LIBS_LD) interpolate qp_control setup interface tddft dipoles pol_function qp bse
YPPSC_MAIN_LIBS    = $(YPP_MAIN_LIBS) collisions hamiltonian sc
YPPSC_MAIN_LIBS_LD = $(YPP_MAIN_LIBS_LD) collisions hamiltonian sc
YPPRT_MAIN_LIBS    = $(BASIC_LIBS) real_time_control interpolate qp_control setup interface \
                     dipoles pol_function qp bse collisions hamiltonian 
YPPRT_MAIN_LIBS_LD = $(BASIC_LIBS_LD) real_time_control interpolate qp_control setup interface \
                     dipoles pol_function qp bse hamiltonian collisions
YPPNL_MAIN_LIBS    = $(BASIC_LIBS) real_time_control interpolate qp_control setup interface \
                     dipoles pol_function qp bse collisions hamiltonian nloptics 
YPPNL_MAIN_LIBS_LD = $(BASIC_LIBS_LD) real_time_control interpolate qp_control setup interface \
                     dipoles pol_function qp bse hamiltonian collisions nloptics 
