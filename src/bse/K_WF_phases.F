!
! License-Identifier: GPL
!
! Copyright (C) 2014 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine K_WF_phases(Xk)
 !
 ! This routine evaluates the WF phases needed to evaluate the correlation
 ! collisions
 !
 !  <n k1_bz |exp iG.r|m k2_bz> = <n k1_ibz s1 |exp iG.r|m k2_ibz s2>  =
 !                                <n k1_ibz |exp iG.r|m k2_ibz s1^{-1} x s2 > 
 !
 ! now, in general, s1^{-1} x s2 is not a symmetry in the star of k2_ibz, so we
 ! define and use the table Xk%s_table:
 !
 ! is_in_the_star_of_k2=Xk%s_table(k2,s1^{-1} x s2 )
 !
 ! to get
 !
 !  <n k1_bz |exp iG.r|m k2_bz> =  <n k1_ibz |exp iG.r|m k2_ibz  is_in_the_star_of_k2>*PHASE
 !
 ! where |k2 ib s1^{-1} x s2 > = PHASE * |k2 ib is_in_the_star_of_k2>
 !
 use pars,          ONLY:SP,cZERO
 use FFT_m,         ONLY:fft_size
 use D_lattice,     ONLY:nsym
 use R_lattice,     ONLY:bz_samp
 use BS,            ONLY:WF_phase,BS_res_K_corr,BS_bands
 use com,           ONLY:msg
 use parallel_m,    ONLY:PAR_IND_WF_linear
 use parallel_int,  ONLY:PP_redux_wait
 use electrons,     ONLY:n_sp_pol,n_spinor
 use interfaces,    ONLY:WF_apply_symm
 use timing_m,      ONLY:timing
 !
#include<y_memory.h>
 !
 ! Work Space
 !
 type(bz_samp) :: Xk
 !
 complex(SP) :: wf_cmp,WF_symm1(fft_size,n_spinor),WF_symm2(fft_size,n_spinor)
 integer     :: i_k,i_s,i_s_star,i_b,i_sp_pol,n_phases(1)
 
 if (.not.BS_res_K_corr) return 
 !
 call timing("K_WF_phases","start")
 call section('=','Wave-Function Phases')
 !
 if (.not.allocated(WF_phase)) then
   YAMBO_ALLOC(WF_phase,(Xk%nibz,nsym,BS_bands(1):BS_bands(2),n_sp_pol))
 endif
 WF_phase=cZERO
 !
 n_phases=0
 !
 do i_sp_pol=1,n_sp_pol
   !
   do i_k=1,Xk%nibz
     !
     do i_s=1,nsym
       !
       i_s_star=Xk%s_table(i_k,i_s)
       !
       if (i_s==i_s_star) then
         !
         do i_b=BS_bands(1),BS_bands(2)
           !
           if (.not.PAR_IND_WF_linear%element_2D(i_b,i_k)) cycle
           !
           n_phases=n_phases+1
           WF_phase(i_k,i_s,i_b,i_sp_pol)=1._SP
           !
         enddo
         !
       else
         !
         do i_b=BS_bands(1),BS_bands(2)
           !
           if (.not.PAR_IND_WF_linear%element_2D(i_b,i_k)) cycle
           !
           if (WF_phase(i_k,i_s,i_b,i_sp_pol)/=cZERO) cycle
           !
           call WF_apply_symm((/i_b,i_k,i_s      ,i_sp_pol/),WF_symm1)
           call WF_apply_symm((/i_b,i_k,i_s_star ,i_sp_pol/),WF_symm2)
           !
           wf_cmp=dot_product((/WF_symm1(:,:)/),(/WF_symm2(:,:)/))
           !
           if (abs(abs(wf_cmp)-1._SP)<=1.E-3_SP) then
             n_phases=n_phases+1
             WF_phase(i_k,i_s,i_b,i_sp_pol)= conjg(wf_cmp)
           else
             WF_phase(i_k,i_s,i_b,i_sp_pol)=-99._SP
           endif
         enddo
         !
       endif
     enddo
   enddo
 enddo
 !
 call PP_redux_wait(WF_phase)
 call PP_redux_wait(n_phases)
 !
 call msg('r','[BSE] WF phases found       ',real(n_phases(1),SP)/real(size(WF_phase),SP)*100._SP,"[o/o]")
 !
 call timing("K_WF_phases","stop")
 !
end subroutine K_WF_phases
