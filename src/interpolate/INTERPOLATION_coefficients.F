!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): CA DS
!
subroutine INTERPOLATION_coefficients(R1D,R2D,C1D,C2D,E,k,Nk,ID,ID_obj)
 !
 ! Notice that input/output k-points for the interpolation are in iku units
 !
 ! Also note that K index is the the second in R2D
 !
 use pars,              ONLY:SP
 use R_lattice,         ONLY:bz_samp
 use electrons,         ONLY:levels
 use interpolate,       ONLY:interpls,REAL1D,REAL2D,CMPLX1D,CMPLX2D,nshells,INTERP_FineGd
 use interpolate_tools, ONLY:get_ID
 !
#include<y_memory.h>
 !
 type(bz_samp), intent(in)           :: k
 real(SP),      intent(in), optional :: R1D(:,:),R2D(:,:,:)
 complex(SP),   intent(in), optional :: C1D(:,:),C2D(:,:,:)
 type(levels),  intent(in), optional :: E
 integer,       intent(in), optional :: Nk
 integer,       intent(in)           :: ID_obj
 integer,       intent(inout)        :: ID
 !
 ! Work Space
 !
 real(SP), allocatable :: RDATA(:,:)
 integer               :: inpdim(2),i1,i2,ik,Nk_local,ik_fg
 !
 call get_ID(ID)
 !
 if(     present(Nk)) Nk_local=Nk
 if(.not.present(Nk)) Nk_local=k%nibz
 !
 ! Set dimensions
 !
 if(present(R1D)) then
   !
   interpls(ID)%interp_type=REAL1D
   interpls(ID)%ndim       =size(R1D(:,1))
   !
 else if(present(C1D)) then
   !
   interpls(ID)%interp_type=CMPLX1D
   inpdim(1)               =size(C1D(:,1))
   interpls(ID)%ndim       =2*inpdim(1)
   !
 elseif(present(E)) then
   !
   interpls(ID)%interp_type=REAL2D
   inpdim(1)               =E%nb
   inpdim(2)               =size( E%E(1,1,:) )
   interpls(ID)%ndim       =inpdim(1)*inpdim(2)
   !
 elseif(present(R2D)) then
   !
   interpls(ID)%interp_type=REAL2D
   inpdim(1)               =size(R2D(:,1,1))
   inpdim(2)               =size(R2D(1,1,:))
   interpls(ID)%ndim       =inpdim(1)*inpdim(2)
   !
 elseif(present(C2D)) then
   !
   interpls(ID)%interp_type=CMPLX2D
   inpdim(1)               =size(C2D(:,1,1))
   inpdim(2)               =size(C2D(1,:,1))
   interpls(ID)%ndim       =2*inpdim(1)*inpdim(2)
   !
 endif
 !
 ! Allocations
 !
 YAMBO_ALLOC(interpls(ID)%engre,(nshells,interpls(ID)%ndim))
 if(.not.present(R1D)) then
   YAMBO_ALLOC(RDATA,(interpls(ID)%ndim,Nk_local))
 endif
 !
 ! Transfer to tmp arrays
 !
 if(present(C1D)) then
   !
   RDATA(1:inpdim(1),1:Nk_local)            = real(C1D(1:inpdim(1),1:Nk_local))
   RDATA(inpdim(1)+1:2*inpdim(1),1:Nk_local)=aimag(C1D(1:inpdim(1),1:Nk_local))
   !
 elseif(present(E)) then
   !
#if defined _RT
   if (allocated(E%FG%E).and.trim(INTERP_FineGd)=="BARE") then
     do i1=1,inpdim(2)
       do ik=1,k%nibz
         do ik_fg=k%FGbare%k_range(ik,1),k%FGbare%k_range(ik,2)
           RDATA((i1-1)*inpdim(1)+1:i1*inpdim(1),ik_fg)=E%FG%E(1:inpdim(1),ik_fg,i1)
         enddo
       enddo
     enddo 
   else
#endif
     do i1=1,inpdim(2)
       RDATA((i1-1)*inpdim(1)+1:i1*inpdim(1),1:Nk_local) = E%E(1:inpdim(1),1:Nk_local,i1)
     enddo
#if defined _RT
   endif
#endif
 elseif(present(R2D)) then
   !
   do i1=1,inpdim(2)
     RDATA((i1-1)*inpdim(1)+1:i1*inpdim(1),1:Nk_local)   = R2D(1:inpdim(1),1:Nk_local,i1)
   enddo
   !
 elseif(present(C2D)) then
   !
   do i1=1,inpdim(2)
     i2=i1+inpdim(2)
     RDATA((i1-1)*inpdim(1)+1:i1*inpdim(1),1:Nk_local) =  real(C2D(1:inpdim(1),i1,1:Nk_local))
     RDATA((i2-1)*inpdim(1)+1:i2*inpdim(1),1:Nk_local) = aimag(C2D(1:inpdim(1),i1,1:Nk_local))
   enddo
   !
 endif
 !
 ! Actual interpolation 
 !
 if(     present(R1D)) call INTERPOLATION_BZ_coeff(k,R1D  ,interpls(ID)%engre,interpls(ID)%ndim,Nk_local,ID_obj)
 if(.not.present(R1D)) call INTERPOLATION_BZ_coeff(k,RDATA,interpls(ID)%engre,interpls(ID)%ndim,Nk_local,ID_obj)
 !
 ! Free tmp array
 !
 if(.not.present(R1D)) then
   YAMBO_FREE(RDATA)
 endif
 !
end subroutine  INTERPOLATION_coefficients
