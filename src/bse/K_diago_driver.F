!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM MG DS BM
!
! headers
!
#if defined _SLEPC && !defined _NL
#include <petsc/finclude/petscsys.h>
#include <petsc/finclude/petscvec.h>
#include <petsc/finclude/petscmat.h>
#include <slepc/finclude/slepcsys.h>
#include <slepc/finclude/slepceps.h>
#endif
!
subroutine K_diago_driver(iq,W,X_static) 
 !
 ! Generic diagonalization method to solve resonant and non resonant Hamiltonians.
 !
 ! 10/06/2015 Added by HM: Generic slepc method to solve 
 !
 use pars,           ONLY:SP
 use stderr,         ONLY:intc
 use BS,             ONLY:BS_K_coupling,BS_H_dim,BS_K_dim,BS_perturbative_SOC,&
&                         BS_res_ares_n_mat,l_BS_ares_from_res !,BS_Blocks_symmetrize_K,&
 use BS_solvers,     ONLY:io_BSS_diago,BSS_perturbative_width,BSS_mode, BSS_resize, &
&                         BSS_write_eig_2_db,BSS_eh_W,BS_mat,BSS_n_eig,BS_E, write_bs_ev_par, &
&                         BSS_ydiago_solver
 use X_m,            ONLY:X_t,X_OUTPUT_driver
 use electrons,      ONLY:n_sp_pol,n_spinor
 use frequency,      ONLY:w_samp
 use com,            ONLY:isec
 use LIVE_t,         ONLY:live_timing
 use linear_algebra, ONLY:DIAGO
 use interfaces,     ONLY:K_diago_response_functions,LINEAR_ALGEBRA_driver,K_diagonalize,&
 &                        K_diago_left_residuals,K_diago_right_residuals,PL_diago_residual,&
 &                        K_diago_residuals, K_perturbative_residuals
 use IO_int,         ONLY:io_control
 use IO_m,           ONLY:REP,VERIFY,OP_WR_CL,OP_RD_CL
 use parser_m,       ONLY:parser
 use timing_m,       ONLY:timing
 use parallel_int,   ONLY:PP_wait
#if defined _SLEPC && !defined _NL
 use interfaces,     ONLY:MATRIX_slepc
 use petscmat
 use slepceps
 use slepcepsdef
 use petscmatdef
 !
 use BS_solvers,     ONLY:BSS_slepc_matrix_format,Slepc_v,BS_HAYVEC_free
#endif
 use BS,             ONLY:l_BS_abs,l_BS_kerr,l_BS_kerr_asymm,l_BS_magnons,l_BS_photolum,l_BS_dichroism
 use MAGNONS,        ONLY:BSS_MAGN_free
 use PHOTOLUM,       ONLY:BSS_PL_free
 !
#include<y_memory.h>
 ! 
 type(w_samp)  :: W
 integer       :: iq
 !
 ! Work Space
 !
 integer          :: i_BS_mat,Input_n_eig, neigs_this_cpu, neig_shift, elpa_solver = 2
 logical          :: K_is_not_hermitian,l_diago,l_slepc,l_target_energy,l_ydiago,l_kerr_lft,l_kerr_rgt,l_abs_res
 character(1)     :: sec
 character(10)    :: Solver
 ! Ydiago varibles
 integer, target  :: neigs_range(2)   = 0      ! index range of eigenvalues to find
 real(SP), target :: eigvals_range(2) = 0.0_SP ! value range of eigenvales to find
 logical          :: l_eval_range ! This is true if eigvals_range is given instead of neigs_range
 !
 ! Slepc specific
 !
#if defined _SLEPC && !defined _NL
 Mat                   :: slepc_mat
 PetscErrorCode        :: ierr
