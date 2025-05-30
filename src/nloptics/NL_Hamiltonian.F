!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): MG CA
!
subroutine NL_Hamiltonian(E,k,q,X,Time,i_time,V_bands)
 !
 ! The subroutine calculate Ho + V + Sigma and the fields E_tot, E_ext, E_ks
 !
 !   H_k=Ho_k+U_k+ V_k^H-V_k^H[rho_ref]+V_xc[rho]
 !                                        
 use pars,           ONLY:SP,cZERO,pi,cONE
 use units,          ONLY:SPEED_OF_LIGHT
 use FFT_m,          ONLY:fft_size
 use electrons,      ONLY:levels,n_sp_pol
 use R_lattice,      ONLY:bz_samp
 use drivers,        ONLY:l_use_Hxc_collisions
 use hamiltonian,    ONLY:rho_n,H_nl_sc,V_hartree_sc,V_xc_sc
 use QP_m,           ONLY:QP_nk
 use X_m,            ONLY:global_gauge,X_t
 use fields,         ONLY:A_ext,A_tot,Efield
 use real_time,      ONLY:eval_DFT,eval_HARTREE,l_RT_induced_Field,rho_reference,&
&                         Ho_plus_Sigma,RT_Vnl_xc,RT_nbands         
 use wave_func,      ONLY:WF
 use xc_functionals, ONLY:V_xc,XC_potential_driver
 use nl_optics,      ONLY:Correlation,V_xc_0,full_rho,IPA,E_full,LRC,JGM,LRCW,l_use_DIPOLES,NL_LRC_alpha,   &
&                         NL_initial_P,E_tot,E_ext,E_ks,E_xc_0,I_relax,Alpha_ED,dG,eval_dG, & 
&                         NL_bands,VAL_BANDS,NL_P,LSEX,LHF
 use global_XC,      ONLY:WF_xc_functional,WF_kind
 use parallel_m,     ONLY:PAR_IND_Xk_ibz,PAR_Xk_ibz_index
 use wrapper_omp,    ONLY:M_plus_alpha_M_omp
 use collision_ext,  ONLY:COLLISIONS_have_HARTREE
 use H_interfaces,   ONLY:V_real_space_to_H
#if defined _TIMING
 use timing_m,       ONLY:timing
#endif
 !
 implicit none
 !
 type(levels),  intent(in)    :: E
 type(bz_samp), intent(in)    :: k,q
 real(SP),      intent(in)    :: Time
 type(X_t),     intent(in)    :: X
 complex(SP),   intent(in)    :: V_bands(NL_bands(2),maxval(E%nbf),QP_nk,n_sp_pol)
 integer,       intent(in)    :: i_time
 !
 ! Working Space
 !
 integer     :: ik,i_sp_pol,is,ir,i1,ik_mem
 complex(SP) :: E_vec_pot(3),E_xc_pot(3)
 real :: alpha_
 !
#if defined _TIMING
 call timing('NL Hamiltonian',OPR='start')
#endif
 !
 if(eval_HARTREE .or.  eval_DFT) then
   !
   call NL_build_valence_bands(E,V_bands,VAL_BANDS,NL_bands(1))
   !
   call el_density_vbands(E,k,rho_n,VAL_BANDS)
   !
 endif
 !
 if(eval_HARTREE) call V_Hartree(rho_n-rho_reference,V_hartree_sc)
 !
 ! I reconstruct the full density if necessary because both TDDFT 
 ! and JGM are not linear in rho_n and require the full density
 ! 
 if(eval_DFT) then
   !
   if(NL_bands(1)>1) rho_n=full_rho+rho_n-rho_reference
   !
   ! Reconstruct the full density
   !
   call XC_potential_driver(E,k,WF_kind,WF_xc_functional,1)
!$omp parallel do default(shared), private(ir,i_sp_pol), collapse(2)
   do ir=1,fft_size
     do i_sp_pol=1,n_sp_pol
       V_xc_sc(ir,i_sp_pol)=V_xc(ir,i_sp_pol)-V_xc_0(ir,i_sp_pol)
     enddo
   enddo
!$omp end parallel do
   !
 endif
 !
 ! Evaluate the G_lesser for current/polarization and collisions
 ! ======================================================
 if(eval_dG)              call NL_build_dG_lesser(E,V_bands,dG)
 !
 ! Evaluate the Polarization 
 ! ===================================================================
 !
 call DIP_polarization(E,k,V_bands,NL_P(4:6))
 if(.not.l_use_DIPOLES) then
   ! This subroutine update also the Sm1_plus,Sm1_minus and All_S_det matrices
#if defined _TIMING
   call timing('NL Hamiltonian',OPR='stop')
#endif
   do i_sp_pol=1,n_sp_pol
     call Berry_Polarization_NEQ(E,k,i_sp_pol,V_bands(:,:E%nbf(i_sp_pol),:,i_sp_pol),NL_P(1:3))
   enddo
#if defined _TIMING
   call timing('NL Hamiltonian',OPR='start')
