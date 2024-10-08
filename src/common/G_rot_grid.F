!
! License-Identifier: GPL
!
! Copyright (C) 2013 The Yambo Team
!
! Authors (see AUTHORS file for details): DS
!
subroutine G_rot_grid(is,call_kind)
 !
 use pars,         ONLY:SP
 use R_lattice,    ONLY:ng_vec,ng_closed,g_vec,minus_G
 use D_lattice,    ONLY:dl_sop,alat
 use zeros,        ONLY:G_iku_zero
 use vec_operate,  ONLY:v_is_zero
#include<y_memory.h>
 !
 integer               :: is
 character(*)          :: call_kind
 !
 ! Work space
 ! 
 integer               :: ig,igp,ng,ng1,i2,i3
 logical               :: inversion,extend_grid,set_table,reflection
 real(SP)              :: g_rot_tmp(3),identity(3,3),rl_sop_square(3,3),rl_sop_local(3,3)
 !
 real(SP),allocatable  :: g_vec_tmp(:,:)
 logical, allocatable  :: g_rot_found(:)
 !
 ! Initialization
 !
 if(is==1) return
 !
 identity=reshape((/ 1._SP, 0._SP, 0._SP, 0._SP, 1._SP, 0._SP, 0._SP, 0._SP, 1._SP/),(/3,3/))
 !
 if(is>0) forall (i2=1:3,i3=1:3) rl_sop_local(i2,i3)=dl_sop(i2,i3,is)*alat(i2)/alat(i3)
 if(is<0) forall (i2=1:3,i3=1:3) rl_sop_local(i2,i3)=-identity(i2,i3)*alat(i2)/alat(i3)
 !
 rl_sop_square=matmul(rl_sop_local,rl_sop_local)
 ! 
 extend_grid = (trim(call_kind)=='extend_grid')
 set_table   = (trim(call_kind)=='set_table')
 inversion   = (is==-1)
 reflection  = all(abs(identity(:,:)-rl_sop_square(:,:))<1.E-5)
 !
 ng=-1
 if(extend_grid) ng=ng_vec
 if(set_table)   ng=ng_closed
 !
 if(ng==-1) call error('find_g_rot: ng=-1')
 !
 if(set_table) minus_G(1)=1
 if(ng==1)  return
 !
 ! Allocation
 !
 YAMBO_ALLOC(g_vec_tmp,(2*ng,3))
 YAMBO_ALLOC(g_rot_found,(2*ng))
 g_vec_tmp(1:ng,:)=g_vec(1:ng,:)
 g_rot_found=.false.
 if(extend_grid) then
   YAMBO_FREE(g_vec)
 endif
 !
 g_rot_found(1)=.true.
 !
 do ig=2,ng
   if(g_rot_found(ig)) cycle
   g_rot_tmp=matmul(rl_sop_local,g_vec_tmp(ig,:))
   !
   ng1=2
   if(reflection) ng1=ig
   do igp=ng1,ng
     if(reflection.and.g_rot_found(igp)) cycle
     if( v_is_zero(g_rot_tmp-g_vec_tmp(igp,:),zero_=G_iku_zero)) then
       g_rot_found(ig)=.true.
       if(reflection) g_rot_found(igp)=.true.
       if(set_table) then
         minus_G(ig)=igp
         minus_G(igp)=ig
       endif
       exit
     endif
   enddo
   !
   if( .not.g_rot_found(ig) .and. .not.extend_grid .and. .not.inversion) &
&    call error('find_g_rot: g_rot not found')
   !
   if(.not.g_rot_found(ig).and.extend_grid) then
     ng_vec=ng_vec+1
     ng=ng_vec
     g_vec_tmp(ng_vec,:)=g_rot_tmp
     g_rot_found(ig)=.true.
     if(reflection) g_rot_found(ng_vec)=.true.
   endif
 enddo
 !
 if(extend_grid) then
   YAMBO_ALLOC(g_vec,(ng_vec,3))
   g_vec=g_vec_tmp(1:ng_vec,:)
 endif
 !
 YAMBO_FREE(g_vec_tmp)
 YAMBO_FREE(g_rot_found)
 !
end subroutine
