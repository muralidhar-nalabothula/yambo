!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): DS
!
subroutine fix_QP_DBs(k,k_save,kpoints_map)
 !
 use pars,                ONLY:lchlen
 use QP_m,                ONLY:QP_t,QP_reset
 use stderr,              ONLY:intc
 use vec_operate,         ONLY:v_is_zero
 use com,                 ONLY:core_io_path
 use IO_int,              ONLY:io_control
 use IO_m,                ONLY:OP_WR_CL,NONE,OP_RD_CL,DUMP
 use descriptors,         ONLY:IO_desc_duplicate
 use electrons,           ONLY:n_sp_pol
 use R_lattice,           ONLY:bz_samp
 !
#include<y_memory.h>
 !
 type(bz_samp),intent(in) :: k
 type(bz_samp),intent(in) :: k_save
 integer,intent(in)       :: kpoints_map(2,k%nibz)
 !
 ! Work space
 !
 type(QP_t) :: qp,qp_expanded
 !
 character(lchlen)     :: core_io_path_save
 integer               :: ID,ik,ik_old,ik_old_prev,ib,i1,i2,i_sp,i_err,io_QP_and_GF_err,i3(k_save%nibz)
 !
 ! External functions
 !
 integer, external :: io_QP_and_GF
 !
 !
 core_io_path_save=core_io_path
 !
 ! Check presence of QP DBs
 !
 call QP_reset(qp)
 !
 call io_control(ACTION=OP_RD_CL,SEC=(/1,2,3/),COM=NONE,MODE=DUMP,ID=ID)
 io_QP_and_GF_err=io_QP_and_GF("QP",qp,ID)
 !  
 if(io_QP_and_GF_err==-1) return
 !
 if(qp%nk/=k_save%nibz) then
   call warning(" Found ndb.QP, but number of kpts does not match kpoints in the old IBZ")
   return
   i_err=0
   do ik=1,k_save%nibz
     if(v_is_zero(k_save%pt(ik,:)-qp%k(ik,:)) .and. &
&       abs(k_save%weights(ik)-qp%wk(ik))< 1.E-5 ) cycle
     call warning(" K point "//trim(intc(ik))//" did not match")
     return
   enddo
 endif 
 !
 call section('=',"QP energies")
 !===============================
 !
 call QP_reset(qp_expanded)
 !
 call IO_desc_duplicate(qp%desc,qp_expanded%desc)
 !
 qp_expanded%nk      =k%nibz
 qp_expanded%nb      =qp%nb
 qp_expanded%n_states=(qp%n_states/qp%nk)*k%nibz
 !
 YAMBO_ALLOC(qp_expanded%k,(k%nibz,3))
 YAMBO_ALLOC(qp_expanded%wk,(k%nibz))
 YAMBO_ALLOC(qp_expanded%table,(qp_expanded%n_states,3+n_sp_pol-1))
 YAMBO_ALLOC(qp_expanded%E_bare,(qp_expanded%n_states))
 YAMBO_ALLOC(qp_expanded%E,(qp_expanded%n_states))
 YAMBO_ALLOC(qp_expanded%Z,(qp_expanded%n_states))
 !
 i1=0
 ik_old_prev=0
 i3(1)=0
 !
 do ik=1,qp_expanded%nk
   !
   i2=0
   ik_old=kpoints_map(1,ik)
   !
   do ib=1,qp_expanded%nb
     if(ib<qp%table(i3(ik_old)+1,1)) cycle
     do i_sp=1,n_sp_pol
       !
       i1=i1+1
       i2=i2+1
       !
       qp_expanded%table(i1,1)=qp%table(i2+i3(ik_old),1)
       qp_expanded%table(i1,2)=qp%table(i2+i3(ik_old),2)
       qp_expanded%table(i1,3)=ik
       if (n_sp_pol==2) qp_expanded%table(i1,4)=qp%table(i2+i3(ik_old),4)
       !
       qp_expanded%E_bare(i1)=qp%E_bare(i2+i3(ik_old))
       qp_expanded%E(i1)     =qp%E(i2+i3(ik_old))
       qp_expanded%Z(i1)     =qp%Z(i2+i3(ik_old))
       !
       !
     enddo
   enddo
   if(ik_old<qp%nk) i3(ik_old+1)=i2+i3(ik_old)
 enddo
 !
 qp_expanded%k  = k%pt
 qp_expanded%wk = k%weights
 !
 call io_control(ACTION=OP_WR_CL,SEC=(/1,2,3/),COM=NONE,ID=ID)
 io_QP_and_GF_err=io_QP_and_GF("QP",qp_expanded,ID)
 !
 core_io_path=core_io_path_save
 !
end subroutine
