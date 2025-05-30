!
! License-Identifier: GPL
!
! Copyright (C) 2017 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine PARALLEL_global_dimensions(E,Xk,q,ENVIRONMENT)
 !
 use com,           ONLY:secnm
 use parallel_m,    ONLY:PAR_Q_bz_range,PAR_Q_ibz_range,PAR_QP_range,PAR_n_v_bands,PAR_n_c_bands,&
&                        PAR_EH_range,PAR_Dip_ib,PAR_Dip_ib_lim,PAR_X_ib,PAR_X_iq,PAR_n_G_vectors,&
&                        PAR_n_freqs,PAR_K_range,PAR_n_bands
 use drivers,       ONLY:l_eval_collisions,l_elph_corr,l_gw0,l_HF_and_locXC,l_life,l_sc_run,l_nl_optics
 use BS,            ONLY:BS_bands,BS_nT_at_k,BS_n_eh_spaces
 use X_m,           ONLY:X_ng
#if defined _PHEL
 use PHEL,          ONLY:PH_Q
#endif
#if defined _ELPH
 use ELPH,          ONLY:elph_nQ_used,QP_PH_n_G_bands,elph_use_q_grid
#endif
#if defined _SC
 use SC,            ONLY:SC_bands
#endif
#if defined _NL
 use nl_optics,     ONLY:n_runs
#endif
#if defined _RT
 use real_time,     ONLY:RT_bands
#endif
#if defined _SC || defined _RT
 use collision_ext, ONLY:COLL_bands,COH_collisions,P_collisions,HXC_collisions
#endif
 use electrons,     ONLY:levels
 use R_lattice,     ONLY:bz_samp,nqibz,nqbz
 use QP_m,          ONLY:QP_n_states,QP_nb,QP_n_G_bands
#include<y_memory.h>
 !
 type(levels)         :: E
 type(bz_samp)        :: Xk,q
 character(*)         :: ENVIRONMENT
 !
 ! Work Space
 !
 integer              :: i_k
 logical :: computing_Fock
 !
 computing_Fock= ( l_HF_and_locXC .and. index(secnm,"Non-Local Fock")/=0 )
 !
 ! K-pts
 !-------
 PAR_K_range=Xk%nibz
 if (ENVIRONMENT=="BZ_Indexes"               ) PAR_K_range=Xk%nibz
 if (ENVIRONMENT=="DIPOLES"                  ) PAR_K_range=Xk%nibz
 if (index(ENVIRONMENT, "Response_G_space")>0) PAR_K_range=Xk%nbz
 if (ENVIRONMENT=="Response_T_space"         ) PAR_K_range=Xk%nibz
 if (ENVIRONMENT=="Real_Time"                ) PAR_K_range=Xk%nibz
 if (ENVIRONMENT=="Non_Linear"               ) PAR_K_range=Xk%nibz
 !
 ! COND bands
 !------------
 if (ENVIRONMENT=="DIPOLES"                  ) PAR_n_c_bands= (/PAR_Dip_ib_lim(2),PAR_Dip_ib(2)/)
 if (index(ENVIRONMENT, "Response_G_space")>0) PAR_n_c_bands= (/minval(E%nbf)+1,PAR_X_ib(2)/)
 if (ENVIRONMENT=="Response_G_space"         ) PAR_n_c_bands= (/minval(E%nbf)+1,PAR_X_ib(2)/)
 if (ENVIRONMENT=="Response_T_space"         ) PAR_n_c_bands= (/minval(E%nbf)+1,BS_bands(2)/)
 !
 ! VAL bands
 !-----------
 if (ENVIRONMENT=="DIPOLES")                          PAR_n_v_bands= (/PAR_Dip_ib(1),PAR_Dip_ib_lim(1)/)
 if (index(ENVIRONMENT, "Response_G_space")>0       ) PAR_n_v_bands= (/PAR_X_ib(1),maxval(E%nbm)/)
#if defined _NL || defined _SC
 if (l_sc_run .or. l_nl_optics) then
   ! DS 2023/07/24 : to check if this is really needed or not
   if (index(ENVIRONMENT, "Response_G_space")>0     ) PAR_n_v_bands= (/1,PAR_X_ib(2)/)
 endif
