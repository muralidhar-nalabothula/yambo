!
! License-Identifier: GPL
!
! Copyright (C) 2018 The Yambo Team
!
! Authors (see AUTHORS file for details): DS
!
subroutine Pseudo_KB_G_to_R_space(Xk,Xen)
 !
 use pars,          ONLY:SP
 use drivers,       ONLY:l_sc_magnetic
 use electrons,     ONLY:levels,n_spinor,n_sp_pol
 use X_m,           ONLY:X_t
 use wave_func,     ONLY:wf_ncx
 use FFT_m,         ONLY:fft_size
 use pseudo,        ONLY:pp_kbv_dim_yambo,pp_kbv_dim_atom
 use R_lattice,     ONLY:bz_samp
 use D_lattice,     ONLY:n_atomic_species,n_atoms_species
 use LIVE_t,        ONLY:live_timing
 use IO_int,        ONLY:io_control
 use IO_m,          ONLY:manage_action,OP_WR_CL,OP_RD,OP_IF_START_APP_CL_IF_END,RD_CL_IF_END
 use timing_m,      ONLY:timing
 use parallel_int,  ONLY:PP_wait
 use parallel_m,    ONLY:master_cpu,PAR_IND_Xk_ibz_ID,PAR_IND_Xk_ibz
 !
#include<y_memory.h>
 !
 type(bz_samp) :: Xk
 type(levels)  :: Xen
 !
 ! Work Space
 !
 type(X_t)     :: X
 !
 complex(SP),allocatable :: kbv(:,:,:,:),kbv_real_space(:,:,:)
 !
 integer,    allocatable :: kbv_real_space_table(:)
 integer                 :: is,ia,ik,i_sp_pol,ifrag,i_atom,npp,npp_tab,pp_range(2)
 !
 ! I / O
 !
 integer                 :: IO_ACT_NOW,ID,ID_R,io_err(3),io_KB_pwscf_err,io_KB_abinit_err,io_Vnl_err,io_KB_real_space_err
 integer, external       :: io_KB_abinit,io_KB_pwscf,io_KB_real_space
 !
 !
#if defined _RT
 call timing('Pseudo kbv FFT',OPR='start')
