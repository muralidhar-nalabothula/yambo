!
! License-Identifier: GPL
!
! Copyright (C) 2009 The Yambo Team
!
! Authors (see AUTHORS file for details): AM CA
!
subroutine RT_start_and_restart(E,k,q)
 !
 ! This subroutine initialize some variables and restart from SC
 ! or from a previous RT calculation:
 !
 ! [1] Initialize the Gf and potentials
 ! [2] Build Ho
 ! [3] Check for SC and RESTART DBs
 !   > Use SC as a starting point
 !   > RESTART from a previous run
 ! [4] Initialize the bare Hartree and XC
 ! [5] Initialize the fields
 ! [6] (Eventually) load the retarded Green Functions
 !
 use pars,           ONLY:SP,cZERO,rZERO
 use units,          ONLY:HA2EV,AUT2FS
 use drivers,        ONLY:l_elph_scatt,l_elel_scatt
 use com,            ONLY:msg
 use QP_CTL_m,       ONLY:QP_ctl_user
 use electrons,      ONLY:levels,n_sp_pol,n_spin
 use R_lattice,      ONLY:bz_samp,nXkibz
 use RT_control,     ONLY:NE_i_start_time,CARR_RT_IO_t,OBS_RT_IO_t,Gless_RESTART_RT_IO_t,OUTPUT_RT_IO_t,&
&                         CACHE_OBS_INTERVAL_time,RT_control_free,RT_control_alloc,RT_DB_name,RT_DB_ID,N_RT_databases,&
&                         RT_return_db_ID
 use real_time,      ONLY:NE_steps,RT_ind_J,l_NE_dynamics,H_EQ,&
&                         G_lesser_reference,rho_reference,magn_reference,  &
&                         l_NE_with_fields,XC0,HARTREE0,NE_time,RT_levels,&
&                         RT_P,RT_step,dG_lesser,NE_i_time,RT_dyn_step,&
&                         Gr_kind,l_RT_is_WFfree,RT_TIME_status,RTibz,&
&                         RT_nk,G_lesser,RT_eh_en,G_MEM_steps,RT_bands,&
&                         NE_time_step_update_jump,l_velocity_gauge_corr,&
&                         RT_P_prev,RT_ind_J_prev
 use RT_lifetimes,   ONLY:RT_life_extrap_times,l_RT_iterative_ELPH_lifetimes
 use fields,         ONLY:A_tot
 use hamiltonian,    ONLY:H_nl_sc,V_hartree_sc,V_xc_sc,E_reference
 use IO_int,         ONLY:io_control
 use IO_m,           ONLY:OP_RD,OP_RD_CL,OP_IF_START_RD_CL_IF_END,RD_CL_IF_END,&
&                         manage_action,REP,VERIFY,NONE,DUMP
 use descriptors,    ONLY:IO_desc_reset,IO_desc_add
 use wave_func,      ONLY:WF
 use xc_functionals, ONLY:V_xc
 use H_interfaces,   ONLY:V_real_space_to_H
 use parallel_m,     ONLY:PAR_G_k_range,PAR_IND_Xk_ibz
 use parallel_int,   ONLY:PP_wait,PP_redux_wait
 use RT_output_m,    ONLY:RT_desc,TIME_STEP_desc,Gr_desc
 !
#include<y_memory.h>
 !
 type(levels)      :: E
 type(bz_samp)     :: k,q
 !
 ! Work Space
 !
 integer :: i_mem,i_sp_pol,ik,IO_ACT,nt,i_db,io_err(N_RT_databases),COM_MODE,ib,iE_fg,ik_RT
 integer, external :: io_RT_components
#if defined _RT_SCATT
 integer, external :: RT_Lifetimes_evaluation_plan