#endif   
 else
   NL_P(1:3)=NL_P(4:6)
 endif
 !
 NL_P=NL_P-NL_initial_P ! Subtract the initial polarization
 !
 ! Evaluate the external/total field
 !=================================
 !
 call RT_Ext_fields_sum(A_ext,Time)
 !
 A_tot=A_ext
 !
 E_ext=-A_ext%vecpot_vel/SPEED_OF_LIGHT
 !
 E_tot=E_ext
 E_ks =E_ext
 !
 if( (Correlation==LRC.or.Correlation==JGM.or.l_RT_induced_Field.or.Correlation==LRCW) .and. .not.l_use_Hxc_collisions) then
    !
    ! Evaluate the induced field and/or the LRC correction
    !
    E_vec_pot=-A_ext%vecpot_vel/SPEED_OF_LIGHT
    !
    if(l_RT_induced_Field) E_vec_pot=E_vec_pot - 4.0*pi*NL_P(1:3)
    !
    E_tot=E_vec_pot
    !
    if(Correlation==LRCW) then 
      !This can be calculated once for each frequency, but I did not want to mess up NL_driver (MG)
      alpha_ = NL_LRC_alpha 
      if (Efield(1)%ef_name=='SOFTSIN'.or.Efield(1)%ef_name=='SIN') &
      &     alpha_  = Alpha_ED(E,Efield(1)%frequency(1))
           E_vec_pot=E_vec_pot + alpha_*NL_P(1:3)
      !
    elseif(Correlation==LRC) then
       ! 
       E_vec_pot=E_vec_pot + NL_LRC_alpha*NL_P(1:3)
       !
    elseif(Correlation==JGM) then
      !  
      ! Recontruct the full density for the JGM
      !
      if(NL_bands(1)>1) rho_n=full_rho+rho_n-rho_reference
      !
      call EXC_macroscopic_JGM(E,NL_P(1:3),rho_n,E_xc_pot,V_xc_sc)
      V_xc_sc=V_xc_sc-V_xc_0
      E_vec_pot=E_vec_pot +  E_xc_pot - E_xc_0
      !
    end if
    !
    E_ks=E_vec_pot
    !
    A_tot%vecpot_vel=-E_vec_pot*SPEED_OF_LIGHT
    !
 endif
 !
 ! Calculate collisions
 ! =======================================
 if(l_use_Hxc_collisions) call COLLISIONS_compose_nl(dG)
 !
 ! Build the Hamiltonian
 ! =====================
 !
!$OMP WORKSHARE  
 Ho_plus_Sigma=cZERO
 I_relax      =cZERO
!$OMP END WORKSHARE 
 !
 do i_sp_pol=1,n_sp_pol
  do ik=1,QP_nk
   !
   if (.not.PAR_IND_Xk_ibz%element_1D(ik)) cycle
   !
   ik_mem=PAR_Xk_ibz_index(ik)
   !
   ! Here I fill H_nl_sc with...
   !
   H_nl_sc=cZERO
   !
   ! Correlation part Hartree + TDDFT
   ! ================================
   !
   if(Correlation/=IPA.and.(.not.l_use_Hxc_collisions.or..not.COLLISIONS_have_HARTREE)) then
     !  
     if (eval_Hartree.and.(eval_DFT.or.Correlation==JGM)) then
       call V_real_space_to_H(ik,i_sp_pol,H_nl_sc,WF,'def+xc',V_hartree_sc,V_xc_sc)
     elseif(eval_Hartree.and.(.not.eval_DFT.and..not.Correlation==JGM)) then
       call V_real_space_to_H(ik,i_sp_pol,H_nl_sc,WF,'def',V_hartree_sc)
     endif
     !
   endif
   !
   ! Add Ho = T+V_ion+V_h+V_xc
   !==================
   !
!$omp parallel do default(shared), private(i1)
   do i1=NL_bands(1),NL_bands(2) 
      H_nl_sc(i1,i1)=H_nl_sc(i1,i1)+E_full(i1,ik,i_sp_pol) 
   enddo
!$omp end parallel do
   !
   if(l_use_DIPOLES.or.trim(global_gauge)=='velocity') then
     !    
     call RT_apply_field(ik,i_sp_pol,H_nl_sc,A_tot)
     !
   else
     !
     ! Use Sm1_plus, Sm1_minus and V_bands to build the W operator
     !
     call  Build_W_operator(E,k,A_tot,ik,i_sp_pol,V_bands(:,:E%nbf(i_sp_pol),:,i_sp_pol),H_nl_sc)
     !
   endif                                                         
   !
!   if(Correlation==LSEX.or.Correlation==LHF) call OSCLL_compose_nl(dG,H_nl_sc,k,q,E,ik,i_sp_pol)
   if(Correlation==LSEX.or.Correlation==LHF) call OSCLL_compose_vbands(V_bands,H_nl_sc,k,q,E,ik,i_sp_pol)
   !
   if(l_use_Hxc_collisions) then
     call M_plus_alpha_M_omp(RT_nbands,cONE,RT_Vnl_xc(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),ik,i_sp_pol),&
&                                            H_nl_sc(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2)))
   endif
   !
   ! Damping: NL_damping fills the I_relax matrix 
   ! ================================================
   call NL_damping(E,ik,i_sp_pol,V_bands(:,:E%nbf(i_sp_pol),ik,i_sp_pol))
   !
   ! Store the Hamiltonian
   ! =====================
!$omp parallel do default(shared), private(i1)
   do i1=NL_bands(1),NL_bands(2)
     Ho_plus_Sigma(NL_bands(1):NL_bands(2),i1,ik_mem,i_sp_pol)=H_nl_sc(NL_bands(1):NL_bands(2),i1)
   enddo
!$omp end parallel do
   !
  enddo  !---- loop on k-point
 enddo  !---- loop in spin polarizations
 !
#if defined _TIMING
 call timing('NL Hamiltonian',OPR='stop')
#endif
 !
end subroutine NL_Hamiltonian

