!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine K_exchange_collisions(iq,Xk,i_T_grp,NG,l_bs_exch_wf_in_loop)
 !
 use pars,           ONLY:SP,cZERO
 use D_lattice,      ONLY:nsym,i_time_rev,sop_inv,sop_inv_d
 use BS,             ONLY:BS_T_grp,K_EXCH_collision,BS_n_g_exch,&
&                         BSE_L_kind,l_BS_magnons,l_BSE_minimize_memory,BS_bands
 use interfaces,     ONLY:WF_load,WF_free
 use wave_func,      ONLY:WF
 use R_lattice,      ONLY:g_rot,g_rot_d,qindx_X,bz_samp
 use stderr,         ONLY:STRING_match
 use electrons,      ONLY:n_sp_pol
 use timing_m,       ONLY:timing
 use openmp,         ONLY:OPENMP_update,master_thread
 use collision_el,   ONLY:elemental_collision_free,elemental_collision_alloc
 use deviceXlib_m,   ONLY:dev_memcpy,dev_conjg
 !
#include<dev_defs.h>
 !
 implicit none
 !
 type(bz_samp),intent(in) :: Xk
 integer,      intent(in) :: iq,i_T_grp,NG(2)
 logical,      intent(in) :: l_bs_exch_wf_in_loop
 !
 ! Work Space
 !
 logical :: l_load_WFs
 integer :: NK(2)
 integer :: i_T_el,i_T_el_p,N_T_el_p,i_c,i_v,i_sp_c,i_sp_v,i_k_bz,i_k,i_s,i_g0,i_g1,i_g2,i_p_bz,i_g_p,i_p,&
&           i_sp,i_T_el_last_with_identity_sym,i_T_grp_last_with_identity_sym,i_T_grp_p
#ifdef _CUDA
  complex(SP), pointer, device :: O_x_d(:,:),O_x_sym_d(:,:)
#endif
 !
 call timing('T_space EXX Osc.',OPR='start')
 !
 ! Allocate
 !
 call elemental_collision_free(K_EXCH_collision)
 !
#if defined(__NOTNOW) && ! defined(_CUDA)
 !$omp parallel default(shared), private( K_EXCH_collision, &
 !$omp &        i_T_el,i_k_bz,i_k,i_s, i_p_bz,i_p,i_sp, i_v,i_c,i_sp_c,i_sp_v, &
 !$omp &        i_T_grp_last_with_identity_sym, i_T_el_last_with_identity_sym, &
 !$omp &        i_T_grp_p, N_T_el_p, i_T_el_p, i_g1, i_g2, NK)
#endif
 !
 call OPENMP_update(master_thread)
 !
 call elemental_collision_alloc(K_EXCH_collision,NG=BS_n_g_exch,TITLE="EXCH_COLL")
 !
#if defined(__NOTNOW) && ! defined(_CUDA)
 !$omp do schedule(dynamic)
#endif
 NK=-1
 T_loop: do i_T_el=1,BS_T_grp(i_T_grp)%size
   !
   i_k_bz=BS_T_grp(i_T_grp)%table(i_T_el,1)
   i_k   =Xk%sstar(i_k_bz,1)
   i_s   =Xk%sstar(i_k_bz,2)
   !
   i_p_bz=qindx_X(iq,i_k_bz,1)
   i_g_p =qindx_X(iq,i_k_bz,2)
   !
   i_p   =Xk%sstar(i_p_bz,1)
   i_sp  =Xk%sstar(i_p_bz,2)
   !
   i_v   =BS_T_grp(i_T_grp)%table(i_T_el,2)
   i_c   =BS_T_grp(i_T_grp)%table(i_T_el,3)
   i_sp_c=BS_T_grp(i_T_grp)%table(i_T_el,4)
   i_sp_v=BS_T_grp(i_T_grp)%table(i_T_el,5)
   !
   K_EXCH_collision%is=(/i_c,i_k,i_s,i_sp_c/)
   K_EXCH_collision%os=(/i_v,i_p,i_sp,i_sp_v/)
   K_EXCH_collision%qs=(/i_g_p,iq,1/)
   !
   l_load_WFs= l_bs_exch_wf_in_loop .and. (NK(1)/=min(i_k,i_p).or.NK(2)/=max(i_k,i_p))
   if (l_load_WFs) then
#if defined(__NOTNOW) && ! defined(_CUDA)
     !$omp critical
#endif
     if (NK(2)/=-1) call WF_free(WF,keep_fft=.true.,keep_states_to_load=.true.)
     NK=(/min(i_k,i_p),max(i_k,i_p)/)
     call WF_load(WF,NG(1),NG(2),BS_bands,NK,k_extrema_only=.true.,quiet=.true.,&
     &            space='R',title="Kernel exch",keep_states_to_load=.true.)
#if defined(__NOTNOW) && ! defined(_CUDA)
     !$omp end critical
