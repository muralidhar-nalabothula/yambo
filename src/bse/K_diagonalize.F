!
! License-Identifier: GPL
! Copyright (C) 2024 The Yambo Team
!
subroutine K_diagonalize(i_BS_mat, BS_energies, BS_VR, &
    & neigs_this_cpu, neig_shift, neigs_range, eigvals_range, &
    & BS_VL, BS_overlap, solver_type, elpasolver)
  !
  ! Here We diagonalize any BSE hamilitioan
  !
  !      | (K_r)     (cI*K_c)    |  
  !  K = |                       |
  !      | (-cI*K_c^*)  (-K_r^*) |
  !
  !  This total number of eigenvectors found can be obtained by
  !  by calling size function of eigvals i.e size(BS_energies)
  use pars,           ONLY:cI,cONE, SP
  use BS,             ONLY:BS_K_dim,BS_H_dim,BS_blk,n_BS_blks,BS_K_coupling,&
    &                        BS_res_ares_n_mat,l_BS_ares_from_res
  use BS_solvers,     ONLY:BSS_eh_E,BSS_eh_W,BSS_perturbative_width
  use cuda_m,         ONLY:have_cuda
  use parallel_m,     ONLY:MPI_COMM_WORLD,par_distribute_set
  use openmp,         ONLY:n_threads_K
  use LIVE_t,         ONLY:live_timing
  use com,            ONLY:msg
  use YDIAGO_interface
  !
  implicit none
  !
  integer, intent(in)      :: i_BS_mat
  complex(SP), allocatable :: BS_energies(:)
  ! Energy values. these will be allocated internally.(realloced if already allocated)
  ! Each cpu gets full set of eigenvalues and size(BS_energies) gives 
  ! total number of eigenvectors found (will be same on all processes).
  complex(SP), allocatable, target :: BS_VR(:,:) 
  ! Right eigenvectors. these will be allocated internally (realloced if allocated)
  ! This process store eigenvectors from [neig_shift+1, neigs_this_cpu+neig_shift]
  integer, intent(out)     :: neigs_this_cpu  
  integer, intent(out)     :: neig_shift
  !
  ! optional arguments  
  integer, optional, target          :: neigs_range(2)
  ! index range of eigen values (input)
  real(SP), optional, target         :: eigvals_range(2)
  ! value range of eigenvalues (input)
  complex(SP), allocatable, optional, target :: BS_VL(:,:) 
  ! Left eigenvectors. these will be allocated internally (input) !(realloced if already allocated)
  character, optional                :: solver_type   ! if 'e' uses elpa, 's' scalapack
  ! SOlver to use Elpa or scalapack (input)
  integer,  optional                 :: elpasolver
  ! 1 or 2. put 2 as default and give an option to user (input)
  complex(SP),pointer,optional       :: BS_overlap(:,:) ! overlap matrix
  ! Note Overlap matrix is allocated and computed only when geev solver is called.
  ! If overlap matrix is not allocated, this implies that BS_overlap is a identity matrix.
  !
  ! FIX ME : Move to a better place (modules)
  integer, parameter                 :: blacs_block_size = 64
  ! blacs block size
  ! 64 is good default but give a variable so advanced expert users can play with it
  !
  ! Local variables
  type(c_ptr)                        :: mpicxt, diago_mat, evecs
  integer                            :: nProcs, my_rank, blacs_blk_size
  integer(YDIAGO_INT)                :: SL_H_dim, ProcX, ProcY, elpa_nthreads
  integer(ERROR_INT)                 :: error_diago ! diagonalization error code
  integer                            :: ierr, i_c, i_r !! mpi error code 
  integer(YDIAGO_INT)                :: neig_found
  integer(YDIAGO_LL_INT)             :: nelements
  ! optional local vars with their defaults
  character                          :: solver_type_aux   = 's'
  integer(YDIAGO_INT)                :: elpa_solver_aux   = 2
  type(c_ptr)                        :: neigs_range_tmp   = c_null_ptr
  type(c_ptr)                        :: eigvals_range_tmp = c_null_ptr
  type(c_ptr)                        :: evecs_left        = c_null_ptr
  logical                            :: compute_left_eigs = .false.
  complex(YDIAGO_CMPLX), target, allocatable :: eig_vals(:)
  !
  ! Gpu support via ELPA.
  type(c_ptr)                             :: gpu_str = c_null_ptr
  character(kind=c_char, len=20), target  :: gpu_device_elpa
  !// Accpeted values for gpu_device_elpa : "nvidia-gpu", "amd-gpu", "intel-gpu"

  integer                            :: evec_fac = 1
  ! evec_fac = 2 if bse_solver function was used to diagonalize else 1

  if(present(neigs_range)) neigs_range_tmp = c_loc(neigs_range)
  if(present(eigvals_range)) eigvals_range_tmp = c_loc(eigvals_range)
  if(present(BS_VL)) compute_left_eigs = .true.
  if(present(solver_type)) solver_type_aux = solver_type
  if(present(elpasolver)) elpa_solver_aux = elpasolver


