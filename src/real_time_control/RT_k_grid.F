!
! License-Identifier: GPL
!
! Copyright (C) 2013 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine RT_k_grid(E,k,q)
 !
 use pars,           ONLY:SP
 use drivers,        ONLY:l_elel_scatt
 use R_lattice,      ONLY:qindx_S
 use C_driver,       ONLY:code_bin
 use electrons,      ONLY:levels
 use real_time,      ONLY:DbGd_EE_scatt_table,DbGd_EE_percent,DbGd_EE_Nk_table,RTibz,&
&                         l_RT_uses_E_FineGd,RT_nk,RT_bands
 use R_lattice,      ONLY:bz_samp,bz_samp_FineGd_alloc,bz_samp_duplicate_Fg,&
&                         bz_samp_FineGd_default
 use parallel_m,     ONLY:PAR_IND_Xk_ibz
 !
#include<y_memory.h>
 !
 type(levels), intent(in)    :: E
 type(bz_samp),intent(in)    :: k
 type(bz_samp),intent(in)    :: q
 !
 ! Work space
 !
 logical :: l_check(k%nibz,k%nibz)
 integer :: ik,ik_rim,iqbz,ik_m_q,ik_m_q_rim,i_loops,N_loops,Nk_rim,Nk_m_q_rim,i1,N_pts
 ! 
 l_RT_uses_E_FineGd=k%FGibz%N>0.and.E%FG%nb>=RT_bands(2)
 !
 ! No DbGd, trivial definitions
 !==============================
 if (.not.l_RT_uses_E_FineGd) then
   !
   RTibz%N = k%nibz
   RT_nk   = k%nibz
   !
   call bz_samp_FineGd_alloc(RTibz,k%nibz)
   !
   DbGd_EE_percent=0._SP
   if(l_elel_scatt) then
     YAMBO_ALLOC(DbGd_EE_scatt_table,(k%nibz,q%nbz))
     YAMBO_ALLOC(DbGd_EE_Nk_table,(k%nibz,k%nibz))
     DbGd_EE_scatt_table=.true.
     DbGd_EE_Nk_table=1
   endif
   !
   call bz_samp_FineGd_default(RTibz,k)
   !
   return
   !
 endif
 !
 ! DbGd support
 !=============
 !
 call bz_samp_FineGd_alloc(RTibz,k%nibz)
 call bz_samp_duplicate_Fg(k%FGibz,RTibz,k%nibz)
 RT_nk=RTibz%N
 !
 ! Define K-weights to be used in the k-points distribution
 !
 YAMBO_ALLOC(PAR_IND_Xk_ibz%weight_1D,(k%nibz))
 PAR_IND_Xk_ibz%weight_1D=RTibz%N_mapped
 !
 if( l_elel_scatt .and. (index(code_bin,'ypp')==0) ) then
   !
   if(.not.allocated(DbGd_EE_scatt_table)) then
     YAMBO_ALLOC(DbGd_EE_scatt_table,(RT_nk,RT_nk))
     YAMBO_ALLOC(DbGd_EE_Nk_table,(RT_nk,k%nibz))
   endif
   !
   l_check=.false.
   DbGd_EE_scatt_table=.false.
   DbGd_EE_Nk_table=0
   !
   do ik=1,k%nibz
     do iqbz=1,q%nbz
       !
       ik_m_q= k%sstar(qindx_S(ik,iqbz,1),1)
       !
       if(l_check(ik,ik_m_q)) cycle
       if(l_check(ik_m_q,ik)) cycle
       !
       Nk_rim=RTibz%N_mapped(ik)
       Nk_m_q_rim=RTibz%N_mapped(ik_m_q)
       !
       if( Nk_rim<Nk_m_q_rim ) cycle
       !
       l_check(ik,ik_m_q)=.true.
       l_check(ik_m_q,ik)=.true.
       !
       N_pts=max(1,int(real(Nk_m_q_rim)*DbGd_EE_percent/100._SP))
       N_loops=max(1, (Nk_rim*N_pts-1)/(Nk_m_q_rim) )
       !
       i_loops=1
       ik_m_q_rim=RTibz%k_range(ik_m_q,1)-1
       !
       do while (i_loops< N_loops+1)
         do ik_rim=RTibz%k_range(ik,1),RTibz%k_range(ik,2)
           !
           do i1=1,N_pts
             ik_m_q_rim=ik_m_q_rim+1
             if(ik_m_q_rim>RTibz%k_range(ik_m_q,2)) then
               ik_m_q_rim=RTibz%k_range(ik_m_q,1)
               i_loops=i_loops+1
             endif
             !
             DbGd_EE_scatt_table(ik_m_q_rim,ik_rim)=.true.
             DbGd_EE_Nk_table(ik_rim,ik_m_q)=DbGd_EE_Nk_table(ik_rim,ik_m_q)+1
             !
             DbGd_EE_scatt_table(ik_rim,ik_m_q_rim)=.true.
             DbGd_EE_Nk_table(ik_m_q_rim,ik)=DbGd_EE_Nk_table(ik_m_q_rim,ik)+1
             !
           enddo
           !
           if(ik_m_q_rim==RTibz%k_range(ik_m_q,2)) i_loops=i_loops+1
           !
         enddo
         !
       enddo
       !
     enddo
   enddo
   !
 endif
 !
end subroutine RT_k_grid
