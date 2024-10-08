!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine X_pre_setup(Xen,Xk,X)
 !
 use pars,          ONLY:SP
 use X_m,           ONLY:X_t,use_X_DbGd,X_DbGd_nkpts,l_X_terminator,X_use_lin_sys,&
&                        X_use_gpu,Chi_linalg_mode,X_ng,l_write_disk_Xo
 use electrons,     ONLY:levels,n_sp_pol
 use drivers,       ONLY:l_bs_fxc,l_col_cut,Finite_Tel,l_cohsex,l_rt_carriers_in_use,l_rpa_IP
 use R_lattice,     ONLY:nqibz,bz_samp
 use QP_m,          ONLY:COHSEX_use_empties
 use TDDFT,         ONLY:FXC_n_g_corr
 use interfaces,    ONLY:eval_G_minus_G
 use parallel_m,    ONLY:PAR_COM_WORLD
 use stderr,        ONLY:intc
 use parser_m,      ONLY:parser
 use gpu_m,         ONLY:have_gpu
 !
 implicit none
 !
 type(X_t)    :: X 
 type(bz_samp):: Xk
 type(levels) :: Xen
 ! 
 ! Work Space
 !
 real(SP), external :: G2E
 !
 if (X%ib(1)<0) X%ib(1)=1
 if (X%ib(2)<0) X%ib(2)=1
 if (X%iq(2)<0.or.X%iq(2)>nqibz) X%iq(2)=nqibz
 if (X%iq(1)<0) X%iq(1)=1
 if (X%iq(1)>X%iq(2)) X%iq(1)=X%iq(2)
 !
 ! In these two lines I ensure the at least all the metallic
 ! bands are included in the X summation
 !
 if (X%ib(1)>minval(Xen%nbf)+1) X%ib(1)=minval(Xen%nbf)+1
 if (X%ib(2)<maxval(Xen%nbm)  ) X%ib(2)=maxval(Xen%nbm)
 !
 ! Other checks
 !
 if (X%ib(1)<0.or.X%ib(1)>maxval(Xen%nbm).or.X%ib(2)<X%ib(1))  X%ib(1)=1
 if (X%ib(2)>Xen%nb.or.X%ib(2)<minval((/Xen%nbf(:n_sp_pol)/))) X%ib(2)=Xen%nb
 !
 ! Here I set up the Double Grid flag to (for example) skip the coarse 
 ! grid generator in the Xo calculation
 !
 use_X_DbGd=Xen%FG%nb/=0.and.X%ib(1)<Xen%FG%nb.and.(.not.l_bs_fxc)
 !
 if (use_X_DbGd) X_DbGd_nkpts=Xk%nbz+Xk%FGbz%N
 !
 ! COH check: when the X terminator is used or the empty bands are NOT used the
 ! response function is accessed in G-G' mode. Here I ensure that all G-G' are in the
 ! range provided externally
 !
 if ((l_cohsex.and..not.COHSEX_use_empties).or.l_X_terminator) then
     X%ng=eval_G_minus_G(X%ng,0,COMM=PAR_COM_WORLD)
     call warning(' Response block size reduced to '//intc(X%ng) &
&     //'RL ('//intc(int(1000.*G2E(X%ng)))//'mHa)')
 endif
 !
 ! Fxc Checks
 !
 if (FXC_n_g_corr>X%ng) FXC_n_g_corr=X%ng
 !
 ! In case the columbian is cutoffed a resonant/antiresonant 
 ! only calculation is meaningless because of the dependence 
 ! of the alpha from X
 !
 if (l_col_cut) then
   if ( trim(X%ordering) == 'a' .or. trim(X%ordering) == 'r' )  then
      X%ordering='T'
      call warning(" Anti/Resonant ordering not compatible with Coulomb cutoff, set to 'T' ")
   endif
 endif
 !
 ! Finite temperature X MUST be causal. This is because in X_eh_setup the
 ! "resonant" or "antiresonant" par of X (in the many body language) include
 ! negative poles as well. Only the sum of the two is meaningful, then.
 !
 if (Finite_Tel .or. l_rt_carriers_in_use) X%ordering="R"
 !
 ! Transfer the GF's ordering 
 !
 if ( allocated(Xen%GreenF).and.     Xen%GreenF_is_causal ) X%ordering='R'
 if ( allocated(Xen%GreenF).and..not.Xen%GreenF_is_causal ) then
   if ( .not.(Finite_Tel.or.l_rt_carriers_in_use) ) X%ordering='T'
   if (      (Finite_Tel.or.l_rt_carriers_in_use) ) then
     call error('Fractional occupations but GF is not retarded (causal in yambo language)')
   endif 
 endif
 !
 ! Dyson solver
 !
 X_use_lin_sys=.true.
 X_use_gpu=have_gpu
 if (index(Chi_linalg_mode,"INVERSION")>0) X_use_lin_sys=.false.
 if (index(Chi_linalg_mode,"LIN_SYS")>0  ) X_use_lin_sys=.true.
 if (index(Chi_linalg_mode,"CPU")>0      ) X_use_gpu=.false.
 if (index(Chi_linalg_mode,"GPU")>0      ) X_use_gpu=.true..and.have_gpu
 !
 ! Copy of X dimension for Parallel default environment solver
 !
 X_ng=X%ng
 !
 ! Check if Xo must be written on-the-fly
 !
 call parser('WriteXo',l_write_disk_Xo)
 !
 if (l_rpa_IP) l_write_disk_Xo=.FALSE.
 !
end subroutine
