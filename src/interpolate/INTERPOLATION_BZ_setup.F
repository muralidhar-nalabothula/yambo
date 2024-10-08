!
! License-Identifier: GPL
!
! Copyright (C) 2011 The Yambo Team
!
! Authors (see AUTHORS file for details): CA
!
subroutine INTERPOLATION_BZ_setup(Xk)
 !
 ! Code inspired by BolzTraP
 ! http://www.icams.de/content/departments/ams/madsen/boltztrap.html
 !
 use pars,              ONLY:SP,pi
 use interpolate,       ONLY:nshells,lattice_vectors,INTERP_shell_factor,int_sop,metric,int_sop,&
&                       INTERPOLATE_use_symm              
 use interpolate_tools, ONLY:make_star
 use D_lattice,         ONLY:nsym,DL_vol,a,dl_sop
 use R_lattice,         ONLY:bz_samp,b
 use vec_operate,       ONLY:sort
 use matrix_operate,    ONLY:m3inv
 use com,               ONLY:msg
 !
#include<y_memory.h>
 !
 type(bz_samp) :: Xk
 !
 !Work Space
 !
 real(SP)                  :: sphere_radius,a_inv(3,3),b_inv(3,3)
 real(SP)                  :: vec(3),vec_mod
 real(SP), allocatable     :: star_vec(:,:)
 real(SP), allocatable     :: all_vec(:,:),all_vec_mod(:),lattice_vec_mod(:),tmp_vec(:,:)
 integer,  allocatable     :: indx(:)
 integer                   :: i1,i2,i3,is,R_max(3),nR_max,n_vec,istart,iend,nstar
 logical                   :: add_vec,INTERPOLATION_vec_in_star
 real(SP),  parameter      :: zero=2e-05
 integer                   :: nsym_interp
 !
 nsym_interp=nsym
 if(.not.INTERPOLATE_use_symm) nsym_interp=1
 !
 YAMBO_ALLOC(int_sop,(3,3,nsym_interp))
 YAMBO_ALLOC(star_vec,(3,nsym_interp))
 ! 
 metric=matmul(a,transpose(a))
 !
 sphere_radius=(INTERP_shell_factor*Xk%nbz*3._SP*DL_vol/4._SP/pi)**(1._SP/3._SP)
 !
 call m3inv(transpose(a),a_inv)
 a_inv=transpose(a_inv)
 call m3inv(b,b_inv)
 !
 do i1=1,3
   R_max(i1)=sphere_radius*sqrt(dot_product(a_inv(:,i1),a_inv(:,i1)))+1
 enddo
 !
 do is=1,nsym_interp
   !
   int_sop(:,:,is)=dl_sop(:,:,is)*(2._SP*pi)
   int_sop(:,:,is)=matmul(transpose(a_inv),int_sop(:,:,is))
   int_sop(:,:,is)=nint(matmul(int_sop(:,:,is),b_inv))
   !
 enddo
 !
 if(abs(int_sop(1,1,1)+1._SP)<zero) int_sop=-int_sop
 !
 nR_max=product(2*R_max+1)
 !
 YAMBO_ALLOC(all_vec,(3,nR_max))
 YAMBO_ALLOC(all_vec_mod,(nR_max))
 YAMBO_ALLOC(indx,(nR_max))
 YAMBO_ALLOC(tmp_vec,(3,nR_max))
 !
 all_vec    =0._SP
 all_vec_mod=0._SP
 !
 n_vec=0
 !
 do i3=-R_max(3),R_max(3)
   do i2=-R_max(2),R_max(2)
     do i1=-R_max(1),R_max(1)
        vec(:)=(/i1,i2,i3/)
        vec_mod=sqrt(dot_product(vec,matmul(metric,vec)))
        if(vec_mod>sphere_radius) cycle
        n_vec=n_vec+1
        all_vec_mod(n_vec)=vec_mod
        all_vec(:,n_vec)  =vec(:)
     enddo
   enddo
 enddo
 !
 ! Sort according to the radius
 !
 call sort(arrin=all_vec_mod(1:n_vec),indx=indx(1:n_vec))
 !
 tmp_vec(:,1:n_vec)=all_vec(:,indx(1:n_vec))
 all_vec(:,1:n_vec)=tmp_vec(:,1:n_vec)
 YAMBO_FREE(tmp_vec)
 !
 ! Find R sheels
 !
 YAMBO_ALLOC_P(lattice_vectors,(3,n_vec))
 YAMBO_ALLOC(lattice_vec_mod,(n_vec))
 !
 istart=1
 iend=1
 nshells=1
 lattice_vectors(:,nshells)=all_vec(:,1)
 lattice_vec_mod(nshells)  =all_vec_mod(1)
 !
 do i2=2,n_vec
   !
   add_vec=.false.
   !
   if((all_vec_mod(i2)-lattice_vec_mod(nshells))>zero) then
     istart=nshells+1
     add_vec=.true.
   endif
   !
   if(.not.add_vec) then
     !  
     call make_star(all_vec(:,i2),nsym_interp,int_sop,nstar,star_vec)
     add_vec=.true.
     !
     do i3=istart,iend
       !
       if(INTERPOLATION_vec_in_star(lattice_vectors(:,i3),nstar,star_vec)) then
         add_vec=.false.
         continue
       endif
       !
     enddo
     !
   endif
   !
   if(add_vec) then
     nshells=nshells+1
     lattice_vectors(:,nshells)=all_vec(:,i2)
     lattice_vec_mod(nshells)  =all_vec_mod(i2)
     iend   =nshells
   endif
   !
 enddo
 !
 call msg('sr','[INTERPOLATION] Number of shells',nshells)
 !
 all_vec(1:3,1:nshells)=lattice_vectors(1:3,1:nshells)
 !
 YAMBO_FREE_P(lattice_vectors)
 YAMBO_FREE(lattice_vec_mod)
 !
 YAMBO_ALLOC_P(lattice_vectors,(3,nshells))
 !
 lattice_vectors(1:3,1:nshells)=all_vec(1:3,1:nshells)
 !
 YAMBO_FREE(all_vec)
 YAMBO_FREE(all_vec_mod)
 YAMBO_FREE(indx)
 YAMBO_FREE(star_vec)
 !
end subroutine INTERPOLATION_BZ_setup
