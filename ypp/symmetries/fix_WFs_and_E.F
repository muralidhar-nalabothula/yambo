!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): CA DS
!
#include<dev_defs.h>
!
subroutine fix_WFs_and_E(E,k,k_save,kpoints_map,old_nsym,S_contains_TR)
 !
 use pars,                ONLY:SP,lchlen,cZERO
 use com,                 ONLY:msg,core_io_path,more_io_path
 use IO_int,              ONLY:io_control
 use IO_m,                ONLY:OP_WR_CL,NONE,OP_APP_CL,OP_WR,OP_RD,&
&                              OP_APP,OP_RD_CL,RD_CL,RD,frag_WF
 use wave_func,           ONLY:io_WF,wf_nc_k, wf_igk,DEV_VAR(wf_igk),wf_ncx,wf_nb_io,wf_ng, &
 &                             WF,wf_nb_io_groups
 use electrons,           ONLY:levels,E_reset,n_sp_pol,n_spinor
 use LIVE_t,              ONLY:live_timing
 use R_lattice,           ONLY:bz_samp,g_rot,ng_closed,nkibz
 use D_lattice,           ONLY:spin_sop
 use interfaces,          ONLY:WF_load,WF_free
 use YPP_symm,            ONLY:wf_nc_k_save,wf_igk_save,wf_nc_k_reduced,wf_igk_reduced,&
&                              wf_nc_k_new,wf_igk_new,&
&                              wf_nc_k_new,wf_ncx_new,wf_ncx_save,wf_ng_new,wf_ng_save
 !
#include<y_memory.h>
 !
 type(levels),intent(in)  :: E
 !
 type(bz_samp),intent(inout) :: k
 type(bz_samp),intent(in)    :: k_save
 integer,intent(in)          :: kpoints_map(2,k%nibz)
 !
 integer,intent(in)       :: old_nsym
 logical,intent(in)       :: S_contains_TR(old_nsym)
 !
 ! Work space
 !
 type(levels)          :: E_new
 !
 character(lchlen)     :: core_io_path_save
 integer               :: n_steps,nb1,nb2,ng_closed_save
 integer               :: ACTION_,ID
 integer               :: io_err
 !
 integer               :: wf_nb_io_save
 !
 integer,     allocatable :: ic_rot_table(:) 
 complex(SP), allocatable :: wf_disk(:,:,:)
 complex(SP), allocatable :: wf_tmp(:,:)
 !
 ! Dummies
 !
 integer               :: is,i_sp_pol,ik,ik_save,ifrag
 integer               :: ib,ib_grp,ib_disk,i_wf,i_spinor
 integer               :: ic,ic_rot,ig,ig_rot
 logical               :: l_found
 !
 ! External functions
 !
 integer, external :: io_DB1
 !
 !
 call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/1/),ID=ID)
 io_err=io_WF(ID)
 !
 core_io_path_save=core_io_path
 core_io_path=more_io_path
 !
 call section('=',"Energies and WFs shells")
 !===========================================
 !
 ! Rotate spheres of G-vectors centered on kpts
 call fix_WFs_Gshells(k,k_save,kpoints_map,old_nsym)
 !
 call map_energies(E,E_new,k,kpoints_map)
 !
 ! For some reason ioDB1 changes the value of ng_closed and of wf_nb_io
 ! This is a work-around to this problem
 ng_closed_save=ng_closed
 wf_nb_io_save=wf_nb_io
 !
 call msg('s',' I/O...')
 call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)
 io_err=io_DB1(E_new,k,ID)
 !
 ng_closed=ng_closed_save
 wf_nb_io=wf_nb_io_save
 !
 call section('=',"Wavefunctions")
 !===============================
 !
 ! After I/O of DB1 I need to restore the old WFs shells
 ! to make sure that WF_load works properly
 !
 YAMBO_FREE(wf_nc_k)
 YAMBO_FREE_GPU(DEV_VAR(wf_igk))
 YAMBO_FREE(wf_igk)
 YAMBO_ALLOC(wf_nc_k,(k_save%nibz))
 YAMBO_ALLOC(wf_igk,(wf_ncx_save,k_save%nibz))
 !
 wf_nc_k=wf_nc_k_save
 wf_igk =wf_igk_save
 wf_ncx =wf_ncx_save
 wf_ng  =wf_ng_save 
 !
   !
   YAMBO_ALLOC(wf_disk,(wf_ncx_new,n_spinor,wf_nb_io))
   !
   call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID)
   io_err=io_WF(ID)
   !
   ACTION_=OP_APP_CL
   if(frag_WF) ACTION_=OP_WR_CL
   !
   do i_sp_pol=1,n_sp_pol
     !
     call live_timing('Reduction',k_save%nibz)
     !
     do ik=1,k_save%nibz
       !
       ifrag=ik+(i_sp_pol-1)*k%nibz
       !
       ik_save=kpoints_map(1,ik)
       !
       do ib_grp=1,wf_nb_io_groups
         !
         wf_disk=cZERO
         !
         nb1=wf_nb_io*(ib_grp-1)+1
         nb2=wf_nb_io*ib_grp
         !
         nkibz=k_save%nibz
         wf_ncx=wf_ncx_save
         core_io_path=core_io_path_save
         call WF_load(WF,wf_ng,1,(/nb1,nb2/),(/ik_save,ik_save/),(/i_sp_pol,i_sp_pol/),&
&                     space='C',title='',impose_free_and_alloc=.true.)
         !
         do ib=nb1,nb2
           ib_disk=ib-nb1+1
           i_wf=WF%index(ib,ik_save,i_sp_pol)
           wf_disk(:wf_nc_k_new(ik),:,ib_disk)= WF%c(:wf_nc_k_reduced(ik_save),:,i_wf)
         enddo
         !
         call WF_free(WF)
         !
         nkibz=k%nibz
         wf_ncx=wf_ncx_new
         core_io_path=more_io_path
         call io_control(ACTION=ACTION_,COM=NONE,SEC=(/ifrag+1,ib_grp/),ID=ID)
         io_err=io_WF(ID,wf_disk)
         !
       enddo
       !
       call live_timing(steps=1)
       !
     enddo
     !
     call live_timing()
     !
     n_steps=(k%nibz-k_save%nibz)
     if (n_steps>0) call live_timing('Rotation',n_steps)
     !
     YAMBO_ALLOC(ic_rot_table,(wf_ncx_new))
     YAMBO_ALLOC(wf_tmp,(wf_ncx_new,n_spinor))
     !
     ACTION_=OP_APP_CL
     if (frag_WF) ACTION_=OP_WR_CL
     !
     do ik=k_save%nibz+1,k%nibz 
       !      
       ifrag=ik+(i_sp_pol-1)*k%nibz
       !
       ik_save=kpoints_map(1,ik)
       is=kpoints_map(2,ik)
       !
       ic_rot_table=-1
       do ic=1,wf_nc_k_reduced(ik_save)
         ig_rot=g_rot(wf_igk_reduced(ic,ik_save),is)
         l_found=.false.
         do ic_rot=1,wf_nc_k_new(ik)
           ig=wf_igk_new(ic_rot,ik)
           if(ig==ig_rot) then
             l_found=.true.
             exit
           endif
         enddo
         if(.not.l_found) call error("Erro rotating an wf_igk array")
         ic_rot_table(ic)=ic_rot
       enddo
       !
       do ib_grp=1,wf_nb_io_groups
         !
         wf_disk=cZERO
         !
         nb1=wf_nb_io*(ib_grp-1)+1
         nb2=wf_nb_io*ib_grp
         !
         nkibz=k_save%nibz
         wf_ncx=wf_ncx_save
         core_io_path=core_io_path_save
         call WF_load(WF,wf_ng,1,(/nb1,nb2/),(/ik_save,ik_save/),(/i_sp_pol,i_sp_pol/),&
&                     space='C',title='',impose_free_and_alloc=.true.)
         !
         do ib=nb1,nb2
           !
           ib_disk=ib-nb1+1
           !
           wf_tmp=cZERO
           !
           i_wf=WF%index(ib,ik_save,i_sp_pol)
           !
           forall(ic=1:wf_nc_k_reduced(ik_save),i_spinor=1:n_spinor) &
