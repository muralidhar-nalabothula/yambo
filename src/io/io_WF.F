!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
integer function io_WF(ID,wf)
 !
 use pars,             ONLY:SP,schlen
 use electrons,        ONLY:n_spinor
 use stderr,           ONLY:intc
 use R_lattice,        ONLY:nkibz
 use wave_func,        ONLY:wf_ncx,wf_nb_io,wf_nb_to_load,wf_b_indx,wf_nb_io_groups
 use IO_m,             ONLY:io_sec,io_resetable,frag_WF
 use IO_int,           ONLY:io_connect,io_disconnect,io_bulk,io_header,&
&                           io_fragment,io_elemental
 use timing_m,         ONLY:timing
 !use devxlib
 !
 implicit none
 integer,       intent(in) :: ID
 complex(SP),   optional   :: wf(:,:,:)
 !
 integer                   :: nb_io,i_sp_pol,ik,ifrag,ib_grp,ib_block,n_blocks,ib,ib_io,ib_prev,ib_lim(3,wf_nb_io),head_io,ID_frag
 character(schlen)         :: VAR_NAME
 !
 call timing('io_WF',OPR='start')
 !
 io_WF=0
 head_io=0
 select case ( count((/io_sec(ID,:)/=0/)) )
   case(0)
     io_resetable(ID)=.true.
     goto 1
   case(1)
     ifrag=0
     ib_grp=0
     head_io=1
   case(2)
     ifrag=io_sec(ID,1)-1
     ib_grp=io_sec(ID,2)
     if (.not. present(wf)) call error(" [WF] unexpected: wf not present (1)")
   case(3)
     ifrag=io_sec(ID,2)-1
     ib_grp=io_sec(ID,3)
     head_io=1
     if (.not. present(wf)) call error(" [WF] unexpected: wf not present (2)")
 end select
 !
 if(ifrag<=nkibz) then
   ik=ifrag
   i_sp_pol=1
 else
   ik=ifrag-nkibz
   i_sp_pol=2
 endif
 !
 io_WF=io_connect(desc="wf",type=0,ID=ID,FORCE_READ_MODE=(head_io/=1).and.frag_WF)
 if (io_WF/=0) goto 1
 !
 ! S/N
 !
 if (head_io==1) then
   !
   io_WF=io_header(ID,IMPOSE_SN=.true.,FRAG=frag_WF)
   !
   call io_elemental(ID, VAR="BAND_GROUPS",VAR_SZ=2,MENU=0)
   call io_elemental(ID, VAR=" Bands in each block              ",I0=wf_nb_io)
   call io_elemental(ID, VAR=" Blocks                           ",I0=wf_nb_io_groups)
   call io_elemental(ID, VAR="",VAR_SZ=0)
   !
   if (io_WF/=0) goto 1
   !
 endif
 !
 if (ifrag==0) goto 1
 !
 if(.not.allocated(wf_b_indx)) then
   ib=1
   nb_io=wf_nb_io
 else
   ib=wf_b_indx(1)
   nb_io=wf_nb_to_load
 endif
 !
 if(nb_io==0) goto 1
 !
 ! Define number of bocks to read inside single fragment
 !
 n_blocks=1
 !
 ib_prev=ib
 ! 
 ib_lim(1,n_blocks)=ib
 ib_lim(2,n_blocks)=1
 !
 if(nb_io==1)        ib_lim(3,n_blocks)=1
 !
 if(nb_io==wf_nb_io) ib_lim(3,n_blocks)=nb_io
 !
 if(nb_io/=1 .and. nb_io/=wf_nb_io) then
   !
   do ib_io=2,nb_io
     !
     if(.not.allocated(wf_b_indx)) ib=ib_io
     if(     allocated(wf_b_indx)) ib=wf_b_indx(ib_io)
     !
     if(ib_prev+1==ib) then
       ib_prev=ib
       cycle
     endif
     !
     ib_lim(3,n_blocks)=ib_io-1
     !
     n_blocks=n_blocks+1
     !
     ib_prev=ib
     ib_lim(1,n_blocks)=ib
     ib_lim(2,n_blocks)=ib_io
     !
   enddo
   !
   ib_lim(3,n_blocks)=ib_io-1
   !
 endif
 !
 ! Fragmentation
 !
 call io_fragment(ID,ID_frag,i_fragment=ifrag,j_fragment=ib_grp)
 !
 VAR_NAME="WF_COMPONENTS_@_SP_POL"//trim(intc(i_sp_pol))//"_K"//trim(intc(ik))//"_BAND_GRP_"//trim(intc(ib_grp))
 call io_bulk(ID_frag,VAR=trim(VAR_NAME),VAR_SZ=(/2,wf_ncx,n_spinor,wf_nb_io/))
 !
 do ib_block=1,n_blocks
   if(ib_grp>1) ib_lim(1,ib_block)=mod(ib_lim(1,ib_block)-1,wf_nb_io)+1
   call io_bulk(ID_frag,C3=wf(:,:,ib_lim(2,ib_block):ib_lim(3,ib_block)),IPOS=(/1,1,1,ib_lim(1,ib_block)/))
 enddo
 !
 call io_fragment_disconnect(ID,ID_frag)
 !
1 call io_disconnect(ID=ID)
 !
 call timing('io_WF',OPR='stop')
 !
end function io_WF