#endif
 !
 ! Excitonic hamiltonian, residuals independent
 !==============================================
 real(SP),allocatable    :: BS_E_real(:)
 real(SP)   ,pointer     :: BS_E_SOC_corr(:,:) => null()
 complex(SP),allocatable :: BS_corrections(:,:)
 !
 ! Coupling
 complex(SP),allocatable, target :: BS_V_left(:,:)
 complex(SP),allocatable, target :: BS_V_right(:,:)
 complex(SP),pointer             :: BS_overlap(:,:)    => null()
 !
 ! Residuals, different for each response function
 !=================================================
 complex(SP),pointer     :: BS_R_left_abs(:)     => null()
 complex(SP),pointer     :: BS_R_right_abs(:)    => null()
 !
 real(SP),   pointer     :: BS_R_PL(:,:)         => null()
 !
 complex(SP),pointer     :: BS_R_left_kerr(:)    => null()
 complex(SP),pointer     :: BS_R_right_kerr(:)   => null()
 complex(SP),pointer     :: BS_R_right_dich(:,:) => null()
 !
 complex(SP),pointer     :: BS_R_left_magn(:,:)  => null()
 complex(SP),pointer     :: BS_R_right_magn(:,:) => null()
 !
 ! Temporary pointer 
 complex(SP),pointer     :: tmp_res_ptrR(:)     => null()
 complex(SP),pointer     :: tmp_res_ptrL(:)     => null()
 !
 ! I/O
 integer                 :: io_err,ID
 type(X_t),intent(in)    :: X_static
 !
 l_abs_res =l_BS_abs.or.l_BS_kerr.or.l_BS_dichroism
 l_kerr_lft=l_BS_kerr_asymm.or.l_BS_dichroism
 l_kerr_rgt=l_BS_kerr      .or.l_BS_dichroism
 !
 l_diago     = index(BSS_mode,'o')/=0 ! old diago
#if defined _SLEPC && !defined _NL
 l_slepc     = index(BSS_mode,'s')/=0
#endif
 l_ydiago    = index(BSS_mode,'d')/=0 
 !
 if(l_diago) Solver="Diago"
#if defined _SLEPC && !defined _NL
 if(l_slepc) Solver="Slepc"
