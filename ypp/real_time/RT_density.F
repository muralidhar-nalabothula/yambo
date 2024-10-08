!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): DS
!
subroutine RT_density(en,kpt,qpt)
 !
 use pars,           ONLY:SP,schlen,cZERO
 use units,          ONLY:FS2AUT
 use R_lattice,      ONLY:bz_samp
 use FFT_m,          ONLY:fft_size,fft_dim
 use electrons,      ONLY:levels,n_spin
 use parser_m,       ONLY:parser
 use stderr,         ONLY:intc,real2ch
 use com,            ONLY:msg,of_open_close
 use IO_int,         ONLY:io_control
 use IO_m,           ONLY:DUMP,OP_RD_CL,OP_IF_START_RD_CL_IF_END,NONE,LOG,manage_action
 use RT_control,     ONLY:TIME_string,RT_apply,Gless_RT_IO_t,CARR_RT_IO_t
 use RT_occupations, ONLY:RT_el_occ,RT_occupation_alloc,RT_occupation_free
 use real_time,      ONLY:RT_nk,RT_bands,NE_i_time,dG_lesser,G_lesser_reference,RT_step
 use YPPm,           ONLY:v2plot,output_fname,plot_dim,plot_title,&
&                         use_xcrysden,use_gnuplot,use_cube,nr,nr_tot,l_norm_to_one
 use YPP_real_time,  ONLY:RT_time,RT_conf,gimme_a_G_Time_Point
 use interfaces,     ONLY:WF_load,WF_free,el_density_and_current
 use wave_func,      ONLY:WF,wf_ng
 use parallel_int,   ONLY:PARALLEL_global_indexes,PARALLEL_WF_distribute,PARALLEL_WF_index
 !
#include<y_memory.h>
 !
 type(levels)  :: en
 type(bz_samp) :: kpt,qpt
 !
 ! Workspace
 !
 integer               :: ID,ik,io_err,i_t,i_dir,IO_ACT
 character(schlen)     :: ch_ws(3)
 logical               :: load_G_history,include_eq_occ
 !
 ! Allocs
 !
 real(SP), allocatable    :: drho(:),delta_magn(:,:)
 complex(SP), allocatable :: G_loc(:,:,:)
 !
 integer, external     :: io_RT_components
 !
 call parser('LoadGhistory',load_G_history)
 call parser('IncludeEQocc',include_eq_occ)
 !
 call section('*','Time dependent density plot')
 !
 call RT_k_grid(en,kpt,qpt)
 !
 ! I/O
 !=====
 if(load_G_history) then
   call io_control(ACTION=OP_RD_CL,COM=LOG,MODE=DUMP,SEC=(/1,2/),ID=ID) 
   io_err=io_RT_components('G_lesser',ID)
   if (io_err/=0) then
     call warning(" History of G_lesser not found. Density will be computed using the occupations")
     load_G_history=.false.
   endif
 endif
 !
 if(load_G_history) then
   ch_ws(1)="Computing the density from the G lesser"
   YAMBO_ALLOC(G_loc,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),RT_nk))
   G_loc=cZERO
   YAMBO_ALLOC(dG_lesser,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),RT_nk,1))
   dG_lesser=cZERO
   if(include_eq_occ) then
     YAMBO_ALLOC(G_lesser_reference,(RT_bands(1):RT_bands(2),RT_bands(1):RT_bands(2),RT_nk))
     G_lesser_reference=cZERO
     call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/2/),ID=ID) 
     io_err=io_RT_components('REFERENCE',ID)
   endif
   call msg('s',trim(ch_ws(1)))
   call RT_time_configuration_setup("G-DENSITY",Gless_RT_IO_t)
 else
   ch_ws(1)="Computing the density from the occupations"
   call RT_apply(RT_bands,En,kpt,IO_COM=LOG,TIMES_ONLY=.TRUE.,skip_interpolation=.TRUE.)
   call RT_occupation_alloc("electrons",RT_el_occ,RT_bands,RT_nk)
   call msg('s',trim(ch_ws(1)))
   call RT_time_configuration_setup("f-DENSITY",CARR_RT_IO_t)
 endif
 !
 ! Parallel Setups & WF_load
 !===========================
 call PARALLEL_global_indexes(en,kpt,qpt," ",RESET=.TRUE.)
 call PARALLEL_WF_distribute(CLEAN_UP=.TRUE.)
 call PARALLEL_WF_index( )
 !
 call WF_load(WF,wf_ng,1,RT_bands,(/1,kpt%nibz/),space='R',title='-WF',impose_free_and_alloc=.TRUE.)
 !
 YAMBO_ALLOC(drho,(fft_size))
 drho=0._SP
 !
 if(n_spin>1.and.load_G_history) then
   call build_spin_sop()
   YAMBO_ALLOC(delta_magn,(fft_size,3))
 endif
 !
 nr_tot = fft_size
 nr     = fft_dim
 YAMBO_ALLOC(v2plot,(nr_tot))
 !
 l_norm_to_one=.false.
 !
 call plot_check_and_launch(.true.)
 !
 do i_T=1,RT_conf%T_n_steps
   !
   call msg('s','RT density at time '//trim(real2ch(real(RT_time(i_T)/FS2AUT,SP)))//' fs')
   !
   if (load_G_history) then
     !
     call gimme_a_G_Time_Point(i_T)
     !
#if defined _PAR_IO
     call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/3/),ID=ID)
     io_err=io_RT_components('G_lesser_K_section',ID)