if (have_cuda) then
  ! Note this is a gpu specific flag. set according to gpu.
  ! Accpeted values for gpu_device_elpa : "nvidia-gpu", "amd-gpu", "intel-gpu"
  ! As yambo supports only nvidia gpus, we set it to nvidia-gpu for now
  gpu_device_elpa =  c_char_"nvidia-gpu"//c_null_char
  gpu_str = c_loc(gpu_device_elpa)
endif

#if defined _OPENMP
  elpa_nthreads = int(n_threads_K,kind=YDIAGO_INT)
#else 
  elpa_nthreads = 1 
#endif
  ! Start the function
  !
  if(     BS_K_coupling) SL_H_dim=BS_H_dim
  if(.not.BS_K_coupling) SL_H_dim=BS_K_dim(i_BS_mat)
  !
  ! Allocate the 2D block cyclic matrix
  !
  ! First create a blacs grid
  call MPI_COMM_SIZE(MPI_COMM_WORLD, nProcs, ierr)
  call MPI_COMM_RANK(MPI_COMM_WORLD, my_rank, ierr)

  ProcX = int(sqrt(real(nProcs)),kind=YDIAGO_INT)
  ProcY = ProcX
  ! Maximize the number of cpus participating
  if ( ProcX * (ProcX + 1) .le. nProcs) ProcY = ProcX + 1
  if ( ProcX * (ProcX + 2) .le. nProcs) ProcY = ProcX + 2
  ! Geev block size must be smaller than mat dim and >=8
  ! Start with the default 64
  blacs_blk_size = blacs_block_size
  ! if not try 32
  if (blacs_blk_size .gt. SL_H_dim/ProcY) blacs_blk_size = blacs_blk_size/2
  ! if not try 16
  if (blacs_blk_size .gt. SL_H_dim/ProcY) blacs_blk_size = blacs_blk_size/2
  ! Last try.
  if (blacs_blk_size .gt. SL_H_dim/ProcY) then
    ! force the solver to be scalapack
    ! If block size is <8, geev solver will fail.
    solver_type_aux = 's'
    blacs_blk_size = SL_H_dim
    ProcX = 1
    ProcY = 1
  endif
  
  call msg("s","BLACS grid",(/ProcX,ProcY/))

  mpicxt = BLACScxtInit_Fortran('R', MPI_COMM_WORLD, ProcX, ProcY)
  if (.not. c_associated(mpicxt)) then
    call error("Failed to initiate BLACS context")
  end if

  diago_mat = init_D_Matrix(SL_H_dim, SL_H_dim, blacs_blk_size, blacs_blk_size, mpicxt)
  if (.not. c_associated(diago_mat)) then
    call error("Failed to initiate block cyclic BSE matrix")
  end if
  !
  ! Fill the block cyclic matrix
  call live_timing('Filling BSE Matrix',1)
  call K_fill_block_cyclic(i_BS_mat, diago_mat)
  call live_timing()
  ! Now we create a matix for eigenvectors
  !
  allocate(eig_vals(SL_H_dim))

  evecs = init_D_Matrix(SL_H_dim, SL_H_dim, blacs_blk_size, blacs_blk_size, mpicxt)
  if (.not. c_associated(evecs)) then
    call error("Failed to initiate eigenvectors for block cyclic BSE matrix")
  end if
  !
  ! Allocate left eigenvectors only incase requested
  if (compute_left_eigs) then 
    !
    if (.not. l_BS_ares_from_res .and. BS_K_coupling) then
      !
      evecs_left = init_D_Matrix(SL_H_dim, SL_H_dim, blacs_blk_size, blacs_blk_size, mpicxt)
      !
      if (.not. c_associated(evecs_left)) then
        call error("Failed to initiate left eigenvectors for block cyclic BSE matrix")
      end if
      !
    endif
    !
  endif
  !
  if (solver_type_aux .eq. 'e') then
    !
    call section('=','ELPA Diagonalization')
    !
  else
    !
    call section('=','Scalapack Diagonalization')
    !
  endif
  !
  ! Call the solvers
  ! 
  neig_found = SL_H_dim ! This will be modified by scalapack functions
  evec_fac = 1 ! This is important set to 1
  !
  call live_timing('BSK diagonalize',1)
  if (.not. BS_K_coupling) then
    !
    ! ===========  TDA Case ===============
