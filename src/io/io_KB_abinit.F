!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
integer function io_KB_abinit(ID)
 !
 use pars,             ONLY:SP
 use stderr,           ONLY:intc
 use D_lattice,        ONLY:n_atoms_species_max,n_atomic_species,n_atoms_species,&
&                           atom_pos
 use R_lattice,        ONLY:nkibz
 use pseudo,           ONLY:pp_n_l_times_proj_max,pp_table,pp_n_l_max,&
&                           pp_n_l_comp,pp_kbs,pp_kb,pp_kbd, &
&                           PP_alloc_abinit
 use IO_m,             ONLY:io_sec,read_is_on,frag_WF
 use IO_int,           ONLY:io_connect,io_disconnect,io_fragment, &
&                           io_elemental,io_bulk,io_header,ver_is_gt_or_eq
 use timing_m,         ONLY:timing
#include<y_memory.h>
 !
 integer,       intent(in) :: ID
 !
 ! Workspace
 !
 integer :: ik,ifrag,i1,i_sp_pol,var_size,ID_frag
 !
 call timing('io_KB_abinit',OPR='start')
 !
 ID_frag=0
 ifrag=maxval(io_sec(ID,:))-1
 if(ifrag<=nkibz) then
   ik=ifrag
   i_sp_pol=1
 else
   ik=ifrag-nkibz
   i_sp_pol=2
 endif
 !
 io_KB_abinit=io_connect(desc="kb_pp",type=0,ID=ID)
 if (io_KB_abinit/=0) goto 1
 !
 ! Dimensions
 !
 if (any((/io_sec(ID,:)==1/))) then
   !
   io_KB_abinit=io_header(ID,IMPOSE_SN=.true.,FRAG=frag_WF)
   if (io_KB_abinit/=0) goto 1
   !
   var_size=3
   if (ver_is_gt_or_eq(ID,revision=898)) var_size=4
   !
   call io_elemental(ID,VAR="PARS",VAR_SZ=var_size,MENU=0)
   !
   ! n_atoms_max and n_atom_species are redundant as they are
   ! already read from the DB1.
   ! In the case when kb_pp is not present these variables
   ! are available anyway.
   !
   call io_elemental(ID,I0=n_atoms_species_max)
   call io_elemental(ID,I0=n_atomic_species)
   if (ver_is_gt_or_eq(ID,revision=898)) &
&    call io_elemental(ID,I0=pp_n_l_times_proj_max)
   call io_elemental(ID,I0=pp_n_l_max)
   call io_elemental(ID,VAR="",VAR_SZ=0,MENU=1)
   !
   if (read_is_on(ID)) then
     ! 
     if (.not.allocated(n_atoms_species)) then
       YAMBO_ALLOC(n_atoms_species,(n_atomic_species))
       YAMBO_ALLOC(atom_pos,(3,n_atoms_species_max,n_atomic_species))
     endif
     if (.not.allocated(pp_n_l_comp)) then
       YAMBO_ALLOC(pp_n_l_comp,(n_atomic_species))
     endif
     !
   endif
   !
   call io_bulk(ID,VAR="N_ATOMS",VAR_SZ=(/n_atomic_species/))
   call io_bulk(ID,I1=n_atoms_species)
   call io_bulk(ID,VAR="ATOM_L_COMP",VAR_SZ=(/n_atomic_species/))
   call io_bulk(ID,I1=pp_n_l_comp)
   !
   if (.not.ver_is_gt_or_eq(ID,revision=898)) pp_n_l_times_proj_max=maxval(pp_n_l_comp)
   if (read_is_on(ID)) then
     YAMBO_FREE(pp_table)
     YAMBO_ALLOC(pp_table,(3,n_atomic_species,pp_n_l_times_proj_max))
   endif
   !
   if (ver_is_gt_or_eq(ID,revision=898)) then
     call io_bulk(ID,VAR="PP_TABLE",VAR_SZ=(/3,n_atomic_species,pp_n_l_times_proj_max/))
     call io_bulk(ID,I3=pp_table)
   else
     do i1=1,pp_n_l_times_proj_max
       pp_table(1,:,i1)=i1
       pp_table(2,:,i1)=1
       pp_table(3,:,i1)=1
     enddo
   endif
   !
   call io_bulk(ID,VAR="ATOM_POS",VAR_SZ=shape(atom_pos))
   call io_bulk(ID,R3=atom_pos)
   !
   if (io_KB_abinit/=0) goto 1
   !
 endif
 !
 if (ifrag==0) goto 1
 !
 if (ifrag==1) then
   if (read_is_on(ID)) call PP_alloc_abinit()
   call io_bulk(ID,VAR="PP_KBS",VAR_SZ=shape(pp_kbs))
   call io_bulk(ID,R2=pp_kbs)
 endif
 !
 call io_fragment(ID,ID_frag,i_fragment=ifrag)
 !
 if (read_is_on(ID)) then
   pp_kb=0._SP
   pp_kbd=0._SP
 endif
 ! 
 call io_bulk(ID_frag,VAR='PP_KB_IK'//trim(intc(ik))//'_SP_POL'//trim(intc(i_sp_pol)),VAR_SZ=shape(pp_kb(:,:,:,i_sp_pol)))
 call io_bulk(ID_frag,R3=pp_kb(:,:,:,i_sp_pol))
 ! 
 call io_bulk(ID_frag,VAR='PP_KBD_IK'//trim(intc(ik))//'_SP_POL'//trim(intc(i_sp_pol)),VAR_SZ=shape(pp_kbd(:,:,:,i_sp_pol)))
 call io_bulk(ID_frag,R3=pp_kbd(:,:,:,i_sp_pol))
 !
 call io_fragment_disconnect(ID,ID_frag)
 !
1 call io_disconnect(ID=ID)
 !
 call timing('io_KB_abinit',OPR='stop')
 !
end function io_KB_abinit
