! 
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine electrons_dos(Xk,Xen)
 !
 use units,          ONLY:HA2EV
 use pars,           ONLY:SP,schlen,rZERO
 use D_lattice,      ONLY:DL_vol
 use R_lattice,      ONLY:bz_samp,bz_samp_reset
 use electrons,      ONLY:levels,spin,n_spinor,n_spin,n_sp_pol,E_reset
 use LIVE_t,         ONLY:live_timing
 use YPP_interfaces, ONLY:electrons_dos_elemental,PROJECTION_plot,PROJECTION_setup
 use YPPm,           ONLY:output_fname,DOS_bands,DOS_E_steps,K_transform,&
&                         INTERP_grid,l_PROJECT_atom,l_PROJECT_line,l_PROJECT_plane,&
&                         PROJECT_N_perp,PROJECT_N_par,SLICE_E,SLICE_k
 use com,            ONLY:msg,of_open_close
 use QP_CTL_m,       ONLY:QP_apply
 use interpolate,    ONLY:INTERPOLATION_driver_seed,INTERPOLATION_driver_do,GRID_k,INTERP_obj
 use stderr,         ONLY:intc
 !
#include<y_memory.h>
 !
 type(bz_samp) ::Xk
 type(levels)  ::Xen
 !
 ! Work Space
 ! 
 real(SP)              :: dos_E(DOS_E_steps),values(DOS_bands(2)+4),dos_integral(2)
 real(SP), external    :: RIntegrate
 real(SP), allocatable :: el_dos(:,:,:)
 real(SP), pointer     :: spin_fac(:,:,:) => null()
 real(SP), pointer     :: magn_fac(:,:,:) => null()
 real(SP), pointer     :: pdos_fac(:,:,:) => null()
 integer               :: i_E,i_f,N_files,N_grid_files,ival,is,ib,ik,ikbz,ID_E,ID_f, &
 &                        ID_spin,ID_magn,ID_pdos,ik_path,n_t
 character(schlen)     :: base_fname,titles(DOS_bands(2)+4)
 logical               :: l_DbGd
 type(levels)          :: GRID_E
 integer, external     :: PROJECTION_k_on_the_path_or_plane
 !
 call section('*','Electronic DOS')
 !
 ! E Double Grid
 !===============
 !
 l_DbGD=Xen%FG%nb>0
 !
 if (l_DbGd) DOS_bands(2)=min(DOS_bands(2),Xen%FG%nb)
 !
 call QP_state_table_setup(Xen)
 call QP_apply(DOS_bands,Xen,Xk,'G',msg_fmt='rs')
 !
 ! Setup
 !=======
 call electrons_dos_setup( Xen, dos_E, DOS_bands )  
 !
 if (l_PROJECT_plane) then
   call warning("Plane Projection not possible in DOS mode. Switched off")
   l_PROJECT_plane=.FALSE.
 endif
 !
 if (l_PROJECT_line) then
   call PROJECTION_setup( "DOS", DOS_bands )
   YAMBO_ALLOC(el_dos,(PROJECT_N_par,DOS_E_steps,n_spin))
 else
   YAMBO_ALLOC(el_dos,(DOS_E_steps,n_spin,2))
 endif
 el_dos=rZERO
 !
 ! DOS on the built-in grid
 !===================================================================
 !
 ! Load the PDOS coefficient
 !---------------------------
 ! Use the INTERPOLATE structure to pass the arrays to the el_density_of_states via the
 ! intermediate electrons_dos_elemental.
 !
 if (l_PROJECT_atom) then
   YAMBO_ALLOC_P(pdos_fac,(DOS_bands(1):DOS_bands(2),Xk%nibz,n_sp_pol))
   call electrons_pdos_factors((/1,Xk%nibz/),DOS_bands,pdos_fac)
 endif
 !
 if (n_spinor==2) then
   YAMBO_ALLOC_P(spin_fac,(DOS_bands(1):DOS_bands(2),Xk%nibz,n_spinor))
   call electrons_spin_factors((/1,Xk%nibz/),DOS_bands,spin_fac)
   YAMBO_ALLOC_P(magn_fac,(DOS_bands(1):DOS_bands(2),Xk%nibz,3))
   call electrons_magn_factors((/1,Xk%nibz/),DOS_bands,magn_fac)
 endif
 !
 if (.not.l_PROJECT_line) then
   call electrons_dos_elemental(Xk,Xen,DOS_bands,el_dos(:,:,1),dos_E,spin_fac,pdos_fac,USE_the_DbGd=l_DbGD)
 endif
 !
 ! Define the regular grid for interpolation if (all(interp_grid>0))
 !===================================================================
 N_grid_files=1
 N_files=1
 ID_E   =0
 ID_f   =0
 !
 if (all(INTERP_grid>0).or.l_PROJECT_line) then
   !
   if (l_PROJECT_atom) call warning(" PDOS and interpolation not yet implemented")
   !
   if (.not.l_PROJECT_line) then
     call INTERPOLATION_create_the_grid(INTERP_grid)
     N_files=2
   endif
   !
   call INTERPOLATION_driver_seed("E_on_built_in",ID_E,DOS_bands,Xk,SEED_E=Xen,NEAREST=.FALSE.)
   call INTERPOLATION_driver_do("E_on_built_in",ID_E,GRID_k,OUT_E=GRID_E)
   !
   call INTERPOLATION_driver_seed("f_on_built_in",ID_f,DOS_bands,Xk,SEED_E=Xen)
   call INTERPOLATION_driver_do("f_on_built_in",ID_f,GRID_k,OUT_E=GRID_E)
   !
   ID_pdos=0
   if (l_PROJECT_atom) then
     call INTERPOLATION_driver_seed("PDOS_factors_on_built_in",ID_pdos,DOS_bands,Xk,SEED_R3=pdos_fac)
     call INTERPOLATION_driver_do("PDOS_factors_on_built_in",ID_pdos,GRID_k)
   endif
   !
   ID_spin=0
   ID_magn=0
   if (n_spinor==2) then
     N_grid_files=N_grid_files+2
     call INTERPOLATION_driver_seed("SPIN_factors_on_built_in",ID_spin,DOS_bands,Xk,SEED_R3=spin_fac)
     call INTERPOLATION_driver_do("SPIN_factors_on_built_in",ID_spin,GRID_k)
     N_grid_files=N_grid_files+3
     call INTERPOLATION_driver_seed("MAGN_factors_on_built_in",ID_magn,DOS_bands,Xk,SEED_R3=magn_fac)
     call INTERPOLATION_driver_do("MAGN_factors_on_built_in",ID_magn,GRID_k)
   endif
   !
   do i_f=1,N_grid_files
   do is=1,n_sp_pol
     !
     if (DOS_bands(2)-DOS_bands(1)>10) cycle
     if (.not.allocated(GRID_k%ptbz)) cycle
     !
     if (i_f==1) base_fname="Egrid"
     if (i_f>=2) base_fname="Sgrid"
     if (i_f>=4) base_fname="Mgrid"
     !
     output_fname=trim(base_fname)
     !
     if (i_f==2) output_fname=trim(base_fname)//"_spin-up"
     if (i_f==3) output_fname=trim(base_fname)//"_spin-dn"
     if (i_f==4) output_fname=trim(base_fname)//"_Mx"
     if (i_f==5) output_fname=trim(base_fname)//"_My"
     if (i_f==6) output_fname=trim(base_fname)//"_Mz"
     if (n_sp_pol==2.and.is==1) output_fname=trim(base_fname)//"_spin-up"
     if (n_sp_pol==2.and.is==2) output_fname=trim(base_fname)//"_spin-dn"
     !
     call of_open_close(trim(output_fname),'ot')
     !
     titles(1)  =  " ik  "
     titles(2:4)=(/" kx [iku]"," ky [iku]"," kz [iku]"/)
     do ib=DOS_bands(1),DOS_bands(2)
       ival=4+ib-DOS_bands(1)+1
       titles(ival)=' b'//trim(intc(ib))
       if (i_f==1) titles(ival)=trim(titles(ival))//' [eV]'
     enddo
     call msg('o '//trim(base_fname),'#',titles(:DOS_bands(2)-DOS_bands(1)+5),INDENT=0,USE_TABS=.true.)
     call msg('o '//trim(base_fname),"#")
     !
     do ikbz=1,GRID_k%nbz
       values(2:4)=GRID_k%ptbz(ikbz,:)
       call K_transform(values(2:4),"iku")
       ik=GRID_k%sstar(ikbz,1)
       values(1)=real(ik,SP)
       ival=DOS_bands(2)-DOS_bands(1)
       if (i_f==1) values(5:ival+5)=GRID_E%E(DOS_bands(1):DOS_bands(2),ik,is)*HA2EV
       if (i_f>=2.and.i_f<=3) values(5:ival+5)=INTERP_obj(ID_spin)%INTERP(DOS_bands(1):DOS_bands(2),ik,i_f-1)
       if (i_f>=4           ) values(5:ival+5)=INTERP_obj(ID_magn)%INTERP(DOS_bands(1):DOS_bands(2),ik,i_f-3)
       call msg('o '//trim(base_fname),' ',values(:ival+5),INDENT=0,USE_TABS=.true.)
     enddo
     !
     call of_open_close(trim(output_fname))
     !
   enddo
   enddo
   !
   if (l_PROJECT_line) then
     call live_timing('Projecting the DOS',PROJECT_N_par)
     do ik=1,GRID_k%nbz
       ik_path=PROJECTION_k_on_the_path_or_plane(ik)
       if (ik_path==0) cycle
       SLICE_E%E=GRID_E%E(DOS_bands(1):DOS_bands(2),PROJECT_N_perp*(ik_path-1)+1:PROJECT_N_perp*ik_path,:)
       SLICE_E%f=GRID_E%f(DOS_bands(1):DOS_bands(2),PROJECT_N_perp*(ik_path-1)+1:PROJECT_N_perp*ik_path,:)
       call electrons_dos_elemental(SLICE_k,SLICE_E,DOS_bands,el_dos(ik_path,:,:),dos_E,&
&                                   spin_fac,pdos_fac,USE_the_DbGd=.FALSE.,QUIET=.TRUE.)
       call live_timing(steps=1)
     enddo
     call live_timing( )
     !
   else
     !
     ! DOS
     !
     call electrons_dos_elemental(GRID_k,GRID_E,DOS_bands,el_dos(:,:,2),dos_E,spin_fac,pdos_fac,USE_the_DbGd=.FALSE.)
     !
   endif
 endif
 !
 ! Interpolation cleaning
 !
 call INTERPOLATION_driver_end(0)
 !
 ! Fermi Level
 !
 if (DOS_bands(1)==1) then
   !
   call section('=','Fermi Levels')
   !
   call msg("s",'Fermi Level  (BUILT-in bands) [eV]:',Xen%E_Fermi*HA2EV)
   if (all(INTERP_grid>0)) call msg("s",'Correction             (GRID) [eV]:',GRID_E%E_Fermi*HA2EV)
   !
 endif
 !
 ! Integrated DOS
 !
 if (n_spin==1) then
   dos_integral(1)=RIntegrate(el_dos(:,1,1),dos_E,DOS_E_steps)
   if (N_files==2) dos_integral(2)=RIntegrate(el_dos(:,1,2),dos_E,DOS_E_steps) 
 else
   dos_integral(1)=RIntegrate(el_dos(:,1,1),dos_E,DOS_E_steps)+RIntegrate(el_dos(:,2,1),dos_E,DOS_E_steps)
   if (N_files==2) dos_integral(2)=RIntegrate(el_dos(:,1,2),dos_E,DOS_E_steps) + RIntegrate(el_dos(:,2,2),dos_E,DOS_E_steps)
 endif
 call msg("s",'Integrated DOS                    :',dos_integral(1)*DL_vol)
 if (N_files==2) then
   call msg("s",'                    [interpolated]:',dos_integral(2)*DL_vol)
 endif
 !
 ! Output file(s)
 !================
 !
 ! ...headers
 !
 do i_f=1,N_files 
   !
   if (i_f==1) output_fname='el_dos'
   if (i_f==2) output_fname='el_dos_INTERPOLATED'
   if (l_PROJECT_line) output_fname='el_dos_projected_LINE'
   !
   call of_open_close(trim(output_fname),'ot')
   n_t=0
   if (l_PROJECT_line) then
     n_t=n_t+1
     titles(n_t)='|k| (a.u.)'
   endif
   n_t=n_t+1
   titles(n_t)='E[eV]'
   if (n_spin==1) then
     n_t=n_t+1
     titles(n_t)='DOS'
   else
     n_t=n_t+1
     titles(n_t)='DOS [up]'
     n_t=n_t+1
     titles(n_t)='DOS [dn]'
     n_t=n_t+1
     titles(n_t)='DOS [up+dn]'
   endif
   call msg('o dos','#',titles(:n_t),INDENT=0,USE_TABS=.true.)    
   call msg('o dos',"#")
   !
   ! ...data
   !
   if (l_PROJECT_line) then
     call PROJECTION_plot( "DOS", DOS_E_steps, n_spin, DOS_bands, W=dos_E, OBS_K=el_dos ) 
   else
     do i_E=1,DOS_E_steps
       if (n_spin==1) call msg('o dos','',(/dos_E(i_E)*HA2EV,el_dos(i_E,1,i_f)/),INDENT=-2,USE_TABS=.true.)
       if (n_spin==2) call msg('o dos','',(/dos_E(i_E)*HA2EV,el_dos(i_E,:,i_f),  &
&                                           el_dos(i_E,1,i_f)+el_dos(i_E,2,i_f)/),INDENT=-2,USE_TABS=.true.)
     enddo
   endif
   !
   call of_open_close(trim(output_fname))
   !
 enddo
 !
 !
 ! CLEAN...
 !
 YAMBO_FREE(el_dos)
 call bz_samp_reset(SLICE_k)
 call E_reset(SLICE_E)
 !
end subroutine
