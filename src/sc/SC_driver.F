!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AM MG
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
subroutine SC_driver(X,Xw,Xk,E,k,q)
 !
 use pars,           ONLY:SP,schlen,cZERO
 use units,          ONLY:HA2EV
 use drivers,        ONLY:l_sc_cohsex,l_use_collisions,l_sc_is_libDFT,l_eval_collisions,l_sc_hartree,&
&                         l_sc_exx
 use electrons,      ONLY:levels,nel,n_met_bands,n_sp_pol,n_spin,spin,n_spinor
 use R_lattice,      ONLY:bz_samp,nkibz
 use QP_m,           ONLY:QP_nk,QP_Sc,QP_n_states,QP_Vnl_xc,SC_E_threshold
 use SC,             ONLY:SC_bands,SC_iterations,rho_n,magn_n,SC_rho_threshold,it_now,E_convergence, &
&                         rho_convergence,magn_convergence,SC_R,V_xc_sc,l_sc_pot_is_local,H_nl_sc,H_rotate,&
&                         l_SC_cycle,SC_cycle_mixing,V_hartree_sc,Ho,E_bare,SC_alloc,SC_free, &
&                         WF_G_max,WF_Go_indx,l_SC_RESTART,l_Mean_Potential,&
&                         l_NSC_shot,l_TF_precond,V_mean,SC_up_W_iters,l_SC_nl_mix,SC_QP_setup,it_to_start
 use wave_func,      ONLY:WF,WAVEs,WF_copy
 use memory_m,       ONLY:mem_est
 use FFT_m,          ONLY:fft_size
 use interfaces,     ONLY:MATRIX_driver,el_density_and_current
 use matrix_operate, ONLY:DIAGO
 use interfaces,     ONLY:PARALLEL_global_indexes,WF_load,PARALLEL_WF_distribute,PARALLEL_WF_index
 use com,            ONLY:msg,warning,error
 use X_m,            ONLY:X_t,current_iq,X_alloc
 use LIVE_t,         ONLY:LIVE_message
 use stderr,         ONLY:intc,real2ch,log_as_a_file
 use xc_functionals, ONLY:E_xc
 use frequency,      ONLY:w_samp
 use parallel_m,     ONLY:PAR_IND_Xk_ibz,PAR_IND_G_b,PAR_IND_QP,PP_redux_wait,ncpu
 use IO_m,           ONLY:OP_RD,RD_CL_IF_END,io_control,REP,VERIFY,io_COLLs,io_RESPONSE,&
&                         OP_WR,WR_CL_IF_END,NONE,WR,OP_WR_CL,OP_RD_CL,IO_and_Messaging_switch
 use vec_operate,    ONLY:degeneration_finder,v_norm
 use LIVE_t,         ONLY:live_timing
 use collision,      ONLY:Fock_collisions,SEX_collisions
 use electrons,      ONLY:Total_magn
 !
 implicit none
 !
 type(levels) ::E
 type(bz_samp)::k,q,Xk
 type(X_t)    ::X(2)  ! Xx Em1s
 type(w_samp) ::Xw(2)
 !
 ! Iterations
 !
 integer                  :: it
 real(SP)                 :: spread(SC_bands(2),k%nibz,n_sp_pol),&
&                            E_previous(SC_bands(2),k%nibz,n_sp_pol),dE(SC_bands(2),k%nibz,n_sp_pol),&
&                            E_conv(n_sp_pol),E_total,E_tot_Hartree,E_tot_xc,max_overlap(SC_bands(2),k%nibz,n_sp_pol)
 real(SP),    allocatable :: V_xc_nm1(:,:),rho_nm1(:),magn_nm1(:,:)
 real(SP),    allocatable :: delta_rho(:),delta_magn(:,:)
 complex(SP), allocatable :: H_nl_nm1(:,:,:,:)
 !
 type(WAVEs)              :: WFo
 ! 
 ! Work Space
 !
 integer                  :: ir,i1,i2,ik,ib,ibp,ID(4),io_E,io_V,io_WF,i_spin,i_io,io_X_err
 real(SP)                 :: max_proj,V_xc_sc_shift(n_spin)
 character(schlen)        :: dumb_ch,dumb_ch2
 integer, external        :: io_SC_components,X_em1
 logical, external        :: stop_now
 !
 ! ws for states spread evaluation
 !
 real(SP)                 :: WS_spread(SC_bands(2))
 integer                  :: first_el(SC_bands(2)),n_of_el(SC_bands(2)),n_deg_grp,&
