!
! License-Identifier: GPL
!
! Copyright (C) 2017 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine PARALLEL_global_reset(ENVIRONMENT,X_type)
 !
 use R_lattice,     ONLY:bz_samp
 use openmp,        ONLY:OPENMP_set_threads
 use wave_func,     ONLY:states_to_load
 use IO_int,        ONLY:IO_and_Messaging_switch
 use parallel_m,    ONLY:PP_indexes_reset,n_groups
 ! SLK
 use parallel_m,    ONLY:PAR_COM_RL_A2A,PAR_COM_RL_INDEX,PAR_COM_X_WORLD,PAR_COM_X_WORLD_RL_resolved
 use matrix,        ONLY:TRANSFER_world
 ! SCHEMES
 use parallel_m,    ONLY:PARs_PH_Q_ibz,PARs_PH_K_bz,PARs_PH_eh_bands,PAR_scheme_reset
 ! COMMUNICATORS
 use parallel_m,    ONLY:COMM_reset,&  
&                        PAR_COM_VAL_INDEX_X,PAR_COM_VAL_INDEX_DIP,PAR_COM_CON_INDEX_X,PAR_COM_CON_INDEX_DIP,&
&                        PAR_COM_VAL_INDEX_OVLP,PAR_COM_CON_INDEX_OVLP,PAR_COM_Q_A2A,&
&                        PAR_COM_Xk_ibz_INDEX,PAR_COM_Xk_ibz_A2A,PAR_COM_Q_INDEX,&
&                        PAR_COM_Xk_bz_INDEX,PAR_COM_SLK_INDEX_global,PAR_COM_SLK,&
&                        PAR_COM_QP_INDEX,PAR_COM_PLASMA_INDEX,PAR_COM_freqs_INDEX,PAR_COM_freqs,&
&                        PAR_COM_QP_A2A,PAR_COM_G_b_INDEX,PAR_COM_G_b_INDEX_global,PAR_COM_G_b_A2A,&
&                        PAR_COM_BZINDXk_ibz_A2A,PAR_COM_WF_k_A2A,PAR_COM_WF_b_INDEX,PAR_COM_WF_k_INDEX,&
&                        PAR_COM_DIPk_bz_A2A,PAR_COM_DIPk_ibz_A2A,PAR_COM_Xk_bz_A2A,PAR_COM_density,&
&                        PAR_COM_eh_INDEX,PAR_COM_eh_A2A,PAR_COM_T_INDEX,PAR_COM_SLK_INDEX_local
 ! IND
 use parallel_m,    ONLY:PAR_IND_Xk_ibz,PAR_IND_CON_BANDS_X,PAR_IND_Xk_bz,&
&                        PAR_IND_VAL_BANDS_X,PAR_IND_Q_ibz,PAR_IND_Q_bz,PAR_IND_SLK,&
&                        PAR_IND_QP,PAR_IND_G_b,PAR_IND_B_mat_ordered,PAR_IND_WF_b,PAR_IND_WF_k,&
&                        PAR_IND_B_mat,PAR_IND_Plasma,PAR_IND_WF_linear,PAR_IND_T_Haydock,&
&                        PAR_IND_Bp_mat,PAR_IND_G_k,PAR_IND_WF_b_and_k,&
&                        PAR_IND_T_groups,PAR_IND_Kk_ibz,PAR_IND_T_ordered,PAR_IND_freqs,&
&                        PAR_IND_CON_BANDS_DIP,PAR_IND_VAL_BANDS_DIP,PAR_IND_CON_BANDS_OVLP,PAR_IND_VAL_BANDS_OVLP
 ! INDEX
 use parallel_m,    ONLY:PAR_QP_index,PAR_G_bands_index,PAR_PLASMA_index, &
&                        PAR_Q_ibz_index,PAR_Q_bz_index,PAR_Xk_ibz_index,PAR_Xk_bz_index,PAR_DIPk_ibz_index,   &
&                        PAR_BS_T_grps_index,PAR_RL_index,PAR_COM_DIPk_bz_INDEX,PAR_COM_DIPk_ibz_INDEX,    &
&                        PAR_COM_BZINDXk_bz_INDEX,PAR_COM_BZINDXk_ibz_INDEX,PAR_BZINDXk_ibz_index,         &
&                        PAR_freqs_index
 ! ID's
 use parallel_m,    ONLY:PAR_IND_CON_BANDS_X_ID,PAR_IND_VAL_BANDS_X_ID,PAR_IND_Xk_bz_ID,&
