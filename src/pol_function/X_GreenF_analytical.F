!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine X_GreenF_analytical(iq,transitions,Xw,Xen,Xk,GreenF,ordering,space,no_occupations,X_terminator)
 !
 ! Compute the GreenF in frequency space starting from it analytical
 ! expression as the Fourier Transform of a Lorentzian
 !
 ! In the K case, the anti-res part of Lo uses a w+\Omega (and not -\Omega) simply
 ! because this routine is always called using the i_res \Omega. Indeed 
 !
 !  \Omega_{anti-res} = -\Omega_{res}
 !
 use units
 use pars,       ONLY:SP,cZERO,cONE
 use X_m,        ONLY:use_X_DbGd,X_t,X_term_E,X_DbGd_nkpt_at_q,X_DbGd_nkpt_at_q_table
 use BS_solvers, ONLY:BSS_uses_DbGd
 use electrons,  ONLY:levels,spin_occ
 use R_lattice,  ONLY:qindx_X,bz_samp
 use frequency,  ONLY:w_samp
 use parallel_m, ONLY:PAR_Xk_bz_index
 !
#include<y_memory.h>
 !
 integer      :: iq,transitions(4)
 type(w_samp) :: Xw
 type(levels) :: Xen
 type(bz_samp):: Xk
 complex(SP)  :: GreenF(Xw%n_freqs)
 character(*) :: ordering,space
 logical      :: no_occupations
 logical      :: X_terminator
 logical      :: intra_band
 !
 ! Work Space
 !
 logical      :: X_os_run,K_inv_run,use_DbGd
 integer      :: ikbz_ikpbz_FineGd_used,ikbz_FineGd,ikpbz_FineGd,iw,ikbz,ikpbz,iv,ic,i_spin,&
&                ik_FineGd,ikp_FineGd,ik,ikp,ikbz_mem
 real(SP)     :: ffac,cg_ffac,f_e,f_h,weight,W_,En1,En2
 complex(SP)  :: Z_,pole,pole_X_term
 !
 complex(SP),external      ::Lorentzian_FT
 !
 GreenF  = cZERO
 !
 X_os_run =trim(space)=="G"
 K_inv_run=trim(space)=="eh"
 !
 ! Transitions
 !
 ikbz   = transitions(1)
 iv     = transitions(2)
 ic     = transitions(3)
 i_spin = transitions(4)
 ! 
 ikpbz  = qindx_X(iq,ikbz,1) 
 ik     = Xk%sstar(ikbz,1)
 ikp    = Xk%sstar(ikpbz,1)
 !
 W_=0._SP
 Z_=cONE
 if (allocated(Xen%W)) W_=abs(Xen%W(ic,ik,i_spin))+abs(Xen%W(iv,ikp,i_spin))
 if (allocated(Xen%Z)) Z_=Xen%Z(ic,ik,i_spin)*Xen%Z(iv,ikp,i_spin)
 !
 use_DbGd= (X_os_run .and.use_X_DbGd.and.ic<=Xen%FG%nb) .or. &
