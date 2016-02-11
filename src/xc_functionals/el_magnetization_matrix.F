!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details):
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
subroutine el_magnetization_matrix(G_lesser,en,Xk,magn,lowest_band)
 !
 ! Electronic magnetization for electronic Spinors
 !
 !  SD = Sum_I (PSI^I)* Sigma_Pauli* PSI^I  I=occupied states
 !
 !  PSI^I = spinor
 !  Sigma_Pauli=the 3 Pauli matrices
 !
 use pars,           ONLY:SP,cI
 use com,            ONLY:error
 use R_lattice,      ONLY:bz_samp
 use electrons,      ONLY:levels,n_spin,n_spinor,n_sp_pol
 use D_lattice,      ONLY:nsym,DL_vol,dl_sop,i_time_rev,inv_index
 use FFT_m,          ONLY:fft_size,fft_rot_r
 use wave_func,      ONLY:WF
 use SC,             ONLY:SC_bands
 use electrons,      ONLY:Total_magn,n_spinor
 use parallel_m,     ONLY:PP_redux_wait,PAR_IND_WF_k,PAR_IND_B_mat_ordered,PAR_IND_WF_linear
 use matrix_operate, ONLY:UP_matrix_index
 use D_lattice,      ONLY:DL_vol
 use matrix_operate, ONLY:m3det
 !
 implicit none
 !
 type(bz_samp)::Xk
 complex(SP), intent(in), optional :: G_lesser(SC_bands(1):SC_bands(2),SC_bands(1):SC_bands(2),Xk%nibz)
 integer,     intent(in) :: lowest_band
 type(levels) ::en       
 real(SP)     ::magn(fft_size,3)
 !
 ! Work Space
 !
 integer :: ib1,ib2,ik,isym,ifft,ifft1(n_spin),ifft2(n_spin)
 real(SP):: cv(fft_size,3),tmp_sop(3,3),f_occ(n_sp_pol)
 !
 magn=0._SP
 cv=  0._SP
 !
 Total_magn=0._SP
 !
 if (n_spin==1) return
 !
 if(lowest_band<SC_bands(1)-1) then
   !
   do ik=1,Xk%nibz
     do ib1=lowest_band,SC_bands(1)-1
       !
       if (.not.PAR_IND_WF_linear%element_2D(ib1,ik)) cycle
       !
       ifft1(:)=WF%index(ib1,ik,:)
       !
       f_occ(:)=en%f(ib1,ik,:)
       !
       if (any(ifft1(:)==0)) cycle
       !
       if (n_spinor==2) then
         !
         ! mx
         !
         cv(:,1)=cv(:,1)+Xk%weights(ik)*(&
&                f_occ(1)*real(conjg(WF%c(:,ifft1(1)))*WF%c(:,ifft1(2)))&
&               +f_occ(1)*real(conjg(WF%c(:,ifft1(2)))*WF%c(:,ifft1(1))) )
         !
         ! my
         !
         cv(:,2)=cv(:,2)+Xk%weights(ik)*(&
&                f_occ(1)*aimag(conjg(WF%c(:,ifft1(1)))*WF%c(:,ifft1(2)))&
&               +f_occ(1)*aimag(conjg(WF%c(:,ifft1(2)))*WF%c(:,ifft1(1))) )
       endif
       !
       ! mz
       !
       cv(:,3)=cv(:,3)+Xk%weights(ik)*(&
&              f_occ(1)       *real(conjg(WF%c(:,ifft1(1)))*WF%c(:,ifft1(1)))&
&             -f_occ(n_sp_pol)*real(conjg(WF%c(:,ifft1(2)))*WF%c(:,ifft1(2))) )
       !
     enddo
   enddo
   !
 endif
 !
 do ik=1,Xk%nibz
   !
   if (.not.PAR_IND_WF_k%element_1D(ik)) cycle
   !      
   do ib1=SC_bands(1),SC_bands(2)
     !
     do ib2=ib1,SC_bands(2)
       !
       if (.not.PAR_IND_B_mat_ordered%element_1D(  UP_matrix_index(ib1-SC_bands(1)+1,ib2-SC_bands(1)+1)-1 )) cycle
       !
       ifft1(:)=WF%index(ib1,ik,:)
       ifft2(:)=WF%index(ib2,ik,:)
       !
       if (ib1==ib2) f_occ(1)=-cI*G_lesser(ib1,ib2,ik)
       if (ib1/=ib2) f_occ(1)=-cI*G_lesser(ib1,ib2,ik)*2._SP
       !
       if (n_spinor==2) then
         !
         ! mx
         !
         cv(:,1)=cv(:,1)+Xk%weights(ik)*(&
&                f_occ(1)*real(conjg(WF%c(:,ifft1(1)))*WF%c(:,ifft2(2)))&
&               +f_occ(1)*real(conjg(WF%c(:,ifft1(2)))*WF%c(:,ifft2(1))) )
         !
         ! my
         !
         cv(:,2)=cv(:,2)+Xk%weights(ik)*(&
&                f_occ(1)*aimag(conjg(WF%c(:,ifft1(1)))*WF%c(:,ifft2(2)))&
&               -f_occ(1)*aimag(conjg(WF%c(:,ifft1(2)))*WF%c(:,ifft2(1))) )
       endif
       !
       ! mz
       !
       cv(:,3)=cv(:,3)+Xk%weights(ik)*(&
&              f_occ(1)       *real(conjg(WF%c(:,ifft1(1))*WF%c(:,ifft2(1))))&
&             -f_occ(n_sp_pol)*real(conjg(WF%c(:,ifft1(2))*WF%c(:,ifft2(2)))) )
       !
     enddo
   enddo
   !
 enddo
 !
 call PP_redux_wait(cv)
 !
 ! Symmetrization
 !
 do isym=1,nsym
   ! The magnetization, like the spin, is a pseudo-vector:
   ! i.e. is invariant under spatial invertion but changes under T-rev
   if (n_spinor==2) then
     tmp_sop(:,:)=dl_sop(:,:,isym)*m3det(dl_sop(:,:,isym))
     if( isym> nsym/(1+i_time_rev) ) tmp_sop(:,:)=-tmp_sop(:,:)
     forall(ifft=1:fft_size) magn(ifft,:)=magn(ifft,:)+ &
&                            matmul(tmp_sop,real( cv(fft_rot_r(ifft,isym),:)/real(nsym) ))
   else
     magn(:,3)=magn(:,3)+real(cv(fft_rot_r(:,isym),3)/real(nsym))
   endif
   !
 enddo
 !
 do ifft=1,fft_size
   Total_magn(:)=Total_magn(:)+magn(ifft,:)
 enddo
 !
end subroutine