#endif
 logical :: RESTART
 !
 ! Initialize the Gf, potentials, levels and occupations
 !=======================================================
 call RT_local_init()
 call RT_occupations_and_levels_init(RT_bands,E,k,q,RTibz,RT_levels)
 call RT_G_lesser_init()
 !
 ! The Equilibrium Hamiltonian
 !=========================
 H_EQ=cZERO
 do ik=1,nXkibz
   if (.not.PAR_IND_Xk_ibz%element_1D(ik)) cycle
   do ik_RT=RTibz%k_range(ik,1),RTibz%k_range(ik,2)
     do ib=RT_bands(1),RT_bands(2)
       if (ik_RT/=RTibz%k_range(ik,1)) then
         iE_fg=RTibz%E_map(ik_RT)
         H_EQ(ib,ib,ik_RT,1)=E_reference%FG%E(ib,iE_fg,1)
       else
         H_EQ(ib,ib,ik_RT,1)=E_reference%E(ib,ik,1)
       endif
     enddo
   enddo
 enddo
 !
 if(.not.l_RT_is_WFfree) then
   !
   call              el_density_matrix(G_lesser_reference(:,:,PAR_G_k_range(1):PAR_G_k_range(2)),E,k,rho_reference,1)
   if(n_spin>1) call el_magnetization_matrix(G_lesser_reference(:,:,PAR_G_k_range(1):PAR_G_k_range(2)),E,k,magn_reference,1)
   !
   call Bare_Hamiltonian(E,k,k)
   !
   ! Reference Hartree and XC
   !==========================
   do i_sp_pol=1,n_sp_pol
     do ik=1,nXkibz
       call V_real_space_to_H(ik,i_sp_pol,HARTREE0(:,:,ik,i_sp_pol),WF,'def',V=V_hartree_sc)
       call V_real_space_to_H(ik,i_sp_pol,     XC0(:,:,ik,i_sp_pol),WF,'xc ',Vxc=V_xc)
     enddo
   enddo
   !
   ! In the driver loop both V_hartree_sc and V_xc corresponds to the [delta_rho] value. As here
   ! delta_rho=0 both V_hartree_sc and V_xc must be set to zero. Eventually a non zero value is read
   ! from the potential databaes in case of a RESTARTed run
   !
   V_xc_sc           =rZERO
   V_hartree_sc      =rZERO
   !
   call PP_redux_wait(HARTREE0)
   call PP_redux_wait(XC0)
   !
 endif
 !
 ! Perform a first I/O to check which DBs are present.
 !=====================================================
 RESTART=.FALSE.
 do i_db=1,N_RT_databases
   COM_MODE=NONE
   if (i_db==RT_return_db_ID("ANY_G")) COM_MODE=REP
   call io_control(ACTION=OP_RD_CL,COM=COM_MODE,SEC=(/1/),MODE=VERIFY,ID=RT_DB_ID(i_db))
   io_err(i_db)=io_RT_components(trim(RT_DB_name(i_db)),RT_DB_ID(i_db))
 enddo
 !
 ! To restart from RT only I need:
 !
 !  1. The GF -> delta_G_lesser
 !  2. The OBSERVABLES -> RT_IO_t
 !  3. The REFERENCE -> G_lesser_ref
 !
 RESTART = io_err(RT_return_db_ID("G_lesser_RESTART"))==0.and.&
&          io_err(RT_return_db_ID("OBSERVABLES"))==0
 !
#if defined _RT_SCATT
 RESTART = RESTART .and. io_err(RT_return_db_ID("REFERENCE"))==0
#endif
 !
#if defined _ELPH_ITERATIVE
 !  4. The THETA (no CCA mode)
 !
 if (l_RT_iterative_ELPH_lifetimes) RESTART = RESTART.and.(io_err(RT_return_db_ID("THETA"))==0)