#if defined _ELPA
    if (solver_type_aux .eq. 'e') then
      !
      if(present(neigs_range))  neig_found = abs(max(neigs_range))
      !
      error_diago = Heev_Elpa(diago_mat, c_loc(eig_vals), evecs, neig_found, elpa_solver_aux, gpu_str, &
        &           elpa_nthreads)
    else
      error_diago = Heev(diago_mat, 'L', neigs_range_tmp, eigvals_range_tmp, c_loc(eig_vals), evecs, neig_found)
    endif
#else 
    error_diago = Heev(diago_mat, 'L', neigs_range_tmp, eigvals_range_tmp, c_loc(eig_vals), evecs, neig_found)
#endif
    !
    !
  else if (l_BS_ares_from_res.and.BS_K_coupling) then
    !
    ! =========  Non-TDA when Anti-res = -conj(res) ==========
    !
    !       // https://doi.org/10.1016/j.laa.2015.09.036
    !     Eigen values come in pair i.e (-lambda, lambda).
    !         Right eigenvectors         Left eigenvectors
    !           +ve     -ve               +ve       -ve
    !     X = [ X_1, conj(X_2) ]    Y = [  X_1, -conj(X_2)]
    !          [X_2, conj(X_1) ]        [ -X_2,  conj(X_1)],
    ! Note that the overlap matrix is identity in this case, so we donot construct
    !
    neig_found = SL_H_dim/2 ! Only +ve eigenvalues computes and rest are retreived
#if defined _ELPA
    if (solver_type_aux .eq. 'e') then
      ! Elpa always gives full spectrum
      error_diago = BSE_Solver_Elpa(diago_mat, c_loc(eig_vals), evecs, elpa_solver_aux, gpu_str, &
        &           elpa_nthreads) 
    else 
      !
      error_diago = BSE_Solver(diago_mat, neigs_range_tmp, eigvals_range_tmp, c_loc(eig_vals), evecs, neig_found)
      !
    endif
#else 
    error_diago = BSE_Solver(diago_mat, neigs_range_tmp, eigvals_range_tmp, c_loc(eig_vals), evecs, neig_found)
