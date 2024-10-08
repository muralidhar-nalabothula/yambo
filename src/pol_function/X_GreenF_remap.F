!
! License-Identifier: GPL
!
! Copyright (C) 2009 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine X_GreenF_remap(bands,E,W)
 !
 use pars,          ONLY:SP,pi
 use units,         ONLY:HA2EV
 use LIVE_t,        ONLY:live_timing
 use electrons,     ONLY:levels,n_sp_pol,E_reset
 use frequency,     ONLY:w_samp,W_reset
#include<y_memory.h>
 integer      :: bands(2)
 type(w_samp) :: W
 type(levels) :: E
 !
 ! Work Space
 !
 integer, parameter ::new_map_points=2000
 integer            ::i_b,i_k,i_spin,i_loop
 type(w_samp)       ::W_A
 type(levels)       ::E_map
 !
 real(SP)           ::W_sign,A_sign,max_GF_E_range(2),proposed_GF_E_range(2),E_step,Ao_norm
 complex(SP)        ::Ao(E%GreenF_n_E_steps),zero_plus
 real, external     ::RIntegrate
 !
 ! Resets
 !
 call W_reset(W_A)
 call E_reset(E_map)
 !
 ! New energy range where the convolution is defined
 !
 W_A%er=W%er
 !
 max_GF_E_range=(/1.E8,-1./)
 do i_b=bands(1),bands(2)
   do i_k=1,E%nk
     do i_spin=1,n_sp_pol
       if (i_b>E%nbf(i_spin)) then
         proposed_GF_E_range(1)=minval(real(E%GreenF_W(i_b,i_k,i_spin,:)))
         proposed_GF_E_range(2)=maxval(real(E%GreenF_W(i_b,i_k,i_spin,:)))
       else
         proposed_GF_E_range(1)=-maxval(real(E%GreenF_W(i_b,i_k,i_spin,:)))
         proposed_GF_E_range(2)=-minval(real(E%GreenF_W(i_b,i_k,i_spin,:)))
       endif
       if (proposed_GF_E_range(1)<max_GF_E_range(1)) max_GF_E_range(1)=proposed_GF_E_range(1)
       if (proposed_GF_E_range(2)>max_GF_E_range(2)) max_GF_E_range(2)=proposed_GF_E_range(2)
     enddo
   enddo
 enddo
 !
 if (W_A%er(1)>max_GF_E_range(1)) W_A%er(1)=max_GF_E_range(1)
 if (W_A%er(2)<max_GF_E_range(2)) W_A%er(2)=max_GF_E_range(2)
 !
 ! To allow a simple convolution algorithm to work we need the lower E range
 ! to be multiple of the energy step 
 !
 do i_loop =1,100
   E_step=(W_A%er(2)-W_A%er(1))/(new_map_points-1)
   W_A%er(1)=nint(W_A%er(1)/E_step)*E_step
 enddo
 !
 W_A%n_freqs=max(new_map_points,W%n_freqs)
 W_A%dr=0.
 call FREQUENCIES_setup(W_A)
 W_A%p=real(W_A%p)
 !
 YAMBO_ALLOC(E_map%GreenF,(bands(2),E%nk,n_sp_pol,W_A%n_freqs))
 E_map%GreenF=(0.,0.)
 !
 call live_timing('GF remapping',(bands(2)-bands(1)+1)*E%nk)
 ! 
 do i_b=bands(1),bands(2)
   do i_k=1,E%nk
     do i_spin=1,n_sp_pol
       !
       if ( i_b> E%nbf(i_spin) ) then
         !
         ! Conduction
         !
         W_sign= 1.
         A_sign=-1.
         if ( E%GreenF_is_causal ) A_sign=1.
       else
         !
         ! Valence
         !
         W_sign=-1.
         A_sign=-1.
       endif
       !
       Ao=A_sign/pi*aimag(E%GreenF(i_b,i_k,i_spin,:))
       Ao(1)                  = (0.,0.)
       Ao(E%GreenF_n_E_steps) = (0.,0.)
       zero_plus=cmplx(0.,0.00001/HA2EV)
       !
       call Kramers_Kronig(Ao,&
&                          real(E%GreenF_W(i_b,i_k,i_spin,:)),E%GreenF_n_E_steps,&
&                          E_map%GreenF(i_b,i_k,i_spin,:),&
&                          W_sign*W_A%p,W_A%n_freqs,W_sign*zero_plus)
       !
     enddo
     !
     call live_timing(steps=1)
     !
   enddo
 enddo
 !
 call live_timing()
 !
 ! Transfer
 !
 ! Note that the spectral function of the Green Functions defined here have 
 ! an integral equal to (Z*pi)
 !
 YAMBO_FREE(E%GreenF)
 YAMBO_FREE(E%GreenF_W)
 E%GreenF_n_E_steps=W_A%n_freqs
 YAMBO_ALLOC(E%GreenF,(bands(2),E%nk,n_sp_pol,E%GreenF_n_E_steps))
 YAMBO_ALLOC(E%GreenF_W,(bands(2),E%nk,n_sp_pol,E%GreenF_n_E_steps))
 do i_b=bands(1),bands(2)
   do i_k=1,E%nk
     do i_spin=1,n_sp_pol
       E%GreenF(i_b,i_k,i_spin,:)  =aimag(E_map%GreenF(i_b,i_k,i_spin,:))
       E%GreenF_W(i_b,i_k,i_spin,:)=W_A%p
       Ao_norm=RIntegrate(real(E%GreenF(i_b,i_k,i_spin,:) ),real(E%GreenF_W(i_b,i_k,i_spin,:)),E%GreenF_n_E_steps) !should be pi
       E%GreenF(i_b,i_k,i_spin,:)  =aimag(E_map%GreenF(i_b,i_k,i_spin,:))*pi/Ao_norm
     enddo
   enddo
 enddo
 !
 ! CLEAN
 !
 call W_reset(W_A)
 YAMBO_FREE(E_map%GreenF)
 call E_reset(E_map)
 !
end subroutine