#endif
 if (ENVIRONMENT=="Response_T_space"                ) PAR_n_v_bands= (/BS_bands(1),maxval(E%nbm)/)
 !
 ! # G vectors
 !-------------
 if (index(ENVIRONMENT, "Response_G_space")>0) PAR_n_G_vectors= X_ng
 !
 ! Q-pts
 !-------
 PAR_Q_ibz_range=(/1,nqibz/)
 PAR_Q_bz_range=(/1,nqbz/)
 if (ENVIRONMENT=="Response_G_space"  )        PAR_Q_ibz_range=(/PAR_X_iq(1),PAR_X_iq(2)/)
 if (ENVIRONMENT=="Real_Time"         )        PAR_Q_bz_range=(/1,nqbz/)
#if defined _PHEL
 if (ENVIRONMENT=="Phonon_Self_Energy")        PAR_Q_ibz_range=PH_Q
#endif
 !
 if (ENVIRONMENT=="Self_Energy"       ) then
   PAR_n_G_vectors= X_ng
#if defined _SC
   if (l_sc_run.and.&
&      any( (/P_collisions%N,COH_collisions%N,HXC_collisions%N/)> 0))  &
&                                               PAR_Q_bz_range=(/1,nqbz/)
#endif
#if defined _SC || defined _RT
   if (l_eval_collisions)                       PAR_Q_bz_range=(/1,nqbz/)
#endif
#if defined _ELPH
   if (l_elph_corr.and.elph_use_q_grid)         PAR_Q_bz_range=(/1,nqbz/)
   if (l_elph_corr.and..not.elph_use_q_grid)    PAR_Q_bz_range=(/1,elph_nQ_used/)
#endif
 endif
 !
 !
 ! EH-range
 !----------
 if (ENVIRONMENT=="Response_T_space") then
   ! Set this value just to properly define a parallel range
   PAR_EH_range=(PAR_n_c_bands(2)-PAR_n_c_bands(1)+1)*PAR_n_v_bands(2)-PAR_n_v_bands(1)+1
 endif
 if (ENVIRONMENT=="Response_T_space_transitions") then
   PAR_EH_range=maxval( BS_nT_at_k )
   do i_k=1,Xk%nibz*BS_n_eh_spaces
     if (BS_nT_at_k(i_k)<PAR_EH_range.and.BS_nT_at_k(i_k)>0) PAR_EH_range=BS_nT_at_k(i_k)
   enddo
 endif
 !
 ! EH Bands 
 !----------
#if defined _ELPH
 if (ENVIRONMENT=="Phonon_Self_Energy"              ) then
    PAR_n_bands=(/1,(QP_PH_n_G_bands(2)-QP_PH_n_G_bands(1)+1)**2/)
 endif
#endif
 !
 ! Generic Bands
 !---------------
 if (ENVIRONMENT=="Self_Energy"                     ) then
   if (l_HF_and_locXC)                               PAR_n_bands=(/1,maxval((/E%nbm(:),QP_nb/))/)
   if ((l_gw0.or.l_life).and..not.computing_Fock)    PAR_n_bands=(/1,max(QP_n_G_bands(2),QP_nb)/)
   if (.not.computing_Fock)                          PAR_n_bands(1)=QP_n_G_bands(1)
#if defined _SC || defined _RT
   if (l_eval_collisions)  PAR_n_bands=COLL_bands
#endif
#if defined _SC
   if (l_sc_run)           PAR_n_bands=SC_bands
#endif
#if defined _ELPH
   if (l_elph_corr)        PAR_n_bands=(/QP_PH_n_G_bands(1),QP_PH_n_G_bands(2)/)
#endif
 endif
#if defined _RT
 if (ENVIRONMENT=="Real_Time"                       ) then
   PAR_n_bands=(/1,(RT_bands(2)-RT_bands(1)+1)**2/)
   PAR_QP_range=(RT_bands(2)-RT_bands(1)+1)**2
 endif
#endif
 !
 ! QP states
 !-----------
 if (ENVIRONMENT=="Self_Energy"                     ) PAR_QP_range=QP_n_states
 !
 ! Oscillators
#if defined _NL || defined _RT
 if (ENVIRONMENT=="Oscillators"                     ) PAR_n_bands =COLL_bands
#endif
 !
#if defined _NL
 if (ENVIRONMENT=="Non_Linear"                      ) PAR_n_freqs =n_runs
#endif
 !
end subroutine PARALLEL_global_dimensions
