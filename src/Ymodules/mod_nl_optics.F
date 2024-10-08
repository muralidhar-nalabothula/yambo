! 
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): MG AC
!
module nl_optics
 !
 use descriptors,     ONLY:IO_desc
 use pars,            ONLY:SP,schlen,lchlen
 use electrons,       ONLY:levels
 use real_time,       ONLY:NE_steps
 !
#include<y_memory.h>
 !
 ! Long range correction field
 !
 real(SP)          :: NL_LRC_alpha
 !
 ! Time steps and step length defined in module real_time.F
 ! --------------------------------------------------------
 !
 ! Polarization 
 ! ------------
 ! Calculated from the string-averaged discretized geometric phase
 ! see ref. PRB 47, 1651 (1993), or from DIPOLES
 !
 complex(SP)    :: NL_P(6)  ! NL_P(1:3) Berry Pol, NL_P(4:6) Dip Pol
 complex(SP)    :: NL_initial_P(6) ! in principle it can be different from zero
 !
 ! Current
 !
 complex(SP)    :: NL_J(6)
 complex(SP)    :: NL_initial_J(6)
 !
 ! Diagonal (QP) and off-diagonal (Phase) relaxation time
 !
 real(SP)    :: NL_damping
 !
 ! Initial Energies and Damping
 !------------
 complex(SP), allocatable :: I_relax(:,:,:,:,:)
 real(SP),    allocatable :: E_full(:,:,:)
 !
 ! For TDDFT, V_xc_0 stores the V_xc at equilibrium
 !
 real(SP), allocatable    :: V_xc_0(:,:)
 !
 ! For JGM E_xc_0 for the microscopic part of the functional
 !
 complex(SP) :: E_xc_0(3)
 !
 ! WFs and Density
 !
 ! Bands in terms of Kohn-Sham orbitals
 complex(SP), allocatable :: V_bands(:,:,:,:)  ! time-dependent valence bands
 ! 
 ! Time-dependent Valence bands in real-space
 complex(SP), allocatable :: VAL_BANDS(:,:,:,:)
 !
 real(SP),    allocatable :: full_rho(:)       ! density of all bands from 1:SC_bands(2)
 !
 ! Density matrix
 complex(SP), allocatable :: dG(:,:,:) 
 !
 ! Sigma sex at equilibrium (for oscillators)
 complex(SP), allocatable :: Sigma_SEX_EQ(:,:,:,:)
 !
 ! Integrator Variables
 !
 integer, parameter :: EULER    = 1
 integer, parameter :: EULEREXP = 2
 integer, parameter :: RK2      = 3
 integer, parameter :: RK4      = 4
 integer, parameter :: RK2EXP   = 5
 integer, parameter :: RK4EXP   = 6
 integer, parameter :: HEUN     = 7
 integer, parameter :: INVINT   = 8
 integer, parameter :: CRANK_NICOLSON = 9
 !
 integer                      :: Integrator
 !
 ! Verbosity
 !
 integer, parameter :: VERB_HIGH = 1
 integer, parameter :: VERB_LOW  = 2
 !
 integer :: NL_verbosity
 character(schlen)            :: NL_verb_name
 !
 ! Correlation
 !
 character(schlen)            :: NL_correlation
 integer                      :: Correlation
 !
 integer, parameter :: IPA    = 1
 integer, parameter :: HARTREE= 2
 integer, parameter :: TDDFT  = 3
 integer, parameter :: LRC    = 4
 integer, parameter :: JGM    = 5
 integer, parameter :: LRCW   = 6
 integer, parameter :: HF     = 7
 integer, parameter :: SEX    = 8
 integer, parameter :: LSEX   = 9
 integer, parameter :: LHF    = 10
 !
 logical :: eval_COLLISIONS
 logical :: eval_OSCLL
 logical :: eval_dG
 !
 ! Non-linear spectra parameters
 !
 real(SP) :: NL_er(2)
 real(SP) :: NL_estep
 real(SP) :: NL_ang_step
 integer  :: NL_bands(2)
 integer  :: NL_nbands
 integer  :: n_angles
 real(SP) :: NL_rot_axis(3)
 real(SP) :: NL_initial_versor(3)
 integer  :: n_frequencies
 integer  :: n_runs_todo
 integer  :: n_runs
 !
 logical  :: Loop_on_frequencies
 logical  :: Loop_on_angles
 !
 ! Velocity gauge in indepdent particle
 !     
 logical :: l_velocity_IPA=.FALSE.
 ! 
 !
 ! Pump and probe
 !
 logical :: l_pump_and_probe=.FALSE.
 ! 
 ! Dephasing time (in units of NL_damping) 
 !
 integer, parameter :: DephMult=6 
 !
 ! Databases input/output
 !
 integer                  :: ID(3)
 !
 ! Other
 !
 logical  :: l_use_DIPOLES   ! Use standard dipoles (valid only for linear response)
 logical  :: l_eval_CURRENT  ! Evaluate current using the commutator v=[H,r] and the IP formulation
 logical  :: l_test_OSCLL    ! Test collisions built using OSCLLs vs standard Collisions
 !
 ! IO variables
 !
 real(SP),     allocatable :: NL_P_t(:,:)
 real(SP),     allocatable :: NL_J_t(:,:)
 complex(SP),  allocatable :: E_tot_t(:,:),E_ext_t(:,:), E_ks_t(:,:),V_bands_t(:,:,:,:,:)
 complex(SP)               :: E_tot(3),E_ext(3),E_ks(3)
 logical,      allocatable :: runs_done(:)
 type(IO_desc)             :: NL_desc
 !
 contains
   !
   subroutine NL_alloc(en)
     !
     use pars,           ONLY:SP
     use FFT_m,          ONLY:fft_size
     use electrons,      ONLY:levels,n_spin,n_sp_pol
     use hamiltonian,    ONLY:H_alloc
     use real_time,      ONLY:rho_reference,RT_Vnl_xc
     use R_lattice,      ONLY:nXkbz
     use QP_m,           ONLY:QP_nk
     use electric,       ONLY:ELECTRIC_alloc
     use drivers,        ONLY:l_use_Hxc_collisions
     !
     implicit none
     !
     type(levels), intent(in) :: en
     !
     call H_alloc(en,.true.,.false.)
     !
     !
     YAMBO_ALLOC(V_bands,(NL_bands(2),maxval(en%nbf),QP_nk,n_sp_pol))
     if (fft_size>0) then
       YAMBO_ALLOC(rho_reference,(fft_size))
       YAMBO_ALLOC(full_rho,(fft_size))
     endif
     !
     if(Correlation==TDDFT.or.Correlation==JGM) then
       YAMBO_ALLOC(V_xc_0,(fft_size,n_spin))
     endif          
     !
     if(l_use_Hxc_collisions) then
       YAMBO_ALLOC(RT_Vnl_xc,(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),QP_nk,n_sp_pol))
     endif          
     !
     if(eval_dG) then
       YAMBO_ALLOC(dG,(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),QP_nk))
     endif
     !
     ! Reference energies
     !
     YAMBO_ALLOC(E_full,(1:NL_bands(2),QP_nk,n_sp_pol))
     !
     if(.not.l_use_DIPOLES) then
       call  ELECTRIC_alloc(en)
     endif
     !
     YAMBO_ALLOC(NL_P_t,(NE_steps,3))
     YAMBO_ALLOC(NL_J_t,(NE_steps,6))
     YAMBO_ALLOC(E_tot_t,(NE_steps,3))
     YAMBO_ALLOC(E_ext_t,(NE_steps,3))
     YAMBO_ALLOC(E_ks_t,(NE_steps,3))
     !
   end subroutine NL_alloc
   !
   subroutine NL_alloc_k_distributed(en)
     !  
     use parallel_m,     ONLY:PAR_Xk_nibz,PAR_Xk_ibz_index
     use pars,           ONLY:SP
     use electrons,      ONLY:levels,n_spin,n_sp_pol
     use real_time,      ONLY:Ho_plus_Sigma
     use R_lattice,      ONLY:nXkbz
     use QP_m,           ONLY:QP_nk
     use FFT_m,          ONLY:fft_size
     !
     implicit none
     !
     type(levels),  intent(in) :: en
     !
     ! Valence bands in fft space
     !
     if(fft_size>0) then
       YAMBO_ALLOC(VAL_BANDS,(fft_size,maxval(en%nbf),PAR_Xk_nibz,n_sp_pol))
     endif
     YAMBO_ALLOC(I_relax,(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),maxval(en%nbf),PAR_Xk_nibz,n_sp_pol))
     YAMBO_ALLOC(Ho_plus_Sigma,(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),PAR_Xk_nibz,n_sp_pol))
     !
     if(Correlation==LSEX.or.Correlation==LHF) then
       YAMBO_ALLOC(Sigma_SEX_EQ,(NL_bands(1):NL_bands(2),NL_bands(1):NL_bands(2),n_sp_pol,PAR_Xk_nibz))
     endif          
     !
   end subroutine NL_alloc_k_distributed
   !
   subroutine NL_free
     !
     use hamiltonian,    ONLY:H_free
     use real_time,      ONLY:rho_reference,Ho_plus_Sigma,RT_Vnl_xc
     use electric,       ONLY:ELECTRIC_free
     use drivers,        ONLY:l_use_Hxc_collisions
     !
     implicit none
     !
     call H_free()
     !
     YAMBO_FREE(Ho_plus_Sigma)
     YAMBO_FREE(I_relax)
     YAMBO_FREE(V_bands)
     !
     YAMBO_FREE(rho_reference)
     YAMBO_FREE(full_rho)
     YAMBO_FREE(E_full)
     YAMBO_FREE(V_xc_0)
     YAMBO_FREE(VAL_BANDS)
     !
     if(.not.l_use_DIPOLES) then
       call ELECTRIC_free()
     endif
     !
     YAMBO_FREE(NL_P_t)
     YAMBO_FREE(NL_J_t)
     YAMBO_FREE(E_tot_t)
     YAMBO_FREE(E_ext_t)
     YAMBO_FREE(E_ks_t)
     !	
     if(eval_dG) then
       YAMBO_FREE(dG)
     endif
     !
     if(l_use_Hxc_collisions) then
       YAMBO_FREE(RT_Vnl_xc)
     endif
     if(eval_dG) then
       YAMBO_FREE(dG)
     endif
     !
   end subroutine NL_free
   !
   real function Alpha_ED(en,omega)
   !
   real(SP) :: Egap,beta,omega
   type(levels) :: en
     !	
     Egap = sum(en%E(en%nbf(1)+1,:,1)-en%E(en%nbf(1),:,1))/real(en%nk,SP)
     beta = NL_LRC_alpha/Egap**2
     Alpha_ED = NL_LRC_alpha + beta*omega**2
   end function
   !
end module
