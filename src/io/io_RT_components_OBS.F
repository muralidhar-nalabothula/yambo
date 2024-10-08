!
! License-Identifier: GPL
!
! Copyright (C) 2020 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine io_RT_components_OBS(ID,what)
 !
 use pars,        ONLY:SP,schlen
 use IO_int,      ONLY:io_variable_bulk,def_variable_bulk
 use IO_m,        ONLY:read_is_on,write_is_on
 use electrons,   ONLY:n_spin
 use real_time,   ONLY:l_NE_with_fields,NE_i_time
 use netcdf,      ONLY:NF90_UNLIMITED
 use RT_control,  ONLY:J_cache,P_cache,Ms_cache,Ml_cache,A_cache,&
&                      CACHE_OBS_steps_now,OBS_RT_IO_t,RT_do_IO
 !
#include<y_memory.h>
 !
 integer,      intent(in) :: ID
 character(*), intent(in) :: what
 !
 integer           :: VAR_SZ(4),CACHE_SZ,IPOS
 character(schlen) :: dim_names(4)
 !
 select case(WHAT)
   !
 case('DEF')
   !
   if (RT_do_IO("JP")) then
     VAR_SZ(1:3)    = (/2,3,NF90_UNLIMITED/)
     dim_names(1:3) = [character(schlen) :: 'complex', 'xyz','time']
     call def_variable_bulk(ID,"Current",     4,VAR_SZ(1:3),SP,dim_names=dim_names(1:3),silent=.true.)
     call def_variable_bulk(ID,"Polarization",5,VAR_SZ(1:3),SP,dim_names=dim_names(1:3),silent=.true.)
   endif
   !
   if(n_spin>1.and.RT_do_IO("M")) then
     VAR_SZ    = (/2,3,3,NF90_UNLIMITED/)
     dim_names = [character(schlen) :: 'complex', 'xyz','tot_c_v','time']
     call def_variable_bulk(ID,"Spin_Magnetization",6,VAR_SZ,SP,dim_names=dim_names,silent=.true.)
     !
     VAR_SZ    = (/2,3,2,NF90_UNLIMITED/)
     dim_names = [character(schlen) :: 'complex', 'xyz','orb_itin','time']
     call def_variable_bulk(ID,"Orbital_Magnetization",7,VAR_SZ,SP,dim_names=dim_names,silent=.true.)
   endif
   !
   if(l_NE_with_fields) then
     VAR_SZ    = (/2,3,3,NF90_UNLIMITED/)
     dim_names = [character(schlen) :: 'complex', 'xyz','A_kind','time']
     call def_variable_bulk(ID,"A_tot",8,VAR_SZ,SP,dim_names=dim_names,silent=.true.)
   endif
   !
 case('FILL')
   !
   if(write_is_on(ID)) then
     if(NE_i_time==1) CACHE_SZ=1
     if(NE_i_time> 1) CACHE_SZ=CACHE_OBS_steps_now
     IPOS    =OBS_RT_IO_t%N-CACHE_OBS_steps_now+1
   else if(read_is_on(ID)) then
     CACHE_SZ=CACHE_OBS_steps_now
     IPOS    =1
   endif
   !
   if (RT_do_IO("JP")) then
     call io_variable_bulk(ID,4,C2=J_cache(:,1:CACHE_SZ),IPOS=(/1,1,IPOS/))
     call io_variable_bulk(ID,5,C2=P_cache(:,1:CACHE_SZ),IPOS=(/1,1,IPOS/))
   endif
   !
   if(n_spin>1.and.RT_do_IO("M")) then
     call io_variable_bulk(ID,6,C3=Ms_cache(:,:,1:CACHE_SZ),IPOS=(/1,1,1,IPOS/))
     call io_variable_bulk(ID,7,C3=Ml_cache(:,:,1:CACHE_SZ),IPOS=(/1,1,1,IPOS/))
   endif
   !
   if(l_NE_with_fields) then
     call io_variable_bulk(ID,8,C3=A_cache(:,:,1:CACHE_SZ),IPOS=(/1,1,1,IPOS/))
   endif
   !
 end select
 !
end subroutine