#endif
 !
 ! In case I restart I need to copy the databases in the WD
 !
 ! Starting point
 !================
 !
 if (RESTART) then
   !
   do i_db=1,N_RT_databases
     call RT_RESTART_database_copy( trim(RT_DB_name(i_db)) )
   enddo
   !
   call PP_wait()
   !
   do i_db=1,N_RT_databases
     if (i_db==RT_return_db_ID("G_lesser_RESTART_K_section").or.i_db==RT_return_db_ID("G_lesser_K_section")) cycle
     call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/2/),MODE=DUMP,ID=RT_DB_ID(i_db))
     io_err(i_db)=io_RT_components(trim(RT_DB_name(i_db)),RT_DB_ID(i_db))
   enddo
   !
   NE_i_start_time=NE_i_time
   !
   call RT_control_free("all")
   call RT_control_alloc("all")
   !
   !AMBO_FREE(RT_TIME_status)
   !
   ! I use G_lesser(:,:,:) to reconstruct everything
   ! Note that the databases must be loaded at the RESTART time (NE_time)
   !
   i_db=RT_return_db_ID("G_lesser_RESTART_K_section")
   !
#if defined _PAR_IO
   call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/3/),MODE=DUMP,ID=RT_DB_ID(i_db))
   io_err(i_db)=io_RT_components('G_lesser_RESTART_K_section',RT_DB_ID(i_db))
#else
   do ik=PAR_G_k_range(1),PAR_G_k_range(2)
     IO_ACT=manage_action(OP_IF_START_RD_CL_IF_END,ik,PAR_G_k_range(1),PAR_G_k_range(2))
     call io_control(ACTION=IO_ACT,COM=NONE,SEC=(/ik+2/),MODE=DUMP,ID=RT_DB_ID(i_db))
     io_err(i_db)=io_RT_components('G_lesser_RESTART_K_section',RT_DB_ID(i_db))
   enddo
#endif
   !
   ! The G_lesser must be now rebuild from the reference (T=0) and latest dG components
   !
   do i_mem=1,G_MEM_steps
     G_lesser(:,:,:,i_mem)=G_lesser_reference(:,:,PAR_G_k_range(1):PAR_G_k_range(2))+dG_lesser(:,:,:,i_mem)
   enddo
   !
#if defined _ELPH_ITERATIVE
   if (l_RT_iterative_ELPH_lifetimes) then
     i_db=RT_return_db_ID("THETA")
     do ik=1,RT_nk
       IO_ACT=manage_action(RD_CL_IF_END,ik,FIRST=1,LAST=RT_nk)
       call io_control(ACTION=IO_ACT,COM=NONE,SEC=(/ik+2/),MODE=VERIFY,ID=RT_DB_ID(i_db))
       io_err(i_db)=io_RT_components('THETA',RT_DB_ID(i_db))
     enddo
   endif
   !
   if( l_RT_iterative_ELPH_lifetimes) call RT_ELPH_zeroing()
#endif
   !
   ! Last thing to do is to update the planned time sampling time (if needed)
   !
#if defined _RT_SCATT
   nt=RT_Lifetimes_evaluation_plan( )
#else
   nt=0
