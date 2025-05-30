!
! License-Identifier: GPL
!
! Copyright (C) 2013 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
module parallel_m
 !
 ! Collective Operations (from  http://linux.die.net/man/3/mpi_lor )
 !
 ! The collective combination operations ( MPI_REDUCE , MPI_ALLREDUCE , MPI_REDUCE_SCATTER , and MPI_SCAN ) take a combination operation. This operation is of type
 ! MPI_Op in C and of type INTEGER in Fortran. The predefined operations are 
 !
 !MPI_MAX
 !    - return the maximum 
 !MPI_MIN
 !    - return the minumum 
 !MPI_SUM
 !    - return the sum 
 !MPI_PROD
 !    - return the product 
 !MPI_LAND
 !    - return the logical and 
 !MPI_BAND
 !    - return the bitwise and 
 !MPI_LOR
 !    - return the logical or 
 !MPI_BOR
 !    - return the bitwise of 
 !MPI_LXOR
 !    - return the logical exclusive or 
 !MPI_BXOR
 !    - return the bitwise exclusive or 
 !MPI_MINLOC
 !    - return the minimum and the location (actually, the value of the second element of the structure where the minimum of the first is found) 
 !MPI_MAXLOC
 !    - return the maximum and the location 
 !
 use pars,       ONLY:SP,DP,schlen,lchlen,max_n_of_cpus,MAX_N_GROUPS,MAX_N_OF_CHAINS,n_CPU_str_max
#if defined _MPI
 use mpi
#endif
 !
#if !defined _io_lib
#include<y_memory.h>
#endif
 !
#if defined _MPI
! 2021/01/14 DS, commented.
! It maybe needed for old libraries
! To be uncommented but protected with precompiler flags on gfortran compiler
! include 'mpif.h'
#else
 integer            :: mpi_comm_world=0
 integer, parameter :: mpi_info_null =0
 integer, parameter :: mpi_comm_null =0
#endif
 !
 integer            :: myid
 integer            :: mygpu_dev   = 0
 integer            :: ncpu
 integer            :: n_nodes(1)  = 1
 integer            :: n_IO_nodes  = 1
 integer            :: n_MPI       = 1
 !
 ! Node name
 !
 character(lchlen)  :: host_name
 integer            :: host_name_length
 !
 ! This should be removed and mpi_comm_null used everywhere
 !
 integer, parameter :: comm_default_value  = mpi_comm_null
 !
 ! Logicals
 !
 logical            :: l_par_X_T,l_par_X_G,l_par_X_G_finite_q,l_par_DIP,l_par_BZINDX,l_par_SE, &
&                      l_par_RT,l_par_SC,l_par_NL,l_par_OSCLL
 !
 ! In a parallel runs, when some loops not involving all CPU's are parallelized it is usefull to keep 
 ! the operations local in the cpu world
 !
 logical           :: HEAD_QP_cpu=.TRUE.
 logical           :: HEAD_k_cpu =.TRUE.
 logical           :: HEAD_q_cpu =.TRUE.
 logical           :: HEAD_b_cpu =.TRUE.
 !
 ! Communicators
 !
 integer            :: n_groups                =0          ! groups of active chains
 integer            :: nchains_group(2*MAX_N_GROUPS)=0     ! chains limits in the group
 integer            :: ncpu_chain(MAX_N_OF_CHAINS)=1       ! #CPUs in each chain
 !
 ! MPI intra-groups Communicators
 !
 type yMPI_comm 
   integer  :: COMM      
   integer  :: CPU_id    
   integer  :: my_CHAIN    ! equivalent to CPU_id+1 in INTER_CHAIN
   integer  :: chain_order ! this corresponds to the order in the local hierarchy
   integer  :: n_CPU     
 end type yMPI_comm
 ! 
 ! CHAINS 
 !========
 type(yMPI_comm),SAVE   :: INTRA_CHAIN(MAX_N_OF_CHAINS) ! COMMUNICATOR among CPUs of the same chain
 type(yMPI_comm),SAVE   :: INTER_CHAIN(MAX_N_OF_CHAINS) ! COMMUNICATOR among same CPU (same ID) of different CHAINS 
 type(yMPI_comm),SAVE   :: CHILD_CHAIN(MAX_N_OF_CHAINS) ! COMMUNICATOR among CPUs (same ID) of different CHAINS enclosed in 
                                                        ! the above INTER_CHAIN cpu's'
 !
 ! CPU's
 !=======
 type CPU_stru 
   integer              :: N_chains  =1
   integer              :: CPU(MAX_N_OF_CHAINS) = 1
   character(4)         :: ROLE(MAX_N_OF_CHAINS)= " "
   character(schlen)    :: CPU_string  = " "
   character(schlen)    :: ROLE_string = " "
   character(schlen)    :: Long_Description  = " "
   character(schlen)    :: Short_Description = " "
   integer              :: nCPU_lin_algebra_INV   =-1
   integer              :: nCPU_lin_algebra_DIAGO =-1
 end type CPU_stru
 !
 character(schlen)   :: CPU_string_save(n_CPU_str_max)
 character(schlen)   :: ROLE_string_save(n_CPU_str_max)
 !
 type(CPU_stru),SAVE :: CPU_structure(n_CPU_str_max)
 integer             :: i_PAR_structure
 !
 !... Running values ...
 !
 integer          :: PARALLEL_CPU_used(MAX_N_OF_CHAINS) = 1
 character(4)     :: PARALLEL_CPU_role(MAX_N_OF_CHAINS) = " "
 integer          :: PARALLEL_n_structures_active = 0
 logical          :: PARALLEL_ENV_uses_default(n_CPU_str_max) = .false.
 logical          :: linear_algebra_is_parallel = .false.
 character(schlen):: PARALLEL_default_mode="balanced" ! "memory"/"workload"
 !
 !... Logging CPUs ...
 !
 integer          :: n_log_CPUs = 0
 !
 ! MPI operations
 !
 integer, parameter :: p_sum =1
 integer, parameter :: p_prod=2
 !
 ! Logicals
 !
 logical            :: IO_write_default(max_n_of_cpus)
 logical            :: master_cpu
 logical            :: l_open_MP
 !
 ! PP indexes
 !
 type PP_indexes
   logical, allocatable :: element_1D(:)
   logical, allocatable :: element_2D(:,:)
   ! Davide 4/09/2015: n_of_elements should be a number. It is useless that it is a vector
   !                   allocated to nCPU and that each CPU fills only the element myid.
   integer, allocatable :: n_of_elements(:)
   integer, allocatable :: weight_1D(:)
   integer, allocatable :: first_of_1D(:)
   integer, allocatable :: last_of_1D(:)
 end type PP_indexes
 !
 ! SCHEMEs ...
 !========================
 type PAR_scheme
   type(yMPI_comm)     :: COMM_i
   type(yMPI_comm)     :: COMM_a2a
   type(PP_indexes)    :: IND
   integer             :: ID
   integer             :: D(2)
   integer             :: N_ser
   integer             :: N_par
   logical             :: consecutive
   integer,allocatable :: table(:)
 end type
 !
 ! ... PH Self Energy
 !--------------------
 type(PAR_scheme),SAVE :: PARs_PH_Q_ibz
 type(PAR_scheme),SAVE :: PARs_PH_K_bz
 type(PAR_scheme),SAVE :: PARs_PH_eh_bands
 !
 ! ... RT 
 !--------
 !type(PAR_scheme),SAVE :: PARs_RT_plasma
 !
 type PARk_str
   type(yMPI_comm)     :: COM_ibz_INDEX
   type(yMPI_comm)     :: COM_ibz_A2A
   type(PP_indexes)    :: IND_ibz
   type(PP_indexes)    :: IND_bz
   integer,allocatable :: ibz_index(:)
   integer,allocatable :: bz_index(:)
   integer             :: nibz
   integer             :: nbz
   integer             :: comm_world
 end type
 !
 type(PARk_str),SAVE   :: PAR_K_scheme
 !
 ! SND & RCV plan
 !=================
 type SND_RCV_geometry
   integer,allocatable :: SND_to_id(:)
   integer,allocatable :: RCV_from_id(:)
 end type
 integer               :: N_SND_RCV_operations
 type(SND_RCV_geometry), allocatable :: SND_RCV_op(:)
 !
 ! Number of Bands to load
 !=========================
 !
 ! When the PARALLEL_global_index define a distribution common to HF,GW and e-p
 ! it defines a global number of bands to load that overwrites the local values
 !
 integer            :: n_WF_bands_to_load
 !
 ! Number of Response functions
 !==============================
 !
 ! 1:X 2:em1s 3:em1d 4:pp 5:bse
 !
 integer, parameter :: n_parallel_X_types=5
 !
 ! Specific PP indexes ...
 !========================
 !
 ! ... linear algebra
 type(PP_indexes),SAVE :: PAR_IND_SLK
 !
 ! ... BZ sampling (Electrons)
 type(PP_indexes),SAVE :: PAR_IND_Q_ibz
 type(PP_indexes),SAVE :: PAR_IND_Q_bz
 type(PP_indexes),SAVE :: PAR_IND_Kk_ibz
 type(PP_indexes),SAVE :: PAR_IND_Xk_ibz
 type(PP_indexes),SAVE :: PAR_IND_Xk_bz
 type(PP_indexes),SAVE :: PAR_IND_G_k
 !
 ! ... BZINDX
 type(PP_indexes),SAVE :: PAR_IND_BZINDXk_ibz
 type(PP_indexes),SAVE :: PAR_IND_BZINDXk_bz
 !
 ! ... DIPOLES
 type(PP_indexes),SAVE :: PAR_IND_DIPk_ibz
 type(PP_indexes),SAVE :: PAR_IND_DIPk_bz
 type(PP_indexes),SAVE :: PAR_IND_VAL_BANDS_DIP
 type(PP_indexes),SAVE :: PAR_IND_CON_BANDS_DIP
 !
 ! ... Overlaps
 type(PP_indexes),SAVE :: PAR_IND_OVLPk_ibz
 type(PP_indexes),SAVE :: PAR_IND_VAL_BANDS_OVLP
 type(PP_indexes),SAVE :: PAR_IND_CON_BANDS_OVLP
 !
 ! ... linear response & BSK
 type(PP_indexes),SAVE :: PAR_IND_VAL_BANDS_X(n_parallel_X_types)
 type(PP_indexes),SAVE :: PAR_IND_CON_BANDS_X(n_parallel_X_types)
 !
 ! ... QP
 type(PP_indexes),SAVE :: PAR_IND_QP
 !
 ! ... Plasma
 type(PP_indexes),SAVE :: PAR_IND_Plasma
 !
 ! ... G bands
 type(PP_indexes),SAVE :: PAR_IND_G_b
 type(PP_indexes),SAVE :: PAR_IND_B_mat
 type(PP_indexes),SAVE :: PAR_IND_Bp_mat
 type(PP_indexes),SAVE :: PAR_IND_B_mat_ordered
 !
 ! ... WF
 type(PP_indexes),SAVE :: PAR_IND_WF_b
 type(PP_indexes),SAVE :: PAR_IND_WF_k
 type(PP_indexes),SAVE :: PAR_IND_WF_b_and_k
 type(PP_indexes),SAVE :: PAR_IND_WF_linear
 !
 ! ... RL vectors
 type(PP_indexes),SAVE :: PAR_IND_RL
 !
 ! ... Transitions
 type(PP_indexes),allocatable,SAVE :: PAR_IND_eh(:)
 type(PP_indexes)            ,SAVE :: PAR_IND_T_groups
 type(PP_indexes)            ,SAVE :: PAR_IND_T_Haydock
 type(PP_indexes)            ,SAVE :: PAR_IND_T_ordered
 !
 ! .... Frequencies 
 type(PP_indexes),SAVE :: PAR_IND_freqs
 !
 ! Specific MPI ID's ...
 !======================
 ! ... QP
 integer            :: PAR_IND_QP_ID
 !
 ! ... PLASMA
 integer            :: PAR_IND_PLASMA_ID
 !
 ! ... G bands
 integer            :: PAR_IND_G_b_ID
 !
 ! ... WF
 integer            :: PAR_IND_WF_b_ID
 integer            :: PAR_IND_WF_k_ID
 !
 ! ... BZ (Electrons)
 integer            :: PAR_IND_Q_ibz_ID
 integer            :: PAR_IND_Q_bz_ID
 integer            :: PAR_IND_Kk_ibz_ID
 integer            :: PAR_IND_Xk_ibz_ID
 integer            :: PAR_IND_Xk_bz_ID
 integer            :: PAR_IND_G_k_ID
 !
 ! ... BZINDX
 integer            :: PAR_IND_BZINDXk_bz_ID
 integer            :: PAR_IND_BZINDXk_ibz_ID
 !
 ! ... DIPOLES
 integer            :: PAR_IND_DIPk_bz_ID
 integer            :: PAR_IND_DIPk_ibz_ID
 integer            :: PAR_IND_VAL_BANDS_DIP_ID
 integer            :: PAR_IND_CON_BANDS_DIP_ID
 !
 ! ... Overlaps
 integer            :: PAR_IND_OVLPk_ibz_ID
 integer            :: PAR_IND_VAL_BANDS_OVLP_ID
 integer            :: PAR_IND_CON_BANDS_OVLP_ID
 !
 ! ... linear response & BSK
 integer            :: PAR_IND_VAL_BANDS_X_ID(n_parallel_X_types)
 integer            :: PAR_IND_CON_BANDS_X_ID(n_parallel_X_types)
 !
 ! ... BSK
 integer            :: PAR_IND_eh_ID
 !
 ! ... RL
 integer            :: PAR_IND_RL_ID
 !
 ! .... Frequencies
 integer            :: PAR_IND_freqs_ID
 !
 ! ... Freqs
 integer            :: PAR_IND_FREQ_ID
 !
 ! Specific MPI COMMUNICATORS...
 !==============================
 ! PAR_COM_*_INDEX is the interchain comunicator
 ! PAR_COM_*_A2A   is the intrachain comunicator
 !
 ! ... World
 type(yMPI_comm),SAVE :: PAR_COM_WORLD
 ! ... Serial
 type(yMPI_comm),SAVE :: PAR_COM_NULL
 ! ... HOST
 type(yMPI_comm),SAVE :: PAR_COM_HOST
 !
 ! ... linear algebra
 type(yMPI_comm),SAVE :: PAR_COM_SLK
 type(yMPI_comm),SAVE :: PAR_COM_SLK_INDEX_global
 type(yMPI_comm),SAVE :: PAR_COM_SLK_INDEX_local
 !
 ! ... RL vectors
 type(yMPI_comm),SAVE :: PAR_COM_RL_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_RL_A2A
 !
 ! ... QP
 type(yMPI_comm),SAVE :: PAR_COM_QP_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_QP_A2A
 !
 ! ... Plasma
 type(yMPI_comm),SAVE :: PAR_COM_PLASMA_INDEX
 !
 ! ... G bands
 type(yMPI_comm),SAVE :: PAR_COM_G_b_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_G_b_A2A
 type(yMPI_comm),SAVE :: PAR_COM_G_b_INDEX_global
 !
 ! ... WF
 type(yMPI_comm),SAVE :: PAR_COM_WF_k_A2A
 type(yMPI_comm),SAVE :: PAR_COM_WF_k_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_WF_b_INDEX
 !
 ! ... BZ (Electrons)
 type(yMPI_comm),SAVE :: PAR_COM_Q_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_Q_A2A
 type(yMPI_comm),SAVE :: PAR_COM_Xk_ibz_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_Xk_ibz_A2A
 type(yMPI_comm),SAVE :: PAR_COM_Xk_bz_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_Xk_bz_A2A
 !
 ! ... BZINDX
 type(yMPI_comm),SAVE :: PAR_COM_BZINDXk_ibz_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_BZINDXk_ibz_A2A
 type(yMPI_comm),SAVE :: PAR_COM_BZINDXk_bz_INDEX
 !
 ! ... DIPOLES
 type(yMPI_comm),SAVE :: PAR_COM_DIPk_ibz_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_DIPk_ibz_A2A
 type(yMPI_comm),SAVE :: PAR_COM_DIPk_bz_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_DIPk_bz_A2A
 type(yMPI_comm),SAVE :: PAR_COM_VAL_INDEX_DIP
 type(yMPI_comm),SAVE :: PAR_COM_CON_INDEX_DIP
 !
 ! ... Overlaps
 type(yMPI_comm),SAVE :: PAR_COM_VAL_INDEX_OVLP
 type(yMPI_comm),SAVE :: PAR_COM_CON_INDEX_OVLP
 !
 ! ... linear response & BSK
 type(yMPI_comm),SAVE :: PAR_COM_VAL_INDEX_X(n_parallel_X_types)
 type(yMPI_comm),SAVE :: PAR_COM_CON_INDEX_X(n_parallel_X_types)
 type(yMPI_comm),SAVE :: PAR_COM_X_WORLD_RL_resolved
 type(yMPI_comm),SAVE :: PAR_COM_X_WORLD
 !
 ! ... BSK
 type(yMPI_comm),SAVE :: PAR_COM_eh_INDEX
 type(yMPI_comm),SAVE :: PAR_COM_eh_A2A
 type(yMPI_comm),SAVE :: PAR_COM_T_INDEX
 !
 ! ... Haydock solver
 type(yMPI_comm),allocatable,SAVE :: PAR_COM_T_Haydock(:)
 !
 ! ... density
 type(yMPI_comm),SAVE :: PAR_COM_density
 !
 ! ... Frequencies 
 type(yMPI_comm),SAVE :: PAR_COM_freqs
 type(yMPI_comm),SAVE :: PAR_COM_freqs_A2A
 type(yMPI_comm),SAVE :: PAR_COM_freqs_INDEX
 !
 ! ... SE
 type(yMPI_comm),SAVE :: PAR_COM_SE_WORLD_RL_resolved
 type(yMPI_comm),SAVE :: PAR_COM_SE_WORLD
 !
 ! ... and dimensions (used for automatic cpu distribution)
 !=========================================================
 integer            :: PAR_K_range       = 0
 integer            :: PAR_EH_range      = 0
 integer            :: PAR_QP_range      = 0
 integer            :: PAR_Q_ibz_range(2)= 0
 integer            :: PAR_Q_bz_range(2) = 0
 integer            :: PAR_Dip_ib(2)     = 0
 integer            :: PAR_Dip_ib_lim(2) = 0
 integer            :: PAR_X_ib(2)       = 0
 integer            :: PAR_X_iq(2)       = 0
 integer            :: PAR_n_bands(2)    = 0
 integer            :: PAR_n_c_bands(2)  = 0
 integer            :: PAR_n_v_bands(2)  = 0
 integer            :: PAR_n_G_vectors   = 0
 integer            :: PAR_G_k_range(2)  = 0  ! For parallel I/O of G
 !
 ! ... and derived variables
 !==========================
 integer            :: PAR_nRL
 integer,allocatable:: PAR_RL_index(:)
 integer            :: PAR_nPlasma
 integer,allocatable:: PAR_PLASMA_index(:)
 integer            :: PAR_nQP
 integer,allocatable:: PAR_QP_index(:)
 integer            :: PAR_nQ_ibz
 integer,allocatable:: PAR_Q_ibz_index(:)
 !integer            :: PAR_PH_nQ_ibz
 !integer,allocatable:: PAR_PH_Q_ibz_index(:)
 integer            :: PAR_nQ_bz
 integer,allocatable:: PAR_Q_bz_index(:)
 integer            :: PAR_Kk_nibz
 integer            :: PAR_Xk_nibz
 integer,allocatable:: PAR_Xk_ibz_index(:)
 integer            :: PAR_Xk_nbz
 integer,allocatable:: PAR_Xk_bz_index(:)
 integer            :: PAR_BZINDXk_nibz
 integer,allocatable:: PAR_BZINDXk_ibz_index(:)
 integer            :: PAR_BZINDXk_nbz
 integer,allocatable:: PAR_BZINDXk_bz_index(:)
 integer            :: PAR_DIPk_nibz
 integer,allocatable:: PAR_DIPk_ibz_index(:)
 integer            :: PAR_DIPk_nbz
 integer,allocatable:: PAR_DIPk_bz_index(:)
 integer            :: PAR_BS_nT_col_grps 
 integer,allocatable:: PAR_BS_T_grps_index(:)
 integer            :: PAR_nG_bands 
 integer,allocatable:: PAR_G_bands_index(:)
 integer            :: PAR_n_freqs 
 integer,allocatable:: PAR_FREQS_index(:)
 integer            :: PAR_n_Bp_mat_elements 
 !
 contains
   !
   subroutine PAR_build_index(PAR_ind,N_elements,V_ind,n_V_ind)
     type(PP_indexes), intent(in)   :: PAR_ind
     integer,          intent(in)   :: N_elements
     integer,          intent(out)  :: n_V_ind,V_ind(N_elements)
     integer                        :: i_p
     V_ind  =0
     n_V_ind=0
     if (N_elements==size(PAR_IND%element_1D)) then
       do i_p=1,N_elements
         if (PAR_IND%element_1D(i_p)) then
           n_V_ind=n_V_ind+1
           V_ind(i_p)=n_V_ind
         endif
       enddo
     else 
       do i_p=1,size(PAR_IND%element_1D)
         if (PAR_IND%element_1D(i_p)) then
           n_V_ind=n_V_ind+1
           V_ind(n_V_ind)=i_p
         endif
       enddo
     endif
     !
   end subroutine
   !
   subroutine CREATE_the_COMM(WORLD, COMM, ID )
     integer       :: WORLD,ID,i_err
     type(yMPI_comm):: COMM
     if (ncpu==1) return
#if defined _MPI
     call MPI_COMM_SPLIT(WORLD,COMM%my_CHAIN,ID,COMM%COMM,i_err)
     call MPI_COMM_RANK(COMM%COMM,COMM%CPU_id,i_err)
     call MPI_COMM_SIZE(COMM%COMM,COMM%n_CPU ,i_err)
#endif
   end subroutine
   !
   integer function i_INTER_CHAIN(N_father,N_child)
     ! Note that N_child/_father are the #cpu's in the two chains
     integer :: N_father,N_child
     i_INTER_CHAIN=(myid/N_father)*(N_father/N_child)+mod(myid,N_father/N_child)
   end function
   !
#if !defined _io_lib
   character(lchlen) function PARALLEL_message(i_s)
     use stderr, ONLY:intc
     use openmp, ONLY:n_threads_X,n_threads_SE,n_threads_RT,n_threads_DIP,n_threads_K, &
&                     n_threads_NL,n_threads_BZINDX,n_threads_OSCLL,n_threads
     integer :: i_s
     !
     PARALLEL_message=" "
     !
#if !defined _MPI && !defined _OPENMP
     return
#endif
     if (i_s>0) then
       if (len_trim(CPU_structure(i_s)%CPU_string)==0) return
     endif
     !
     if (i_s==0) then
       PARALLEL_message=trim(intc(ncpu))//"(CPU)"
       if (n_threads       >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads))//"(threads)"
       if (n_threads_X     >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_X))//"(threads@X)"
       if (n_threads_BZINDX>0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_BZINDX))//"(threads@BZINDX)"
       if (n_threads_DIP   >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_DIP))//"(threads@DIP)"
       if (n_threads_SE    >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_SE))//"(threads@SE)"
       if (n_threads_RT    >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_RT))//"(threads@RT)"
       if (n_threads_K     >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_K))//"(threads@K)"
       if (n_threads_NL    >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_NL))//"(threads@NL)"
       if (n_threads_OSCLL >0) PARALLEL_message=trim(PARALLEL_message)//"-"//trim(intc(n_threads_OSCLL))//"(threads@OSCLL)"
     else
       PARALLEL_message=trim(CPU_structure(i_s)%Short_Description)//"(environment)-"//&
