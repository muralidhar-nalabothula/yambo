/*
        Copyright (C) 2000-2022 the YAMBO team
              http://www.yambo-code.org

 Authors (see AUTHORS file for details): AF
 
 This file is distributed under the terms of the GNU 
 General Public License. You can redistribute it and/or 
 modify it under the terms of the GNU General Public 
 License as published by the Free Software Foundation; 
 either version 2, or (at your option) any later version.

 This program is distributed in the hope that it will 
 be useful, but WITHOUT ANY WARRANTY; without even the 
 implied warranty of MERCHANTABILITY or FITNESS FOR A 
 PARTICULAR PURPOSE.  See the GNU General Public License 
 for more details.

 You should have received a copy of the GNU General Public 
 License along with this program; if not, write to the Free 
 Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
 MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
*/

#include <device_macros.h>

#ifdef __STDC__
#  define CAT(a,b) a##b 
#else
#  define PASTE(a) a
#  define CAT(a,b) PASTE(a)b
#endif

#ifdef _CUDA
#  define DEV_SUBNAME(x)        CAT(x,_gpu)
#  define DEV_SUBNAME_ALT(x)    CAT(x,_gpu)
#  define DEV_VARNAME(x)        CAT(x,_d)
#  define DEV_ATTRIBUTE         , device
#  define DEV_PINNED            , pinned
#else
#  define DEV_SUBNAME(x)        x
#  define DEV_SUBNAME_ALT(x)    CAT(x,_cpu)
#  define DEV_VARNAME(x)        x
#  define DEV_ATTRIBUTE
#  define DEV_PINNED
#endif

#define DEV_SUB(x)          DEV_SUBNAME(x)
#define DEV_SUB_ALT(x)      DEV_SUBNAME_ALT(x)
#define DEV_VAR(x)          DEV_VARNAME(x)
#define DEV_ATTR            DEV_ATTRIBUTE
#define DEV_PIN             DEV_PINNED


#if defined _OPENACC
#  define DEV_ACC $acc
#else
#  define DEV_ACC !!!!
#endif

#if defined _CUDA
#  define DEV_CUF $cuf
#else
#  define DEV_CUF !!!!
#endif

#if defined _OPENMP && !defined (_HAVE_DEVICE)
#  define DEV_OMP $omp
#else
#  define DEV_OMP !!!!
#endif