&                        PAR_IND_Xk_ibz_ID,PAR_IND_Q_ibz_ID,PAR_IND_Q_bz_ID,PAR_IND_CON_BANDS_DIP_ID,&
&                        PAR_IND_VAL_BANDS_DIP_ID,PAR_IND_VAL_BANDS_OVLP_ID,PAR_IND_CON_BANDS_OVLP_ID,&
&                        PAR_IND_QP_ID,PAR_IND_G_b_ID,PAR_IND_PLASMA_ID,&
&                        PAR_IND_WF_k_ID,PAR_IND_WF_b_ID,PAR_IND_G_k_ID,PAR_IND_freqs_ID
#if defined _RT || defined _SC || defined _QED || defined _NL
 use collision_ext, ONLY:COH_collisions,HXC_collisions,GW_NEQ_collisions,P_collisions
#endif
#if defined _SCALAPACK
 use SLK_m,         ONLY:SLK_COM_INDEX,SLK_COM_A2A
#endif
 !
#include <y_memory.h>
 !
 type(bz_samp)        :: Xk
 character(*)         :: ENVIRONMENT
 integer              :: X_type
 !
 ! Work Space
 !
 !
 call PP_indexes_reset(PAR_IND_SLK)
 call PP_indexes_reset(PAR_IND_Q_ibz)
 call PP_indexes_reset(PAR_IND_Q_bz)
 call PP_indexes_reset(PAR_IND_T_groups)
 call PP_indexes_reset(PAR_IND_Kk_ibz)
 call PP_indexes_reset(PAR_IND_Xk_ibz)
 call PP_indexes_reset(PAR_IND_Xk_bz)
 call PP_indexes_reset(PAR_IND_CON_BANDS_X(X_type))
 call PP_indexes_reset(PAR_IND_VAL_BANDS_X(X_type))
 call PP_indexes_reset(PAR_IND_CON_BANDS_DIP)
 call PP_indexes_reset(PAR_IND_VAL_BANDS_DIP)
 call PP_indexes_reset(PAR_IND_CON_BANDS_OVLP)
 call PP_indexes_reset(PAR_IND_VAL_BANDS_OVLP)
 call PP_indexes_reset(PAR_IND_QP)
 call PP_indexes_reset(PAR_IND_Plasma)
 call PP_indexes_reset(PAR_IND_B_mat)
 call PP_indexes_reset(PAR_IND_Bp_mat)
 call PP_indexes_reset(PAR_IND_B_mat_ordered)
 call PP_indexes_reset(PAR_IND_G_b)
 call PP_indexes_reset(PAR_IND_G_k)
 call PP_indexes_reset(PAR_IND_WF_b)
 call PP_indexes_reset(PAR_IND_WF_k)
 call PP_indexes_reset(PAR_IND_WF_b_and_k)
 call PP_indexes_reset(PAR_IND_WF_linear)
 call PP_indexes_reset(PAR_IND_T_ordered)
 call PP_indexes_reset(PAR_IND_T_Haydock)
 call PP_indexes_reset(PAR_IND_freqs)
 !
 YAMBO_FREE(PAR_QP_index)
 YAMBO_FREE(PAR_G_bands_index)
 YAMBO_FREE(PAR_PLASMA_index)
 YAMBO_FREE(PAR_Q_ibz_index)
 YAMBO_FREE(PAR_Q_bz_index)
 YAMBO_FREE(PAR_Xk_ibz_index)
 YAMBO_FREE(PAR_Xk_bz_index)
 YAMBO_FREE(states_to_load)
 YAMBO_FREE(PAR_DIPk_ibz_index)
 YAMBO_FREE(PAR_BZINDXk_ibz_index)
 YAMBO_FREE(PAR_BS_T_grps_index)
 YAMBO_FREE(PAR_RL_index)
 YAMBO_FREE(PAR_freqs_index)
 !
 PAR_IND_Q_ibz_ID=0
 PAR_IND_Q_bz_ID=0
 PAR_IND_Xk_ibz_ID=0
 PAR_IND_Xk_bz_ID=0
 PAR_IND_CON_BANDS_X_ID(X_type)=0
 PAR_IND_VAL_BANDS_X_ID(X_type)=0
 PAR_IND_CON_BANDS_DIP_ID=0
 PAR_IND_VAL_BANDS_DIP_ID=0
 PAR_IND_CON_BANDS_OVLP_ID=0
 PAR_IND_VAL_BANDS_OVLP_ID=0
 PAR_IND_QP_ID=0
 PAR_IND_PLASMA_ID=0
 PAR_IND_G_b_ID=0
 PAR_IND_G_k_ID=0
 PAR_IND_WF_b_ID=0
 PAR_IND_WF_k_ID=0
 PAR_IND_freqs_ID=0
 !
 call COMM_reset(PAR_COM_VAL_INDEX_X(X_type))
 call COMM_reset(PAR_COM_CON_INDEX_X(X_type))
 call COMM_reset(PAR_COM_Xk_ibz_INDEX)
 call COMM_reset(PAR_COM_Xk_ibz_A2A)
 call COMM_reset(PAR_COM_Xk_bz_INDEX)
 call COMM_reset(PAR_COM_Xk_bz_A2A)
 call COMM_reset(PAR_COM_Q_INDEX)
 call COMM_reset(PAR_COM_Q_A2A)
 call COMM_reset(PAR_COM_SLK_INDEX_global)
 call COMM_reset(PAR_COM_SLK)
 call COMM_reset(PAR_COM_PLASMA_INDEX)
 call COMM_reset(PAR_COM_QP_INDEX)
 call COMM_reset(PAR_COM_QP_A2A)
 call COMM_reset(PAR_COM_G_b_INDEX)
 call COMM_reset(PAR_COM_G_b_A2A)
 call COMM_reset(PAR_COM_G_b_INDEX_global)
 call COMM_reset(PAR_COM_WF_k_A2A)
 call COMM_reset(PAR_COM_WF_b_INDEX)
 call COMM_reset(PAR_COM_WF_k_INDEX)
 call COMM_reset(PAR_COM_VAL_INDEX_DIP)
 call COMM_reset(PAR_COM_CON_INDEX_DIP)
 call COMM_reset(PAR_COM_VAL_INDEX_OVLP)
 call COMM_reset(PAR_COM_CON_INDEX_OVLP)
 call COMM_reset(PAR_COM_DIPk_bz_INDEX)
 call COMM_reset(PAR_COM_DIPk_bz_A2A)
 call COMM_reset(PAR_COM_DIPk_ibz_INDEX)
 call COMM_reset(PAR_COM_DIPk_ibz_A2A)
 call COMM_reset(PAR_COM_BZINDXk_bz_INDEX)
 call COMM_reset(PAR_COM_BZINDXk_ibz_INDEX)
 call COMM_reset(PAR_COM_BZINDXk_ibz_A2A)
 call COMM_reset(PAR_COM_X_WORLD_RL_resolved)
 call COMM_reset(PAR_COM_X_WORLD)
 call COMM_reset(PAR_COM_density)
 call COMM_reset(PAR_COM_eh_INDEX)
 call COMM_reset(PAR_COM_RL_INDEX)
 call COMM_reset(PAR_COM_RL_A2A)
 call COMM_reset(PAR_COM_eh_A2A)
 call COMM_reset(PAR_COM_T_INDEX)
 call COMM_reset(PAR_COM_SLK_INDEX_local)
 call COMM_reset(TRANSFER_world)
#if defined _SCALAPACK
 call COMM_reset(PAR_COM_SLK)
 call COMM_reset(PAR_COM_SLK_INDEX_global)
 call COMM_reset(SLK_COM_INDEX(1))
 call COMM_reset(SLK_COM_INDEX(2))
 call COMM_reset(SLK_COM_A2A(1))
 call COMM_reset(SLK_COM_A2A(2))
#endif
 call COMM_reset(PAR_COM_freqs_INDEX)
 call COMM_reset(PAR_COM_freqs)
#if defined _RT || defined _SC || defined _QED || defined _NL
 call PARALLEL_collisions_reset(HXC_collisions)
 call PARALLEL_collisions_reset(COH_collisions)
 call PARALLEL_collisions_reset(GW_NEQ_collisions)
 call PARALLEL_collisions_reset(P_collisions)
#endif
 !
 call PAR_scheme_reset(PARs_PH_Q_ibz)
 call PAR_scheme_reset(PARs_PH_K_bz)
 call PAR_scheme_reset(PARs_PH_eh_bands)
 !
 call IO_and_Messaging_switch("RESET")
 !
 n_groups=0
 !
 call OPENMP_set_threads( )
 !
end subroutine PARALLEL_global_reset
