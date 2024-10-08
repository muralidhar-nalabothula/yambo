!
! License-Identifier: GPL
!
! Copyright (C) 2020 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine RT_alloc(en,what)
 !
 use pars,           ONLY:SP,cZERO
 use parallel_m,     ONLY:PAR_G_k_range
#if defined _ELPH || defined _PHEL
 use ELPH,           ONLY:elph_branches
#endif
 use drivers,        ONLY:l_use_Hxc_collisions
 use hamiltonian,    ONLY:H_alloc,H_QP_table_setup
 use FFT_m,          ONLY:fft_size
 use electrons,      ONLY:levels,n_spin,n_sp_pol
 use xc_functionals, ONLY:E_xc
 use R_lattice,      ONLY:nXkibz,nqibz
 use RT_occupations, ONLY:RT_EL_occupations_alloc,RT_PH_occupations_alloc,RT_RTA_E_occ_infty,&
&                         RT_RTA_H_occ_infty,l_RT_relax_time_approx
 use RT_lifetimes,   ONLY:RT_EL_lifetimes_alloc,RT_PH_lifetimes_alloc
 use real_time,      ONLY:RT_levels,RT_is_dynamically_dephased,&
&                         Ho_plus_Sigma,H_EQ,H_pseudo_eq,RT_Vnl_xc,HARTREE0,XC0,G_lesser_reference,&
&                         dG_lesser,G_lesser,MEM_pointer,G_MEM_steps,REF_V_xc_sc,REF_V_hartree_sc,rho_reference,&
&                         magn_reference,RT_bands,RT_nk,l_RT_is_WFfree,l_RT_rotate_DM,&
&                         l_velocity_gauge_corr
 !
#include<y_memory.h>
 !
 type(levels), intent(in) :: en
 character(*), intent(in) :: what
 !
 integer :: nk(2)
 logical :: l_carriers,l_all
 !
 l_carriers = trim(what)=="carriers"
 l_all      = trim(what)=="all"
 !
 call H_alloc(en,.not.l_RT_is_WFfree,l_RT_rotate_DM)
 !
 call H_QP_table_setup(en)
 !
 if (RT_is_dynamically_dephased) then
   call RT_EL_lifetimes_alloc(RT_bands,RT_nk)
#if defined _PHEL
   call RT_PH_lifetimes_alloc(elph_branches,nqibz)
#endif
 endif
 !
 nk=PAR_G_k_range
 !
 YAMBO_ALLOC(RT_levels%E,(RT_bands(1):RT_bands(2),RT_nk,n_sp_pol))
 YAMBO_ALLOC(RT_levels%W,(RT_bands(1):RT_bands(2),RT_nk,n_sp_pol))
 !
 if(l_RT_relax_time_approx) then
   YAMBO_ALLOC(RT_RTA_E_occ_infty,(RT_bands(1):RT_bands(2),RT_nk))
   YAMBO_ALLOC(RT_RTA_H_occ_infty,(RT_bands(1):RT_bands(2),RT_nk))
 endif
 !
 if( l_all .or. l_carriers) then
   call RT_EL_occupations_alloc(RT_bands,RT_nk)
#if defined _ELPH || defined _PHEL
   call RT_PH_occupations_alloc(elph_branches,nqibz)
#endif
 endif
 !
 if (l_all) then
   !
   YAMBO_ALLOC(Ho_plus_Sigma,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nk(1):nk(2),n_sp_pol))
   !
   YAMBO_ALLOC(H_EQ,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nk(1):nk(2),n_sp_pol))
   !
   if (l_velocity_gauge_corr) then
     YAMBO_ALLOC(H_pseudo_eq,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),RT_nk,n_sp_pol))
   endif
   !
   if(l_use_Hxc_collisions) then
     YAMBO_ALLOC(RT_Vnl_xc,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nXkibz,n_sp_pol))
     RT_Vnl_xc=(0._SP,0._SP)
   endif
   !
   YAMBO_ALLOC(HARTREE0,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nXkibz,n_sp_pol))
   HARTREE0=cZERO
   !
   YAMBO_ALLOC(XC0,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nXkibz,n_sp_pol))
   XC0=cZERO
   !
   ! G's ...
   YAMBO_ALLOC(G_lesser_reference,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),RT_nk))
   YAMBO_ALLOC(dG_lesser,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nk(1):nk(2),G_MEM_steps))
   YAMBO_ALLOC(G_lesser,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nk(1):nk(2),G_MEM_steps))
   G_lesser_reference=cZERO
   dG_lesser         =cZERO
   G_lesser          =cZERO
   !
   YAMBO_ALLOC(MEM_pointer,(G_MEM_steps))
   MEM_pointer(1)=1
   MEM_pointer(2)=0
   if(G_MEM_steps==3) MEM_pointer(3)=-1
   !
 endif
 !
 if (fft_size==0) return
 !
 YAMBO_ALLOC(E_xc,(fft_size))
 !
 YAMBO_ALLOC(REF_V_xc_sc,(fft_size,n_spin))
 YAMBO_ALLOC(REF_V_hartree_sc,(fft_size,n_spin))
 !
 if( .not.l_RT_is_WFfree ) then
   !
   YAMBO_ALLOC(rho_reference,(fft_size))
   !
   if(n_spin>1) then
     YAMBO_ALLOC(magn_reference,(fft_size,3))
   endif
   !
 endif
 !
end subroutine RT_alloc