#endif
 if (l_ydiago) Solver="Ydiago" 
 !
 call timing(trim(Solver)//' Solver',OPR='start')
 !
 ! Output files initialization
 !=============================
 call X_OUTPUT_driver("DEF INIT",solver=Solver) 
 !
 ! Sectioning
 !============
 if (isec(2)/=0) sec="="
 if (isec(2)==0) sec="+"
 call section(sec,trim(Solver)//' Solver @q'//trim(intc(iq)))
 !  
#if defined _SLEPC && !defined _NL
 if(l_slepc) call K_slepc_local_init()
#endif
 !
 ! Eigenstates 2 DB ?
 !====================
 if (.not.BSS_write_eig_2_db) call parser('WRbsWF',BSS_write_eig_2_db)
 call parser('BSSPertWidth',BSS_perturbative_width)
 !
 do i_BS_mat=1,BS_res_ares_n_mat
   !
   if(l_diago .or. l_ydiago) then
     ! NM : In case of ydiago, BSS_n_eig will be overwritten after the solver is called! 
     if(.not.BS_K_coupling) BSS_n_eig = BS_K_dim(i_BS_mat)
     if(     BS_K_coupling) BSS_n_eig = BS_H_dim
   endif
   Input_n_eig=BSS_n_eig

   ! set a Ydiago defaults.
   if(.not.BS_K_coupling) neigs_range = (/1, BS_K_dim(i_BS_mat)/)
   if(     BS_K_coupling) neigs_range = (/1, BS_H_dim/)
   ! NM  : FIX , create a user varaible and 
   l_eval_range = .false. ! Incase user gives value range, then set this to true.
   ! false for index range
   ! each cpu contains eigen-vectors from [neig_shift + 1, neigs_this_cpu + neig_shift]
   ! For backward compatibitly I set  
   neig_shift = 0
   neigs_this_cpu = BSS_n_eig
   ! These will be changed by the ydiago_interface routine
   !
   ! Allocation (BS_R and BS_E)
   !===========================
   YAMBO_ALLOC(BS_E,(BSS_n_eig))
   call local_alloc("E")
   !
   ! Diagonalization DB (IN)
   !========================
   call io_control(ACTION=OP_RD_CL,COM=REP,MODE=VERIFY,SEC=(/1,2/),ID=ID)
   io_err=io_BSS_diago(iq,i_BS_mat,ID,X_static,BS_E,BS_R_left_abs,BS_R_right_abs,BS_E_SOC_corr,&
  &                    BS_R_left_magn,BS_R_right_magn,BS_R_left_kerr,BS_R_right_kerr,BS_R_right_dich,BS_R_PL)
   !
   K_is_not_hermitian=BS_K_coupling.or.(allocated(BSS_eh_W).and..not.BSS_perturbative_width)
   !
   ! Kernel and/or BSS components loading
   !======================================
   if (io_err<0) then
     !
     call K_components_folded_in_serial_arrays(iq)
     !
     ! Below two operations:
     ! - The blocks are sent  either to a big matrix or
     !   to a distributed (SLEPC shells / or eventually BLACS) matrix
     ! - The resulting matrix is symmetrized
     !
     if (.not. l_ydiago) then
     if (l_diago) then
       !
       call K_stored_in_a_big_matrix(i_BS_mat,iq,"DIAGO")
       !
       ! These line will be needed when the BS kernel will not be folded in BS_mat. But in order to do so
       ! also linear_algebra_is_parallel must be swiched off when K is not hermitian.
       !=========================
       !
       !if (.not.linear_algebra_is_parallel) call K_stored_in_a_big_matrix(iq,"DIAGO")
       !
#if defined _SCALAPACK
       ! Here maybe the name "K_blacs_matrix(iq)" would probably be more appropiate
       !if (     linear_algebra_is_parallel) call BS_Blocks_symmetrize_K()
#endif
       !
     endif
     !
#if defined _SLEPC && !defined _NL
     if(l_slepc) then
       ! 1. Here we will define a PetscShell matrix and define the matrix-vector multiplication
       ! using the K_multiply_by_V function used in the Haydock method
       if (BSS_slepc_matrix_format=="shell") then 
         call K_shell_matrix(i_BS_mat,slepc_mat)
       ! 2. Here we create a distributed PETSC matrix from the BS_blks
       else if (BSS_slepc_matrix_format=="explicit") then
         if (BS_K_coupling.and.l_BS_ares_from_res) then
           ! 2.1. With memory optimization using nest matrix (only possible for the coupling case)      
           call K_stored_in_a_nest_matrix(i_BS_mat,slepc_mat)
         else
           ! 2.2. Explicit PETSc matrix for the rest of the cases      
           call K_stored_in_a_slepc_matrix(i_BS_mat,slepc_mat)
         endif
       ! 2.3 No optimization of memory for the coupling case (debug)
       else if (BSS_slepc_matrix_format=="explicit-debug") then
         call K_stored_in_a_slepc_matrix(i_BS_mat,slepc_mat)
       else 
         call error(" wrong value of slepc matrix format: "//trim(BSS_slepc_matrix_format))
       endif        
     endif
#endif
     endif !l_ydiago
     !
   endif
   !
   ! Allocation (BS_E_real or BS_V)
   !===============================
   if (.not. l_ydiago) call local_alloc("V")
   !
   if (io_err<0) then
     !
     ! Diagonalization of the excitonic hamiltonian
     !==============================================
     if(l_diago) call live_timing('BSK diagonalize',1)
     !
     if (l_ydiago) then 
       ! SL and diagonalize entire hamilitonian
       ! NM : BS_V_left are only referenced in non-hermitian case
       ! Note that in coupling case, if the user requested n values,
       ! This means that the we compute the first min(n,BS_H_dim/2) positive and 
       ! min(n,BS_ham/2) negative eigvals and eigvectors, making it a total of 2*min(n,BS_ham/2)
       !
       if (.not. l_eval_range) then
         ! Use index range
         call K_diagonalize(i_BS_mat, BS_E, BS_V_right, neigs_this_cpu, neig_shift, &
&                         neigs_range=neigs_range, BS_VL=BS_V_left,BS_overlap=BS_overlap, &
&                         solver_type=BSS_ydiago_solver, elpasolver=elpa_solver)
       else
        ! use value range
        call K_diagonalize(i_BS_mat, BS_E, BS_V_right, neigs_this_cpu, neig_shift, &
&                         eigvals_range=eigvals_range, BS_VL=BS_V_left,BS_overlap=BS_overlap, &
&                         solver_type=BSS_ydiago_solver, elpasolver=elpa_solver)
       endif
       ! NM : K_diagonalize will autamatically resizes variables
       ! The size can change in case range is requested !
       BSS_n_eig = size(BS_E)
       !
     else
     !
     !
     if (K_is_not_hermitian) then
       !
       if(l_diago) call LINEAR_ALGEBRA_driver(DIAGO,M=BS_mat,E_cmpl=BS_E,V_left=BS_V_left,V_right=BS_V_right)
#if defined _SLEPC && !defined _NL
       if(l_slepc) call MATRIX_slepc(slepc_mat,l_target_energy,BSS_n_eig,BS_V_right,V_left=BS_V_left,E_cmpl=BS_E)
#endif
       !
       if (BSS_write_eig_2_db) BS_mat=BS_V_right
       !
     else
       !
       if(l_diago) call LINEAR_ALGEBRA_driver(DIAGO,M=BS_mat,E_real=BS_E_real)
#if defined _SLEPC && !defined _NL
       if(l_slepc) call MATRIX_slepc(slepc_mat,l_target_energy,BSS_n_eig,BS_mat,E_real=BS_E_real)
#endif
       !
       BS_E=cmplx(BS_E_real,0._SP,kind=SP)
       !
     endif
     endif !l_ydiago
     ! For backward compatitity
     if (.not. l_ydiago) neigs_this_cpu = BSS_n_eig
     !
#if defined _SLEPC && !defined _NL
     !
     if (l_slepc) then
       ! BSS_n_eig could be lowered by MATRIX_slepc
       if (Input_n_eig>BSS_n_eig) call K_slepc_resize_variables()
       ! Destroy the matrix
       call MatDestroy(slepc_mat,ierr)
     endif
     !
#endif
     !
     if(l_diago) call live_timing( )
     !
     ! Construct the residuals of epsilon
     !====================================
     if (.not. l_ydiago) then 
     if (K_is_not_hermitian) then
       !
       ! Right residuals
       if(l_abs_res) then
                        call K_diago_right_residuals("opt1",i_BS_mat,BS_E,BS_R_right_abs, BS_V_right)
         if(l_kerr_rgt) call K_diago_right_residuals("opt2",i_BS_mat,BS_E,BS_R_right_kerr,BS_V_right)
       endif
       if(l_BS_dichroism) then
         call K_diago_right_residuals("dic1",i_BS_mat,BS_E,BS_R_right_dich(:,1),BS_V_right)
         call K_diago_right_residuals("dic2",i_BS_mat,BS_E,BS_R_right_dich(:,2),BS_V_right)
       endif
       if(l_BS_magnons)   then
                          call K_diago_right_residuals("mag1",i_BS_mat,BS_E,BS_R_right_magn(1,:),BS_V_right)
         if(n_spinor==2)  call K_diago_right_residuals("mag2",i_BS_mat,BS_E,BS_R_right_magn(2,:),BS_V_right)
       endif
       !
       call K_diago_overlap_matrix(BS_V_left,BS_V_right,BS_overlap)
       !
       ! Left residuals
       if(l_abs_res) then
                        call K_diago_left_residuals("opt1",i_BS_mat,BS_E,BS_R_left_abs, BS_V_left,BS_overlap)
         if(l_kerr_lft) call K_diago_left_residuals("opt2",i_BS_mat,BS_E,BS_R_left_kerr,BS_V_left,BS_overlap)
       endif
       if(l_BS_magnons) then
                         call K_diago_left_residuals("mag1",i_BS_mat,BS_E,BS_R_left_magn(1,:),BS_V_left,BS_overlap)
         if(n_spinor==2) call K_diago_left_residuals("mag2",i_BS_mat,BS_E,BS_R_left_magn(2,:),BS_V_left,BS_overlap)
       endif
       !
       ! DS: this also should be changed according to the general structure
       if(l_BS_photolum) call PL_diago_residual(BS_V_left,BS_V_right,BS_R_PL,K_is_not_hermitian,BS_overlap)
       !
     else
       !
       ! Right residuals
       if(l_abs_res) then
                        call K_diago_right_residuals("opt1",i_BS_mat,BS_E,BS_R_right_abs, BS_mat)
         if(l_kerr_rgt) call K_diago_right_residuals("opt2",i_BS_mat,BS_E,BS_R_right_kerr,BS_mat)
       endif
       if(l_BS_dichroism) then
         call K_diago_right_residuals("dic1",i_BS_mat,BS_E,BS_R_right_dich(:,1),BS_mat)
         call K_diago_right_residuals("dic2",i_BS_mat,BS_E,BS_R_right_dich(:,2),BS_mat)
       endif
       if(l_BS_magnons) then
                          call K_diago_right_residuals("mag1",i_BS_mat,BS_E,BS_R_right_magn(1,:),BS_mat)
         if(n_spinor==2)  call K_diago_right_residuals("mag2",i_BS_mat,BS_E,BS_R_right_magn(2,:),BS_mat)
       endif
       !
       ! Left residuals
       if( l_abs_res  ) BS_R_left_abs =conjg(BS_R_right_abs)
       if( l_kerr_lft ) BS_R_left_kerr=conjg(BS_R_right_kerr)
       if(l_BS_magnons) BS_R_left_magn=conjg(BS_R_right_magn)
       !
       ! DS: this also should be changed according to the general structure
       if(l_BS_photolum) call PL_diago_residual(BS_mat,BS_mat,BS_R_PL,K_is_not_hermitian)
       !
     endif
     else 
       !
       ! We need to realloc as sizes can change.
       if(allocated(BS_corrections)) call BSS_resize(BS_corrections)
       if(associated(BS_E_SOC_corr)) call BSS_resize(BS_E_SOC_corr)
       !
       if(associated(BS_R_left_abs) )  call BSS_resize(BS_R_left_abs)
       if(associated(BS_R_right_abs))  call BSS_resize(BS_R_right_abs)
       !
       if(associated(BS_R_left_kerr) ) call BSS_resize(BS_R_left_kerr)
       if(associated(BS_R_right_kerr)) call BSS_resize(BS_R_right_kerr)
       if(associated(BS_R_right_dich)) call BSS_resize(BS_R_right_dich)
       if(associated(BS_R_left_magn) ) call BSS_resize(BS_R_left_magn)
       if(associated(BS_R_right_magn)) call BSS_resize(BS_R_right_magn)
       if(associated(BS_R_PL)        ) call BSS_resize(BS_R_PL)
       !
       ! Compute residuals
       !
       YAMBO_ALLOC_P(tmp_res_ptrR,(BSS_n_eig))
       YAMBO_ALLOC_P(tmp_res_ptrL,(BSS_n_eig))
       ! Absorption
       if(l_abs_res) then
         call K_diago_residuals("opt1",i_BS_mat,BS_E,BS_R_right_abs, BS_V_right, &
&                               neigs_this_cpu, neig_shift, BS_R_left_abs,BS_V_left,BS_overlap)
         !
         if(l_kerr_rgt) call K_diago_residuals("opt2",i_BS_mat,BS_E,BS_R_right_kerr, &
&                       BS_V_right, neigs_this_cpu, neig_shift, BS_R_left_kerr,BS_V_left,BS_overlap)
         !
         if(l_kerr_lft .and. .not. l_kerr_rgt) call K_diago_residuals("opt2",i_BS_mat,BS_E,tmp_res_ptrR, &
&                       BS_V_right, neigs_this_cpu, neig_shift, BS_R_left_kerr,BS_V_left,BS_overlap)
         !
        endif
       !
       ! Dichroism
        if(l_BS_dichroism) then
           call K_diago_residuals("dic1",i_BS_mat,BS_E,tmp_res_ptrR,BS_V_right, &
&                               neigs_this_cpu, neig_shift, null(),BS_V_left,BS_overlap)
           BS_R_right_dich(:,1) = tmp_res_ptrR
!
           call K_diago_residuals("dic2",i_BS_mat,BS_E,tmp_res_ptrR,BS_V_right, &
&                               neigs_this_cpu, neig_shift, null(),BS_V_left,BS_overlap)
           BS_R_right_dich(:,2) = tmp_res_ptrR
       endif
       !
       ! Magnons
       if(l_BS_magnons)   then
         call K_diago_residuals("mag1",i_BS_mat,BS_E,tmp_res_ptrR,BS_V_right, &
&                               neigs_this_cpu, neig_shift, tmp_res_ptrL,BS_V_left,BS_overlap)
           BS_R_right_magn(1,:) = tmp_res_ptrR
           BS_R_left_magn(1,:)  = tmp_res_ptrL
           if(n_spinor==2)  then
             call K_diago_residuals("mag2",i_BS_mat,BS_E,tmp_res_ptrR,BS_V_right,&
&                               neigs_this_cpu, neig_shift, tmp_res_ptrL,BS_V_left,BS_overlap)
             BS_R_right_magn(2,:) = tmp_res_ptrR
             BS_R_left_magn(2,:)  = tmp_res_ptrL
           endif
       endif
       !
       !
       if (l_BS_photolum) call error("PL not implemented in Ydiago solver")
       !
       if( BS_perturbative_SOC ) call K_perturbative_residuals(2/n_sp_pol,'SOC', i_BS_mat, &
       &           BS_corrections, BS_V_right, neigs_this_cpu, neig_shift, BS_V_left, BS_Overlap) 
       !
       if(BSS_perturbative_width) call K_perturbative_residuals(1,'WID', i_BS_mat, &
       &           BS_corrections, BS_V_right, neigs_this_cpu, neig_shift, BS_V_left, BS_Overlap) 

       if(BSS_perturbative_width) BS_E=BS_E-aimag(BS_corrections(1,:))
       !
       if( BS_perturbative_SOC ) BS_E_SOC_corr=real(BS_corrections)
       !
       !if (l_BS_photolum) call K_PL_residuals(BS_V_left,BS_V_right,BS_R_PL,K_is_not_hermitian, &
!&     !                                        neigs_this_cpu, neig_shift,BS_overlap) 
       !
       !
       YAMBO_FREE_P(tmp_res_ptrR)
       YAMBO_FREE_P(tmp_res_ptrL)     
     endif ! l_ydiago
     !
   endif
   !
   ! Define perturbative corrections
   !=================================
   if (.not. l_ydiago) then 
   if( BS_perturbative_SOC ) then
     !
     ! To check if the expression for the non hermitian case is correct
     if (     K_is_not_hermitian) call K_diago_perturbative(transpose(BS_V_left)*BS_V_right,BS_corrections,2/n_sp_pol,'SOC')
     if (.not.K_is_not_hermitian) call K_diago_perturbative(    conjg(BS_mat)   *BS_mat    ,BS_corrections,2/n_sp_pol,'SOC')
     BS_E_SOC_corr=real(BS_corrections)
     !
   endif
   !
   if(BSS_perturbative_width) then
     !
     if(     K_is_not_hermitian) call K_diago_perturbative(transpose(BS_V_left)*BS_V_right,BS_corrections(1,:),1,'WID')
     if(.not.K_is_not_hermitian) call K_diago_perturbative(    conjg(BS_mat)   *BS_mat    ,BS_corrections(1,:),1,'WID')
     BS_E=BS_E-aimag(BS_corrections(1,:))
     !
   endif
   endif
   !
   ! Now I calculate the physical quantities
   !=========================================
   call K_diago_response_functions(iq,i_BS_mat,W,BS_E,BS_R_left_abs,BS_R_right_abs,BS_E_SOC_corr,&
   &               BS_R_left_magn,BS_R_right_magn,BS_R_left_kerr,BS_R_right_kerr,BS_R_right_dich,BS_R_PL)
   !
   ! Diagonalization DB (OUT)
   !==========================
   if (io_err/=0) then
     !
     call io_control(ACTION=OP_WR_CL,COM=REP,MODE=VERIFY,SEC=(/1,2,3/),ID=ID)
     io_err=io_BSS_diago(iq,i_BS_mat,ID,X_static,BS_E,BS_R_left_abs,BS_R_right_abs,BS_E_SOC_corr,&
     &     BS_R_left_magn,BS_R_right_magn,BS_R_left_kerr,BS_R_right_kerr,BS_R_right_dich,BS_R_PL,&
     &                                                                     write_ev=.not.l_ydiago)
     !
     call PP_wait()
     if (l_ydiago .and. BSS_write_eig_2_db) call write_bs_ev_par(iq, i_BS_mat, BS_V_right, BS_V_left)
   endif
   !
   YAMBO_FREE(BS_E)
   call local_free( )
   !
 enddo
 !
 ! Initialize & write the output file 
 !====================================
 call K_OUTPUT(iq,W,"open dump close "//trim(Solver),"ALL")
 !
 ! CLEAN
 !
#if defined _SLEPC && !defined _NL
 if(l_slepc) call K_slepc_local_free()
#endif
 !
 call BSS_PL_free( )
 call BSS_MAGN_free( )
 !
 call timing(trim(Solver)//' Solver',OPR='stop')
 !
 contains
   !
   subroutine local_alloc(what)
     !
     character(*) :: what
     !
     select case(what)
     case("E")
       !
       if( BS_perturbative_SOC) then
         YAMBO_ALLOC(BS_corrections,(2/n_sp_pol,BSS_n_eig))
         YAMBO_ALLOC_P(BS_E_SOC_corr,(2/n_sp_pol,BSS_n_eig))
       endif
       if (l_abs_res) then
         YAMBO_ALLOC_P(BS_R_left_abs,(BSS_n_eig))
         YAMBO_ALLOC_P(BS_R_right_abs,(BSS_n_eig))
       endif
       if (l_kerr_rgt) then
         YAMBO_ALLOC_P(BS_R_right_kerr,(BSS_n_eig))
       endif
       if (l_kerr_lft) then
         YAMBO_ALLOC_P(BS_R_left_kerr,(BSS_n_eig))
       endif
       if (l_BS_dichroism) then
         YAMBO_ALLOC_P(BS_R_right_dich,(BSS_n_eig,2))
       endif
       if (l_BS_magnons) then
         YAMBO_ALLOC_P(BS_R_left_magn,(2,BSS_n_eig))
         YAMBO_ALLOC_P(BS_R_right_magn,(2,BSS_n_eig))
       endif
       if(l_BS_photolum) then
         YAMBO_ALLOC_P(BS_R_PL,(2,BSS_n_eig))
       endif
       !
     case("V")
       !
       if(K_is_not_hermitian) then
         YAMBO_ALLOC(BS_V_left,(BS_H_dim,BSS_n_eig))
         YAMBO_ALLOC(BS_V_right,(BS_H_dim,BSS_n_eig))
         YAMBO_ALLOC_P(BS_overlap,(BSS_n_eig,BSS_n_eig))
       else
         YAMBO_ALLOC(BS_E_real,(BSS_n_eig))
#if defined _SLEPC && !defined _NL
         if(l_slepc) then
           if (BS_K_coupling) then
             YAMBO_ALLOC(BS_mat,(BS_H_dim,BSS_n_eig))
           else
             YAMBO_ALLOC(BS_mat,(BS_K_dim(i_BS_mat),BSS_n_eig))
           endif
         endif
#endif
         if(BSS_perturbative_width.and..not.allocated(BS_corrections)) then
           YAMBO_ALLOC(BS_corrections,(1,BSS_n_eig))
         endif
       endif
       !
     end select
     !
   end subroutine local_alloc
   !
   subroutine local_free()
     !
     YAMBO_FREE(BS_E_real)
     YAMBO_FREE(BS_corrections)
     YAMBO_FREE(BS_V_right)
     YAMBO_FREE(BS_V_left)
     YAMBO_FREE_P(BS_overlap)
     YAMBO_FREE_P(BS_E_SOC_corr)
     YAMBO_FREE_P(BS_R_right_abs)
     YAMBO_FREE_P(BS_R_left_abs)
     YAMBO_FREE_P(BS_R_right_kerr)
     YAMBO_FREE_P(BS_R_left_kerr)
     YAMBO_FREE_P(BS_R_right_dich)
     YAMBO_FREE_P(BS_R_right_magn)
     YAMBO_FREE_P(BS_R_left_magn)
     YAMBO_FREE_P(BS_R_PL)
     !
     ! BS_mat must be cleaned as it contains the eigenvectors. 
     !
     YAMBO_FREE(BS_mat)
     !
   end subroutine local_free
   !
#if defined _SLEPC && !defined _NL
   !
   subroutine K_slepc_resize_variables()
     !
     use BS_solvers,   ONLY:BSS_resize
     !
     call warning(" resizing alla variables whose size depends on BSS_n_eig ")
     if(allocated(BS_E))          call BSS_resize(BS_E)
     !
     if(allocated(BS_corrections)) call BSS_resize(BS_corrections)
     if(associated(BS_E_SOC_corr)) call BSS_resize(BS_E_SOC_corr)
     !
     if(associated(BS_R_left_abs) )  call BSS_resize(BS_R_left_abs)
     if(associated(BS_R_right_abs))  call BSS_resize(BS_R_right_abs)
     !
     if(associated(BS_R_left_kerr) ) call BSS_resize(BS_R_left_kerr)
     if(associated(BS_R_right_kerr)) call BSS_resize(BS_R_right_kerr)
     if(associated(BS_R_right_dich)) call BSS_resize(BS_R_right_dich)
     if(associated(BS_R_left_magn) ) call BSS_resize(BS_R_left_magn)
     if(associated(BS_R_right_magn)) call BSS_resize(BS_R_right_magn)
     if(associated(BS_R_PL)        ) call BSS_resize(BS_R_PL)
     !
     if(allocated(BS_V_left))   call BSS_resize(BS_V_left)
     if(allocated(BS_V_right))  call BSS_resize(BS_V_right)
     if(associated(BS_overlap)) call BSS_resize(BS_overlap,.true.)
     !
     if(allocated(BS_E_real))   call BSS_resize(BS_E_real)
     if(allocated(BS_mat))      call BSS_resize(BS_mat)
     !
   end subroutine
   !
   subroutine K_slepc_local_init()
     !
     use com,           ONLY:msg
     call msg( 'sr', '[SLEPC] BSS_slepc_matrix_format                          ',BSS_slepc_matrix_format)
     !
     call parser('BSSEnTarget',l_target_energy)
     !
     if (index(BSS_slepc_matrix_format,'explicit')>0) &
     & call msg( 's', '[SLEPC] Faster algorithm but BSE matrix duplicated over MPI tasks')
     if (BSS_slepc_matrix_format=='shell')            &
     & call msg( 's', '[SLEPC] Slower algorithm but BSE matrix distributed over MPI tasks')
     !
     ! Number of states for partial diagonalization
     !================================================
     if (BSS_n_eig==0) then
       BSS_n_eig = nint(BS_H_dim*.01)
       call warning(' Calculating only 1% of the eigenvalues.')
     endif
     !
     ! if the number of eigenvalues to calculate is larger than matrix dimensions
     !
     if (BSS_n_eig>BS_H_dim) then
       call warning(' Number of eigenvalues is larger than hamiltonian. Calculating only 1% of the eigenvalues.')
       BSS_n_eig = nint(BS_H_dim*.01)
     endif
     !
     ! if the number of eigenvalued to calculate is smaller than 1
     !
     if (BSS_n_eig<1) then
       call warning(' Number of eigenvalues is smaller than hamiltonian. Calculating 1 eigenvalue.')
       BSS_n_eig = 1
     endif
     !
     call SlepcInitialize(PETSC_NULL_CHARACTER,ierr)
     !
   end subroutine K_slepc_local_init
   !
   subroutine K_slepc_local_free()
     !
     if (BSS_slepc_matrix_format=='shell') then
       call BS_HAYVEC_free(Slepc_v%Vi)
       call BS_HAYVEC_free(Slepc_v%Vo)
       deallocate(Slepc_v%Vi)
       deallocate(Slepc_v%Vo)
       call PARALLEL_Haydock_VEC_COMMs('reset')
     endif
     !
     call SlepcFinalize(ierr)
   end subroutine K_slepc_local_free
#endif
   !
end subroutine
