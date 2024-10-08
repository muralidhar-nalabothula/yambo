!
! License-Identifier: GPL
!
! Copyright (C) 2013 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine PARALLEL_add_Q_to_K_list(ZONE,IND_in,IND_in_ID,IND_k_out,IND_k_out_ID,&
&                                   IND_q,COMM,q_range,k,q)
 !
 use parallel_m,    ONLY:PP_indexes,yMPI_comm
 use R_lattice,     ONLY:qindx_X,nkbz,nkibz,bz_samp,nqbz,qindx_S,qindx_B
 use QP_m,          ONLY:QP_n_states,QP_table
 use R_lattice,     ONLY:k_map
 use vec_operate,   ONLY:k_periodic_idx
 !
#include<y_memory.h>
 !
 character(*)           ::ZONE
 type(PP_indexes)       ::IND_in,IND_k_out,IND_q
 integer                ::IND_in_ID,IND_k_out_ID,q_range(2)
 type(yMPI_comm)         ::COMM
 type(bz_samp)          ::k,q
 !
 integer :: iq,ikp,ikbz,ik,ikpbz,iqp,iqbz
 integer :: id,istep,idx_kp(3),idx_k(3),max_step,ikbzp
 !
 IND_k_out_ID=IND_in_ID
 !
 YAMBO_ALLOC(IND_k_out%n_of_elements,(COMM%n_CPU))
 YAMBO_ALLOC(IND_k_out%element_1D,(nkibz))
 !
 IND_k_out%n_of_elements(IND_k_out_ID+1)=0
 IND_k_out%element_1D(:)=.FALSE.
 !
 if (ZONE=="k_bz_q_ibz") then
   !
   do ikbz=1,nkbz
     !
     if (.not.IND_in%element_1D(ikbz)) cycle
     !
     ik  =k%sstar(ikbz,1)
     !
     if (.not.IND_k_out%element_1D(ik)) then
       IND_k_out%element_1D(ik)=.TRUE.
       IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
     endif
     !
     do iq=q_range(1),q_range(2)
       !
       if (.not.IND_q%element_1D(iq)) cycle
       !
       ikpbz=qindx_X(iq,ikbz,1)
       ikp  =k%sstar(ikpbz,1)
       !
       if (.not.IND_k_out%element_1D(ikp)) then
         IND_k_out%element_1D(ikp)=.TRUE.
         IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
       endif
       !
     enddo
     !
   enddo
   !
 else if (ZONE=="k_bz_q_bz".or.ZONE=="k_bz_q_bz_p_bz") then
   !
   do ikbz=1,nkbz
     !
     if (.not.IND_in%element_1D(ikbz)) cycle
     !
     ik=k%sstar(ikbz,1)
     if (ZONE=="k_bz_q_bz_p_bz") ik=ikbz
     !
     if (.not.IND_k_out%element_1D(ik)) then
       IND_k_out%element_1D(ik)=.TRUE.
       IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
     endif 
     !
     do iq=1,nqbz
       !
       if (.not.IND_q%element_1D(iq)) cycle
       !
       ! This is strange qindx_B is allocated nK,nK, why ranging over q ?
       !
       ikpbz=qindx_B(ikbz,iq,1)
       ikp  =k%sstar(ikpbz,1)
       if (ZONE=="k_bz_q_bz_p_bz") ikp=ikpbz
       !
       if (.not.IND_k_out%element_1D(ikp)) then
         IND_k_out%element_1D(ikp)=.TRUE.
         IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
       endif
       !
     enddo
     !
   enddo
   !
 else if (ZONE=="k_qp_q_ibz".or.ZONE=="k_qp_q_bz") then
   !
   do iqp=1,QP_n_states
     !
     if (.not.IND_in%element_1D(iqp)) cycle
     !
     ik=QP_table(iqp,3)
     !
     if (.not.IND_k_out%element_1D(ik)) then
       IND_k_out%element_1D(ik)=.TRUE.
       IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
     endif 
     !
     do iqbz=1,nqbz
       !
       iq=q%sstar(iqbz,1)
       if (ZONE=="k_qp_q_ibz") then
         if(.not.IND_q%element_1D(iq)) cycle
       endif
       if (ZONE=="k_qp_q_bz") then
         if(.not.IND_q%element_1D(iqbz)) cycle
       endif
       !
       ikpbz=qindx_S(ik,iqbz,1)
       ikp  =k%sstar(ikpbz,1)
       !
       if (.not.IND_k_out%element_1D(ikp)) then
         IND_k_out%element_1D(ikp)=.TRUE.
         IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
       endif 
       !
     enddo
     !
   enddo
   !
 else if (ZONE=="overlaps") then
   !
   ! K-sampling
   ! ===========
   !
   if(.not.allocated(k_map%k_map_dir)) call k_map_nearest_by_dir(k,k_map)
   !
   do ikbz=1,nkbz
     !
     if (.not.IND_in%element_1D(ikbz)) cycle
     !
     ik=k%sstar(ikbz,1)
     !
     if (.not.IND_k_out%element_1D(ik)) then
       IND_k_out%element_1D(ik)=.TRUE.
       IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
     endif 
     !
     idx_k=k_map%k_map_inv(ikbz,:)
     !
     do id=1,3
       !
       max_step=1
       !
       if(k_map%max_kdir(id)==1) cycle
       !
       if(k_map%max_kdir(id)>=6) max_step=2
       !
       do istep=1,max_step
         !
         idx_kp=idx_k
         idx_kp(id)=idx_kp(id)+istep
         idx_kp=k_periodic_idx(idx_kp,k_map)
         !
         ikbzp=k_map%k_map_dir(idx_kp(1),idx_kp(2),idx_kp(3))
         !
         ikp = k%sstar(ikbzp,1)
         !
         if (.not.IND_k_out%element_1D(ikp)) then
           IND_k_out%element_1D(ikp)=.TRUE.
           IND_k_out%n_of_elements(IND_k_out_ID+1)=IND_k_out%n_of_elements(IND_k_out_ID+1)+1
         endif 
         !
       enddo
       !
     enddo
     !
   enddo
 endif
 !
end subroutine PARALLEL_add_Q_to_K_list