#endif
   !
   ! Update occupations after loading from DB
   !==========================================
   call RT_occupations_update(E,q)
   !
   call RT_IO_type_time_steps("RESTART")
   !
   call msg( 'nr','---RESTART report---')
   !
   call msg('s','[RESTART] Number of steps done         ',real(NE_i_time)/real(NE_steps)*100._SP,"[o/o]")
   call msg('r','Number of steps done              ',real(NE_i_time)/real(NE_steps)*100._SP,"[o/o]")
   call msg('r','Time reached                      ',real(NE_i_time-1)*RT_step*AUT2FS,"[fs]")
   call msg('r','Time step                         ',RT_dyn_step*AUT2FS,"[fs]")
   !
   call msg('r',  'dT Update Interval                ',NE_time_step_update_jump*AUT2FS,"[fs]")
   call msg('r',  'Lifetimes inter/intr times        ',RT_life_extrap_times*AUT2FS,"[fs]")
   call msg('r',  'T cache step  of J,P,M            ',CACHE_OBS_INTERVAL_time*AUT2FS,"[fs]")
   call msg('r',  'T between I/O of J,P,M            ',OBS_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
   call msg('r',  '          I/O of carriers         ',CARR_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
   call msg('r',  '          I/O of   GFs            ',Gless_RESTART_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
   call msg('r',  '               outputs            ',OUTPUT_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
   !
 endif
 !
 if (.not.RESTART) NE_time=0._SP
 !
 ! Zeroing DESCs
 !===============
 call IO_desc_reset(RT_desc)
 call IO_desc_reset(Gr_desc)
 call IO_desc_reset(TIME_STEP_desc)
 !
 if (l_NE_dynamics) NE_i_time=NE_i_start_time
 !
 ! Initialize the Vector Potential
 !=================================
 !
 if (l_NE_with_fields) call RT_propagate_fields(E,k,A_tot,A_tot,dG_lesser(:,:,:,1),NE_time-RT_step,RT_step)
 !
 ! Pseudo potential terms needed for velocity gauge
 !==================================================
 if (l_velocity_gauge_corr) then
   call Pseudo_KB_G_to_R_space(k,E)
   call Pseudo_Hamiltonian(k,E,.true.)
 endif
 !
 call msg('r','')
 !
 ! Define RT_eh_en
 !================
 if( all(RT_eh_en(:)==0._SP) ) then
   ! Case A: was not defined in input
   RT_eh_en(1)=minval(RT_levels%E(RT_bands(1):RT_bands(2),:,1))
   RT_eh_en(2)=maxval(RT_levels%E(RT_bands(1):RT_bands(2),:,1))
 else
   ! Case B: was defined in input
   RT_eh_en(1)=RT_eh_en(1)+E%E_VBM(1)
   RT_eh_en(2)=RT_eh_en(2)+E%E_CBm(1)
 endif
 !
 ! Retarded Green Functions matrix
 ! ===============================
 if (l_elph_scatt.or.l_elel_scatt) then
   !
   call k_build_up_BZ_tables(q)
   call k_build_up_BZ_tables(k)
   !
   call IO_desc_add(Gr_desc,'s',"[Gr] Retarded Green`s function",S=trim(Gr_kind))
   call IO_desc_add(Gr_desc,'r',"[Gr] Damping (c) Energy ref",R= (/QP_ctl_user(3,1)%Wc_E_ref*HA2EV/),term="ev")
   call IO_desc_add(Gr_desc,'r',"[Gr] Damping (c)",SZ=3,R=QP_ctl_user(3,1)%Wc(1:3),term="ev,adim,ev^-1")
   call IO_desc_add(Gr_desc,'r',"[Gr] Damping (v) Energy ref",R= (/QP_ctl_user(3,1)%Wv_E_ref*HA2EV/),term="ev")
   call IO_desc_add(Gr_desc,'r',"[Gr] Damping (v)",SZ=3,R=QP_ctl_user(3,1)%Wv(1:3),term="ev,adim,ev^-1")
   !
 else
   !
   call IO_desc_add(Gr_desc,'s',"[Gr] Retarded Green`s function",S="none")
   !
 endif
 !
 call PP_wait()
 !
 contains
   !
   subroutine RT_local_init()
     !
     implicit none
     !
     G_lesser          =cZERO
     G_lesser_reference=cZERO
     dG_lesser         =cZERO
     !
     H_nl_sc           =cZERO
     !
     if(.not.l_RT_is_WFfree) then
       !
       V_xc_sc           =rZERO
       V_hartree_sc      =rZERO
       HARTREE0          =cZERO
       XC0               =cZERO
       !
       rho_reference     =rZERO
       if(n_spin>1) magn_reference    =rZERO
       !
     endif
     !
     ! Set to zero current and fields
     !
     RT_P              =cZERO
     RT_ind_J          =cZERO
     RT_P_prev         =cZERO
     RT_ind_J_prev     =cZERO
     !
   end subroutine
   !
end subroutine RT_start_and_restart