&                       trim(CPU_structure(i_s)%CPU_string)//"(CPUs)-"//&
&                       trim(CPU_structure(i_s)%ROLE_string)//"(ROLEs)"
     endif
     !
   end function
#endif
   !
   subroutine CPU_and_ROLE_strings_save()
     implicit none
     !
     CPU_string_save (:)=CPU_structure(:)%CPU_string
     ROLE_string_save(:)=CPU_structure(:)%ROLE_string
     ! 
   end subroutine CPU_and_ROLE_strings_save
   !
   subroutine CPU_and_ROLE_strings_restore()
     implicit none
     !
     CPU_structure(:)%CPU_string = CPU_string_save(:)
     CPU_structure(:)%ROLE_string=ROLE_string_save(:)
     ! 
   end subroutine CPU_and_ROLE_strings_restore
   !
   subroutine CPU_str_reset()
     CPU_structure(1)%Long_Description="DIPOLES"
     CPU_structure(1)%Short_Description="DIP"
     CPU_structure(2)%Long_Description="Response_G_space_and_IO"
     CPU_structure(2)%Short_Description="X_and_IO"
     CPU_structure(3)%Long_Description="Response_G_space"
     CPU_structure(3)%Short_Description="X"
     CPU_structure(4)%Long_Description="Response_T_space"
     CPU_structure(4)%Short_Description="BS"
     CPU_structure(5)%Long_Description="Self_Energy"
     CPU_structure(5)%Short_Description="SE"
     CPU_structure(6)%Long_Description="Real_Time"
     CPU_structure(6)%Short_Description="RT"
     CPU_structure(7)%Long_Description="ScaLapacK"
     CPU_structure(7)%Short_Description="SLK"
     CPU_structure(8)%Long_Description="Non_Linear"
     CPU_structure(8)%Short_Description="NL"
     CPU_structure(9)%Long_Description="BZ_Indexes"
     CPU_structure(9)%Short_Description="BZINDX"
     CPU_structure(10)%Long_Description="Phonon_Self_Energy"
     CPU_structure(10)%Short_Description="PH_SE"
     CPU_structure(11)%Long_Description="Oscillators"
     CPU_structure(11)%Short_Description="OSCLL"
   end subroutine
   !
   subroutine COMM_reset(COMM)
     type(yMPI_comm):: COMM
     COMM%n_CPU      =1
     COMM%COMM       =comm_default_value
     COMM%my_CHAIN   =1
     COMM%chain_order=nchains_group(2)
     COMM%CPU_ID     =0
   end subroutine
   !
