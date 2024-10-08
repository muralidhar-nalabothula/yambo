!
! License-Identifier: GPL
!
! Copyright (C) 2010 The Yambo Team
!
! Authors (see AUTHORS file for details): MG
!
subroutine OEP_driver(X,Xw,E,k,q,V_oep)
 !
 ! Driver for OEP potentials. Variables: 
 !  * the approximation for the OEP eq. (Exact, Slater, CEDA, KLI, +Levy Weighted apprx.) 
 !  * the solution method (iterative Bulat-Levy way or by Chi inversion) 
 !  * the approximation for correlation (nothing, LDA, static RPA)
 !
 ! STATUS (22/04/11)
 !
 ! sRPA to be tested
 ! Collisions not available anymore
 ! OEP_app_inversion, partially tested
 ! OEP_exact_inversion, partially tested
 ! OEP_iterative, partially tested, missing parallel => exact not working well???
 ! OEP_Hole, partially tested 
 ! NOTES:
 ! In the future we might choose just the iterative option. Now both for testing purpose. 
 ! Later should also distiguish in case of real time evolution between memory/not memory 
 !
 use pars,            ONLY:SP
 use X_m,             ONLY:X_t
 use electrons,       ONLY:levels,n_met_bands
 use R_lattice,       ONLY:bz_samp,nkibz
 use interfaces,      ONLY:el_density_and_current
 use FFT_m,           ONLY:fft_size
 use drivers,         ONLY:l_oep_exact,l_oep_slater,l_sc_srpa
 use SC,              ONLY:it_now,l_oep_iterative,l_oep_EWeight 
 use frequency,       ONLY:w_samp
 !
#include<y_memory.h>
 real(SP),intent(inout)  :: V_oep(fft_size)
 type(X_t),intent(in)    :: X(2)  
 type(w_samp),intent(in) :: Xw
 type(levels),intent(in) :: E
 type(bz_samp),intent(in):: k,q
 !
 ! Work Space
 !
 real(SP)    ::V_io(fft_size)
 real(SP),allocatable    ::rho(:),V_slt(:)
 complex(SP)             ::W(nkibz,maxval(n_met_bands),fft_size)
 !
 V_io = V_oep
 V_oep= 0._SP
 !
 call OEP_ApplySigmaX(E,k,q,W)
 if (l_sc_srpa) call OEP_ApplySigmaCSX(X(2),Xw,E,k,q,W)
 if (l_oep_iterative.or.(.not.l_oep_exact)) then
   YAMBO_ALLOC(rho,(fft_size))
   YAMBO_ALLOC(V_slt,(fft_size))
   if (l_oep_EWeight) then
     call OEP_Weighted_Density(E,k,rho)
   else
     call el_density_and_current(E,k,rho=rho)
   end if
   call OEP_Hole(E,k,V_slt,W)  
 endif
 !    
 if (l_oep_slater.or.(l_oep_iterative.and.it_now==1)) V_io = V_slt/rho
 !
 if (l_oep_iterative) call OEP_iterative(E,k,V_io,V_slt,W,rho)
 if (.not.l_oep_iterative.and..not.l_oep_slater) then
   if (.not.l_oep_exact) then
     call OEP_app_inversion(E,k,V_oep,V_slt,W,rho)
   else
     call OEP_exact_inversion(X(1),E,k,V_oep,W)
   endif
 end if
 if (l_oep_iterative.or.l_oep_slater) V_oep = V_io
 if (allocated(rho).and.allocated(V_slt)) then
   YAMBO_FREE(rho)
   YAMBO_FREE(V_slt)
 endif
 !
end subroutine OEP_driver