#else
     do ik = 1, RT_nk 
       IO_ACT=manage_action(OP_IF_START_RD_CL_IF_END,ik,1,RT_nk)
       call io_control(ACTION=IO_ACT,COM=NONE,SEC=(/ik+2/),ID=ID)
       io_err=io_RT_components('G_lesser_K_section',ID)
     enddo
#endif
     !
     if(     include_eq_occ) G_loc=dG_lesser(:,:,:,1)+G_lesser_reference
     if(.not.include_eq_occ) G_loc=dG_lesser(:,:,:,1)
     !
     call el_density_matrix(G_loc,en,kpt,drho,RT_bands(1))
     !
     if(n_spin>1) call el_magnetization_matrix(G_loc,en,kpt,delta_magn,RT_bands(1))
     !
   else
     !
     call RT_apply(RT_bands,en,kpt,Time=RT_time(i_T),keep_RT_carriers=.TRUE.)
     !
     call el_density_and_current(en,kpt,rho=drho,bands=RT_bands)
     !
     ! To be coded
     !if(n_spin>1) call el_magnetization(en,kpt,delta_magn,bands=RT_bands)
     !
   endif
   !
   v2plot=drho
   !
   ch_ws(2)='RT_density_'//trim(intc(plot_dim))//'d@t'//trim(TIME_string( RT_time(i_T) ))
   if (use_cube)     output_fname=trim(ch_ws(2))//'.cube'
   if (use_xcrysden) output_fname=trim(ch_ws(2))//'.xsf'
   if (use_gnuplot)  output_fname=trim(ch_ws(2))//''
   !
   if (use_cube) then 
     call of_open_close(trim(output_fname),'o')
   else
     call of_open_close(trim(output_fname),'ot')
     call msg('o RT_den',"# "//trim(ch_ws(1)))
     call msg('o RT_den',"#")
   endif
   !
   plot_title='RT_density'
   call plot_check_and_launch(.false.)
   !
   call of_open_close(trim(output_fname))
   !
   if(n_spin>1.and.load_G_history) then
     !
     do i_dir=1,3
       !
       v2plot=delta_magn(:,i_dir)
       !
       if(i_dir==1) ch_ws(2)='RT_magne_x'
       if(i_dir==2) ch_ws(2)='RT_magne_y'
       if(i_dir==3) ch_ws(2)='RT_magne_z'
       ch_ws(3)=trim(ch_ws(2))//'_'//trim(intc(plot_dim))//'d@t'//trim(TIME_string( (NE_i_time-1)*RT_step ))
       !
       if (use_cube)     output_fname=trim(ch_ws(3))//'.cube'
       if (use_xcrysden) output_fname=trim(ch_ws(3))//'.xsf'
       if (use_gnuplot)  output_fname=trim(ch_ws(3))//''
       !
       if (use_cube) then 
         call of_open_close(trim(output_fname),'o')
       else
         call of_open_close(trim(output_fname),'ot')
         call msg('o RT_magn',"# "//trim(ch_ws(1)))
         call msg('o RT_magn',"#")
       endif
       !
       plot_title=trim(ch_ws(2)//" ")
       call plot_check_and_launch(.false.)
       !
       call of_open_close(trim(output_fname))
       !
     enddo
     !
   endif
   !
 enddo
 !
 if (load_G_history) then
   YAMBO_FREE(dG_lesser)
   YAMBO_FREE(G_lesser_reference)
   YAMBO_FREE(G_loc)
 else
   call RT_occupation_free(RT_el_occ)
 endif
 YAMBO_FREE(drho)
 !
 if(n_spin>1.and.load_G_history) then
   YAMBO_ALLOC(delta_magn,(fft_size,3))
 endif
 !
 call WF_free(WF)
 !
end subroutine RT_density
