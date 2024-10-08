!
! License-Identifier: GPL
!
! Copyright (C) 2017 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine PARALLEL_global_Response_G(E,Xk,q,ENVIRONMENT,X_type)
 !
 use drivers,       ONLY:l_life
 use electrons,     ONLY:levels
 use R_lattice,     ONLY:bz_samp,nXkibz,nXkbz
 use linear_algebra,ONLY:INV
 use IO_int,        ONLY:IO_and_Messaging_switch
 use openmp,        ONLY:n_threads_X,OPENMP_set_threads
 use parallel_int,  ONLY:PARALLEL_index,PARALLEL_assign_chains_and_COMMs,PARALLEL_live_message
 use parallel_m,    ONLY:ncpu,CPU_structure,COMM_copy,PAR_Q_ibz_range
 ! SLK
 use parallel_m,    ONLY:PAR_COM_RL_A2A,PAR_COM_RL_INDEX,PAR_COM_X_WORLD,PAR_COM_X_WORLD_RL_resolved,PAR_build_index
 !
 ! COMMUNICATORS
 use parallel_m,    ONLY:PAR_COM_Xk_ibz_INDEX,PAR_COM_Xk_bz_INDEX,PAR_COM_Q_INDEX,&
&                        PAR_COM_Q_A2A,PAR_COM_Xk_bz_A2A,PAR_COM_Xk_bz_A2A, &
&                        PAR_COM_CON_INDEX_X,PAR_COM_VAL_INDEX_X
 ! IND
 use parallel_m,    ONLY:PAR_IND_Xk_ibz,PAR_IND_Xk_bz,PAR_IND_Q_ibz
 ! INDEX
 use parallel_m,    ONLY:PAR_Xk_bz_index,PAR_Xk_ibz_index,PAR_Q_ibz_index
 ! DIMENSIONS
 use parallel_m,    ONLY:PAR_nQ_ibz,PAR_Xk_nbz,PAR_Xk_nibz
 ! ID's
 use parallel_m,    ONLY:PAR_IND_Xk_ibz_ID,PAR_IND_Xk_bz_ID,PAR_IND_Q_ibz_ID
 !
