!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine RT_time_configuration_setup(what,GENERAL_RT_IO_t)
 !
 use units,          ONLY:AUT2FS,pi,HA2EV
 use YPP_real_time,  ONLY:RT_conf,RT_time,RT_conf_save,RT_conf_duplicate
 use pars,           ONLY:SP
 use com,            ONLY:msg
 use real_time,      ONLY:RT_step
 use RT_control,     ONLY:TIME_adjust,RT_IO_t
 !
#include<y_memory.h>
 !
 character(*),  intent(in) :: what
 type(RT_IO_t), intent(in) :: GENERAL_RT_IO_t
 !
 ! Work Space
 !
 integer  :: i_t,i_ref(2),j_ref
 logical  :: UNIFORM,l_current,l_G_lesser,l_reset
 real(SP) :: STEP,TIME,TIME_diff,REF_diff(2)
 integer, allocatable :: i_table(:)
 !
 ! Backup
 !========
 if (RT_conf_save%delta_T==0._SP) call RT_conf_duplicate(RT_conf,RT_conf_save)
 !
 ! Definitions
 !==============
 l_current =index(what,"CURRENT")>0
 l_G_lesser=index(what,"Glesser")>0
 l_reset   =index(what,"reset")>0
 !
 ! Reset
 !========
 if (l_reset) call RT_conf_duplicate(RT_conf_save,RT_conf)
 !
 TIME  = GENERAL_RT_IO_t%Time(GENERAL_RT_IO_t%N)
 STEP  = RT_step
 if (GENERAL_RT_IO_t%N> 1) STEP  = (GENERAL_RT_IO_t%Time(GENERAL_RT_IO_t%N)-GENERAL_RT_IO_t%Time(GENERAL_RT_IO_t%N-1))
 !
 !  In the case of non-uniform T samplings the last time points can be imposed by the total time and, hence, the
 !  STEP can appear even smaller than the effective step.
 if (GENERAL_RT_IO_t%N> 2) STEP  = (GENERAL_RT_IO_t%Time(GENERAL_RT_IO_t%N-1)-GENERAL_RT_IO_t%Time(GENERAL_RT_IO_t%N-2))
 !
 ! Time range ...
 !===============
 !
 if (any(RT_conf%T_range>0._SP)) then
   !
   RT_conf%T_range(1)=TIME_adjust( RT_conf%T_range(1), STEP )
   RT_conf%T_range(2)=TIME_adjust( RT_conf%T_range(2), STEP )
   !
   i_ref      = 0
   REF_diff   = 100.*STEP
   !
   do i_t=1,GENERAL_RT_IO_t%N
     !
     TIME_diff=abs(GENERAL_RT_IO_t%Time(i_t)-RT_conf%T_range(1))
     if ( TIME_diff<REF_diff(1) ) then
       REF_diff(1)=TIME_diff
       i_ref(1) = i_t
     endif
     !
   enddo
   !
   do i_t=1,GENERAL_RT_IO_t%N
     !
     TIME_diff=abs(GENERAL_RT_IO_t%Time(i_t)-RT_conf%T_range(2))
     if ( TIME_diff<REF_diff(2) ) then
       REF_diff(2)=TIME_diff
       i_ref(2) = i_t
     endif
     !
   enddo
   !
   if (i_ref(1)==0) i_ref(1)=1
   if (i_ref(2)==0) i_ref(2)=GENERAL_RT_IO_t%N
   !
 else
   !
   i_ref           = (/1,GENERAL_RT_IO_t%N/)
   !
 endif
 !
 RT_conf%T_n_range=i_ref
 RT_conf%T_range=(/GENERAL_RT_IO_t%Time(i_ref(1)),GENERAL_RT_IO_t%Time(i_ref(2))/)
 !
 ! Uniform time sampling?
 !========================
 !
 UNIFORM=.TRUE.
 do i_t=1,GENERAL_RT_IO_t%N-1
   TIME_diff= abs ( GENERAL_RT_IO_t%Time(i_t+1)-GENERAL_RT_IO_t%Time(i_t) - STEP )
   if (TIME_diff>RT_step) UNIFORM=.FALSE.
 enddo
 !
 ! Time step ...
 !============== 
 !
 if (RT_conf%delta_T> 0._SP) then
   if (GENERAL_RT_IO_t%N>1) then
     RT_conf%delta_T=max(TIME_adjust(RT_conf%delta_T,STEP),STEP)
     REF_diff(1)= STEP
     YAMBO_ALLOC(i_table,(GENERAL_RT_IO_t%N))
     i_table=0
     i_table(1)=i_ref(1)
     !
     j_ref=i_ref(1)
     !
     RT_conf%T_n_steps=1
     do i_t=i_ref(1)+1,i_ref(2)-1
       TIME_diff= abs ( (GENERAL_RT_IO_t%Time(j_ref)+RT_conf%delta_T) -GENERAL_RT_IO_t%Time(i_t) )
       if (abs(TIME_diff)<REF_DIFF(1) ) then
         REF_diff(1)=TIME_diff
         i_table(RT_conf%T_n_steps+1)=i_t
       endif
       TIME_diff= abs ( (GENERAL_RT_IO_t%Time(j_ref)+RT_conf%delta_T) -GENERAL_RT_IO_t%Time(i_t+1) )
       if ( abs(TIME_diff)>REF_diff(1) .and. i_table(RT_conf%T_n_steps+1)>0 ) then
         REF_diff(1)= GENERAL_RT_IO_t%Time(i_t+1)-GENERAL_RT_IO_t%Time(i_t-1)
         RT_conf%T_n_steps=RT_conf%T_n_steps+1
         j_ref= i_t
       endif
     enddo
     if (i_ref(2)>i_ref(1)) then
       i_table(RT_conf%T_n_steps+1)=i_ref(2)
       RT_conf%T_n_steps=RT_conf%T_n_steps+1
     endif
     !
     YAMBO_ALLOC(RT_time,(RT_conf%T_n_steps))
     !
     do i_t=1,RT_conf%T_n_steps
       RT_time(i_t)=GENERAL_RT_IO_t%Time(i_table(i_t))
     enddo
     !
     YAMBO_FREE(i_table)
     !
   else
     RT_conf%T_n_steps=1
     YAMBO_ALLOC(RT_time,(RT_conf%T_n_steps))
     RT_time=0._SP
     RT_conf%delta_T=0._SP
   endif
 else
   RT_conf%T_n_steps = GENERAL_RT_IO_t%N
   YAMBO_ALLOC(RT_time,(RT_conf%T_n_steps))
   RT_time=GENERAL_RT_IO_t%Time
   RT_conf%delta_T   = STEP
 endif
 !
 ! Messaging
 !===========
 !
 call msg('s','['//what//'] Uniform grid       :',UNIFORM)
 call msg('s','['//what//'] Time range         :',(/minval(RT_time),maxval(RT_time)/)*AUT2FS,"[fs]")
 call msg('s','['//what//'] Time step          :',RT_conf%delta_T*AUT2FS,"[fs]")
 call msg('s','['//what//'] Time steps         :',RT_conf%T_n_steps)
 !
 if (.not.(l_current.or.l_G_lesser)) return
 !
 call msg('s','['//what//'] Damping            :',RT_conf%damp_factor*1000._SP*HA2EV,"[meV]")
 !
 if (.not.l_current) return
 !
 ! Field deduced dumping
 !=======================
 RT_conf%Field_damp_factor= 2._SP*pi/(real(RT_conf%T_n_steps-1,SP)*RT_conf%delta_T)
 call msg('s','['//what//'] Field damping      :',RT_conf%Field_damp_factor*1000._SP*HA2EV,"[meV]")
 !
end subroutine RT_time_configuration_setup