&                            b_of_max_proj(SC_bands(2),k%nibz,n_sp_pol)
 !
 ! SC_bands(1)
 !=============
 !
 if (SC_bands(1)/= 1  ) call error(' Lower bound of band indexes must to be 1')
 if (SC_bands(2)> E%nb) call error(' Upper bound of band indexes cannot to be higher than '//trim(intc(E%nb)))
 !
 call SC_QP_setup(E)
 !
 ! Parallel Setup
 !================
 if (.not.l_eval_collisions) then
   call PARALLEL_global_indexes(E,k,q," ",RESET=.TRUE.)
   call PARALLEL_global_indexes(E,k,q,"Self_Energy") 
   call PARALLEL_WF_distribute(K_index=PAR_IND_Xk_ibz,B_index=PAR_IND_G_b,CLEAN_UP=.TRUE.)
   call PARALLEL_WF_distribute(QP_index=PAR_IND_QP)
   call PARALLEL_WF_index( )
 endif
 !
 ! Initial Start & Restart 
 !==========================
 ! 
 call SC_start_and_restart(X,E,Xk)
 !
 ! DIPOLES
 !=========
 if (l_sc_exx.and.l_SC_cycle) call DIPOLE_driver(E, Xk, X(1), X(1)%q0)
 if (SC_up_W_iters>0)         call DIPOLE_driver(E, Xk, X(2), X(2)%q0)
 !
 if (.not.any((/l_SC_RESTART,l_SC_cycle,l_NSC_shot/))) return
 !
 ! Allocation(s)...
 !==================
 !
 call SC_alloc(E)
 call SC_local_alloc( )
 !
 ! COLLISIONS
 !============
 !
 if (io_COLLs) call COLLISIONS_load(.FALSE.)
 !
 ! Initialize SC_R matrix
 !========================
 !
 if(.not.l_SC_RESTART.and.l_use_collisions) then
   !      
   SC_R=cZERO
   forall(i1=1:SC_bands(2))
     SC_R(i1,i1,:,:)=1._SP
   end forall
   !
 else if (.not.l_SC_cycle.and.l_SC_RESTART) then
   !
   ! load SC_R rotation matrices
   !=============================
   call io_control(ACTION=OP_RD,COM=NONE,SEC=(/1/),MODE=VERIFY,ID=ID(2))
   io_WF=io_SC_components('WF',E,ID(2))
   do ik=1,QP_nk
     call io_control(ACTION=RD_CL_IF_END,SEC=(/ik+1/),ID=ID(2))
     io_WF=io_SC_components('WF',E,ID(2))
   enddo
   call msg('r',' ')
   !
   call SC_report()
   return
   !
 endif
 !
 call msg('r','')
 !
 !  Ho (kinetic + potential)
 !===========================
 call SC_bare_Hamiltonian(E,Xk,k)
 !
 ! Reference wavefunctions
 !
 call WF_copy(WF,WFo)
 !
 ! Start-Up setup.  Eventually restart setup.
 !
 ! WFs
 !=====
 call io_control(ACTION=OP_RD,COM=NONE,SEC=(/1/),MODE=VERIFY,ID=ID(2))
 io_WF=io_SC_components('WF',E,ID(2))
 !
 if (l_SC_RESTART.or.l_NSC_shot) then
   call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/1/),ID=ID(3))  ! Local potential
   io_V=io_SC_components('V' ,E,ID(3))
 endif
 !
 if (l_SC_RESTART) then
   !
   if ((1._SP-SC_cycle_mixing)>1.E-5) call &
