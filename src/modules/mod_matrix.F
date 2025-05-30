!
! License-Identifier: GPL
!
! Copyright (C) 2017 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
module matrix
 !
 use pars,       ONLY:schlen,SP
 use parallel_m, ONLY:yMPI_comm
 use devxlib,    ONLY:devxlib_mapped,devxlib_memset_d
 !
#include<dev_defs.h>
#include<y_memory.h>
 !
 ! Distributed Matrix structure
 !
 integer, parameter   :: desc_len= 9
 logical              :: I_do_RCV=.TRUE.
 logical              :: I_do_SND=.TRUE.
 type(yMPI_comm)       :: TRANSFER_world
 !
 ! PAR to PAR special COMMs
 !
 integer              :: N_MAX_PAR_to_PAR_comms=0
 integer              :: N_PAR_to_PAR_comms    =0
 character(schlen)    :: PAR_to_PAR_comm_NAME
 type(yMPI_comm),   allocatable  :: PAR_to_PAR_comm_SAVE(:)
 character(schlen), allocatable  :: PAR_to_PAR_comm_SAVE_NAME(:)
 !
 type PAR_matrix
   !
   character(3) :: kind   ! "PAR" "SLK" "XUP" "XDN" "SER"
   !
   ! Dimensions
   integer :: I           ! Block element
   integer :: N           ! Global dimension (Parent Matrix)
   integer :: rows(2)     ! Real
   integer :: cols(2)     !
   integer :: nrows       ! 
   integer :: ncols       ! 
   !
   ! BLACS
   integer :: BLCnrows    ! Dimension of the BLACS matrix (in general larger then the Real's)
   integer :: BLCncols    !
   integer :: BLCrows(2)  ! Dimension of the BLACS matrix (in general larger then the Real's)
   integer :: BLCcols(2)  !
   integer :: desc(desc_len)
   integer :: lwork
   integer :: lrwork
   integer :: liwork
   integer :: info
   !
   ! COMMs
   type(yMPI_comm) :: INTRA_comm
   type(yMPI_comm) :: INTER_comm 
   !
   ! DATA
   integer :: Nb          ! # of Blocks
   complex(SP), allocatable DEV_PINNED :: blc(:,:,:)         ! pinned host var if CUDA
   complex(SP), allocatable DEV_ATTR   :: blc_d(:,:,:)       ! device var if CUDA
   !
 end type PAR_matrix 
 !
 contains
   !
   subroutine MATRIX_copy(M_in,M_out,ALLOC)
     use pars,          ONLY:cZERO
     use gpu_m,         ONLY:have_gpu
     type(PAR_matrix)   :: M_in,M_out
     logical            :: ALLOC
     integer            :: NW
     !
     !DEV_ACC enter data copyin(M_out)
     M_out%kind       = M_in%kind
     M_out%I          = M_in%I   
     M_out%N          = M_in%N   
     M_out%rows       = M_in%rows
     M_out%cols       = M_in%cols
     M_out%nrows      = M_in%nrows
     M_out%ncols      = M_in%ncols
     M_out%BLCrows    = M_in%BLCrows
     M_out%BLCcols    = M_in%BLCcols
     M_out%BLCnrows   = M_in%BLCnrows
     M_out%BLCncols   = M_in%BLCncols
     M_out%desc       = M_in%desc
     M_out%lwork      = M_in%lwork
     M_out%lrwork     = M_in%lrwork
     M_out%liwork     = M_in%liwork
     M_out%info       = M_in%info
     M_out%Nb         = M_in%Nb  
     M_out%INTER_comm = M_in%INTER_comm
     M_out%INTRA_comm = M_in%INTRA_comm
     !
     if (.not.ALLOC) return
     if (allocated(M_in%blc)) then
       NW=size(M_in%blc,3)
       YAMBO_ALLOC(M_out%blc,(M_out%rows(1):M_out%rows(2),M_out%cols(1):M_out%cols(2),NW))
       M_out%blc=cZERO
     endif
     if (have_gpu.and.devxlib_mapped(DEV_VAR(M_in%blc))) then
       YAMBO_ALLOC_GPU(DEV_VAR(M_out%blc),(M_out%rows(1):M_out%rows(2),M_out%cols(1):M_out%cols(2),NW))
       call devxlib_memset_d(DEV_VAR(M_out%blc),cZERO)
     endif
     !
   end subroutine 
   !
   subroutine MATRIX_reset(M_par)
     use parallel_m, ONLY:COMM_reset
     type(PAR_matrix)   :: M_par
     !
     M_par%kind       = "NAN"
     !
     M_par%I          = 1
     M_par%N          = -1
     M_par%rows       = (/0,-1/)
     M_par%cols       = (/0,-1/)
     M_par%nrows      = -1
     M_par%ncols      = -1
     !
     M_par%BLCrows    = (/0,-1/)
     M_par%BLCcols    = (/0,-1/)
     M_par%BLCnrows   = -1
     M_par%BLCncols   = -1
     M_par%desc       = 0
     M_par%lwork      = -1
     M_par%lrwork     = -1
     M_par%liwork     = -1
     M_par%info       = -1
     !
     M_par%Nb         = 1
     !
     call COMM_reset(M_par%INTER_comm)
     call COMM_reset(M_par%INTRA_comm)
     !
     YAMBO_FREE_GPU(DEV_VAR(M_par%blc))
     YAMBO_FREE(M_par%blc)
     !
     !DEV_ACC exit data delete(M_par)
     !
   end subroutine
   !
end module matrix
