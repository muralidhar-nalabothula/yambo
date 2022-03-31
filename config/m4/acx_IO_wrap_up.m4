#
#        Copyright (C) 2000-2021 the YAMBO team
#              http://www.yambo-code.org
#
# Authors (see AUTHORS file for details): AM
#
# This file is distributed under the terms of the GNU
# General Public License. You can redistribute it and/or
# modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation;
# either version 2, or (at your option) any later version.
#
# This program is distributed in the hope that it will
# be useful, but WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place - Suite 330,Boston,
# MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
#
AC_DEFUN([ACX_IO_WRAP_UP],
[
#
# NETCDF-HDF5 PAR IO or HDF5-DATA COMPRESSION (the two are exclusive)
#
compile_pnetcdf="no"
IO_MODE="serial"
PARIO_info=" "
#
if test x"$netcdf" = "xyes" && test x"$hdf5" = "xyes" && test x"$enable_hdf5" = "xyes" && test x"$enable_hdf5_par_io" = "xyes" ; then
    def_netcdf="${def_netcdf} -D_PAR_IO";
    enable_hdf5_compression="no";
    IO_MODE="parallel";
    PARIO_info="(via HDF5)";    
elif test x"$netcdf" = "xyes" && test x"$enable_pnetcdf" = "xyes" ; then
    def_netcdf="${def_netcdf} -D_PAR_IO";
    compile_pnetcdf=${compile_netcdf};
    enable_hdf5_compression="no";
    IO_MODE="parallel";
    PARIO_info="(via PNETCDF)";    
elif test x"$netcdf" = "xyes" && test x"$hdf5" = "xyes" && test x"$enable_hdf5" = "xyes" && test x"$enable_hdf5_compression" = "xyes" ; then
    def_netcdf="${def_netcdf} -D_HDF5_COMPRESSION";
    IO_MODE="parallel";
    PARIO_info="(via COMPRESS-HDF5)";    
fi
#
AC_SUBST(compile_pnetcdf)
AC_SUBST(PARIO_info)
AC_SUBST(IO_MODE)
])