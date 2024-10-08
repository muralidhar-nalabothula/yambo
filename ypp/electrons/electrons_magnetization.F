! 
! License-Identifier: GPL
!
! Copyright (C) 2017 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
subroutine electrons_magnetization(Xk,Xen)
 !
 use pars,           ONLY:SP,lchlen
 use stderr,         ONLY:intc
 use R_lattice,      ONLY:bz_samp
 use electrons,      ONLY:levels,n_sp_pol
 use FFT_m,          ONLY:fft_size
 use interfaces,     ONLY:el_magnetization
 use YPPm,           ONLY:v2plot,output_fname,plot_dim,use_xcrysden,&
&                         use_gnuplot,use_cube,plot_title,l_density,mag_dir
 use com,            ONLY:msg,of_open_close
 use xc_functionals, ONLY:magn
 !
#include<y_memory.h>
 !
 type(bz_samp) ::Xk
 type(levels)  ::Xen
 !
 ! Work Space
 !
 real(SP)              :: el_den(fft_size)
 integer               :: i_sp_pol,mag_i_dir
 character(lchlen)     :: ch_ws(2)
 !
 call section('*','Magnetiziation')
 !
 mag_i_dir=-1
 if (mag_dir=='X'.or.mag_dir=='x') mag_i_dir=1
 if (mag_dir=='Y'.or.mag_dir=='y') mag_i_dir=2
 if (mag_dir=='Z'.or.mag_dir=='z') mag_i_dir=3
 if (mag_i_dir<0) return
 !
 YAMBO_ALLOC(magn,(fft_size,3))
 !
 call section('*','Single Particle Magnetization along '//mag_dir)
 !
 call el_magnetization(Xen,Xk,magn)
 !
 v2plot=magn(:,mag_i_dir)
 !
 if (use_cube) output_fname='mag_'//trim(mag_dir)//'_'//trim(intc(plot_dim))//'d.cube'
 if (use_xcrysden) output_fname='mag_'//trim(mag_dir)//'_'//trim(intc(plot_dim))//'d.xsf'
 if (use_gnuplot)  output_fname='mag_'//trim(mag_dir)//'_'//trim(intc(plot_dim))//'d'
 !
 if (use_cube) then 
   call of_open_close(trim(output_fname),'o')
 else
   call of_open_close(trim(output_fname),'ot')
   call msg('o mag',"#")
 endif
 !
 plot_title='magnetization'
 !
 call plot_check_and_launch(.false.)
 !
 call of_open_close(trim(output_fname))
 !
 if (n_sp_pol==2.and.l_density) then
   !
   call section('*','Spin Polarized densities')
   !
   do i_sp_pol=1,2
     !
     ! rho DN
     if (i_sp_pol==1) then
       v2plot=(el_den(:)-magn(:,3))/2.
       ch_ws(1)='density_DN_'//trim(intc(plot_dim))
     else
       !
       ! rho UP
       v2plot=(el_den(:)+magn(:,3))/2.
       ch_ws(1)='density_UP_'//trim(intc(plot_dim))
     endif
     !
     if (use_cube) output_fname=trim(ch_ws(1))//'d.cube'
     if (use_xcrysden) output_fname=trim(ch_ws(1))//'d.xsf'
     if (use_gnuplot)  output_fname=trim(ch_ws(1))//'d'
     !
     if (use_cube) then 
       call of_open_close(trim(output_fname),'o')
     else
       call of_open_close(trim(output_fname),'ot')
       call msg('o density_UP density_DN',"#")
     endif
     !
     if (i_sp_pol==1) plot_title='den DN'
     if (i_sp_pol==2) plot_title='den UP'
     call plot_check_and_launch(.false.)
     !
     call of_open_close(trim(output_fname))
     !
   enddo
   !
 endif
 !
 YAMBO_FREE(magn)
 !
end subroutine