&            wf_tmp(ic_rot_table(ic),i_spinor)=WF%c(ic,i_spinor,i_wf)
           !
           if(n_spinor==2) then
             forall(ic=1:wf_nc_k_new(ik)) wf_tmp(ic,:)=matmul(spin_sop(:,:,is),wf_tmp(ic,:))
           endif
           !
           if ( S_contains_TR(is) ) wf_tmp=conjg(wf_tmp)
           !  
           wf_disk(:,:,ib_disk)= wf_tmp(:,:)
           !
         enddo
         !
         call WF_free(WF)
         !
         nkibz=k%nibz
         wf_ncx=wf_ncx_new
         core_io_path=more_io_path
         call io_control(ACTION=ACTION_,COM=NONE,SEC=(/ifrag+1,ib_grp/),ID=ID)
         io_err=io_WF(ID,wf=wf_disk)
         !
       enddo
       !
       if(n_steps>0) call live_timing(steps=1)
       !
     enddo
     !
     YAMBO_FREE(ic_rot_table)
     YAMBO_FREE(wf_tmp)
     !
   enddo
   !
 ! 
 if(frag_WF) then
   call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID)
   io_err=io_WF(ID)
 endif
 !
 core_io_path=core_io_path_save
 !
 call fix_QP_DBs(k,k_save,kpoints_map)
 !
#if defined _YPP_SC
 call fix_SC_DBs(k,k_save,kpoints_map)
#endif
 !
 ! Finally I save again the new WFs_shells to be used by fix_PPs
 YAMBO_FREE(wf_nc_k)
 YAMBO_FREE_GPU(DEV_VAR(wf_igk))
 YAMBO_FREE(wf_igk)
 YAMBO_ALLOC(wf_nc_k,(k%nibz))
 YAMBO_ALLOC(wf_igk,(wf_ncx,k%nibz))
 !
 wf_nc_k=wf_nc_k_new
 wf_igk =wf_igk_new
 wf_ncx =wf_ncx_new
 wf_ng  =wf_ng_new 
 !
 ! CLEAN
 !=======
 call E_reset(E_new)
 YAMBO_FREE(wf_disk)
 !
end subroutine
!
subroutine map_energies(E,E_new,k,kpoints_map)
 !
 use electrons,           ONLY:levels,E_reset,n_sp_pol
 use R_lattice,           ONLY:bz_samp
 !
#include<y_memory.h>
 !
 type(levels), intent(in)     :: E
 type(levels), intent(out)    :: E_new
 type(bz_samp), intent(in)    :: k
 integer,       intent(in)    :: kpoints_map(2,k%nibz)
 !
 ! Work Space
 !
 integer :: ik
 !
 call E_reset(E_new)
 E_new%nb=E%nb
 E_new%nk=k%nibz
 YAMBO_ALLOC(E_new%E,(E%nb,k%nibz,n_sp_pol))
 !
 do ik=1,k%nibz
   E_new%E(:,ik,:)=E%E(:,kpoints_map(1,ik),:)+E%E_Fermi
 enddo
 !
end subroutine map_energies