#include<y_memory.h>
 !
 type(levels)         :: E
 type(bz_samp)        :: Xk,q
 character(*)         :: ENVIRONMENT
 integer              :: X_type,n_cpu_la
 !
 ! Work space
 !
 character(10)        :: WHAT,WHATp
 !
 CALL PARALLEL_structure(5,(/"q","g","k","c","v"/))
 !
 call PARALLEL_assign_chains_and_COMMs(5,COMM_index_1=PAR_COM_Q_INDEX,&
&                                        COMM_index_2=PAR_COM_RL_INDEX,&
&                                        COMM_index_3=PAR_COM_Xk_bz_INDEX,&
&                                        COMM_index_4=PAR_COM_CON_INDEX_X(X_type),&
&                                        COMM_index_5=PAR_COM_VAL_INDEX_X(X_type),&
&                                        COMM_A2A_1=PAR_COM_Q_A2A,&
&                                        COMM_A2A_2=PAR_COM_RL_A2A,&
&                                        COMM_A2A_3=PAR_COM_Xk_bz_A2A)
 !
 ! COMMs setup
 !
 call COMM_copy(PAR_COM_Q_A2A,PAR_COM_X_WORLD)
 call COMM_copy(PAR_COM_Q_A2A,PAR_COM_X_WORLD_RL_resolved)
 !
 ! AM May 2017. The _RL_ COMM is not meant to distribute the work like all other COMMs.
 ! It is rather an additional level of parallelization.
 !
 if (PAR_COM_RL_INDEX%n_CPU>1) call COMM_copy(PAR_COM_RL_A2A,PAR_COM_X_WORLD_RL_resolved)
 !
 ! K-points 
 !
 call PARALLEL_index(PAR_IND_Xk_bz,(/nXkbz/),COMM=PAR_COM_Xk_bz_INDEX,CONSECUTIVE=.TRUE.,NO_EMPTIES=.TRUE.)
 PAR_IND_Xk_bz_ID=PAR_COM_Xk_bz_INDEX%CPU_id
 PAR_Xk_nbz=PAR_IND_Xk_bz%n_of_elements(PAR_IND_Xk_bz_ID+1)
 !
 call PARALLEL_live_message("K(bz)",ENVIRONMENT=ENVIRONMENT,&
&                           LOADED=PAR_IND_Xk_bz%n_of_elements(PAR_COM_Xk_bz_INDEX%CPU_id+1),TOTAL=nXkbz,&
&                           NCPU=PAR_COM_Xk_bz_INDEX%n_CPU)
 YAMBO_ALLOC(PAR_Xk_bz_index,(nXkbz))
 call PAR_build_index(PAR_IND_Xk_bz,nXkbz,PAR_Xk_bz_index,PAR_Xk_nbz)
 !
 ! Q-points 
 !
 WHAT="ibz"
 !
 call PARALLEL_index(PAR_IND_Q_ibz,(/PAR_Q_ibz_range(2)/),low_range=(/PAR_Q_ibz_range(1)/),COMM=PAR_COM_Q_INDEX,&
&                    CONSECUTIVE=.TRUE.,NO_EMPTIES=.TRUE.)
 PAR_IND_Q_ibz_ID=PAR_COM_Q_INDEX%CPU_id
 PAR_nQ_ibz=PAR_IND_Q_ibz%n_of_elements(PAR_IND_Q_ibz_ID+1)
 !
 call PARALLEL_live_message("Q("//trim(WHAT)//")",ENVIRONMENT=ENVIRONMENT,&
&                           LOADED=PAR_IND_Q_ibz%n_of_elements(PAR_IND_Q_ibz_ID+1),&
&                           TOTAL=PAR_Q_ibz_range(2)-PAR_Q_ibz_range(1)+1,&
&                           NCPU=PAR_COM_Q_INDEX%n_CPU)
 !
 ! RL space
 !
 call  PARALLEL_live_message("G-vectors",ENVIRONMENT=ENVIRONMENT,NCPU=PAR_COM_RL_INDEX%n_CPU)
 !
 ! AM March 2019. Lifetimes calculations do not support the parallel Q distribution
 !
 if (l_life.and.PAR_COM_Q_INDEX%n_CPU>1) then
   call warning("Parallel Q-distribution still not working for lifetime calculations")
   call error("USER parallel structure does not fit the current run parameters")
 endif
 !
 YAMBO_ALLOC(PAR_Q_ibz_index,(PAR_Q_ibz_range(2)))
 call PAR_build_index(PAR_IND_Q_ibz,PAR_Q_ibz_range(2),PAR_Q_ibz_index,PAR_nQ_ibz)
 !
 ! K-points (IBZ) after shifting of Q (BZ/IBZ)
 !
 WHATp="k_bz_q_"//trim(WHAT) 
 !
 call PARALLEL_add_Q_to_K_list(trim(WHATp),PAR_IND_Xk_bz,PAR_IND_Xk_bz_ID,PAR_IND_Xk_ibz,PAR_IND_Xk_ibz_ID,&
&                              PAR_IND_Q_ibz,PAR_COM_Xk_bz_INDEX,PAR_Q_ibz_range,Xk,q)
 PAR_Xk_nibz=PAR_IND_Xk_ibz%n_of_elements(PAR_IND_Xk_ibz_ID+1)
 !
 ! ... indexes
 !
 YAMBO_ALLOC(PAR_Xk_ibz_index,(nXkibz))
 call PAR_build_index(PAR_IND_Xk_ibz,nXkibz,PAR_Xk_ibz_index,PAR_Xk_nibz)
 !
 call PARALLEL_live_message("K-q(ibz)",ENVIRONMENT=ENVIRONMENT,LOADED=PAR_Xk_nibz,TOTAL=nXkibz,&
&                           NCPU=PAR_COM_Xk_ibz_INDEX%n_CPU)
 !
 ! Inversion
 !
 if(index(ENVIRONMENT,"IO")> 0) n_cpu_la=CPU_structure(2)%nCPU_lin_algebra_INV
 if(index(ENVIRONMENT,"IO")==0) n_cpu_la=CPU_structure(3)%nCPU_lin_algebra_INV
 call PARALLEL_assign_LA_COMMs(ENVIRONMENT,INV,n_cpu_la)
 !
 call PARALLEL_live_message("K(ibz)",ENVIRONMENT=ENVIRONMENT,LOADED=PAR_Xk_nibz,TOTAL=Xk%nibz,&
&                           NCPU=PAR_COM_Xk_ibz_INDEX%n_CPU)
 !
 ! I/O privileges
 !
 if (ncpu>1) then
   call IO_and_Messaging_switch("+output",CONDITION=PAR_COM_X_WORLD%CPU_id==0)
#if defined _PAR_IO
   call IO_and_Messaging_switch("+io_out",CONDITION=.TRUE.)
#else
   call IO_and_Messaging_switch("+io_out",CONDITION=PAR_COM_X_WORLD%CPU_id==0)
#endif
 else
   call IO_and_Messaging_switch("+io_out",CONDITION=.TRUE.)
 endif
 !
 call OPENMP_set_threads(n_threads_in=n_threads_X)
 !
 if (ENVIRONMENT=="Response_G_space_and_IO") call PARALLEL_global_Response_IO( )
 !
end subroutine PARALLEL_global_Response_G
