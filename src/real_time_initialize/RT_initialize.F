!
! License-Identifier: GPL
!
! Copyright (C) 2009 The Yambo Team
!
! Authors (see AUTHORS file for details):
!
subroutine RT_initialize(E,k,q)
 !
 use drivers,        ONLY:l_use_collisions,l_elph_scatt,l_elel_scatt,l_sc_hartree,l_use_Hxc_collisions,&
&                         l_sc_is_libDFT,l_sc_sex,l_sc_fock,l_elphoton_scatt,l_rt_carriers_in_use,l_phel_scatt
#if defined _PHEL
 use drivers,        ONLY:l_phel_scatt
#endif
 use pars,           ONLY:SP,pi,schlen
 use stderr,         ONLY:STRING_split
 use units,          ONLY:HA2EV,HBAR_eVfs,AU2VMm1,AU2KWCMm2,AUT2FS
 use stderr,         ONLY:intc
 use com,            ONLY:msg
 use QP_CTL_m,       ONLY:QP_ctl_user
 use vec_operate,    ONLY:normalize_v
 use plasma,         ONLY:EH_gas
 use X_m,            ONLY:global_gauge
 use electrons,      ONLY:levels
 use collision_ext,  ONLY:COLLISIONS_have_HARTREE
 use RT_control,     ONLY:CARR_RT_IO_t,OBS_RT_IO_t,RT_IO_t,Gless_RESTART_RT_IO_t,OUTPUT_RT_IO_t,         &
&                         TIME_adjust,SAVE_G_history,CACHE_OBS_INTERVAL_time
 use RT_occupations, ONLY:l_RT_relax_time_approx
 use RT_lifetimes,   ONLY:RT_life_extrap_times,RT_life_extrap_times_INPUT,l_RT_lifetimes_extrapolation,&
&                         Life_MEM_steps,l_RT_lifetimes_Tfit,l_RT_skip_ph_abs_lifetimes,l_RT_iterative_ELPH_lifetimes
 use real_time,      ONLY:RT_potential,RT_step,l_NE_with_fields,RT_bands,RT_dyn_step,RT_nk,   &
&                         NE_steps,NE_tot_time,l_RT_induced_field,Gr_kind,       &
&                         RAD_LifeTime,Phase_LifeTime,         &
&                         NE_MEM_treshold,G_MEM_steps,l_RT_uses_E_FineGd,DbGd_EE_Nk_table,    &
&                         l_RT_impose_N_dN,Integrator_name,l_RT_impose_E,DbGd_EE_percent,     &
&                         l_RT_update_Energies,eval_HARTREE,eval_DFT,l_NE_dynamics,           &
&                         NE_time_step_update_jump,NE_initial_time_step_update,NE_i_time,     &
&                         RAD_magnification,NE_step_update_treshold, &
&                         NE_time_step_update_jump_INPUT,NE_initial_time_step_update,          &
&                         RT_is_dynamically_dephased,RT_is_statically_dephased,RT_MAX_step,   &
&                         eval_energy,eval_entropy,l_RT_is_WFfree,l_update_SOC,    &
&                         l_RT_eq_is_zero_temp,l_RT_include_eq_scatt,  &
&                         l_velocity_gauge_corr,l_velocity_gauge_diam,l_RT_impose_for_metals, &
&                         l_P_integrating_J,l_RT_rotate_DM,RT_deph_cv_only,RTibz,RT_nbands
 use IO_m,           ONLY:io_COLLs
 use R_lattice,      ONLY:bz_samp
 use D_lattice,      ONLY:Bose_Temp
 use fields,         ONLY:Efield,n_ext_fields,field_is_ok,EtoT,Efield_strength
 use parser_m,       ONLY:parser
 use parallel_m,     ONLY:PAR_IND_Xk_ibz,PAR_COM_Xk_ibz_INDEX,PAR_G_k_range
 use parallel_int,   ONLY:PP_redux_wait
 !