#endif
   endif
   !
   if (iq==1) then
     !
     ! G==0 term
     !
     if (STRING_match(BSE_L_kind,"full")) BS_T_grp(i_T_grp)%DEV_VAR(O_x)(1,i_T_el)=BS_T_grp(i_T_grp)%dipoles_opt(1,i_T_el,1)
     if (STRING_match(BSE_L_kind,"bar"))  BS_T_grp(i_T_grp)%DEV_VAR(O_x)(1,i_T_el)=cZERO
     !
     ! G/=0 terms
     !
     i_T_grp_last_with_identity_sym=-1
     i_T_el_last_with_identity_sym=-1
     if (i_s>1) then
       do i_T_grp_p=i_T_grp,1,-1
         if ( .not.allocated(BS_T_grp(i_T_grp_p)%O_x)      ) cycle
         if ( BS_T_grp(i_T_grp_p)%ik/=BS_T_grp(i_T_grp)%ik ) exit
         if ( i_T_grp_p==i_T_grp ) N_T_el_p=i_T_el-1
         if ( i_T_grp_p/=i_T_grp ) N_T_el_p=BS_T_grp(i_T_grp_p)%size
         do i_T_el_p=N_T_el_p,1,-1
           if ( all( BS_T_grp(i_T_grp_p)%table(i_T_el_p,:)==(/Xk%k_table(i_k,1),i_v,i_c,i_sp_c,i_sp_v/)) ) then
             i_T_grp_last_with_identity_sym=i_T_grp_p
             i_T_el_last_with_identity_sym =i_T_el_p
             exit
           endif
         enddo
       enddo
     endif
     !
     if  (i_s==1.or.i_T_grp_last_with_identity_sym<0) then
       !
       call DEV_SUB(scatter_Bamp)(K_EXCH_collision)
       !
#ifdef _CUDA
       call dev_memcpy(BS_T_grp(i_T_grp)%O_x_d(:,i_T_el),K_EXCH_collision%rhotw_d,range1=(/2,BS_n_g_exch/) )
#else
       call dev_memcpy(BS_T_grp(i_T_grp)%O_x(:,i_T_el),K_EXCH_collision%rhotw,range1=(/2,BS_n_g_exch/) )
#endif
       !
     else
       !
#ifdef _CUDA
       !
       O_x_d     => BS_T_grp(i_T_grp)%O_x_d
       O_x_sym_d => BS_T_grp(i_T_grp_last_with_identity_sym)%O_x_d
       !
       !$cuf kernel do (1) <<<*,*>>>
       do i_g1=2,BS_n_g_exch
         i_g2=g_rot_d(i_g1,sop_inv_d(i_s))
         O_x_d(i_g1,i_T_el) = O_x_sym_d(i_g2,i_T_el_last_with_identity_sym)
       enddo
       !
#else
       !
       !$omp parallel do default(shared), private(i_g1,i_g2)
       do i_g1=2,BS_n_g_exch
         i_g2=g_rot(i_g1,sop_inv(i_s))
         BS_T_grp(i_T_grp)%O_x(i_g1,i_T_el)=&
         & BS_T_grp(i_T_grp_last_with_identity_sym)%O_x(i_g2,i_T_el_last_with_identity_sym)
       enddo
       !$omp end parallel do
       !
#endif
       if (i_s>nsym/(i_time_rev+1)) call dev_conjg(BS_T_grp(i_T_grp)%DEV_VAR(O_x)(:,i_T_el),range1=(/2,BS_n_g_exch/) )
       !
     endif
     !
   else
     !
     call DEV_SUB(scatter_Bamp)(K_EXCH_collision)
     !
     BS_T_grp(i_T_grp)%DEV_VAR(O_x)(1,i_T_el)=cZERO
     !
     if (STRING_match(BSE_L_kind,"full")) i_g0=1
     if (STRING_match(BSE_L_kind,"bar"))  i_g0=2
     !
#ifdef _CUDA
     call dev_memcpy(BS_T_grp(i_T_grp)%O_x_d(:,i_T_el),K_EXCH_collision%rhotw_d, range1=(/i_g0,BS_n_g_exch/))
#else
     call dev_memcpy(BS_T_grp(i_T_grp)%O_x(:,i_T_el),K_EXCH_collision%rhotw, range1=(/i_g0,BS_n_g_exch/))
#endif
     !
   endif
   !
 enddo T_loop
#if defined(__NOTNOW) && ! defined(_CUDA)
 !$omp end do
#endif
 !
 call elemental_collision_free(K_EXCH_collision) 
#if defined(__NOTNOW) && ! defined(_CUDA)
 !$omp end parallel
#endif
 !
 if(l_bs_exch_wf_in_loop) call WF_free(WF,keep_fft=.true.,keep_states_to_load=.true.)
 !
 call timing('T_space EXX Osc.',OPR='stop')
 !
end subroutine K_exchange_collisions