&          (K_inv_run.and.BSS_uses_DbGd)
 !
 ! Case without DbGd
 !===================
 !
 ! In K_inversion_Lo the occupations and the Z_factor are not included.
 ! Thus I have to multiply by them the Green function
 !
 if ( .not.use_DbGd ) then
   !
   pole=cmplx(Xen%E(ic,ik,i_spin)-Xen%E(iv,ikp,i_spin),-W_,KIND=SP)
   !
   pole_X_term=0.0_SP
   if(X_terminator) pole_X_term= cmplx(X_term_E-Xen%E(iv,ikp,i_spin),-W_,KIND=SP)
   !
   if( X_os_run  )      ffac = 1._SP
   if( K_inv_run )      ffac = ( Xen%f(iv,ikp,i_spin) - Xen%f(ic,ik ,i_spin) )/spin_occ*real(Z_)
   if( no_occupations ) ffac = 1._SP
   !
   do iw=1,Xw%n_freqs
     !
     GreenF(iw)= Lorentzian_FT(Xw%p(iw),pole,ordering)*ffac
     !
     if (X_terminator.and.ic>Xen%nbm(i_spin)) then
       GreenF(iw)= GreenF(iw) -Lorentzian_FT(Xw%p(iw),pole_X_term,ordering)*ffac  
     endif
     !
     if (X_terminator.and.ic<=Xen%nbm(i_spin)) then
       GreenF(iw)= -Lorentzian_FT(Xw%p(iw),pole_X_term,ordering)*ffac 
     endif
     !
   enddo
   !
   return
   !
 endif
 !
 ! Case with DbGd
 !================
 !
 ! In X_os the GreenF is multiplied by the occupations on the coarse grid.
 ! Thus, to correctly renormalize, I have to:
 ! - divide   by the occupations on the coarse grid
 ! - multiply by the occupations on the fine   grid
 !
 if( X_os_run  ) cg_ffac = Xen%f(iv,ikp,i_spin)*( spin_occ-Xen%f(ic,ik ,i_spin) )
 if( K_inv_run ) cg_ffac = spin_occ/real(Z_)
 !
 ! In the K case, the anti-res part of Lo uses a w+\Omega (and not -\Omega) simply
 ! because this routine is always called using the i_res \Omega. Indeed 
 !
 intra_band = .FALSE.
 if( ic <= Xen%nbf(i_spin) ) intra_band = .TRUE.
 !
 ! 1/6/2020 CA When Terminator is on, there are v->v' transition and therefore occupation factor
 ! cg_ffac goes to zeros and gives NaN. Fixed by introducing a flag for intra-band transitions
 !
 !  \Omega_{anti-res} = -\Omega_{res}
 !
 ikbz_mem=PAR_Xk_bz_index(ikbz)
 !
 weight = 1._SP/real(X_DbGd_nkpt_at_q(ikbz_mem),SP)
 !
 do ikbz_ikpbz_FineGd_used=1,X_DbGd_nkpt_at_q(ikbz_mem)
   !
   ikbz_FineGd =X_DbGd_nkpt_at_q_table(ikbz_mem, ikbz_ikpbz_FineGd_used ,1)
   ikpbz_FineGd=X_DbGd_nkpt_at_q_table(ikbz_mem, ikbz_ikpbz_FineGd_used ,2)
   !
   if(ikbz_FineGd==Xk%FGbz%k_range(ikbz,1)) then
     En1       = Xen%E(ic,ik,i_spin)
     ffac      = Xen%f(ic,ik,i_spin)
   else
     ik_FineGd = Xk%FGbz%E_map(ikbz_FineGd)
     En1       = Xen%FG%E(ic,ik_FineGd,i_spin)
     ffac      = Xen%FG%f(ic,ik_FineGd,i_spin)
   endif
   !
   if( X_os_run  ) f_h = spin_occ-ffac
   if( K_inv_run ) f_h =          ffac
   !
   if(ikpbz_FineGd==Xk%FGbz%k_range(ikpbz,1)) then
     En2       = Xen%E(iv,ikp,i_spin)
     f_e       = Xen%f(iv,ikp,i_spin)
   else
     ikp_FineGd= Xk%FGbz%E_map(ikpbz_FineGd)
     En2       = Xen%FG%E(iv,ikp_FineGd,i_spin)
     f_e       = Xen%FG%f(iv,ikp_FineGd,i_spin)
   endif
   !
   pole=cmplx(En1-En2,-W_)
   !
   if(X_terminator) pole_X_term=cmplx(X_term_E-En2,-W_,KIND=SP)
   !
   if( X_os_run       ) ffac=(f_e*f_h)/cg_ffac*weight
   if( K_inv_run      ) ffac=(f_e-f_h)/cg_ffac*weight
   if( no_occupations .or. intra_band ) ffac = 1._SP
   !
   do iw=1,Xw%n_freqs
     !
     GreenF(iw)=GreenF(iw)+Lorentzian_FT(Xw%p(iw),pole,ordering)*ffac
     !
     if (X_terminator.and.ic>Xen%nbm(i_spin)) then 
       GreenF(iw)= GreenF(iw) -Lorentzian_FT(Xw%p(iw),pole_X_term,ordering)*ffac
     endif
     !
     if (X_terminator.and.ic<=Xen%nbm(i_spin)) then
       GreenF(iw)= -Lorentzian_FT(Xw%p(iw),pole_X_term,ordering)*ffac
     endif      
     !
   enddo  
   !
 enddo
 !
end subroutine
