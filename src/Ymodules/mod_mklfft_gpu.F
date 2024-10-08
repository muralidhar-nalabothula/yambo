!
!        Copyright (C) 2000-2022 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AF
!
! This file is distributed under the terms of the GNU
! General Public License. You can redistribute it and/or
! modify it under the terms of the GNU General Public
! License as published by the Free Software Foundation;
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will
! be useful, but WITHOUT ANY WARRANTY; without even the
! implied warranty of MERCHANTABILITY or FITNESS FOR A
! PARTICULAR PURPOSE.  See the GNU General Public License
! for more details.
!
! You should have received a copy of the GNU General Public
! License along with this program; if not, write to the Free
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston,
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
#if defined _OPENMP_GPU && defined _MKLGPU
!=====================================================================
! Driver to 3D FFT: FFTW, Goedecker
!
! fft_sign = +1  : G-space to R-space, output = \sum_G f(G)exp(+iG*R) (FW)
! fft_sign = -1  : R-space to G-space, output = \int_R f(R)exp(-iG*R) (BW)
!
! Note that as the YAMBO convention for the oscillators is
!
!  <n k | e ^{iq.r} | n' k-q>
!
! the +1 sign (FW) is used in scatter_Bamp as well.
!
! Note that that inverse operation of
!
! call fft_3d(wf,fft_dim, 1,bw_plan)
!
! is
!
! call fft_3d(wf/real(fft_size,SP),fft_dim, 1,fw_plan)
!
!=====================================================================
!
#include<dev_defs.h>
include "mkl_dfti_omp_offload.f90"
!
module mklfft_gpu

use pars,                 only: DP
use gpu_m,                only: gpu_devsync
use devxlib_environment
use mkl_dfti_omp_offload

 type(dfti_descriptor), pointer :: mklgpu_desc

contains
subroutine fft_3d_mklgpu(c_d,n,fft_sign,mklgpu_desc)
 !
#include<y_memory.h>
 !
 integer                :: fft_sign,n(3)
 type(dfti_descriptor), pointer :: mklgpu_desc
 complex(DP)            :: c_d(1:product(n))
 !
 !
 ! Work Space
 !
 integer :: desc_status
 integer :: istat
 !
! istat = DftiGetValue( mklgpu_desc, DFTI_COMMIT_STATUS, desc_status )
! if (istat/=0) call error("[FFT] Invalid MKL GPU desc "// DftiErrorMessage(istat))
! if (desc_status==DFTI_UNCOMMITTED) then
 if (.not. associated(mklgpu_desc)) then
   !
   istat = DftiCreateDescriptor( mklgpu_desc, DFTI_DOUBLE, DFTI_COMPLEX, 3, n)
   if(istat /= 0) CALL error('[FFT] stopped in DftiCreateDescriptor '// DftiErrorMessage(istat))
   !
   istat = DftiSetValue(mklgpu_desc, DFTI_PLACEMENT, DFTI_INPLACE)
   if(istat /= 0) CALL error('[FFT] stopped in DFTI Placement '// DftiErrorMessage(istat))
   !
   !$omp dispatch
   istat = DftiCommitDescriptor(mklgpu_desc)
   !$omp end dispatch
   if(istat /= 0) CALL error('[FFT] stopped in DFTI desc commit '// DftiErrorMessage(istat))
 endif
 !
 !DEV_OMPGPU target data use_device_addr(c_d)
 !
 if (fft_sign<0) then
    !$omp dispatch
    istat = DftiComputeForward(mklgpu_desc, c_d)
    !$omp end dispatch
    if(istat /= 0) CALL error('[FFT] stopped in DFTI ComputeFW '// DftiErrorMessage(istat))
 elseif(fft_sign>0) then
    !$omp dispatch
    istat = DftiComputeBackward(mklgpu_desc, c_d)
    !$omp end dispatch
    if(istat /= 0) CALL error('[FFT] stopped in DFTI ComputeBW '// DftiErrorMessage(istat))
 endif
 !
 !DEV_OMPGPU end target data
 !
end subroutine fft_3d_mklgpu
!
endmodule mklfft_gpu
#endif