#endif
 !
 call DIPOLE_kb_init(Xen,X,io_err,ID)
 !
 io_KB_abinit_err= io_err(1)
 io_KB_pwscf_err = io_err(2)
 io_Vnl_err     = io_err(3)
 !
 if(io_KB_abinit_err/=0.and.io_KB_pwscf_err/=0) return
 !
 ! Define pp_kbv_dim_yambo and pp_kbv_table
 !
 if (io_KB_pwscf_err==0) then
   call io_control(ACTION=OP_RD,SEC=(/2/),ID=ID)
   io_KB_pwscf_err=io_KB_pwscf(ID)
   call DIPOLE_kb_pwscf_def_dim()
 endif
 !
 if (io_KB_abinit_err==0) then
   call io_control(ACTION=OP_RD,SEC=(/2/),ID=ID)
   io_KB_abinit_err=io_KB_abinit(ID)
   call DIPOLE_kb_abinit_def_dim()
 endif
 !
 if(fft_size==0) call fft_setup(0,1,.not.l_sc_magnetic)
 !
 YAMBO_ALLOC(kbv,(wf_ncx,n_spinor,4,pp_kbv_dim_atom))
 YAMBO_ALLOC(kbv_real_space,(fft_size,n_spinor,pp_kbv_dim_yambo))
 YAMBO_ALLOC(kbv_real_space_table,(pp_kbv_dim_yambo))
 !
 call define_kbv_table()
 !
 if(.not.master_cpu) goto 1
 !
 call io_control(ACTION=OP_WR_CL,SEC=(/1/),ID=ID_R)
 io_KB_real_space_err=io_KB_real_space(ID_R,kbv_real_space,kbv_real_space_table)
 !
 call live_timing('KBV-pseudo',PAR_IND_Xk_ibz%n_of_elements(PAR_IND_Xk_ibz_ID+1)*n_sp_pol)
 call live_timing('KBV-pseudo',Xk%nibz*n_sp_pol)
 !
 do i_sp_pol=1,n_sp_pol
   do ik=1,Xk%nibz
     !
     ifrag=ik+(i_sp_pol-1)*Xk%nibz
     ! 
     ! [Vnl,r]
     !
     if (io_KB_pwscf_err==0.and.ifrag>1) then
       IO_ACT_NOW=manage_action(RD_CL_IF_END,ifrag,1,Xk%nibz*n_sp_pol)
       call io_control(ACTION=IO_ACT_NOW,SEC=(/ifrag+1/),ID=ID)
       io_KB_pwscf_err=io_KB_pwscf(ID)
     endif
     !
     if (io_KB_abinit_err==0.and.ifrag>1) then
       IO_ACT_NOW=manage_action(RD_CL_IF_END,ifrag,1,Xk%nibz*n_sp_pol)
       call io_control(ACTION=IO_ACT_NOW,SEC=(/ifrag+1/),ID=ID)
       io_KB_abinit_err=io_KB_abinit(ID)
     endif
     !
     if (io_KB_pwscf_err==0 .or. io_KB_abinit_err==0) then
       !
       i_atom=0
       npp_tab=0
       pp_range(2)=0
       do is = 1,n_atomic_species
         do ia = 1,n_atoms_species(is)
           !
           i_atom=i_atom+1
           !
           pp_range(1)=pp_range(2)+1
           !  
           ! Pseudo(k+G,k+G',i1) = kbv^*(k+G,i1,1) kbv(k+G',i1,1)
           ! i1 runs over atomic_species, atoms_per_specie , l_per_atom, m=-l,-l+1,...,l-1,sl
           if (io_KB_abinit_err==0) call DIPOLE_kb_abinit_comp(npp,npp_tab,ia,is,ik,i_sp_pol,Xk,kbv)
           if (io_KB_pwscf_err ==0) call DIPOLE_kb_pwscf_comp(npp,npp_tab,ia,is,ik,Xk,kbv)
           !
           if (npp==0) cycle
           !
           pp_range(2)=pp_range(1)+npp-1
           !
           call Pseudo_KB_FFT(kbv(:,:,:,:npp),kbv_real_space(:,:,pp_range(1):pp_range(2)),Xk%pt(ik,:),pp_range,npp,i_atom,is,ia,ik)
           !
         enddo
       enddo
       !
       IO_ACT_NOW=manage_action(OP_IF_START_APP_CL_IF_END,ifrag,1,Xk%nibz*n_sp_pol)
       call io_control(ACTION=IO_ACT_NOW,SEC=(/ifrag+1/),ID=ID_R)
       io_KB_real_space_err=io_KB_real_space(ID_R,kbv_real_space,kbv_real_space_table)
       !
       call live_timing(steps=1)
       !
     endif
     !
   enddo
 enddo
 !
 call live_timing()
 !
1 call PP_wait()
 !
 ! Free mem
 YAMBO_FREE(kbv_real_space_table)
 YAMBO_FREE(kbv_real_space)
 YAMBO_FREE(kbv)
 !
#if defined _RT
 call timing('Pseudo kbv FFT',OPR='stop')
#endif
 !
 contains
   !
   subroutine define_kbv_table()
     !
     use electrons,     ONLY:n_spinor
     use pseudo,        ONLY:pp_n_l_times_proj_max,pp_table,pp_kbv_table
     use D_lattice,     ONLY:n_atomic_species,n_atoms_species,n_atoms
     !
     integer :: i_atom,i1,is,ia,i_pp,il,im,i_spinor,pp_spin
     !
     i_atom=0
     i1=0
     do is = 1,n_atomic_species
       do ia = 1,n_atoms_species(is)
         i_atom=i_atom+1
         do i_pp = 1, pp_n_l_times_proj_max
           il = pp_table(1,is,i_pp)
           pp_spin = pp_table(3,is,i_pp)   ! neglect the so-term for abinit KB
           if(pp_spin>1) cycle
           do im = 1,2*(il-1)+1
             do i_spinor=1,n_spinor
               i1=i1+2-i_spinor
               if(pp_kbv_table(i1)==0) cycle
               kbv_real_space_table(pp_kbv_table(i1))=i_atom
             enddo
           enddo
         enddo
       enddo
     enddo

   end subroutine define_kbv_table
   !
end subroutine Pseudo_KB_G_to_R_space
