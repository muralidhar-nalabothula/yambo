!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
module electrons
 !
 use pars,  ONLY:SP,rZERO
 !
#include<y_memory.h>
 !
 real(SP) :: nel
 real(SP) :: default_nel
 real(SP) :: spin_occ
 real(SP) :: filled_tresh
 integer  :: n_bands
 integer  :: n_met_bands(2)
 integer  :: n_full_bands(2)
 !
 ! Spin support
 !
 !     n_spin n_sp_pol n_spinor n_spin_den 
 !       1        1        1       1              
 !       2        1        2       1          non collinear, v[rho] 
 !       2        1        2       4          non collinear, v[rho_{\sigma,\tau}] 
 !       2        2        1       2          collinear,     v[rho_{\sigma}]
 !
 ! Note that in the non collinear case n_spin is an index
 ! for the spinor components. It is not a Physical quantity.
 !
 integer  :: n_spin
 integer  :: n_sp_pol
 integer  :: n_spinor
 integer  :: n_spin_den
 logical  :: l_spin_orbit
 !
 ! Average magnetization density
 !
 logical                  :: eval_magn
 real(SP)                 :: Spin_magn(3)
 real(SP)                 :: Orbital_magn(3)
 real(SP)                 :: Itinerant_magn(3)
 !
 ! Fine grid
 !-----------
 type E_fine_grid
   integer              :: nk
   integer              :: nb
   real(SP), allocatable:: E(:,:,:)
   real(SP), allocatable:: W(:,:,:)
   real(SP), allocatable:: f(:,:,:)
   real(SP), allocatable:: df(:,:,:)
   real(SP)             :: E_Fermi
 end type E_fine_grid
 !
 ! Levels 
 !--------
 type levels
   !
   integer         :: nb                 ! Number of bands
   integer         :: nk                 ! Numbef of k-points
   integer         :: nbf(2)             ! 1-2 refers to spin polarizations
   integer         :: nbm(2)
   integer         :: nbc(2)             ! Number of bands with NEQ carriers for yambo_rt
   real(SP)        :: E_Fermi
   real(SP)        :: E_dir_gap(2)       ! 1-2 refers to spin polarizations
   real(SP)        :: E_ind_gap(2)
   real(SP)        :: E_VBM(2)           ! Valence    Band Maximum
   real(SP)        :: E_CBm(2)           ! Conduction Band minimum
   !
   ! QP corrections
   !
   real(SP),   allocatable :: E(:,:,:)        ! Kohn-Sham or Quasi-particle energies 
   real(SP),   allocatable :: Eo(:,:,:)       ! Bare energies (Kohn-Sham) 
   real(SP),   allocatable :: f(:,:,:)        ! Electronic occupation 
   real(SP),   allocatable :: fo(:,:,:)       ! Bare electronic occupation 
   real(SP),   allocatable :: df(:,:,:)        
   real(SP),   allocatable :: W(:,:,:)        ! Imaginary part of the quasi-particle 
   complex(SP),allocatable :: Z(:,:,:)        ! Renormalization factor 
   !
   ! Green Functions
   !
   logical                 :: GreenF_is_causal
   integer                 :: GreenF_n_E_steps
   complex(SP),allocatable :: GreenF_W(:,:,:,:)   
   complex(SP),allocatable :: GreenF(:,:,:,:)     
   ! 
   ! Fine grid energy and k-points grid
   !
   type (E_fine_grid) :: FG
   !   
   ! Perturbative SOC
   !
   integer              :: nb_SOC
   integer,    allocatable :: table_SOC(:,:,:)
   real(SP),   allocatable :: E_SOC(:,:)           
   !
 end type levels
 ! 
 contains
   !
   subroutine E_duplicate(Ei,Eo)
     type(levels):: Ei,Eo
     !
     integer :: BOUNDS(2)
     logical :: naive
     !
     naive=Eo%nk==0
     Eo%nb=Ei%nb
     Eo%nb_SOC=Ei%nb_SOC
     Eo%FG%nb=Ei%FG%nb
     if (naive) then
       Eo%nk=Ei%nk
       Eo%nbf=Ei%nbf
       Eo%nbm=Ei%nbm
       Eo%nbc=Ei%nbc
       Eo%E_Fermi=Ei%E_Fermi
       Eo%E_VBM=Ei%E_VBM
       Eo%E_CBm=Ei%E_CBm
       Eo%E_ind_gap=Ei%E_ind_gap
       Eo%E_dir_gap=Ei%E_dir_gap
       Eo%E_ind_gap=Ei%E_ind_gap
     endif
     YAMBO_ALLOC(Eo%E,(Eo%nb,Eo%nk,n_sp_pol))
     YAMBO_ALLOC(Eo%f,(Eo%nb,Eo%nk,n_sp_pol))
     Eo%E=0._SP
     Eo%f=0._SP
     !
     ! This line is beacause in _RT calculations the actual first size of %Eo may differ
     ! from %nb as it is limited by SC_bands.
     !
     BOUNDS(1)=Ei%nb
     if (allocated(Ei%Eo)) then
       BOUNDS(1)=size(Ei%Eo,1)
     endif
     BOUNDS(2)=BOUNDS(1)
     !
     if (naive) then
       ! %E
       Eo%E(:,:,:)=Ei%E(:,:,:)
       if (allocated(Ei%Eo)) then
         YAMBO_ALLOC(Eo%Eo,(BOUNDS(1),Eo%nk,n_sp_pol))
         Eo%Eo(:BOUNDS(1),:,:)=Ei%Eo(:BOUNDS(1),:,:)
       endif
       ! %f
       Eo%f(:,:,:)=Ei%f(:,:,:) 
       if (allocated(Ei%fo)) then
         YAMBO_ALLOC(Eo%fo,(BOUNDS(1),Eo%nk,n_sp_pol))
         Eo%fo(:BOUNDS(1),:,:)=Ei%fo(:BOUNDS(1),:,:)
       endif
       if (allocated(Ei%df)) then
         YAMBO_ALLOC(Eo%df,(BOUNDS(1),Eo%nk,n_sp_pol))
         Eo%df(:BOUNDS(1),:,:)=Ei%df(:BOUNDS(1),:,:)
       endif
       ! %W
       if (allocated(Ei%W)) then
         YAMBO_ALLOC(Eo%W,(BOUNDS(2),Eo%nk,n_sp_pol))
         Eo%W(:BOUNDS(2),:,:)=Ei%W(:BOUNDS(2),:,:)
       endif
       ! %Z
       if (allocated(Ei%Z)) then
         YAMBO_ALLOC(Eo%Z,(BOUNDS(2),Eo%nk,n_sp_pol))
         Eo%Z(:BOUNDS(2),:,:)=Ei%Z(:BOUNDS(2),:,:)
       endif
     else
       Eo%E(:,:,:)=Ei%E(:,:Eo%nk,:)
     endif
     !
     ! E Double Grid
     !
     if (Eo%FG%nb/=0.and.Ei%nk==Eo%nk) then
       Eo%FG%nk=Ei%FG%nk
       YAMBO_ALLOC(Eo%FG%E,(Eo%FG%nb,Eo%FG%nk,n_sp_pol))
       YAMBO_ALLOC(Eo%FG%W,(Eo%FG%nb,Eo%FG%nk,n_sp_pol))
       YAMBO_ALLOC(Eo%FG%f,(Eo%FG%nb,Eo%FG%nk,n_sp_pol))
       Eo%FG%E=Ei%FG%E
       Eo%FG%W=Ei%FG%W
       Eo%FG%f=Ei%FG%f
       if(allocated(Ei%FG%df)) then
         YAMBO_ALLOC(Eo%FG%df,(Eo%FG%nb,Eo%FG%nk,n_sp_pol))
         Eo%FG%df=Ei%FG%df
       endif
     endif
     !
     ! E_SOC
     !
     if (Eo%nb_SOC/=0.and.Ei%nk==Eo%nk) then
       YAMBO_ALLOC(Eo%E_SOC,(Eo%nb_SOC,Eo%nk))
       Eo%E_SOC=Ei%E_SOC
       YAMBO_ALLOC(Eo%table_SOC,(2,Eo%nb,Eo%nk))
       Eo%table_SOC=Ei%table_SOC
     endif
     !
   end subroutine
   !
   subroutine E_reset(E)
     type(levels)::E
     !
     E%E_dir_gap=0._SP
     E%E_ind_gap=0._SP
     E%E_Fermi=0._SP
     E%E_VBM=0._SP
     E%E_CBm=0._SP
     E%nb=0
     E%nk=0
     E%nbf=0 
     E%nbm=0
     E%nbc=0
     E%GreenF_n_E_steps=0 
     E%GreenF_is_causal=.FALSE. 
     YAMBO_FREE(E%E)
     YAMBO_FREE(E%Eo)
     YAMBO_FREE(E%Z)
     YAMBO_FREE(E%W)
     YAMBO_FREE(E%f)
     YAMBO_FREE(E%fo)
     YAMBO_FREE(E%df)
     YAMBO_FREE(E%GreenF)
     YAMBO_FREE(E%GreenF_W)
     !
     call FineGd_E_components_reset(E,.FALSE.)
     !
     E%nb_SOC=0
     YAMBO_FREE(E%E_SOC)
     YAMBO_FREE(E%table_SOC)
     !
   end subroutine
   !
   subroutine FineGd_E_components_alloc(E)
     !
     type(levels)::E
     !
     YAMBO_ALLOC(E%FG%E,(E%FG%nb,E%FG%nk,n_sp_pol))
     YAMBO_ALLOC(E%FG%W,(E%FG%nb,E%FG%nk,n_sp_pol))
     YAMBO_ALLOC(E%FG%f,(E%FG%nb,E%FG%nk,n_sp_pol))
     YAMBO_ALLOC(E%FG%df,(E%FG%nb,E%FG%nk,n_sp_pol))
     E%FG%E=rZERO
     E%FG%W=rZERO
     E%FG%f=rZERO
     E%FG%df=rZERO
     !
   end subroutine
   !
   subroutine FineGd_E_components_reset(E,FULL_RESET)
     !
     type(levels)::E
     logical     ::FULL_RESET
     !
     E%FG%nb=0
     E%FG%nk=0
     !
     if (.not.FULL_RESET) return
     !
     YAMBO_FREE(E%FG%E)
     YAMBO_FREE(E%FG%W)
     YAMBO_FREE(E%FG%f)
     YAMBO_FREE(E%FG%df)
     !
   end subroutine
   !
   integer function spin(v)
     integer :: v(:)
     !
     spin=1
     if (n_sp_pol==2) spin=v(4)
     !
   end function
   !
   character(2) function spin_string(i_spin)
     integer :: i_spin
     !
     if (n_sp_pol==1) spin_string="  "
     if (i_spin==1)   spin_string="up"
     if (i_spin==2)   spin_string="dn"
     !
   end function
   !
end module electrons
