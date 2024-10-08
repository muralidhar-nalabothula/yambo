!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
!#ifdef _MKLGPU
!include "mkl_dfti_omp_offload.f90"
!#endif

module FFT_m
 use pars,          ONLY: SP
 use iso_c_binding, ONLY: c_ptr
#ifdef _MKLGPU
 use mklfft_gpu
#endif
 !
#include<dev_defs.h>
 !
 implicit none
 !
 real(SP)             :: fft_norm
 integer              :: fft_size
 integer              :: fft_dim(3)
 integer              :: fft_multiplier(3)
 integer              :: fft_dim_loaded(3)
 integer, allocatable :: fft_g_table(:,:)
 integer, allocatable :: fft_rot_r(:,:)
 integer, allocatable :: fft_rot_r_inv(:)
 integer, allocatable DEV_ATTR :: fft_g_table_d(:,:)
 integer, allocatable DEV_ATTR :: fft_rot_r_d(:,:)
 integer, allocatable DEV_ATTR :: fft_rot_r_inv_d(:)
 !
 ! FFTW support
 !
 integer(8)  :: fftw_plan  !(FW) +1 sign: G-space to R-space & oscillators
                           !(BW) -1 sign: R-space to G-space
 !
 ! cuFFT support  (CUDA)
 !
 integer     :: cufft_plan !(FW) +1 sign: G-space to R-space & oscillators
                           !(BW) -1 sign: R-space to G-space
 !
 ! hipFFT support (AMD GPUs)
 !
 type(c_ptr) :: hipfft_plan
                           !(BW) -1 sign: R-space to G-space

 contains
   !
   integer function modx(i,j)
     !
     !  Calculate a function similar to MOD:
     !  modx(i,j) = mod (i,j) i>=0
     !            = mod ( mod(i,j)+j , j) i<0
     !  Thus
     !   modx(3,2)=1
     !   modx(-1,2)=1.
     !  This is different from MOD for i negative.
     !
     implicit none
     integer i,j
     if (i>=0) then
       modx = mod(i,j)
     else
       modx = mod( mod(i,j) + j , j)
     endif
     !
   end function
   !
end module
