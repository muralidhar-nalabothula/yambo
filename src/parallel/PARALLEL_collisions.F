!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine PARALLEL_collisions( k, COLL )
 !
 ! SC
 !====
 !
 ! e-e correlation (HF and COHSEX)
 !=================================
 !
 ! n,k
 ! --<--.
 !      | 
 !      |
 !      |
 !     \|/ m,k-q
 !      |
 !      |
 !      | 
 !      .-->-- n',k
 !      
 ! "SC"="q.qp.b" 
 !  
 !   "q"   -> q 
 !   "qp"  -> QP (k,n,n')  
 !   "b"   -> m and PAR_IND_Bp_mat (this second is for the COLLISIONS case)
 !
 ! Local XC
 !==========
 !                        _ \ _
 !                       /  /  \
 !              G_p{n,m}|       | p
 !                       \_ _ _/
 !                          | 
 !                          | W
 !                          |
 !    (n,k)------>----------.---------->----(n',k)
 !
 ! "SC"="q.qp.b" 
 !  
 !   "q"   -> q 
 !   "qp"  -> QP (k,n,n')  
 !   "b"   -> m and PAR_IND_Bp_mat (this second is for the COLLISIONS case)
 !
 ! REAL-TIME
 !===========
 !
 ! e-e scattering
 !================
 !
 !      __/__ p,m'
 !    ./  \
 !    |\__\__ p-q,m
 !    |   /
 !   \|/
 !    | q
 !    |
 !    | __/__ k-q,n'
 !    ./  \
 !     \__\__ k,n
 !        /
 !      
 ! "RT"="k.b.q.qp"
 !  
 !   "k.b" -> (k,n,n')  
 !   "q"   -> q (BZ)
 !   "qp"  -> Plasma (J)
 !
 ! e-e correlation (HF and COHSEX)
 !=================================
 !
 ! n,k
 ! --<--.
 !      | m
 !      |
 !      |
 !     \|/ k-q
 !      |
 !      |
 !      | m'
 !      .-->-- n',k
 !      
 ! "RT"="k.b.q.qp" 
 !  
 !   "k.b" -> (k,n,n')  
 !   "q"   -> q (BZ)
 !   "qp"  -> Bp_mat (m,m')
 !
 ! Local XC
 !==========
 !                        _ \ _
 !                       /  /  \
 !              G_p{n,m}|       | p
 !                       \_ _ _/
 !                          | 
 !                          | W
 !                          |
 !    (n,k)------>----------.---------->----(n',k)
 !
 !   "k.b" -> (k,n,n')  
 !   "q"   -> q_fake (to span the "p= k-q")
 !   "qp"  -> Bp_mat (m,m')
 !
 ! e-photon correlation 
 !======================
 !
 ! m,k-q   n,k
 ! --<--.-<--
 !      | m
 !      |
 !     \|/ q,G,\alpha
 !      |
 !      
 ! "RT"="k.b.q.qp" 
 !  
 !   "k.b" -> (k,n,m)  
 !   "q"   -> q (BZ)
 !   "qp"  -> G
 !  
 !.........................................................................
 !   "k.b" -> QP (k,n,n')  
 !.........................................................................
 !
 use drivers,       ONLY:l_eval_collisions
 use parallel_int,  ONLY:PARALLEL_live_message,PARALLEL_check_phase_space
 use collision_ext, ONLY:COLLISIONS_group,COLL_bands
 use parallel_m,    ONLY:PAR_IND_Xk_ibz,PAR_IND_B_mat,PAR_IND_G_k,PAR_IND_Q_bz,PAR_IND_QP,&
&                        l_par_RT,l_par_SE,l_par_SC,l_par_NL
 use hamiltonian,   ONLY:B_mat_index
 use R_lattice,     ONLY:bz_samp,qindx_S,nqbz
 !
#include<y_memory.h>
 !
 type(bz_samp)          :: k
 type(COLLISIONS_group) :: COLL
 !
 ! Work Space
 !
 integer :: i_coll,i_k,ib1,ib2,NC_tot,i_q,i_p,i_p_bz
 !
 if ( COLL%N == 0 ) return
 !
 YAMBO_ALLOC(COLL%PAR_map,(COLL%N))
 YAMBO_ALLOC(COLL%PAR_IND%element_1D,(COLL%N))
 !
 if (.not.allocated(PAR_IND_G_k%element_1D).and.l_eval_collisions ) then
   YAMBO_ALLOC(PAR_IND_G_k%element_1D,(k%nibz))
   PAR_IND_G_k%element_1D=.FALSE.
 endif
 COLL%PAR_IND%element_1D=.FALSE.
 COLL%PAR_N=0
 COLL%PAR_map=0
 NC_tot=0
 !
 do i_coll=1,COLL%N
   !
   ib1 = COLL%state(i_coll,1)
   ib2 = COLL%state(i_coll,2)
   i_k = COLL%state(i_coll,3)
   NC_tot=NC_tot+1
   !
   if (l_par_RT) then
     if (.not.PAR_IND_Xk_ibz%element_1D(i_k)) cycle
     if (.not.PAR_IND_B_mat%element_1D( B_mat_index(ib1,ib2,COLL_bands) ) ) cycle
   endif
   !
   if (l_par_NL) then
     if (.not.PAR_IND_Xk_ibz%element_1D(i_k)) cycle
   endif
   !
   ! l_par_SE is for LAMB
   if (l_par_SE.or.l_par_SC) then
     if (.not.PAR_IND_QP%element_1D(i_coll)) cycle
   endif
   !
   COLL%PAR_N=COLL%PAR_N+1
   COLL%PAR_map(i_coll)=COLL%PAR_N
   COLL%PAR_IND%element_1D(i_coll)=.TRUE.
   !
   if (l_eval_collisions) then
     !
     if ( (.not.l_par_SE) ) then
       !
       do i_q=1,nqbz
         !
         if (.not.PAR_IND_Q_bz%element_1D(i_q)) cycle
         !
         i_p_bz=qindx_S(i_k,i_q,1)
         i_p   =k%sstar(i_p_bz,1)
         !
         PAR_IND_G_k%element_1D(i_p)=.TRUE.
         !
       enddo
       !
     endif
     !
   endif
   !
 enddo
 !
 call PARALLEL_live_message(trim(COLL%name)//" Number of Collisions",LOADED=COLL%PAR_N,TOTAL=NC_tot)
 !
 call PARALLEL_check_phase_space(COLL%PAR_N,MSG=trim(COLL%name)//" COLLISIONS")
 !
end subroutine PARALLEL_collisions
!
!
subroutine PARALLEL_collisions_reset(COLL)
 !
 use collision_ext, ONLY:COLLISIONS_group
 !
#include<y_memory.h>
 !
 type(COLLISIONS_group), intent(inout) :: COLL
 !
 YAMBO_FREE(COLL%PAR_map)
 YAMBO_FREE(COLL%PAR_IND%element_1D)
 !
end subroutine PARALLEL_collisions_reset
