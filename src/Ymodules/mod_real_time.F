!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM MG DS
!
module real_time
 !
 use drivers,        ONLY:l_elel_scatt,l_elph_scatt,l_elphoton_scatt,l_phel_scatt
 use pars,           ONLY:DP,SP,schlen,lchlen,LP
 use units,          ONLY:FS2AUT
 use global_XC,      ONLY:QP_SE_NONE
 use R_lattice,      ONLY:bz_fine_grid
 use RT_lifetimes,   ONLY:RT_obj_lifetime,RT_obj_lifetime_alloc,RT_obj_lifetime_free
 use RT_occupations, ONLY:RT_obj_occupation,RT_obj_occupation_alloc,RT_obj_occupation_free
 use electrons,      ONLY:E_fine_grid
 !
#include<y_memory.h>
 !
 ! CORE LOGICALS
 !
 ! NE dynamics
 !
 logical           :: l_NE_dynamics
 logical           :: l_NE_with_fields
 logical           :: l_Dynamics_is_over
 logical           :: l_Update_Time_Step  = .FALSE.
 logical           :: l_RT_is_WFfree
 !
 character(schlen) :: RT_potential
 !
 ! Possible Kinds, functionals and external perturbations
 !
 integer           :: RT_kind
 integer           :: RT_xc_functional
 integer           :: RT_perturbation
 !
 ! Evaluation logicals
 !
 logical          :: eval_energy
 logical          :: eval_entropy
 logical          :: eval_HARTREE
 logical          :: eval_DFT
 !
 ! To include the induced field in the coupling and current
 !
 logical          :: l_RT_induced_field = .FALSE.
 logical          :: l_P_integrating_J
 logical          :: l_velocity_gauge_corr
 logical          :: l_velocity_gauge_diam
 !
 ! Specific flag for when Yambo libraries are called to perform TRabs via YPP
 !
 logical  :: l_TRabs_YPP = .false.
 !
 ! ... core step length and Time-points array...
 !
 real(SP)              :: RT_step             ! Elemental step used to define dimensions and time-points
 real(SP)              :: RT_dyn_step = 0._SP ! On-the-fly time-step
 real(SP)              :: RT_MAX_step =-1._SP*FS2AUT ! MAX value of the dynamical RT step value
 real(SP)              :: RT_step_manual_prefactor
 !
 ! ... NE dynamics ...
 !
 real(SP) :: NE_time    =0._SP  ! <- incremented
 real(SP) :: NE_tot_time=0._SP  ! Total (fixed)
 !
 integer  :: NE_time_step_update_last_point      ! Last time-point of the dT update
 real(SP) :: NE_time_step_update_jump            ! Time BETWEEN two time-steps dynamically updated (0. means RT_step)
 real(SP) :: NE_time_step_update_jump_INPUT
 real(SP) :: NE_initial_time_step_update         ! Time above which the time-step is dynamically updated (0. means no update)
 real(SP) :: NE_step_update_treshold             ! Time-step update treshold
 real(SP) :: NE_time_step_update_manual          ! Time at which the time step is updated with a manual pre-factor
 !
 integer  :: NE_i_time=1 ! = NE_time/RT_step+1
 integer  :: NE_steps    ! Still relative to RT_step
 !
 ! Lifetimes Extrapolation Time status
 !
 integer(LP), allocatable :: RT_TIME_status(:)
 !
 ! Kind of e-e interactions (for the CORR and SCATT parts)
 !
 integer           :: RT_EE_CORR_kind=QP_SE_NONE
 integer           :: RT_EE_SCATT_kind=QP_SE_NONE
 !
 ! ... Memory ...
 !
 real(SP) :: NE_MEM_treshold
 integer  :: G_MEM_steps                ! By default only G_lesser@t and @t+1
 integer  :: i_MEM_prev                 ! Updated in RT_driver
 integer  :: i_MEM_now                  ! Updated in RT_driver
 integer  :: i_MEM_old                  ! Updated in RT_driver
 integer, allocatable :: MEM_pointer(:) ! Time memory pointers
 !
 ! ... Window on the k-points/bands allowed to follow the dynamics ...
 !
 real(SP)    :: RT_eh_en(2)
 real(SP)    :: RT_scatt_tresh
 !
 ! Macroscopic induced current ...
 !--------------------------------
 complex(SP) :: RT_ind_J(3)
 complex(SP) :: RT_ind_J_prev(3)
 !
 ! ... polarization ...
 !----------------------
 complex(SP) :: RT_P(3)
 complex(SP) :: RT_P_prev(3)
 !
 ! ... and magnetization
 !----------------------
 complex(SP) :: RT_spin_magn(3,3)
 complex(SP) :: RT_orbt_magn(3,2)
 !
 ! Diagonal (QP) and off-diagonal (Phase) relaxation time
 !
 real(SP)    :: Phase_LifeTime
 real(SP)    :: RAD_LifeTime
 real(SP)    :: RAD_magnification=1._SP
 real(SP)    :: RT_deph_deg_thresh
 logical     :: RT_deph_cv_only
 logical     :: RT_is_statically_dephased=.FALSE.
 logical     :: RT_is_dynamically_dephased=.FALSE.
 !
 ! FineGd kind mapping the kpts grid (w and w/o FineGd database)
 !
 type(bz_fine_grid), SAVE :: RTibz
 !
 ! K-points: In case I want to use the G_lesser to define the occupations
 ! of a post-run I need to keep here the number of k-points
 !
 integer                 :: RT_nk
 integer                 :: RT_bands(2)
 integer                 :: RT_nbands
 !
 ! Equilibrium V_xc and V_hartree in real space
 ! Presently REF_V_hartree_sc is not used
 !
 real(SP),    allocatable :: REF_V_xc_sc(:,:)
 real(SP),    allocatable :: REF_V_hartree_sc(:,:)
 !
 ! Update Energies, eval Lifetimes rotate DM (density matrix)
 !-----------------------------------------------------------
 logical                  :: l_eval_Lifetimes
 logical                  :: l_RT_update_Energies
 logical                  :: l_RT_rotate_DM
 logical                  :: l_update_SOC
 !
 ! Relaxation and Dissipation
 !----------------------------
 logical                  :: l_RT_uses_E_FineGd
 logical                  :: l_RT_eq_is_zero_temp
 logical                  :: l_RT_include_eq_scatt
 logical                  :: l_RT_impose_for_metals
 logical,     allocatable :: DbGd_EE_scatt_table(:,:)  
 integer,     allocatable :: DbGd_EE_Nk_table(:,:)  
 real(SP)                 :: DbGd_EE_percent 
 !
 ! Conservations
 !----------------------
 logical                  :: l_RT_impose_N_dN = .TRUE.
 logical                  :: l_RT_impose_E    = .TRUE.
 !
 ! Energies
 !---------------------
 type(E_fine_grid)       :: RT_levels
 !
 ! Relaxation: Dephasing Matrix
 !------------------------------
 real(SP)                 :: RT_ave_dephasing
 real(SP)                 :: RT_deph_range(2)
 real(SP),    allocatable :: RT_INPUT_Deph_limits(:,:)
 real(SP),    allocatable :: RT_Deph_Matrix(:,:,:)
 !
 ! GFs (retarded)
 !----------------
 integer           :: two_alpha
 real(SP)          :: Gr_QP_width
 character(schlen) :: Gr_kind
 !
 ! GFs
 !-----
 complex(SP), allocatable :: G_lesser(:,:,:,:)          ! Band, Band, K, Time
 complex(SP), allocatable :: dG_lesser(:,:,:,:)
 complex(SP), allocatable :: G_lesser_reference(:,:,:)  ! Band, Band, K
 complex(SP), allocatable :: I1_matrix(:,:)
 !
 ! RT_Hamiltonian
 !----------------
 !
 complex(SP), allocatable :: Ho_plus_Sigma(:,:,:,:)
 complex(SP), allocatable :: H_EQ(:,:,:,:)
 complex(SP), allocatable :: H_pseudo_eq(:,:,:,:)
 complex(SP), allocatable :: RT_Vnl_xc(:,:,:,:)
 !
 ! Density
 !---------
 !
 real(SP),    allocatable :: rho_reference(:)    ! reference density from all bands
 real(SP),    allocatable :: magn_reference(:,:) ! reference magnetization from all bands
 !
 ! Integrators
 !
 logical  :: l_RT_EULER
 logical  :: l_RT_EXP
 logical  :: l_RT_INV
 !
 logical  :: l_RT_RWA
 logical  :: l_RT_ACC
 logical  :: l_RT_PERT
 logical  :: l_RT_DIAG
 !
 logical  :: l_RT_SIMPLE
 logical  :: l_RT_RK2
 logical  :: l_RT_RK4
 logical  :: l_RT_HEUN
 !
 integer  :: Integrator_step
 integer  :: Integrator_nsteps
 integer  :: Integrator_exp_order
 !
 real(SP) :: a_tableau(4)
 real(SP) :: b_tableau(4)
 real(SP) :: c_tableau(4)
 real(SP) :: RWA_table(5)
 !
 ! Integrate exactly the part of the dynamics due to H_o
 ! as it is done in Comp. Phys. Comm. 123(1999)
 ! in this case I choosed H_o = H_lda ( rho_0 )
 !
 character(schlen)            :: Integrator_name
 !
 ! Hartree term
 !
 complex(SP), allocatable :: XC0(:,:,:,:)
 complex(SP), allocatable :: HARTREE0(:,:,:,:)
 !
 type RT_t
   !
   ! Sizes and definitions
   !
   integer  :: nk
   integer  :: nb(2)
   integer  :: nstates
   character(schlen)  :: description
   !
   integer,    allocatable:: table(:,:)      ! ib,ik_RT,ik,i_spin
   real(SP)   ,allocatable:: kpt(:,:)
   real(SP)   ,allocatable:: k_weight(:)
   !
   ! Energies
   !
   real(SP)   ,allocatable:: E_bare(:)       ! equilibrium energy, i.e. the QP energy
   real(SP)   ,allocatable:: delta_E(:)      ! change in E (BGR)
   !
   ! Occupations
   !
   type(RT_obj_occupation):: OCC_el
   type(RT_obj_occupation):: OCC_ph
   !
   ! Lifetimes
   !
   real(SP)   ,allocatable:: NEQ_Lifetime(:) ! time dependent lifetime defined as for Silicon
   type(RT_obj_lifetime)  :: GAMMA_EP_abs
   type(RT_obj_lifetime)  :: GAMMA_EP_emit
   type(RT_obj_lifetime)  :: GAMMA_EE
   type(RT_obj_lifetime)  :: GAMMA_EH
   type(RT_obj_lifetime)  :: GAMMA_PE
   !
 end type RT_t
 !
 type(RT_t),save  :: RT_carriers
 !
 contains
   !
   !------------
   ! RT_OBJECTS
   !------------
   !
   subroutine RT_obj_alloc(RT)
     !
     use D_lattice, ONLY:Bose_Temp
     type(RT_t)        ::RT
     !
     if (allocated(RT%kpt)) return
     !
     YAMBO_ALLOC(RT%kpt,(RT%nk,3))
     YAMBO_ALLOC(RT%k_weight,(RT%nk))
     YAMBO_ALLOC(RT%table,(RT%nstates,4))
     YAMBO_ALLOC(RT%E_bare,(RT%nstates))
     RT%table         =0
     RT%E_bare        =0._SP
     RT%OCC_el%active =.TRUE.
     RT%OCC_ph%active =l_phel_scatt
     call RT_obj_occupation_alloc("El",RT%OCC_el,RT%nstates)
     call RT_obj_occupation_alloc("Ph",RT%OCC_ph,RT%nstates)
     if (l_elel_scatt) then
       RT%GAMMA_EE%active=.TRUE.
       call RT_obj_lifetime_alloc("el-el",RT%GAMMA_EE,RT%nstates)
     endif
     if (l_elph_scatt) then
       RT%GAMMA_EP_emit%active=.TRUE.
       call RT_obj_lifetime_alloc("el-ep_emit",RT%GAMMA_EP_emit,RT%nstates)
       if (Bose_Temp>0._SP.or.l_phel_scatt) then
         RT%GAMMA_EP_abs%active=.TRUE.
         call RT_obj_lifetime_alloc("el-ep_abs",RT%GAMMA_EP_abs,RT%nstates)
       endif
     endif
     if (l_elphoton_scatt) then
       RT%GAMMA_EH%active=.TRUE.
       call RT_obj_lifetime_alloc("el-photon",RT%GAMMA_EH,RT%nstates)
     endif
     if (l_phel_scatt) then
       RT%GAMMA_PE%active=.TRUE.
       call RT_obj_lifetime_alloc("pe-el",RT%GAMMA_PE,RT%nstates)
     endif
     if (l_elel_scatt.or.l_elph_scatt.or.l_elphoton_scatt) then
       YAMBO_ALLOC(RT%NEQ_Lifetime,(RT%nstates))
       RT%NEQ_Lifetime=0._SP
     endif
     YAMBO_ALLOC(RT%delta_E,(RT%nstates))
     RT%delta_E=0._SP
   end subroutine
   !
   subroutine RT_obj_free(RT)
     type(RT_t)::RT
     RT%nk=0
     RT%nb=0
     RT%nstates=0
     YAMBO_FREE(RT%E_bare)
     YAMBO_FREE(RT%delta_E)
     YAMBO_FREE(RT%NEQ_Lifetime)
     YAMBO_FREE(RT%kpt)
     YAMBO_FREE(RT%k_weight)
     YAMBO_FREE(RT%table)
     call RT_obj_occupation_free(RT%OCC_el)
     call RT_obj_lifetime_free(RT%GAMMA_EE)
     call RT_obj_lifetime_free(RT%GAMMA_EP_abs)
     call RT_obj_lifetime_free(RT%GAMMA_EP_emit)
     call RT_obj_lifetime_free(RT%GAMMA_EH)
     call RT_obj_lifetime_free(RT%GAMMA_PE)
   end subroutine
   !
end module
