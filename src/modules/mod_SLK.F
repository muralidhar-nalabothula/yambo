!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AM, AF
! 
! This file is distributed under the terms of the GNU 
! General Public License. You can redistribute it and/or 
! modify it under the terms of the GNU General Public 
! License as published by the Free Software Foundation; 
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will 
! be useful, but WITHOUT ANY WARRANTY; without even the 
! implied warranty of MERCHANTABILITY or FITNESS FOR A 
! PARTICULAR PURPOSE.  See the GNU General Public License 
! for more details.
!
! You should have received a copy of the GNU General Public 
! License along with this program; if not, write to the Free 
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
module SLK_m
 !
 use parallel_m, ONLY  : MPI_comm
 !
 implicit none
 !
 integer              :: n_pools = 1 ! number of pools
 !
 ! SLK test
 !
 integer              :: SLK_test_H_dim=1
 !
 ! POOL type
 !===========
 type POOL_group
   integer :: CPU_id      = 0  ! index of the processor within a pool 
   integer :: ID          = 0  ! index of my pool
   integer :: n_CPU       = 1  ! number of processors within a pool
   integer :: INTER_comm  = 0  ! inter pool communicator
   integer :: INTRA_comm  = 0  ! intra pool communicator
 end type POOL_group
 ! 
 ! BLACS Ortho group
 !===================
 type ORTHO_group 
   INTEGER :: grid(2) = 1        ! size of the processor grid used in ortho
   INTEGER :: coordinate(2) = 0  ! coordinates of the processors
   INTEGER :: task   = 0         ! task id for the ortho group
   INTEGER :: n_CPU = 1          ! size of the ortho group:
   INTEGER :: leg   = 1          ! the distance in the father communicator
                                 ! of two neighbour processors in ortho_comm
   INTEGER :: COMM  = 0          ! communicator for the ortho group
   INTEGER :: ROW_comm  = 0      ! communicator for the ortho row group
   INTEGER :: COL_comm  = 0      ! communicator for the ortho col group
   INTEGER :: COMM_id   = 0      ! id of the ortho_comm
   !
   INTEGER :: BLACS_id   =  0    ! BLACS processor index starting from 0
   INTEGER :: BLACS_np   =  1    ! BLACS number of processor
   INTEGER :: world_cntx = -1    ! BLACS context of all processor 
   INTEGER :: ortho_cntx = -1    ! BLACS context for ortho_comm
 end type ORTHO_group
 !
 ! Specific SLK worlds ...
 !========================
 !
 type(POOL_group ),SAVE :: SLK_INV_pool
 type(ORTHO_group),SAVE :: SLK_INV_ortho
 !
 type(POOL_group ),SAVE :: SLK_DIAGO_pool
 type(ORTHO_group),SAVE :: SLK_DIAGO_ortho
 !
 type(MPI_comm),SAVE    :: SLK_COM_INDEX(2)
 type(MPI_comm),SAVE    :: SLK_COM_A2A(2)
 !
end module SLK_m