#if !defined _io_lib
   !
   subroutine PAR_scheme_reset(PARs)
     type(PAR_scheme):: PARs
     call COMM_reset(PARs%COMM_i)
     call COMM_reset(PARs%COMM_a2a)
     call PP_indexes_reset(PARs%IND)
     YAMBO_FREE(PARs%table)
     PARs%D    = 0
     PARs%N_ser= 0
     PARs%N_par= 0
     PARs%ID   = -1
     PARs%consecutive= .FALSE.
   end subroutine
   !
   subroutine COMM_copy(COMM_in,COMM_out)
     type(yMPI_comm):: COMM_in,COMM_out
     COMM_out%n_CPU      =COMM_in%n_CPU
     COMM_out%my_CHAIN   =COMM_in%my_CHAIN
     COMM_out%chain_order=COMM_in%chain_order
     COMM_out%COMM       =COMM_in%COMM
     COMM_out%CPU_ID     =COMM_in%CPU_ID
   end subroutine
   !
   subroutine PAR_INDEX_copy(IND_in,IND_out)
     type(PP_indexes):: IND_in,IND_out
     integer :: dim_
     if (allocated(IND_in%n_of_elements)) then
       dim_=size(IND_in%n_of_elements)
       YAMBO_ALLOC(IND_out%n_of_elements,(dim_))
       IND_out%n_of_elements=IND_in%n_of_elements
     endif
     if (allocated(IND_in%element_1D)) then
       dim_=size(IND_in%element_1D)
       YAMBO_ALLOC(IND_out%element_1D,(dim_))
       IND_out%element_1D=IND_in%element_1D
     endif
     if (allocated(IND_in%weight_1D)) then
       dim_=size(IND_in%weight_1D)
       YAMBO_ALLOC(IND_out%weight_1D,(dim_))
       IND_out%weight_1D=IND_in%weight_1D
     endif
     if (allocated(IND_in%first_of_1D)) then
       dim_=size(IND_in%first_of_1D)
       YAMBO_ALLOC(IND_out%first_of_1D,(dim_))
       IND_out%first_of_1D=IND_in%first_of_1D
     endif
     if (allocated(IND_in%last_of_1D)) then
       dim_=size(IND_in%last_of_1D)
       YAMBO_ALLOC(IND_out%last_of_1D,(dim_))
       IND_out%last_of_1D=IND_in%last_of_1D
     endif
   end subroutine
   !
   subroutine PP_indexes_reset(IND_out)
     type(PP_indexes)::IND_out
     YAMBO_FREE(IND_out%element_1D)
     YAMBO_FREE(IND_out%element_2D)
     YAMBO_FREE(IND_out%weight_1D)
     YAMBO_FREE(IND_out%n_of_elements)
     YAMBO_FREE(IND_out%first_of_1D)
     YAMBO_FREE(IND_out%last_of_1D)
   end subroutine
