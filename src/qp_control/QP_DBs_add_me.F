!
! License-Identifier: GPL
!
! Copyright (C) 2017 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine QP_DBs_add_me(qp_base,qp2add,plan_EWZG,SAME_states,SAME_desc,OP,PRE_FAC)
 !
 ! This routine just adds to qp_base qp with the plan plan_EWZG
 !
 use pars,           ONLY:cZERO,rZERO,cI,SP,rONE
 use QP_m,           ONLY:QP_t,QP_reset,QP_copy,QP_alloc
 use electrons,      ONLY:n_sp_pol
 !
#include<y_memory.h>
 !
 type(QP_t)         ::qp_base,qp2add
 logical            ::plan_EWZG(4),SAME_states,SAME_desc
 character(*)       ::OP
 real(SP)           ::PRE_FAC
 !
 ! Work Space

 logical    ::l_QP_db,CONDITION
 integer    ::N_states,i_s,i_sp
 type(QP_t) ::qp
 real(SP)   ::PRE_SIGN
 complex(SP)::dE
 integer, allocatable :: dummy_table(:,:)
 !
 ! Check if there is any new state to fill
 !
 YAMBO_ALLOC(dummy_table,(qp_base%n_states+qp2add%n_states,3+n_sp_pol-1))
 dummy_table=0
 dummy_table(:qp_base%n_states,:)=qp_base%table
 N_states=qp_base%n_states
 I_S_LOOP: do i_s=1,qp2add%n_states
   do i_sp=1,qp_base%n_states
     if (all(qp2add%table(i_s,:)==qp_base%table(i_sp,:))) cycle I_S_LOOP
   enddo
   N_states=N_states+1
   dummy_table(N_states,:)=qp2add%table(i_s,:)
 enddo I_S_LOOP
 !
 ! Prepare the new QP type
 !
 call QP_reset(qp)
 !
 ! Add new descs/k-points
 !
 call ADD_descs(.FALSE.,qp_base)
 if (.not.SAME_desc)   call ADD_descs(.FALSE.,qp2add)
 call ADD_descs(.TRUE.,qp_base)
 if (.not.SAME_states) call ADD_descs(.TRUE.,qp2add)
 !
 qp%nb=maxval(dummy_table(:,1))
 qp%nk=maxval(dummy_table(:,3))
 qp%n_states=N_states
 qp%GreenF_n_steps=qp_base%GreenF_n_steps
 !
 ! Is a QP/GF database?
 !
 l_QP_db=allocated(qp_base%E)
 !
 ! Allocation
 !
 call QP_alloc(qp)
 !
 ! Zeroing
 !
 qp%k =rZERO
 qp%wk=rZERO
 qp%Z=rONE
 qp%E=cZERO
 qp%E_bare=rZERO
 !
 ! Copying from qp_base
 !
 qp%table=dummy_table(:qp%n_states,:)
 qp%k(:qp_base%nk,:)=qp_base%k
 qp%wk(:qp_base%nk)=qp_base%wk
 if (l_QP_db) then
   qp%Z(:qp_base%n_states)=qp_base%Z
   qp%E(:qp_base%n_states)=qp_base%E
   qp%E_bare(:qp_base%n_states)=qp_base%E_bare
 else
   qp%S_total(:qp_base%n_states,:)=qp_base%S_total
   qp%GreenF(:qp_base%n_states,:)=qp_base%GreenF
   qp%GreenF_W(:qp_base%n_states,:)=qp_base%GreenF_W
 endif
 !
 ! Adding/Merging |
 !
 PRE_SIGN=1.
 if (OP=="-") PRE_SIGN=-1
 !
 do i_s=1,qp%n_states
   do i_sp=1,qp2add%n_states
     if (all(qp2add%table(i_sp,:)==qp%table(i_s,:))) then
       !
       if (l_QP_db) then
         !
         if (i_s>qp_base%n_states) then
           qp%E_bare(i_s)=qp2add%E_bare(i_sp)
           qp%E(i_s)=qp2add%E_bare(i_sp)
         endif
         !
         if (plan_EWZG(1)) then
           dE=qp2add%E(i_sp)-qp2add%E_bare(i_sp)
           qp%E(i_s)=qp%E(i_s)+PRE_SIGN*PRE_FAC*real(dE)
         endif
         if (plan_EWZG(2)) qp%E(i_s)=qp%E(i_s)+PRE_SIGN*PRE_FAC*cI*aimag(qp2add%E(i_sp))
         if (plan_EWZG(3)) then
           if (OP=="x") then
             dE=qp2add%E(i_sp)-qp2add%E_bare(i_sp)
             qp%E(i_s)=qp%E(i_s)-dE+qp2add%Z(i_sp)*dE
           endif
           qp%Z(i_s)=1.+(qp%Z(i_s)-1.)+(qp2add%Z(i_sp)-1.)
         endif
       else
         if (plan_EWZG(4)) then
           if (i_s>qp_base%n_states) then
             CONDITION=.TRUE.
           else
             CONDITION=abs(qp%GreenF_W(i_s,qp%GreenF_n_steps)-qp2add%GreenF_W(i_sp,qp%GreenF_n_steps))<1.E-5.and.&
&                      abs(qp%GreenF_W(i_s,1)-qp2add%GreenF_W(i_sp,1))<1.E-5
           endif
           if (CONDITION) then
             qp%S_total(i_s,:)=qp%S_total(i_s,:)+qp2add%S_total(i_sp,:)
             qp%GreenF(i_s,:)=qp%GreenF(i_s,:)+qp2add%GreenF(i_sp,:)
             qp%GreenF_W(i_s,:)=qp2add%GreenF_W(i_sp,:)
           endif
         endif
       endif
       qp%k(qp%table(i_s,3),:)=qp2add%k( qp2add%table(i_sp,3),:)
       qp%wk(qp%table(i_s,3) )=qp2add%wk( qp2add%table(i_sp,3) )
     endif
   enddo
 enddo
 !
 ! Finalization
 !
 call QP_reset(qp_base)
 call QP_copy(qp,qp_base,"ALL","+",1._SP)
 call QP_reset(qp)
 !
 YAMBO_FREE(dummy_table)
 !
 contains 
   !
   subroutine ADD_descs(STATES,qp_in)
     use descriptors,  ONLY:IO_desc_element_duplicate
     integer    :: i_d_in,i_d_out
     logical    :: STATES
     type(QP_t) :: qp_in
     do i_d_in=1,qp_in%desc%n
       if (     STATES.and.index(qp_in%desc%str(i_d_in),"QP @ state") == 0) cycle
       if (.not.STATES.and.index(qp_in%desc%str(i_d_in),"QP @ state") >  0) cycle
       if (len_trim(qp_in%desc%str(i_d_in)) == 0) cycle
       qp%desc%n=qp%desc%n+1
       i_d_out=qp%desc%n
       call IO_desc_element_duplicate(qp_in%desc,qp%desc,i_d_in,i_d_out)
     enddo
   end subroutine
end subroutine
