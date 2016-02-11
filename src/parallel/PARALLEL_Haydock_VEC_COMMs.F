!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): MG, DS
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
subroutine PARALLEL_Haydock_VEC_COMMs(what)
 !
 ! Set up the mask and communicators for the Haydock part.  
 !
 use BS,          ONLY:BS_nT_grps,n_BS_blks,BS_blk
 use parallel_m,  ONLY:myid,mpi_comm_world,PAR_IND_T_groups,PAR_IND_T_Haydock,&
&                      PAR_COM_T_Haydock,ncpu
 !
 implicit none
 !
 character(*),       intent(in) :: what     
 !
 ! Work Space
 !
 integer :: i_g,i_err,i_b,iT_grp_k,iT_grp_p
 integer :: local_key
 !
 select case (what)
   case('assign')
     !
#if defined _MPI
     !
     !allocate(PAR_IND_T_Haydock%element_1D(BS_nT_grps))
     !
     !PAR_IND_T_Haydock%element_1D = .false.
     !do i_b=1,n_BS_blks
     !  iT_grp_k = BS_blk(i_b)%iT_k
     !  iT_grp_p = BS_blk(i_b)%iT_p
     !  PAR_IND_T_Haydock%element_1D(iT_grp_k)=.true.
     !  PAR_IND_T_Haydock%element_1D(iT_grp_p)=.true.
     !end do
     !
     ! Communicators along each groups (this will be row of the _full_ matrix)
     ! Needed in distributed M|V> and <V|W> (redux) and |Vn> initialization (bcast)
     ! Notice that here I need one different communicator for each group becasue
     ! the distribution of the groups is derived from the distribution of the matrix
     ! elements
     !
     allocate( PAR_COM_T_Haydock(BS_nT_grps))
     PAR_COM_T_Haydock(:)%n_CPU=0
     PAR_COM_T_Haydock(:)%chain_order=0
     !
     do i_g=1,BS_nT_grps
       !
       if (.not.PAR_IND_T_Haydock%element_1D(i_g)) then
         local_key=-1
         PAR_COM_T_Haydock(i_g)%my_chain=BS_nT_grps+1
       else
         !
         !local_key=myid
         local_key = 1
         if (PAR_IND_T_groups%element_1D(i_g)) local_key = 0
         !
         PAR_COM_T_Haydock(i_g)%n_CPU=PAR_COM_T_Haydock(i_g)%n_CPU+1
         PAR_COM_T_Haydock(i_g)%my_chain = i_g
         !
       endif
       !
       call MPI_COMM_SPLIT(mpi_comm_world,PAR_COM_T_Haydock(i_g)%my_chain,local_key,PAR_COM_T_Haydock(i_g)%COMM,i_err)
       call MPI_COMM_RANK(PAR_COM_T_Haydock(i_g)%COMM,PAR_COM_T_Haydock(i_g)%CPU_id,i_err)
       !
     enddo
     !
#else
     !
     return
     !
#endif
     !
     case('reset')
       !
#if defined _MPI
       do i_g=1,BS_nT_grps
         call MPI_Comm_free(PAR_COM_T_Haydock(i_g)%COMM)
       enddo
       deallocate(PAR_COM_T_Haydock)
#endif
       ! This is allocated in K_Transitions setup
       deallocate(PAR_IND_T_Haydock%element_1D)
       !
   end select
   !
end subroutine PARALLEL_Haydock_VEC_COMMs