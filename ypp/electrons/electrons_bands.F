! 
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): CA DS AM
!
subroutine electrons_bands(Xk,Xen)
 !
 ! Levels produced by this routine:
 !
 ! CIRCUIT_E    = Eo (+delta E if QP) interpolated @ CIRCUIT_k (no GS SAVE)
 !              = Eo                  interpolated @ CIRCUIT_k (if GS SAVE)
 ! CIRCUIT_dE   = delta E (if QP) interpolated @ CIRCUIT_k (eventually read from GS SAVE)
 ! GRID_E       = interpolated @ GRID_k (if INTERP_grid>0)
 ! CIRCUIT_E_db = eventually read from GS SAVE
 !
 use pars,           ONLY:SP,rZERO,schlen
 use units,          ONLY:HA2EV
 use YPP_interfaces, ONLY:PROJECTION_plot,PROJECTION_setup,k_special
 use YPPm,           ONLY:BANDS_steps,INTERP_grid,&
&                         BANDS_bands,CIRCUIT_E_DB_path,CIRCUIT_E_db,USER_k,CIRCUIT_k,&
&                         BANDS_path,BANDS_from_db,l_PROJECT_line,l_PROJECT_plane
 use electrons,      ONLY:levels,n_sp_pol,n_spinor,E_reset,n_spin
 use R_lattice,      ONLY:bz_samp
 use D_lattice,      ONLY:lattice
 use com,            ONLY:msg 
 use parser_m,       ONLY:parser
 use interpolate,    ONLY:electrons_bands_interpolate,GRID_k,INTERP_mode,INTERP_shell_factor
 use QP_CTL_m,       ONLY:QP_apply
 use interfaces,     ONLY:OCCUPATIONS_Fermi
#if defined _YPP_SC
 use SC,             ONLY:SC_neq_kind
#endif
 !
#include<y_memory.h>
 !
 type(bz_samp), intent(inout) :: Xk
 type(levels),  intent(inout) :: Xen
 !
 ! Work Space
 !
 type(levels)          :: GRID_E,CIRCUIT_E,CIRCUIT_dE
 integer               :: ID_spin,ID_magn,ID_bands(3),IDs(5),nfiles(5),nqnt,ib
 real(SP)              :: dEf
 logical               :: BANDS_built_in,BANDS_interpolated,GRID_interpolate
#if defined _YPP_SC
 integer               :: ID_proj
 logical               :: proj_wfc
