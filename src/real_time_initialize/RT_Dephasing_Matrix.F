!
! License-Identifier: GPL
!
! Copyright (C) 2011 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine RT_Dephasing_Matrix(E)
 !
 use pars,          ONLY:SP
 use units,         ONLY:FS2AUT
 use com,           ONLY:msg
 use electrons,     ONLY:levels
 use R_lattice,     ONLY:nXkibz
 use real_time,     ONLY:RT_Deph_Matrix,RT_is_statically_dephased,Phase_LifeTime,&
&                        RAD_LifeTime,RT_bands,RT_INPUT_Deph_limits,RT_deph_cv_only, &
&                        RT_deph_deg_thresh
 !
#include<y_memory.h>
 !
 type(levels), intent(in) :: E
 !
 ! Work Space
 !
 logical :: Matr_Deph
 integer :: ik,ib_1,ib_2,i1
 real(SP), parameter   :: thresh=1.E-5_SP
 !
 ! %DephMatrix fields
 !
 if ( .not. (allocated(RT_INPUT_Deph_limits) .or. (RAD_LifeTime>thresh) .or. (Phase_LifeTime>thresh) .or. allocated(E%W) ) ) return
 !
 YAMBO_ALLOC(RT_Deph_Matrix,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),nXkibz))
 !
 RT_Deph_Matrix=(0._SP,0._SP)
 !
 RT_is_statically_dephased=.TRUE.
 !
 ! DIAGONAL or DEGENERATE SPACE 
 !==============================
 !
 if (RAD_LifeTime > thresh) then
   !
   call msg('rs','[RT] External scalar Radiative Scattering lifetime applied')
   !
   do ik=1,nXkibz
     do ib_1=RT_bands(1),RT_bands(2)
       do ib_2=ib_1,RT_bands(2)
         if ( abs(E%E(ib_1,ik,1)-E%E(ib_2,ik,1))>=RT_deph_deg_thresh ) cycle
         RT_Deph_Matrix(ib_1,ib_2,ik)=1._SP/RAD_LifeTime
         RT_Deph_Matrix(ib_2,ib_1,ik)=1._SP/RAD_LifeTime
       enddo
     enddo
   enddo
   !
 endif
 !
 ! OFF-DIAGONAL and NON-DEGENERATE SPACE
 !=======================================
 !
 if (Phase_LifeTime > thresh) then
   !
   ! Scalar Phase value
   !--------------------
   !
   call msg('rs','[RT] External Scalar Dephasing applied')
   !
   do ik=1,nXkibz
     do ib_1=RT_bands(1),RT_bands(2)
       do ib_2=ib_1+1,RT_bands(2)
         if ( abs(E%E(ib_1,ik,1)-E%E(ib_2,ik,1))<RT_deph_deg_thresh ) cycle
         if ( (ib_1> E%nbf(1) .or. ib_2<=E%nbf(1)) .and. RT_deph_cv_only )  cycle
         RT_Deph_Matrix(ib_1,ib_2,ik)=1._SP/Phase_LifeTime
         RT_Deph_Matrix(ib_2,ib_1,ik)=1._SP/Phase_LifeTime
       enddo
     enddo
   enddo
   !
 endif
 !
 if (allocated(RT_INPUT_Deph_limits)) then
   !
   Matr_Deph=.true.
   if (any(RT_INPUT_Deph_limits(:,4)<0._SP)) Matr_Deph =.false.
   !
   ! Convert fs to atomic units
   !
   RT_INPUT_Deph_limits(:,4)=RT_INPUT_Deph_limits(:,4)*FS2AUT
   !
   if(Matr_Deph) then
     !
     ! Non null %DephMatrix fields
     !------------------------------
     call msg('rs','[RT] External Matricial Dephasing applied')
     !
     do i1=1,size(RT_INPUT_Deph_limits,1)
       ib_1=int(RT_INPUT_Deph_limits(i1,1))
       ib_2=int(RT_INPUT_Deph_limits(i1,2))
       ik=int(RT_INPUT_Deph_limits(i1,3))
       if(any((/ib_1,ib_2/)>RT_bands(2)).or.any((/ib_1,ib_2/)<RT_bands(1))) then
         call warning("DephMatrix indexes out of the range. Ignoring wrong band   assignment") 
         cycle
       endif
       if(ik<=0.or.ik>nXkibz) then
         call warning("DephMatrix indexes out of the range. Ignoring wrong kpoint assignment") 
         cycle
       endif
       if ( abs(E%E(ib_1,ik,1)-E%E(ib_2,ik,1))<RT_deph_deg_thresh ) cycle
       if ( (ib_1> E%nbf(1) .or. ib_2<=E%nbf(1)) .and. RT_deph_cv_only )  cycle
       RT_Deph_Matrix(ib_1,ib_2,ik)  =RT_Deph_Matrix(ib_1,ib_2,ik)+1._SP/RT_INPUT_Deph_limits(i1,4)
       RT_Deph_Matrix(ib_2,ib_1,ik)  =RT_Deph_Matrix(ib_2,ib_1,ik)+1._SP/RT_INPUT_Deph_limits(i1,4)
     enddo
     !
   endif
   !
   YAMBO_FREE(RT_INPUT_Deph_limits)
   !
 endif
 !
 if (allocated(E%W)) then
   !
   ! QP database 
   !-------------
   !
   call msg('rs','[RT] Quasiparticle Dephasing applied')
   !
   do ik=1,nXkibz
     do ib_1=RT_bands(1),RT_bands(2)
       do ib_2=ib_1+1,RT_bands(2)
         if ( abs(E%E(ib_1,ik,1)-E%E(ib_2,ik,1))<RT_deph_deg_thresh ) cycle
         if ( (ib_1> E%nbf(1) .or. ib_2<=E%nbf(1)) .and. RT_deph_cv_only )  cycle
         RT_Deph_Matrix(ib_1,ib_2,ik)=RT_Deph_Matrix(ib_1,ib_2,ik)+(abs(E%W(ib_1,ik,1))+abs(E%W(ib_2,ik,1)))
         RT_Deph_Matrix(ib_2,ib_1,ik)=RT_Deph_Matrix(ib_2,ib_1,ik)+(abs(E%W(ib_1,ik,1))+abs(E%W(ib_2,ik,1)))
       enddo     
       !
     enddo
   enddo
   !
 endif
 !
end subroutine
