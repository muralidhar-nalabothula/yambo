!
! License-Identifier: GPL
!
! Copyright (C) 2020 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine k_map_fine_to_coarse_engine(zone,pts_fg,N_pts_fg,pts_cg,N_pts_cg,MAP)
 !
 use pars,                ONLY:SP,rZERO,zero_dfl
 use R_lattice,           ONLY:k_the_nearest
 use vec_operate,         ONLY:sort
 use parallel_m,          ONLY:PP_indexes,myid,PP_indexes_reset
 use parallel_int,        ONLY:PP_wait,PP_redux_wait,PARALLEL_index
 use LIVE_t,              ONLY:live_timing
 use com,                 ONLY:msg
 !
#include<y_memory.h>
 !
 character(*)      , intent(in)    :: zone
 integer           , intent(in)    :: N_pts_fg,N_pts_cg
 real(SP)          , intent(in)    :: pts_fg(N_pts_fg,3)
 real(SP)          , intent(in)    :: pts_cg(N_pts_cg,3)
 integer           , intent(out)   :: MAP(N_pts_fg)
 !
 ! Work Space
 !
 integer, parameter   :: MAX_n_near_border=8  ! I assume max 8 points with common border
 integer              :: ik_near,ik,i_err,i_fg,i_b,i_cg,Nb,k_dist_index(N_pts_cg),&
&                        BORDER(N_pts_fg,MAX_n_near_border),N(N_pts_cg),N_border
 real(SP)             :: k_dist(N_pts_cg)
 type(PP_indexes)     :: px
 logical              :: I_am_border
 !
 call PP_indexes_reset(px)
 call PARALLEL_index(px,(/N_pts_fg/))
 call PP_wait()
 !
 call live_timing(zone//' Double Grid Map',px%n_of_elements(myid+1))
 !
 N=0
 MAP   =0
 BORDER=0
 k_dist_index=0
 k_dist=rZERO
 !
 ! Step #1: define the MAP and label the FG points at the BORDER point
 !
 do i_fg=1,N_pts_fg
   !
   if (.not.px%element_1D(i_fg)) cycle
   !
   ik_near=k_the_nearest(pts_fg(i_fg,:),pts_cg(:,:),N_pts_cg,border_point=I_am_border,i_err=i_err,k_dist=k_dist)
   !
   if (i_err==0                     ) MAP(i_fg)=-ik_near
   if (i_err/=0.and..not.I_am_border) MAP(i_fg)= ik_near
   !
   if (i_err/=0.and.I_am_border) then
     Nb=0
     call sort(k_dist,indx=k_dist_index,r_zero=zero_dfl)
     do i_cg=1,N_pts_cg
       if ( abs(k_dist(i_cg)-k_dist(1))<zero_dfl ) then
         Nb=Nb+1
         BORDER(i_fg,Nb)=k_dist_index(i_cg)
       endif
     enddo
   endif
   !
   call live_timing(steps=1)
   !
 enddo
 !
 call PP_redux_wait(MAP)
 call PP_redux_wait(BORDER)
 !
 call live_timing( )
 !
 N_border=count(BORDER(:,1)/=0)
 if (N_border>0) call msg('s',':: '//zone//' Border points                       :',N_border)
 !
 ! Step #2: Assign the BORDER points
 !
 call N_update( )
 !
 do i_fg=1,N_pts_fg
   !
   if ( BORDER(i_fg,1) == 0 ) then
     ik_near=MAP(i_fg)
     cycle
   endif
   !
   ik_near=BORDER(i_fg,1)
   do i_b=2,MAX_n_near_border
     if ( BORDER(i_fg,i_b)== 0 ) cycle
     if ( N(BORDER(i_fg,i_b)) < N(ik_near) ) ik_near=BORDER(i_fg,i_b)
   enddo
   !
   MAP(i_fg)=ik_near
   !
   call N_update( )
   !
 enddo
 !
 contains
   !
   subroutine N_update( )
     do i_cg=1,N_pts_cg
       N(i_cg)=count(MAP==i_cg)
     enddo
   end subroutine
   !
end subroutine