&    warning('Short splitted runs with fractional mixing may give different results')
   !
   ! RESTART
   !
   do ik=1,QP_nk
     call io_control(ACTION=RD_CL_IF_END,SEC=(/ik+1/),ID=ID(2))
     io_WF=io_SC_components('WF',E,ID(2))
     call WF_rotate(ik,WFo,fft_size)
   enddo
   !
   ! ... rho_n and V_hartree_sc
   !
   call el_density_and_current(E,k,rho=rho_n)
   if (n_spin>1) call el_magnetization(E,k,magn_n)
   call V_Hartree(rho_n,V_hartree_sc)
   !
   V_xc_nm1 = V_xc_sc
   rho_nm1  = rho_n
   if(n_spin>1) magn_nm1  = magn_n
   !
   it_to_start=it_now+1
   !
 else if (l_NSC_shot) then
   !
   ! Non-SC shot
   !
   it_to_start=1
   it_now=0
   !
 else
   !
   it_to_start=1
   it_now=0
   !
   V_xc_sc  =0._SP
   V_xc_nm1 =0._SP
   !
 endif
 !
 ! SCF cycle & NSC shot
 !=====================
 ! 
 if (l_NSC_shot) call live_timing('[NSC] Single shot loop',QP_nk,SERIAL=.true.)
 !
 do it = 1, SC_iterations
   !
   E_previous(:,:,:) = E%E(:SC_bands(2),:,:)
   !
   it_now=it_now+1
   !
   ! Exchange & Correlation
   !========================
   !
   if (l_SC_cycle) call SC_add_XC(X,Xw,Xk,E,k,q,it,V_xc_nm1)
   !
   ! Hartree potential
   !===================
   !
   if (it>1) then
     !
     if (.not.l_TF_precond) then 
       rho_n = SC_cycle_mixing*rho_n + (1._SP-SC_cycle_mixing)*rho_nm1
       if(n_spin>1) magn_n= SC_cycle_mixing*magn_n+ (1._SP-SC_cycle_mixing)*magn_nm1
     else
       delta_rho =rho_n -rho_nm1
       call SC_precondition(delta_rho)
       rho_n =rho_nm1 +SC_cycle_mixing*delta_rho
       !
       if(n_spin>1) then
         delta_magn=magn_n-magn_nm1
         if (n_spinor==2) then
           call SC_precondition(delta_magn(i1,1))
           call SC_precondition(delta_magn(i1,2))
         endif
         call SC_precondition(delta_magn(i1,3))
         magn_n=magn_nm1+SC_cycle_mixing*delta_magn
       endif
     endif
     !
     call V_Hartree(rho_n,V_hartree_sc)
     !
   endif
   !
   ! IO [V_xc]: this is the only DB that must be written on-fly
   !            Both WFs and Energies are written ay the end of the loop
   !===========
   !
   if (     l_sc_pot_is_local) call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID(3))
   if (.not.l_sc_pot_is_local) call io_control(ACTION=OP_WR,   COM=NONE,SEC=(/1/),ID=ID(3))
   io_V=io_SC_components('V' ,E,ID(3))
   !
   do ik = 1, QP_nk 
     !
     ! Build H_nl_sc
     !===============
     !
     if (l_sc_pot_is_local) then
       !
       H_nl_sc(:,:,:) = Ho(:,:,ik,:)/real(ncpu)
       if(n_spinor==1) call V_real_space_to_H(ik,V_hartree_sc+V_xc_sc,H_nl_sc,WFo,'def')
       if(n_spinor==2) then
         call V_real_space_to_H(ik,V_hartree_sc,H_nl_sc,WFo,'def')
         call V_real_space_to_H(ik,V_xc_sc     ,H_nl_sc,WFo,'xc ')
       endif
       !
     else
       !
       H_nl_sc=cZERO
       !
       ! Add Sigma_x and, eventually, Sigma_c (COHSEX)
       !
       call V_qp_basis_to_H(ik,QP_Vnl_xc,H_nl_sc)
       !
       if (l_sc_cohsex) call V_qp_basis_to_H(ik,QP_Sc,H_nl_sc)
       !
       if (.not.l_use_collisions.and.it_now>1) then
         !
         ! Rotate H_nl_sc in the WFo basis.
         !
         do i_spin=1,n_sp_pol
           call H_rotate(SC_R(:,:,ik,i_spin),H_nl_sc(:,:,i_spin),SC_bands(2),-1)
         end do
         !
       endif
       ! 
       ! IO [H_nl_sc]
       !==============
       !
       call io_control(ACTION=WR_CL_IF_END,COM=NONE,SEC=(/ik+1/),ID=ID(3))
       io_V=io_SC_components('V',E,ID(3))
       !
       H_nl_sc = H_nl_sc + Ho(:,:,ik,:)/real(ncpu)
       !
       ! Mixing for non-local self-energies
       !====================================
       !
       if (l_SC_nl_mix) then
          !
          if (it==1) H_nl_nm1(:,:,ik,:) = H_nl_sc
          !
          H_nl_sc = H_nl_nm1(:,:,ik,:) + SC_cycle_mixing*(H_nl_sc - H_nl_nm1(:,:,ik,:))
          H_nl_nm1(:,:,ik,:)= H_nl_sc
          !
       endif
       !
       ! Add V_Hartree
       !
       call V_real_space_to_H(ik,V_hartree_sc,H_nl_sc,WFo,'def')
       !
     endif
     !
     call PP_redux_wait(H_nl_sc)
     !
     ! Diagonalize H_nl_sc 
     !=====================
     do i_spin=1,n_sp_pol
       !
       call MATRIX_driver(DIAGO,H_nl_sc(:,:,i_spin),E_real=E%E(:SC_bands(2),ik,i_spin))
       !
       ! Rotation (WFo->WF) matrix
       !
       SC_R(:,:,ik,i_spin)=H_nl_sc(:,:,i_spin) 
       !
     enddo
     !
     ! New wave functions 
     !====================
     !
     call WF_rotate(ik,WFo,fft_size)
     !
     if (l_NSC_shot) call live_timing(steps=1)
     ! 
     ! Mean Potential 
     !================
     !
     if (l_Mean_Potential) call V_Mean_Potential(ik,WFo)
     !
   end do
   !
   if (l_NSC_shot) call OCCUPATIONS_Fermi(E,k,1) 
   !
   if (l_SC_cycle) then
     !
     ! New occupations 
     !=================
     !
     ! 21/01/2010 (Andrea): All bands above SC_bands(2) must be shifted
     ! in order to be consistent with the SC values. Otherwise these
     ! bands could interfere with the SC_bands(2) yielding non physical
     ! occupations.
     !
     forall (ib=SC_bands(2)+1:E%nb) E%E(ib,:,:)=E%E(ib,:,:)+E%E(SC_bands(2),:,:)-E_previous(SC_bands(2),:,:)
     !
     ! The same for the bands below SC_bands(1)
     !
     forall (ib=1:SC_bands(1)-1) E%E(ib,:,:)=E%E(ib,:,:)+E%E(SC_bands(1),:,:)-E_previous(SC_bands(1),:,:)
     !
     call OCCUPATIONS_Fermi(E,k,1) 
     !
     ! New density 
     !=============
     !
     rho_nm1 = rho_n 
     if(n_spin>1) magn_nm1 = magn_n 
     !
     call el_density_and_current(E,k,rho=rho_n)
     if(n_spin>1) call el_magnetization(E,k,magn_n)
     !
     ! Update dipoles and recalcolate the dielectric constant
     ! ======================================================
     !
     if (SC_up_W_iters>0.and.mod(it,SC_up_W_iters)==0) then
       !
       ! Update dipoles
       !
       ! Davide: this should be replaced by the use of covariant dipoles ...
       call DIPOLE_rotate(SC_R,E,Xk,X(2), 1)
       call DIPOLE_project_along_q(E,Xk,X(2),X(2)%q0)
       call DIPOLE_rotate(SC_R,E,Xk,X(2),-1)
       !
       ! Recalcolate Xo and X  
       !
       current_iq=0
       call IO_and_Messaging_switch("-report")
       io_X_err=X_em1(E,Xk,q,X(2),Xw(2),.true.)
       call IO_and_Messaging_switch("+report")
       !
       ! Reload and rotate wave-functions if W is updated
       ! =======================================
       !
       call WF_load(WF,WF_G_max,WF_Go_indx,(/1,max(SC_bands(2),E%nbm)/),(/1,nkibz/),title='-SC',force_WFo=.true.)
       !
       do ik=1,QP_nk
         call WF_rotate(ik,WFo,fft_size)
       enddo
       !  
     endif
     !
     ! Total Energy 
     !==============
     !
     call SC_Energy(E_total,E_tot_Hartree,E_tot_xc,E,k,rho_n)
     !
     ! Convergences
     !==============
     !
     E_convergence=0.
     E_conv=0.
     do ik=1,k%nibz
       do i_spin=1,n_sp_pol
         E_conv(i_spin) = max( E_conv(i_spin),&
&                         maxval(abs(E%E(:SC_bands(2),ik,i_spin)-E_previous(:,ik,i_spin)-&
&                                    E%E(1,ik,i_spin)+E_previous(1,ik,i_spin)       )))
       enddo
       E_convergence=max(E_convergence,maxval(E_conv))
     enddo
     !
     rho_convergence = 0._SP
     do ir=1,fft_size
       rho_convergence = rho_convergence + abs(rho_n(ir)-rho_nm1(ir))/nel
     enddo
     !
     magn_convergence = 0._SP
     if(n_spin>1) then
       do ir=1,fft_size
         if (n_sp_pol==2) magn_convergence = abs(magn_n(ir,3)-magn_nm1(ir,3))/nel
         if (n_spinor==2) magn_convergence = v_norm(magn_n(ir,:)-magn_nm1(ir,:))/nel
       enddo
     endif
     !
     if(it_now==it_to_start) dumb_ch ='[SC] Iteration;'
     dumb_ch2='            '//trim(intc(it_now))//' ;'
     if (l_sc_pot_is_local) then
       if(it==1) dumb_ch= trim(dumb_ch) //'  E_tot(Ha) ;'
       dumb_ch2=trim(dumb_ch2)//'  '//trim(real2ch(E_total))//' ; '
     endif
     if (n_spin==2) then
       if(n_sp_pol==2) dumb_ch=trim(dumb_ch)//'  Mz  [muB] ;'
       if(n_spinor==2) dumb_ch=trim(dumb_ch)//'  |M| [muB] ;'
       dumb_ch2=trim(dumb_ch2)//'  '//trim(real2ch(v_norm(Total_magn(:))))//' ;'
     endif
     if(it_now==it_to_start) dumb_ch =trim(dumb_ch)//' Acc.  E(ev)  -  rho(%)'
     dumb_ch2=trim(dumb_ch2)//'    '//trim(real2ch(E_convergence*HA2EV)) &
