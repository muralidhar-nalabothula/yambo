! 
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): DS AM
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
subroutine RT_occupations_driver(kpt,En)
 !
 use drivers,        ONLY:l_rt_carriers_in_use
 use R_lattice,      ONLY:bz_samp
 use electrons,      ONLY:levels
 use IO_m,           ONLY:LOG
 use QP_CTL_m,       ONLY:QP_apply
 use YPP_real_time,  ONLY:RT_conf
 use RT_control,     ONLY:RT_apply
 use real_time,      ONLY:RT_bands
 use YPP_real_time,  ONLY:l_RT_time,l_RT_energy,l_RT_bands,l_RT_lifetimes,l_RT_2D_dos
 !
 implicit none
 !
 type(bz_samp) :: kpt
 type(levels)  :: En
 !
 call section('+','Real-Time occupations')
 !============================================
 !
 ! Pre-setup of carrier components and Time evolution parameters
 !===============================================================
 call RT_apply(RT_bands,En,kpt,IO_COM=LOG,keep_RT_carriers=.TRUE.)
 !
 if (.not.l_rt_carriers_in_use) return
 !
 call RT_time_configuration_setup("CARRIERS")
 !
 ! Additional QP corrections
 !===========================
 call QP_state_table_setup(en)
 !
 call QP_apply(RT_bands,En,kpt,'G',msg_fmt='s')
 !
 ! Occupations energy plot 
 !=========================
 if (l_RT_energy) call RT_occ_energy_plot(En,kpt,RT_conf%T_n_steps)
 !
 ! Occupations time plot 
 !=========================
 if (l_RT_time)   call RT_occ_time_plot(En,kpt,RT_conf%T_n_steps)
 !
 ! Occupations 2D dos plot 
 !=========================
 if (l_RT_2D_dos) call RT_occ_2D_dos_plot(En,kpt,RT_conf%T_n_steps)
 !
 ! Occupations bands fit 
 !=========================
 if (l_RT_lifetimes) RT_conf%T_n_steps=1
 if (l_RT_bands) call RT_occ_bands_interpolation(En,kpt,RT_conf%T_n_steps)
 !
end subroutine RT_occupations_driver