#endif
    !
    ! Incase of Chosleky failure (due to not being +ve definite, fall back to Geev solver)
    ! -50 is the error code when CHOLESKY factorization fails. see Ydiago/src/common/error.h
    if (error_diago == -50) then
      !
      call msg("s", 'Warning : Cholesky decomposition failed. &
        & Switching to slow scalapack solver. This solver is not-GPU supported.')
      !
      if (compute_left_eigs .and. .not. c_associated(evecs_left)) then 
        ! initiate left eigenvectors in case not
        evecs_left = init_D_Matrix(SL_H_dim, SL_H_dim, blacs_blk_size, blacs_blk_size, mpicxt)
        if (.not. c_associated(evecs_left)) then
          call error("Failed to initiate left eigenvectors for block cyclic BSE matrix")
        end if
        !
      endif
      !
      neig_found = SL_H_dim
      !
      if (blacs_blk_size .lt. 8 ) call error("Too small block size. User solver: o")
      ! NM : FIX ME : In this case, simply switch to lapack solver.
      error_diago = Geev(diago_mat, c_loc(eig_vals), evecs_left, evecs)
      !
      evec_fac = 1
    else 
      evec_fac = 2
    endif
    !
    !
  else 
    ! 
    ! ========== General solver =================
    neig_found = SL_H_dim
    !
    if (blacs_blk_size .lt. 8 ) call error("Too small block size. User solver: o")
  ! NM : FIX ME : In this case, simply switch to lapack solver.
    error_diago = Geev(diago_mat, c_loc(eig_vals), evecs_left, evecs)
    ! On output diago_mat has overlap i.e VL^H @ VR
    !
  endif

  if (error_diago /= 0) call error("Diagonalization failed")
  call live_timing()

  if(allocated(BS_energies)) deallocate(BS_energies)
  ! 
  allocate(BS_energies(neig_found*evec_fac))
  !
  BS_energies(1:neig_found*evec_fac:evec_fac) = eig_vals(1:neig_found)
  
  if (evec_fac == 2) then 
    ! set -ve values in case of special solver
    BS_energies(2:neig_found*evec_fac:2) = -eig_vals(1:neig_found)
  endif
  !
  deallocate(eig_vals)
  !
  !call section('=','Folding eigenvectors')
  ! Now retreive the right eigen_vectors
  !
  ! Compute number of right eigenvectors residing in this cpu
  ! neigs_this_cpu, neig_shift
  call par_distribute_set(neig_found, neigs_this_cpu, neig_shift)

  ! Retreive inverse of overlap matrix if case geev is used. (VL^H @ VR)^-1
  ! As mentioned above, in all other cases overlap is identity
  if (evec_fac == 1 .and. BS_K_coupling .and. present(BS_overlap)) then
    call live_timing('Retrieving Overlap',1)
    if (.not. associated(BS_overlap)) allocate(BS_overlap(neig_found,neigs_this_cpu))
    !
    nelements = neig_found*neigs_this_cpu
    ! Compute inverse of Overlap matrix (inplace operation)
    error_diago = Inverse_Dmat(diago_mat)
    if (error_diago /= 0) call error("Inversion of overlap matrix Failed.")
    !
    ! Now retreive
    error_diago = initiateGetQueue(diago_mat, nelements)
    if (error_diago /= 0) call error("Failed to initiate overlap GetQueue.")
    !
    ! get the overlap matrix. The overlap matrix is distributed along the right eigenvectors
    do i_c = 1, neigs_this_cpu
      do i_r = 1, neig_found
        error_diago = dmatget_fortran(diago_mat, i_r, i_c + neig_shift, c_loc(BS_overlap(i_r, i_c)) )
        if (error_diago /= 0) call error("Failed to retreive overlap matrix from distributed matrix.")
      enddo
    enddo
    ! finalize the queue
    error_diago = ProcessGetQueue(diago_mat)
    if (error_diago /= 0) call error("Failed to Process overlap matrix GetQueue.")
    call live_timing()
  else 
    if (present(BS_overlap)) BS_overlap => null()
  endif

  ! Free the space of the distributed matrix 
  call free_D_Matrix(diago_mat)

  nelements = neigs_this_cpu*SL_H_dim
  !
  if(allocated(BS_VR)) deallocate(BS_VR)
  !
  allocate(BS_VR(SL_H_dim, evec_fac*neigs_this_cpu))
  !
  ! retreive right eigenvectors
  ! initiate get queue
  call live_timing('Retrieving Right eigenvectors',1)
  error_diago = initiateGetQueue(evecs, nelements)
  if (error_diago /= 0) call error("Failed to initiate GetQueue")
  !
  ! request the right eigenvectors
  do i_c = 0, neigs_this_cpu-1
    do i_r = 1, SL_H_dim
      error_diago = dmatget_fortran(evecs, i_r, i_c + neig_shift + 1, c_loc(BS_VR(i_r, evec_fac*i_c + 1)) )
      if (error_diago /= 0) call error("Failed to retreive eigenvectors from distributed matrix")
    enddo
  enddo
  !
  ! finalize the queue. The eigenvectors buffer gets magically filled after this call !
  error_diago = ProcessGetQueue(evecs)
  if (error_diago /= 0) call error("Failed to Process GetQueue")
  ! we got the data ! Free right eigen-vectors.
  call free_D_Matrix(evecs)
  call live_timing()

  if (evec_fac == 2) then
    ! set the right eigenvectors for -ve eigenvalues
    BS_VR(1:SL_H_dim/2, 2:2*neigs_this_cpu:2)  = conjg(BS_VR(SL_H_dim/2 + 1:SL_H_dim, 1:2*neigs_this_cpu:2))
    BS_VR(SL_H_dim/2 + 1:SL_H_dim, 2:2*neigs_this_cpu:2) = conjg(BS_VR(1:SL_H_dim/2, 1:2*neigs_this_cpu:2))
  endif
  !
  ! Set the left eigen vectors in case requested
  if (BS_K_coupling .and. compute_left_eigs) then 
  !
    if(allocated(BS_VL)) deallocate(BS_VL)
    allocate(BS_VL(SL_H_dim, evec_fac*neigs_this_cpu))

    if (evec_fac  == 2) then 
      ! left eigen-vectors for +ve eigenvalues
      BS_VL(1:SL_H_dim/2, 1:2*neigs_this_cpu:2)            =  BS_VR(1:SL_H_dim/2, 1:2*neigs_this_cpu:2)
      BS_VL(SL_H_dim/2 + 1:SL_H_dim, 1:2*neigs_this_cpu:2) = -BS_VR(SL_H_dim/2 + 1:SL_H_dim, 1:2*neigs_this_cpu:2)
      ! left eigen-vectors for -ve eigenvalues
      BS_VL(1:SL_H_dim/2, 2:2*neigs_this_cpu:2)  = CONJG(BS_VL(SL_H_dim/2 + 1:SL_H_dim, 1:2*neigs_this_cpu:2))
      BS_VL(SL_H_dim/2 + 1:SL_H_dim, 2:2*neigs_this_cpu:2) = CONJG(BS_VL(1:SL_H_dim/2, 1:2*neigs_this_cpu:2))
    else 
      ! set the Queue for the left eigen vectors
      call live_timing('Retrieving Left eigenvectors',1)
      error_diago = initiateGetQueue(evecs_left, nelements)
      if (error_diago /= 0) call error("Failed to initiate left eigvec GetQueue")
      !
      ! request the left eigenvectors
      do i_c = 0, neigs_this_cpu-1
        do i_r = 1, SL_H_dim
          error_diago = dmatget_fortran(evecs_left, i_r, i_c + neig_shift + 1, c_loc(BS_VL(i_r, evec_fac*i_c + 1)) )
          if (error_diago /= 0) call error("Failed to retreive left eigenvectors from distributed matrix")
        enddo
      enddo
      ! finalize the queue
      error_diago = ProcessGetQueue(evecs_left)
      if (error_diago /= 0) call error("Failed to Process left eigen vectors GetQueue")
      call live_timing()
    endif
  !
  endif
  !
  ! Free remaining resources
  call free_D_Matrix(evecs_left)
  ! Free blacs context
  call BLACScxtFree(mpicxt)

  neigs_this_cpu = evec_fac*neigs_this_cpu
  neig_shift     = evec_fac*neig_shift
  !
end subroutine K_diagonalize 