&                      //' - '//trim(real2ch(rho_convergence))//'%'
     if (n_spin==2) then
       if(it_now==it_to_start) dumb_ch =trim(dumb_ch)//'     -  magn(%)    '
       dumb_ch2=trim(dumb_ch2)//'  - '//trim(real2ch(magn_convergence))//'%'
     endif
     !
     if (.not.log_as_a_file.or.it_now==1) then
       if(it_now==it_to_start) call LIVE_message(dumb_ch ,"n","","%s")
       call LIVE_message(dumb_ch2,"n","","%s")
     else
       if (l_sc_pot_is_local) then
         if (.not.log_as_a_file) then
           if(it_now==1) call LIVE_message(dumb_ch ,"r","","%s")
           call LIVE_message(dumb_ch2,"r","","%s")
         endif
         if (     log_as_a_file) then
           if(it_now==1) call LIVE_message(dumb_ch ,"n","","%s")
           call LIVE_message(dumb_ch2,"n","","%s")
         endif
       else
         if(it_now==1) call LIVE_message(dumb_ch ,"n","","%s")
         call LIVE_message(dumb_ch2,"n","","%s")
       endif
     endif
     !
     ! History
     !=========
     !
     call SC_History(it,E)
     !
   endif
   !
   ! IO [Energies]
   !===============
   !
   call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID(1))
   io_E=io_SC_components('E' ,E,ID(1))
   !
   ! IO [SC_R & Mean Potential]
   !============================
   !
   do i_io=1,2
     !
     if (.not.l_Mean_Potential.and.i_io==2) cycle
     !
     dumb_ch='WF'
     if ( i_io==2 ) dumb_ch='MP'
     !
     if (it==1) call io_control(ACTION=OP_WR,COM=REP, SEC=(/1/),ID=ID(2))
     if (it> 1) call io_control(ACTION=OP_WR,COM=NONE,SEC=(/1/),ID=ID(2))
     io_WF=io_SC_components(trim(dumb_ch),E,ID(2))
     do ik = 1, QP_nk 
       call io_control(ACTION=WR_CL_IF_END,COM=NONE,SEC=(/ik+1/),ID=ID(2))
       io_WF=io_SC_components(trim(dumb_ch),E,ID(2))
     enddo
     !
   enddo
   !
   if ( (E_convergence<SC_E_threshold.and.rho_convergence<SC_rho_threshold.and.magn_convergence<SC_rho_threshold) .or.&
&       stop_now(.FALSE.) ) exit
   !
 end do
 !
 call SC_History(-1,E)
 !
 ! Hartree and xc Energy 
 !=======================
 !
 call SC_Energy(E_total,E_tot_Hartree,E_tot_xc,E,k,rho_n,magn_n)
 !
 if (l_SC_cycle) then
   !
   ! exit SCF cycle and report
   !
   call msg('nr','[SC] Iterations               :',it_now)
   call msg('r' ,'[SC] Accuracy on density      :',rho_convergence)
   if(n_spin>1) call msg('r' ,'[SC] Accuracy on magnetization:',magn_convergence)
   call msg('r' ,'[SC]          on energies [ev]:',E_convergence*HA2EV)
   if (l_sc_pot_is_local)      call msg('r' ,'[SC] Total Energy (no Ewald) [Ha/Ry]:',E_total*(/1._SP,2._SP/))
   if(.not.l_sc_pot_is_local)  call msg('r','')
   if (l_sc_hartree.or.l_sc_is_libDFT) &