#endif
   !
   subroutine CREATE_hosts_COMM( )
#if defined _MPI
     use LexicalSort,  ONLY:ch_sort
     character (MPI_MAX_PROCESSOR_NAME), pointer :: tmp_hosts(:)
     integer :: i_err,i_cpu
#endif
     !
     if (ncpu==1) then
       call igethname(host_name,host_name_length)
       return
     endif
     !
#if defined _MPI
     !
     allocate(tmp_hosts(0:ncpu-1))
     !
     call MPI_GET_PROCESSOR_NAME(tmp_hosts(myid),host_name_length,i_err)
     host_name=tmp_hosts(myid)
     !
     do i_cpu=0,ncpu-1
       call MPI_BCAST(tmp_hosts(i_cpu),MPI_MAX_PROCESSOR_NAME,MPI_CHARACTER,i_cpu,MPI_COMM_WORLD,i_err)
     end do
     !
     call ch_sort(tmp_hosts)
     !
     ! assign the same color to the same node
     PAR_COM_HOST%my_CHAIN=0
     do i_cpu=1,ncpu-1
       if ( trim(tmp_hosts(i_cpu-1))/=trim(tmp_hosts(i_cpu)) ) PAR_COM_HOST%my_CHAIN=PAR_COM_HOST%my_CHAIN+1
       if ( trim(host_name)==tmp_hosts(i_cpu) ) exit
    end do
    !
    call MPI_COMM_SPLIT(MPI_COMM_WORLD,PAR_COM_HOST%my_CHAIN,myid,PAR_COM_HOST%COMM,i_err)
    call MPI_COMM_RANK(PAR_COM_HOST%COMM,PAR_COM_HOST%CPU_id,i_err)
    call MPI_COMM_SIZE(PAR_COM_HOST%COMM,PAR_COM_HOST%n_CPU ,i_err)
    !
    deallocate(tmp_hosts)
#endif
   end subroutine CREATE_hosts_COMM
   !
end module parallel_m
