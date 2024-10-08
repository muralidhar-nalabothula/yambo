!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine TDDFT_ALDA_G_space(E,k)
 !
 use pars,          ONLY:DP,SP
 use TDDFT,         ONLY:FXC_n_g_corr,F_xc_gspace
 use com,           ONLY:msg
 use FFT_m,         ONLY:fft_size,fftw_plan,fft_dim,fft_g_table
 use electrons,     ONLY:levels,n_spin
 use R_lattice,     ONLY:bz_samp,G_m_G
 use wave_func,     ONLY:WF
 use xc_functionals,ONLY:V_xc,F_xc,magn,XC_potential_driver
 use global_XC,     ONLY:WF_xc_functional,WF_kind
 use interfaces,    ONLY:WF_load,WF_free,eval_G_minus_G
 !
#include<y_memory.h>
 !
 type(levels) ::E
 type(bz_samp)::k
 ! 
 ! Work Space
 !
 integer                  :: i1,i2,nG
 complex(DP), allocatable :: F_xc_DP(:)
 !
 integer, external        :: G_index_energy_factor
 !
 if (allocated(F_xc_gspace)) return
 !
 ! Fxc RL size setup looking at the max index of G-G'
 !
 if (FXC_n_g_corr/= eval_G_minus_G(FXC_n_g_corr,0) ) then
   FXC_n_g_corr   = eval_G_minus_G(FXC_n_g_corr,0)
   call msg('s','[TDDFT] ALDA Fxc size forced by symmetry to be ',FXC_n_g_corr)
 endif
 !
 ! WF distributed & load
 !=======================
 !
 nG=G_index_energy_factor(FXC_n_g_corr,4._SP)
 !
 call WF_load(WF,nG,1,(/1,E%nbm/),(/1,k%nibz/),title='-Rho')
 !
 ! ALDA functional
 !
 YAMBO_ALLOC(F_xc,(fft_size,n_spin,n_spin))
 YAMBO_ALLOC(V_xc,(fft_size,n_spin))
 V_xc=0._SP
 YAMBO_ALLOC(F_xc_DP,(fft_size))
 if (n_spin>1) then
   YAMBO_ALLOC(magn,(fft_size,3))
 endif
 call XC_potential_driver(E,k,WF_kind,WF_xc_functional,2)
 do i1=1,fft_size
   F_xc_DP(i1)=sum(cmplx(F_xc(i1,:,:),kind=DP))
 enddo
 !
 ! need to reset the plan to do a BACKWARD FFT (R->G)
 !
 fftw_plan=0
#if defined _FFTW
 call fft_3d(F_xc_DP,fft_dim,-1,fftw_plan)
#else
 call fft_3d(F_xc_DP,fft_dim,-1)
#endif
 !
 ! F_xc in gspace
 !
 YAMBO_ALLOC(F_xc_gspace,(FXC_n_g_corr,FXC_n_g_corr,1))
 do i1=1,FXC_n_g_corr
   do i2=1,FXC_n_g_corr
     F_xc_gspace(i1,i2,1)=cmplx(F_xc_DP( fft_g_table( G_m_G(i1,i2),1) ),kind=SP)/real(fft_size,SP)
   enddo
 enddo
 !
 ! Clean
 !
 YAMBO_FREE(V_xc)
 YAMBO_FREE(F_xc)
 YAMBO_FREE(F_xc_DP)
 YAMBO_FREE(magn)
 call WF_free(WF)
 !
end subroutine