#include<y_memory.h>
 !
 type(levels), intent(inout) :: E
 type(bz_samp),intent(in)    :: q,k
 !
 ! Work space
 !
 integer                  :: i1,N_T_samplings,ik,NK_cpu(PAR_COM_Xk_ibz_INDEX%n_CPU)
 character(schlen)        :: MSG_ch,field_defs(3)
 real(SP)                 :: T_memory
 logical                  :: l_Full_RT_T_evolution,l_skip_it,l_velocity_gauge_tmp
 real(SP), parameter      :: thresh=1.E-5_SP
#if defined _RT_SCATT
 integer,  external       :: RT_Lifetimes_evaluation_plan
#endif
 !
 ! Logicals
 !==========
 !
 call parser('InducedField' ,        l_RT_induced_field)
 call parser('VelGaugeNoDiam',       l_velocity_gauge_tmp)
 l_velocity_gauge_diam=.not.l_velocity_gauge_tmp
 !
 call parser('DephCVonly',           RT_deph_cv_only)
 call parser('RADmagnific',          RAD_magnification)
 call parser('VelGaugeCorr',         l_velocity_gauge_corr)
 call parser('PfromJ',               l_P_integrating_J)
 call parser('RT_T_evol',            l_Full_RT_T_evolution)
 !
 !...updates
 call parser('RTUpdateE',            l_RT_update_Energies)
 call parser('RTUpdateSOC',          l_update_SOC)
 l_RT_rotate_DM                     =l_RT_update_Energies
 !
 !...imposes
 call parser('RTskipImposeN',        l_skip_it)
 if (l_skip_it) l_RT_impose_N_dN=.FALSE.
 call parser('RTskipImposeE',        l_skip_it)
 if (l_skip_it) l_RT_impose_E=.FALSE.
 call parser('RTImpForMet',          l_RT_impose_for_metals)
 !
 !..lifetimes
 call parser('LifeExtrapolation',    l_RT_lifetimes_extrapolation)
 call parser('LifeFitTemp',          l_RT_lifetimes_Tfit)
 call parser('RelaxTimeApprox',      l_RT_relax_time_approx)
 call parser('RTzeroTempRef',        l_RT_eq_is_zero_temp)
 call parser('RTEqScatt',            l_RT_include_eq_scatt)
 call parser('RTskipPHabs',          l_RT_skip_ph_abs_lifetimes)
 !
 if (.not.l_RT_skip_ph_abs_lifetimes) l_RT_skip_ph_abs_lifetimes=.not.(Bose_Temp>0..or.l_phel_scatt)
 !
 !...evals
 call parser('RTEvalEnergy',         eval_energy)
 call parser('RTEvalEntropy',        eval_entropy)
 if(.not.eval_energy) eval_entropy=.false.
 call parser('SaveGhistory',         SAVE_G_history)
 !
 !...drivers
 !
#if defined _ELPH_ITERATIVE
 l_RT_iterative_ELPH_lifetimes  =l_Full_RT_T_evolution.and.l_elph_scatt
#else
 l_RT_iterative_ELPH_lifetimes  = .FALSE.