#endif
 !
 logical, external     :: file_exists
 character(schlen)     :: INTERP_mode_save
 real(SP)              :: INTERP_shell_factor_save
 !
 ! Apply QP corrections
 !====================== 
 INTERP_mode_save        =INTERP_mode
 INTERP_shell_factor_save=INTERP_shell_factor
 !
 call QP_apply(BANDS_bands,Xen,Xk,'G',msg_fmt='rs')
 !
 INTERP_mode        =INTERP_mode_save
 INTERP_shell_factor=INTERP_shell_factor_save
 !
 ! IBZ => BZ: need to be done here as QP_apply cleans the %ptbz allocation
 !
 call k_ibz2bz(Xk,'iku',.TRUE.)
 !
 call section('*','Interpolation tool')
 !=====================================
 call parser('BANDS_built_in',BANDS_built_in)
 !
 call E_reset(GRID_E)
 call E_reset(CIRCUIT_E)
 call E_reset(CIRCUIT_DE)
 call E_reset(CIRCUIT_E_db)
 !
 if (.not.file_exists(trim(CIRCUIT_E_DB_path)//"/SAVE/ns.db1")) CIRCUIT_E_DB_path="none"
 !
 BANDS_from_db       = trim(CIRCUIT_E_DB_path)/="none"
 BANDS_interpolated  = BANDS_steps>0.or.trim(CIRCUIT_E_DB_path)/="none"
 BANDS_built_in      = BANDS_built_in .and. (.not. BANDS_from_db)
 GRID_interpolate    = all(INTERP_grid>0)
 if (l_PROJECT_line) then
   call warning("Line Projection not possible in BANDS mode. Switched off")
   l_PROJECT_line=.FALSE.
 endif
 if (l_PROJECT_plane) GRID_interpolate=.FALSE.
 !
 ! Define the circuit
 !====================
 call k_special( )
 call k_circuit_driver( BANDS_path, BANDS_steps )
 if (CIRCUIT_k%nbz==0.and..not.GRID_interpolate) then
   call k_special(.TRUE.)
   call error(' [electrons_bands] No BZ circuit defined in input')
 endif
 !
 if (BANDS_interpolated.or.l_PROJECT_plane) then
   !
   ! Perform the energies interpolation
   !====================================
   if (l_PROJECT_plane) then
     call section('=','Interpolation@work: Projection')
     call PROJECTION_setup( "BANDS", BANDS_bands )
   else
     if (.not.GRID_interpolate) call section('=','Interpolation@work: Circuit')
     if (     GRID_interpolate) call section('=','Interpolation@work: Circuit and Grid')
   endif
   !
   call electrons_bands_interpolate(Xen,Xk,BANDS_bands,ID_bands,CIRCUIT_E,GRID_E=GRID_E,CIRCUIT_dE=CIRCUIT_dE)
   !
   ! Perform interpolation of spinorial factors and magnetization
   !==============================================================
   if(n_spinor>1 .and. BANDS_steps> 0) then
     INTERP_mode='NN'
     call section('=','Interpolation@work: Spin and Magnetization')
     call electrons_spin_and_magn_interpolate("S M",Xk,CIRCUIT_k,BANDS_bands,ID_spin,ID_magn)
   endif
   !
#if defined _YPP_SC
   !
   proj_wfc=(trim(SC_neq_kind)=="matsubara")
   !
   ! Perform interpolation of projection factors
   !=============================================
   if(proj_wfc) then
     call section('=','Interpolation@work: SC-WFs projections')
     call electrons_WFs_proj_interpolate(Xen,Xk,CIRCUIT_k,BANDS_bands,ID_proj)
   endif
   !
#endif
   !
 endif
 !
 ! Fermi Levels
 !==============
 !
 call section('=','Fermi Levels')
 !
 ! AM (March 2018): The dEf must be applied in order to have consistent
 !                  shift of the BUILT-in and the INTERPOLATED grids. Thus it is non-zero
 !                  only when it can be correctly (all occupied bands) evaulated with GRID_E
 !
 if (GRID_interpolate.and.BANDS_bands(1)==1) call OCCUPATIONS_Fermi(GRID_E,GRID_k,"GRID",mode="FERMI")
 !
 call msg("s",'Fermi Level  (BUILT-in bands)     ',Xen%E_Fermi*HA2EV,"[eV]")
 !
 dEf=rZERO
 !
 if (BANDS_bands(1)==1) then
   dEf=-GRID_E%E_Fermi
   call msg("s",'Correction             (GRID)     ',GRID_E%E_Fermi*HA2EV,"[eV]")
 endif
 !
 call section('=','Bands output')
 !===============================
 !
 IDs=0
 nqnt=1
 nfiles(1)=n_sp_pol
 IDs(1)=ID_bands(2)
 if(allocated(Xen%Eo).and.BANDS_from_db) IDs(1)=ID_bands(3)
 if(n_spinor==2) then
   nqnt=nqnt+2
   nfiles(nqnt-1:nqnt)=(/2,3/)
   IDs(nqnt-1:nqnt)=(/ID_spin,ID_magn/)
 endif
#if defined _YPP_SC
 if( proj_wfc  ) then
   nqnt=nqnt+1
   nfiles(nqnt)=2
   IDs(nqnt)=ID_proj
 endif
#endif
 !
 if (BANDS_built_in.and.USER_k%nbz>0     )  call plot_interpolated_values &
&   (Xk,Xen,dEf,USER_k,   IDs(1:nqnt),BANDS_bands,nqnt,nfiles(1:nqnt),"built_in",    "bands",0)
 !
 if (BANDS_interpolated.and.BANDS_from_db)  call plot_interpolated_values &
&   (Xk,Xen,dEf,CIRCUIT_k,IDs(1:1),   BANDS_bands,1,   nfiles(1:1),   "from_DB",     "bands",0)
 !
 if(BANDS_interpolated                   )  call plot_interpolated_values &
&   (Xk,Xen,dEf,CIRCUIT_k,IDs(1:nqnt),BANDS_bands,nqnt,nfiles(1:nqnt),"interpolated","bands",0)
 !
 if (l_PROJECT_plane) call PROJECTION_plot( "BANDS", 1, n_spin, BANDS_bands, OBS_B=GRID_E%E ) 
 !
 ! Close & Clean
 !
 call E_reset(GRID_E)
 call E_reset(CIRCUIT_E)
 call E_reset(CIRCUIT_DE)
 call E_reset(CIRCUIT_E_db)
 !
 call INTERPOLATION_driver_end(0)
 !
end subroutine