&                         call msg('r' ,'[SC] Hartree Energy          [Ha/Ry]:',E_tot_Hartree*(/1._SP,2._SP/))
   if (l_sc_is_libDFT) call msg('rn','[SC] xc Energy               [Ha/Ry]:',E_tot_xc*(/1._SP,2._SP/))
   !
 else
   call msg('r','')
 endif
 !
 if (l_NSC_shot) call live_timing(steps=1)
 !
 call SC_report()
 !
 deallocate(E_bare)
 call mem_est("E_bare")
 if (l_SC_cycle.or.l_NSC_shot) then
   call WF_free(WF)
   call WF_free(WFo)
   call SC_free()
   call SC_local_free()
 endif
 !
 contains
   !
   subroutine SC_local_alloc()
     !
     allocate(rho_nm1(fft_size))
     call mem_est("rho_nm1",(/fft_size/),(/SP/))
     !
     if(n_spin>1) then
       allocate(magn_nm1(fft_size,3))
       call mem_est("magn_nm1",(/fft_size*3/),(/SP/))
     endif
     !
     allocate(E_xc(fft_size))
     call mem_est("E_xc",(/fft_size/),(/SP/))
     !
     allocate(V_xc_nm1(fft_size,n_spin))
     call mem_est("V_xc_nm1",(/size(V_xc_nm1)/))
     !
     if (l_TF_precond) then
       allocate(delta_rho(fft_size))
       call mem_est("delta_rho",(/fft_size/),(/SP/))
       if(n_spin>1) then
         allocate(delta_magn(fft_size,3))
         call mem_est("delta_magn",(/fft_size*3/),(/SP/))
       endif
     endif
     !
     if (l_Mean_Potential) then
       allocate(V_mean(fft_size,SC_bands(2)))
       call mem_est("V_mean",(/fft_size*SC_bands(2)/))
     endif
     !
     if(l_use_collisions) then
       !
       allocate(QP_Vnl_xc(QP_n_states))
       call mem_est("QP_Vnl_xc",(/size(QP_Vnl_xc)/),(/2*SP/))
       !
     endif
     !
     if (l_SC_nl_mix) then
       allocate(H_nl_nm1(SC_bands(2),SC_bands(2),QP_nk,n_sp_pol))
       call mem_est("H_nl_nm1",(/size(QP_Vnl_xc)/),(/2*SP/))
     endif
     !
   end subroutine
   !
   subroutine SC_local_free()
     !
     deallocate(rho_nm1)
     call mem_est("rho_nm1")
     !
     if(n_spin>1) then
       deallocate(magn_nm1)
       call mem_est("magn_nm1")
     endif
     !
     deallocate(E_xc)
     call mem_est("E_xc")
     !
     deallocate(V_xc_nm1)
     call mem_est("V_xc_nm1")
     !
     if (l_TF_precond) then
       deallocate(delta_rho)
       call mem_est("delta_rho")
       if(n_spin>1) then
         deallocate(delta_magn)
         call mem_est("delta_magn")
       endif
     endif
     !
     if (l_Mean_Potential) then
       deallocate(V_mean)
       call mem_est("V_mean")
     endif
     !
     if(l_use_collisions) then
       !
       if (allocated(QP_Vnl_xc)) deallocate(QP_Vnl_xc)
       call mem_est("QP_Vnl_xc")
       !
       if (allocated(Fock_collisions))   call COLLISIONS_alloc_and_free("Fock","v1 table","clean",0)
       if (allocated(SEX_collisions))    call COLLISIONS_alloc_and_free("SEX","v1 table","clean",0)
       !
     endif
     !
     if (l_SC_nl_mix) then
       deallocate(H_nl_nm1)
       call mem_est("H_nl_nm1")
     endif
     !
     if (.not.io_RESPONSE) call X_alloc('X')
     !
   end subroutine
   !
   subroutine SC_report()
     !     
     ! Before all the DFT energies are shifted the V_xc_sc
     ! must be shifted of max(Ev)-max(E_bare_v)
     ! for more details see A. Fleszar PRB 64, 245204
     !
     if (l_SC_cycle) then
       do i_spin=1,n_sp_pol
         V_xc_sc_shift(i_spin )= maxval(E_bare(:n_met_bands,:,i_spin))-maxval(E%E(:n_met_bands,:,i_spin)) 
         if (l_sc_pot_is_local) then
           V_xc_sc(:,i_spin)=V_xc_sc(:,i_spin)+V_xc_sc_shift(i_spin)
           call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID(3))
           io_V=io_SC_components('V' ,E,ID(3))
         endif
       enddo
     endif
     !
     do i_spin=1,n_sp_pol
       do ik=1,k%nibz
         !
         ! Check for degenrate bands in the bare energies
         !
         call degeneration_finder(E_bare(:,ik,i_spin),SC_bands(2),first_el,n_of_el,n_deg_grp,0.0001/HA2EV)
         !
         do ib=1,SC_bands(2)
           !
           ! Then search for the max projection   
           ! 
           max_proj=-1.
           do i1=1,SC_bands(2)
             if (abs(SC_R(i1,ib,ik,i_spin))**2.>max_proj) then
               b_of_max_proj(ib,ik,i_spin)=i1
               max_proj=abs(SC_R(i1,ib,ik,i_spin))**2.
             endif
           enddo
           !
           ! Max Overlap
           !
           max_overlap(ib,ik,i_spin)=maxloc(abs(SC_R(ib,1:SC_bands(2),ik,i_spin)),1)
           ! 
           ! simmetrize the spreads summing over all possible degenerate
           ! bands
           !
           forall (ibp=1:SC_bands(2)) WS_spread(ibp)=abs(SC_R(ibp,ib,ik,i_spin))**2.*100./HA2EV
           !
           ibp=b_of_max_proj(ib,ik,i_spin)
           spread(ib,ik,i_spin)=WS_spread( ibp )
           !
           do i1=1,n_deg_grp
             if (ibp>=first_el(i1).and.ibp<=first_el(i1)+n_of_el(i1)-1) then
               spread(ib,ik,i_spin)=0.
               do i2=first_el(i1),first_el(i1)+n_of_el(i1)-1
                 spread(ib,ik,i_spin)=spread(ib,ik,i_spin)+WS_spread(i2)
               enddo
             endif
           enddo
         enddo
         !
         ! end do SC_bands(2)
         !
         dE(:,ik,i_spin)=E%E(:SC_bands(2),ik,i_spin)-E_bare(:,ik,i_spin)
         !
       enddo
       !
     enddo
     !
     ! Final occupations 
     !====================
     if (l_SC_cycle.or.(l_SC_RESTART.and..not.l_SC_cycle).or.l_NSC_shot) call OCCUPATIONS_Fermi(E,k,2)  
     !
     dE(:,:,:)=E%E(:SC_bands(2),:,:)-E_bare(:,:,:)
     !
     call msg('r',' ')
     !
     do ik=1,k%nibz
       call REPORT_Energies(E%E(:SC_bands(2),:,:),k,Xk,SC_bands(2),(/ik,ik/),'E  ',.TRUE.)
       call REPORT_Energies(E%f(:SC_bands(2),:,:)/HA2EV,k,Xk,SC_bands(2),(/ik,ik/),'occ',.FALSE.)
       call REPORT_Energies(E_bare,k,Xk,SC_bands(2),(/ik,ik/),'E_o',.FALSE.)
       call REPORT_Energies(dE,k,Xk,SC_bands(2),(/ik,ik/),'d_E',.FALSE.)
       call REPORT_Energies(spread,k,Xk,SC_bands(2),(/ik,ik/),'Spr',.FALSE.)
       call REPORT_Energies(max_overlap/HA2EV,k,Xk,SC_bands(2),(/ik,ik/),'MxO',.FALSE.)
       call REPORT_Energies(real(b_of_max_proj)/HA2EV,k,Xk,SC_bands(2),(/ik,ik/),'Bnd',.FALSE.)
     enddo
     !
   end subroutine SC_report
   !
end subroutine SC_driver