#endif
 !
 eval_DFT     =  l_sc_is_libDFT
 eval_HARTREE =  l_sc_hartree
 !
 RT_nbands=RT_bands(2)-RT_bands(1)+1
 !
 ! DbGd PAR memory distribution index updated
 !============================================
 if (l_RT_uses_E_FineGd) then
   PAR_G_k_range(1)=RTibz%k_range(PAR_G_k_range(1),1)
   PAR_G_k_range(2)=RTibz%k_range(PAR_G_k_range(2),2)
 endif
 !
 ! Integrator FLAGS
 !==================
 call RT_Integrator_init()
 !
 ! Global gauge
 !==============
 if(.not.any((/trim(global_gauge)=="velocity".or.trim(global_gauge)=="length"/)) ) then
   call warning(" Not a valid gauge in input. Switching to length gauge")
   global_gauge="length"
 endif
 if(l_velocity_gauge_corr) l_velocity_gauge_corr=(trim(global_gauge)=="velocity")
 if(l_velocity_gauge_diam) l_velocity_gauge_diam=(trim(global_gauge)=="velocity")
 !
 ! Use NE_tot_time if provided
 !==============================
 NE_i_time=1
 if (NE_tot_time>0._SP) NE_steps=max(NE_steps,nint(NE_tot_time/RT_step)+1)
 !
 ! Initialize RT_dyn_step
 !========================
 RT_dyn_step=RT_step
 !
 ! I/O steps
 !===========
 call RT_IO_type_time_steps("INIT")
 !
 ! Dephasing Matrix. Including user-defined matrix-like dephasing factors, constant
 !==================
 ! radiative/phase, polaronic based
 !
 call section('+P','Dephasing matrix setup')
 !
 call RT_Dephasing_Matrix(E)
 !
 if (.not.RT_is_statically_dephased) then
   !
   if (l_elph_scatt.or.l_elel_scatt) then
     call warning('No Dephasing provided. E-E and/or E-P scatterings switched off')
     l_elph_scatt=.FALSE.
     l_elel_scatt=.FALSE.
   endif
   !
 endif
 !
 ! Memory Depth (Lifetimes) & extrapolation steps
 !================================================
 if (RT_is_statically_dephased) then
   !
   RT_life_extrap_times=RT_life_extrap_times_INPUT
   !
   if (all(RT_life_extrap_times>0)) then
     Life_MEM_steps=nint(RT_life_extrap_times(1)/RT_life_extrap_times(2))
     if (Life_MEM_steps<3) Life_MEM_steps=3
     if (RT_life_extrap_times(2)<RT_step) RT_life_extrap_times(2)=RT_step
     RT_life_extrap_times(2)=max(TIME_adjust(RT_life_extrap_times(2)),RT_step)
     RT_life_extrap_times(1)=RT_life_extrap_times(2)*Life_MEM_steps
   endif
   !
   RT_life_extrap_times_INPUT=RT_life_extrap_times
   !
 endif
 !
 ! Memory Depth (G_lesser)
 !=========================
 T_memory=0._SP
 if (l_elph_scatt.and.NE_MEM_treshold>0._SP) then
   T_memory=-1._SP/minval( abs(E%W(RT_bands(1):RT_bands(2),:,:)))*log(NE_MEM_treshold)
   G_MEM_steps=nint(T_memory/RT_step)
 endif
 !
 ! Update time Step
 !==================
 !
 if (NE_initial_time_step_update>0._SP) then
   !
   if (G_MEM_steps<3) G_MEM_steps=3
   !
   if (all(RT_life_extrap_times>0)) then
     NE_time_step_update_jump_INPUT = TIME_adjust(NE_time_step_update_jump_INPUT,2._SP*RT_life_extrap_times(1))
     if(NE_time_step_update_jump_INPUT<2._SP*RT_life_extrap_times(1)) NE_time_step_update_jump_INPUT=2._SP*RT_life_extrap_times(1)
   endif
   !
   NE_time_step_update_jump=NE_time_step_update_jump_INPUT
   !
   if (RT_MAX_step<1.E-5) RT_MAX_step=10._SP*RT_step
   !
 endif
 !
 ! External fields checks
 !========================
 !
 l_NE_with_fields=.false.
 !
 do i1=1,n_ext_fields
   !
   Efield(i1)%ef_name=trim(Efield(i1)%ef_name)
   !
   MSG_ch="Field#"//trim(intc(i1))//" "//trim(Efield(i1)%ef_name)
   !
   if(trim(Efield(i1)%ef_name)/='none') then
     !
     if (.not.field_is_ok( Efield(i1)) ) call error(trim(MSG_ch)//' not supported or polarization is wrong')
     !
     l_NE_with_fields=.true.
     !
     call STRING_split(Efield(i1)%ef_name,field_defs)
     !
     if(field_defs(1)/='DELTA'.and.Efield(i1)%frequency(1)==0._SP) &
&      call error(trim(MSG_ch)//" field has zero frequency.")
     !
     if(Efield(i1)%intensity==0._SP) &
&      call warning(trim(MSG_ch)//" field has zero intensity.")
     !
     if( all( abs(Efield(i1)%versor(:))<epsilon(1.) ) ) &
&      call error(trim(MSG_ch)//" field has undefined direction.")
     !
     if ( ((field_defs(1)=='QSSIN') .or. (field_defs(1)=='GAUSS') .or. (field_defs(1)=='PULSE')) &
&        .and. Efield(i1)%width<epsilon(1.)  ) &
&      call error(trim(MSG_ch)//" field has undefined duration.")
     !
     Efield(i1)%versor   =normalize_v(Efield(i1)%versor)
     Efield(i1)%amplitude=Efield_strength(Efield(i1)%intensity,'AU')
     !
     Efield(i1)%t_initial_indx=max(nint(Efield(i1)%t_initial/RT_step)+1,2)
     !
     Efield(i1)%t_initial=real(Efield(i1)%t_initial_indx-1)*RT_step
     !
     call Check_symmetries(Efield(i1)%versor,"electric")
     !
     if ( field_defs(1)=='DELTA' ) then
       Efield(i1)%t_final_indx=Efield(i1)%t_initial_indx+2
       Efield(i1)%t_final=RT_step*(Efield(i1)%t_final_indx-1)
     else if ( (field_defs(1)=='QSSIN') .or. (field_defs(1)=='QSFIEL') .or. &
     &         (field_defs(1)=='GAUSS') .or.                                     &
     &         (field_defs(1)=='PULSE') .or. (field_defs(1)=='SPULSE')      ) then
       call RT_Fluence_and_PI_kind(E,i1)
     else
       Efield(i1)%t_final_indx=    NE_steps
       Efield(i1)%t_final=RT_step*(NE_steps-1)
     endif
     !
   endif
   !
 enddo
 !
 l_NE_dynamics= l_NE_with_fields .or. l_rt_carriers_in_use
 !
 ! Check on the PROBE/PUMP frequencies
 !====================================
 call RT_Field_Commensurable_Frequencies()
 !
 if ( .not. l_NE_dynamics ) call error('No external fields nor manual pumping provided')
 !
 ! Number of K-points
 !====================
 NK_cpu=0
 do ik=1,k%nibz
   if (.not.PAR_IND_Xk_ibz%element_1D(ik)) cycle
   NK_cpu(PAR_COM_Xk_ibz_INDEX%CPU_id+1)= NK_cpu(PAR_COM_Xk_ibz_INDEX%CPU_id+1)+RTibz%N_mapped(ik)
 enddo
 call PP_redux_wait(NK_cpu,COMM=PAR_COM_Xk_ibz_INDEX%COMM)
 !
 ! Memory Depth & Simulation points (Lifetimes)
 !=============================================
 if (l_elph_scatt.or.l_elel_scatt) then
   if (.not.allocated(E%W)) then
     call warning("NO QP damping provided. E-E and/or E-P switched off")
     l_elph_scatt=.FALSE.
     l_elel_scatt=.FALSE.
   endif
 endif
 !
 ! Checking extended COLLISIONS
 !==============================
 if (l_elel_scatt.or.l_sc_sex.or.l_sc_fock.or.l_sc_hartree.or.l_sc_is_libDFT) then
   !
   call section('=','Electronic Collisions loading and setup')
   !
   if (l_elel_scatt) then
     call PLASMA_build_up(E,k,q)
     call PLASMA_parallel_setup(EH_gas)
   endif
   !
   if (io_COLLs) call COLLISIONS_load(.TRUE.)
   !
 endif
 !
#if defined _ELPH
 !
 ! Electron-phonon
 ! ===============
 !
 call RT_ELPH_initialize(E,k,q)
 !
#endif
 !
 l_RT_is_WFfree = (l_use_Hxc_collisions .or. trim(RT_potential)=="IP")   .and.     &
&                 (.not.eval_energy) .and. (.not.l_velocity_gauge_corr)  .and.     &
&                 (COLLISIONS_have_HARTREE.or.index(trim(RT_potential),"HARTREE")==0)
 !
 RT_is_dynamically_dephased=l_elel_scatt.or.l_elph_scatt.or.l_elphoton_scatt.or.l_phel_scatt
 !
#if defined _RT_SCATT
 if (     RT_is_dynamically_dephased) N_T_samplings = RT_Lifetimes_evaluation_plan( )
 if (.not.RT_is_dynamically_dephased) N_T_samplings = 0
#else
 N_T_samplings = 0
#endif
 !
 call RT_adjust_equilibrium()
 !
 ! LOG
 ! ===
 !
 call section('=','Messaging')
 !
 call msg( 'r','---General---')
 call msg( 'r', 'Integrator                 ',trim(Integrator_name))
 call msg( 'r', 'Simulation time            ',NE_tot_time*AUT2FS,"[fs]")
 call msg( 'r', 'Basic time step            ',RT_step*AUT2FS,"[fs]")
 call msg( 'r', '           steps           ',NE_steps)
 !
 call msg( 'r', '      time step   (now)    ',RT_dyn_step*AUT2FS,"[fs]")
 !
 if (NE_initial_time_step_update>0.) then
   call msg( 'r','---Time Step Update---')
   call msg( 'r', 'Initial time               ',NE_initial_time_step_update*AUT2FS,"[fs]")
   call msg( 'r', 'Time Interval              ',NE_time_step_update_jump*AUT2FS,"[fs]")
   call msg( 'r', 'Treshold                   ',NE_step_update_treshold,"[o/o]")
   call msg( 'r',  'dT maximum value          ',RT_MAX_step*AUT2FS,"[fs]")
 endif
 !
 call msg( 'r','---Memory---')
 call msg( 'r', 'Memory depth(G)            ',T_memory*AUT2FS,"[fs]")
 call msg( 'r', 'Memory steps(G)            ',G_MEM_steps)
 !
 if (RT_is_statically_dephased) then
   call msg( 'nr','---Lifetimes---')
   if (all(RT_life_extrap_times>0)) then
     call msg( 'r', 'Point groups (inter/intra)     ',RT_life_extrap_times*AUT2FS,"[fs]")
     call msg( 'r', 'Extrapolation                  ',l_RT_lifetimes_extrapolation)
     call msg( 'r', 'Memory steps                   ',Life_MEM_steps)
   endif
   call msg( 'r', 'Evaluated Time points          ',N_T_samplings)
   call msg( 'r', 'Relaxation time approximation  ',l_RT_relax_time_approx)
   call msg( 'r', 'Equilibrium is zero temperature',l_RT_eq_is_zero_temp)
   call msg( 'r', 'Equilibrium scattering included',l_RT_include_eq_scatt)
 endif
 !
 call msg( 'nr','---Flags (if any)---')
 !
 call msg( 'r','Hxc approximation          ',trim(RT_potential))
 !
 if (l_elph_scatt)         call msg( 'r','El-Ph         scattering   ',l_elph_scatt)
#if defined _PHEL
 if (l_phel_scatt)         call msg( 'r','Ph-El         scattering   ',l_phel_scatt)
#endif
 if (l_elel_scatt)         call msg( 'r','El-El         scattering   ',l_elel_scatt)
 if (l_elphoton_scatt)     call msg( 'r','El-Photon     scattering   ',l_elphoton_scatt)
 if (l_RT_update_Energies) then
   call msg( 'r','Update QP Energies         ',l_RT_update_Energies)
 endif
 if (l_update_SOC)         call msg( 'r','Update SOC Interaction     ',l_update_SOC)
 !
 call msg( 'nr','---I/O---')
 call                          msg('r', 'T cache step  of J,P,M     ',CACHE_OBS_INTERVAL_time*AUT2FS,"[fs]")
 call                          msg('r', 'T between I/O of   OBS     ',OBS_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
 call                          msg('r', 'T between I/O of   CAR     ',CARR_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
 call                          msg('r', '          I/O of   GFs     ',Gless_RESTART_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
 call                          msg('r', '               outputs     ',OUTPUT_RT_IO_t%INTERVAL_time*AUT2FS,"[fs]")
 if (l_use_collisions)    call msg( 'r','Extended collisions   [I/O]',io_COLLs)
 !
 if(Phase_LifeTime>thresh.or.RAD_LifeTime>thresh) then
   call msg( 'nr','---Damping---')
   if(Phase_LifeTime>thresh) &
   & call msg( 'r', 'Damping (Phase)            ',(/Phase_LifeTime*AUT2FS,HBAR_eVfs/Phase_LifeTime*AUT2FS*1000._SP/),'[fs/meV]')
   if(RAD_LifeTime>thresh) &
   & call msg( 'r', '        (Radiative)        ',(/RAD_LifeTime  *AUT2FS,HBAR_eVfs/RAD_LifeTime  *AUT2FS*1000._SP/),'[fs/meV]')
 endif
 !
 call msg( 'nr','---Retarded GF---')
 call msg( 'r', 'Retarded Green`s function  ',Gr_kind)
 call msg( 'r', '        Energy ref  (c)    ',QP_ctl_user(3,1)%Wc_E_ref*HA2EV,"[eV]")
 call msg( 'r', '                    (v)    ',QP_ctl_user(3,1)%Wv_E_ref*HA2EV,"[eV]")
 call msg( 'r', '        Analytic term (c)               ',QP_ctl_user(3,1)%Wc,"[eV,adim,eV^-1]") 
 call msg( 'r', '                      (v)               ',QP_ctl_user(3,1)%Wv,"[eV,adim,eV^-1]")
 !
 if ((l_elel_scatt.or.l_elph_scatt).and.(.not.l_RT_impose_N_dN.or.l_RT_impose_E)) then
   call msg( 'nr','---Conservation Rules---')
   call msg( 'r',                  'dN (e-p) and N (e-p + e-e)  ',l_RT_impose_N_dN)
   if (l_elel_scatt) call msg( 'r','Energy (e-e)                ',l_RT_impose_E)
 endif
 !
 call msg( 'nr','---K Grid---')
 call msg( 'r', 'Double Grid support          ',l_RT_uses_E_FineGd)
 if (l_RT_uses_E_FineGd) then
   call msg( 'r', 'K-pts  (Coarse grid IBZ/BZ)',(/k%nibz,k%nbz/))
   call msg( 'r', 'K-pts    (Fine grid IBZ/BZ)',(/k%FGibz%N,k%FGbz%N/))
   call msg( 'r', 'K-pts  (Real-time IBZ only)',RT_nk)
   if (PAR_COM_Xk_ibz_INDEX%n_CPU>1) then
     call msg( 'r',  '      (DISTRIBUTED min-MAX)',(/minval(NK_cpu),maxval(NK_cpu)/))
   endif
   if (l_elel_scatt) then
     call msg( 'r',  'Percentual used in e-e     ',DbGd_EE_percent,"[o/o]")
     call msg( 'r',  'Max e-e scattering states  ',maxval(DbGd_EE_Nk_table))
   endif
 else
   call msg( 'r',    'K-points            (TOTAL)',RT_nk)
 endif
 !
 if (l_NE_with_fields) then
   call msg( 'nr','---Fields---')
   call msg('r','Gauge                               ',trim(global_gauge))
   !
   if (any(Efield(:)%W_step>0)) then
     call msg('r','Pump/Probe periodicity',EtoT(E=maxval(Efield(:)%W_step))*AUT2FS,'[fs]')
     call msg('r','Pump/Probe energy step',maxval(Efield(:)%W_step)*HA2EV,'[eV]')
   endif
   !
   do i1=1,n_ext_fields
     MSG_ch="Field#"//trim(intc(i1))
     call msg('r', trim(MSG_ch)//' field                       ',trim(Efield(i1)%ef_name))
     call msg('r', trim(MSG_ch)//' polarization                ',trim(Efield(i1)%ef_pol))
     call msg('r', trim(MSG_ch)//' frequency range             ',(/Efield(i1)%frequency*HA2EV,&
&                  2._SP*pi*HBAR_evfs/(Efield(i1)%frequency*HA2EV)/),'[eV/fs]')
     call msg('r', trim(MSG_ch)//' elemental oscillation       ',EtoT(E=Efield(i1)%frequency(2)-&
&                                                                       Efield(i1)%frequency(1))*AUT2FS,'[fs]')
     call msg('r', trim(MSG_ch)//' width                       ',Efield(i1)%width*AUT2FS,'[fs]')
     call msg('r', trim(MSG_ch)//' start time                  ',Efield(i1)%t_initial*AUT2FS,'[fs]')
     call msg('r', trim(MSG_ch)//' energy steps                ',Efield(i1)%n_frequencies)
     call msg('r', trim(MSG_ch)//' electric field              ',Efield(i1)%amplitude*AU2VMm1,'[V/m]')
     call msg('r', trim(MSG_ch)//' max intensity               ',Efield(i1)%intensity*AU2KWCMm2,'[kW/cm^2]')
     !
     if( (field_defs(1)=='QSSIN') .or. (field_defs(1)=='GAUSS') .or. (field_defs(1)=='DELTA') ) then
       call msg('r', trim(MSG_ch)//' max fluence                 ',Efield(i1)%fluence,'[nJ/cm^2]')
       call msg('r', trim(MSG_ch)//' area at selected Rabi trans.',Efield(i1)%pi_kind )
       call msg('r', trim(MSG_ch)//' final time                  ',Efield(i1)%t_final*AUT2FS,'[fs]')
       call msg('r', trim(MSG_ch)//' half maximum full width     ',Efield(i1)%width*2.*sqrt(2.*log(2.))*AUT2FS,'[fs]')
     endif
     !
   enddo
   !
 endif
 !
 call section('-P',' ')
 !
 contains
   !
   subroutine RT_adjust_equilibrium()
     !
     use electrons,          ONLY:spin_occ,n_sp_pol
     !
     integer :: ik,ik_RT_DbGd,ik_E_fg,ib
     !
     if(.not.l_RT_eq_is_zero_temp) return
     !
     if(.not.allocated(E%fo)) then
       YAMBO_ALLOC(E%fo,(E%nb,E%nk,n_sp_pol))
       E%fo=E%f
     endif
     !
     if(.not.allocated(E%df)) then
       YAMBO_ALLOC(E%df,(E%nb,E%nk,n_sp_pol))
       E%df=0._SP
     endif
     !
     if (l_RT_uses_E_FineGd.and..not.allocated(E%FG%df)) then
       YAMBO_ALLOC(E%FG%df,(E%nb,k%FGibz%N,n_sp_pol))
       E%FG%df=0._SP
     endif
     !
     ! Defined from occupations %f
     ! In case RT_apply has been used the reference is
     ! defined from the %fo occupations
     !
     do ib=RT_bands(1),RT_bands(2)
       do ik=1,k%nibz
         do ik_RT_DbGd=RTibz%k_range(ik,1),RTibz%k_range(ik,2)
           !
           if (l_RT_uses_E_FineGd) then
             ik_E_fg=RTibz%E_map(ik_RT_DbGd)
             if(E%FG%E(ib,ik_E_fg,1)<=E%E_Fermi) then
               E%FG%df(ib,ik_E_fg,1)=(E%FG%f(ib,ik_E_fg,1)-spin_occ)
             else
               E%FG%df(ib,ik_E_fg,1)= E%FG%f(ib,ik_E_fg,1)
             endif
           else
             if(E%E(ib,ik,1)<=E%E_Fermi) then
               E%df(ib,ik,1)=(E%f(ib,ik,1)-spin_occ)
               E%fo(ib,ik,1)= spin_occ
             else
               E%df(ib,ik,1)= E%f(ib,ik,1)
               E%fo(ib,ik,1)= 0._SP
             endif
           endif
           !
         enddo
       enddo
     enddo
     !
   end subroutine RT_adjust_equilibrium
   !
end subroutine RT_initialize
