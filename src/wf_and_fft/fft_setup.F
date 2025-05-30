!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
#include<dev_defs.h>
!
subroutine fft_setup(iG_max,iGo_max,ONLY_SIZE)
 !
 use pars,           ONLY:SP,pi
 use D_lattice,      ONLY:a,nsym,dl_sop,sop_inv,i_time_rev,alat
 use R_lattice,      ONLY:b,g_vec,ng_vec
 use matrix_operate, ONLY:m3inv
 use FFT_m,          ONLY:fft_dim,fft_size,fft_rot_r,fft_rot_r_inv,&
&                         fft_norm,fft_g_table,fft_multiplier,modx,&
&                         DEV_VAR(fft_g_table),DEV_VAR(fft_rot_r),DEV_VAR(fft_rot_r_inv)
 use FFT_m,          ONLY:fftw_plan,cufft_plan,hipfft_plan
#if defined _FFTQE
 use fft_base,       ONLY:dffts
#endif
 use wave_func,      ONLY:wf_ng
 use timing_m,       ONLY:timing
 use gpu_m,          ONLY:have_gpu,gpu_devsync
 use devxlib,        ONLY:devxlib_memcpy_h2d,devxlib_memcpy_d2h,devxlib_memset_d
 use iso_c_binding,  ONLY:c_null_ptr
#if defined _MKLGPU
 use mkl_dfti_omp_offload
 use FFT_m,          ONLY:mklgpu_desc
#endif
 !
#include<y_memory.h>
 !
 integer :: iG_max,iGo_max,ierr
 logical :: ONLY_SIZE
#if defined _FFTQE
 integer, external :: fft_setmap
#endif
 !
 ! Work Space
 !
 integer  :: i1,i2,i3,i4,iv(3),ln(3),is,space_inv(3,3)
 real(SP) :: v1(3),M1(3,3),M2(3,3),mat(3,3),scal(3)
 real(SP), allocatable :: g_vec_rot(:,:)
 real(SP), allocatable DEV_ATTR :: g_vec_rot_d(:,:)
#ifdef _GPU
 integer :: ln_1,ln_2,ln_3,iv_1,iv_2,iv_3
 integer :: fft_dim_1,fft_dim_2,fft_dim_3
 integer :: temp_1,temp_2,temp_3,i1_max
 integer,  allocatable :: ivec_GmG(:,:,:)
 integer,  allocatable DEV_ATTR :: ivec_GmG_d(:,:,:)
#endif

 call timing("FFT_setup",opr="start")
 !
 space_inv=reshape((/-1, 0, 0, 0,-1, 0, 0, 0,-1/),(/3,3/))
 call m3inv(transpose(b),mat)
 scal(:)=2._SP*pi/alat(:)
 !
 mat(:,1)=scal(1)*mat(:,1)
 mat(:,2)=scal(2)*mat(:,2)
 mat(:,3)=scal(3)*mat(:,3)
 !
 YAMBO_ALLOC_MOLD(g_vec_rot,g_vec)
 g_vec_rot=transpose(matmul(mat,transpose(g_vec)))
 !
#ifdef _GPU
 YAMBO_ALLOC_GPU_SOURCE(DEV_VAR(g_vec_rot),g_vec_rot)
#endif
 !
 if (.not.ONLY_SIZE) then
   !
   YAMBO_FREE_GPU(DEV_VAR(fft_g_table))
   YAMBO_FREE(fft_g_table)
   !
   YAMBO_ALLOC(fft_g_table,(max(iG_max,wf_ng),iGo_max))
   fft_g_table=0
   !
   if (have_gpu) then
     YAMBO_ALLOC_GPU(DEV_VAR(fft_g_table),(max(iG_max,wf_ng),iGo_max))
     call devxlib_memset_d(DEV_VAR(fft_g_table),val=0)
   endif
   !
 endif
 !
 ! SIZE estimation
 !
!#ifdef _GPU
! ln_1=-1
! ln_2=-1
! ln_3=-1
!#endif
 ln=-1
 i4=-1
 do while(.true.)
   !
#if defined _FFTQE
   if (i4>0.and..not.ONLY_SIZE) call fft_desc_init(fft_dim,iGo_max,dffts)
#endif
   !
#ifdef _GPU
   !
   fft_dim_1 = fft_dim(1)
   fft_dim_2 = fft_dim(2)
   fft_dim_3 = fft_dim(3)
   i1_max = min(max(iG_max,wf_ng),ng_vec)
   !
   YAMBO_ALLOC(ivec_GmG,(iGo_max,i1_max,3))
   YAMBO_ALLOC_GPU(DEV_VAR(ivec_GmG),(iGo_max,i1_max,3))
   call devxlib_memset_d(DEV_VAR(ivec_GmG),val=-1)
   !
   !DEV_ACC_DEBUG data present(g_vec_rot,fft_g_table)
   !DEV_ACC parallel loop collapse(2)
   !DEV_CUF kernel do(2)
   !DEV_OMPGPU target map(present,alloc:g_vec_rot,fft_g_table)
   !DEV_OMPGPU teams loop collapse(2) private(iv_1,iv_2,iv_3,temp_1,temp_2,temp_3)
   !!!!!!! &          reduction(max:ln_1,ln_2,ln_3)
   do i1=1,i1_max
     do i2=1,iGo_max
       !
       iv_1 = nint(DEV_VAR(g_vec_rot)(i1,1) - DEV_VAR(g_vec_rot)(i2,1))
       iv_2 = nint(DEV_VAR(g_vec_rot)(i1,2) - DEV_VAR(g_vec_rot)(i2,2))
       iv_3 = nint(DEV_VAR(g_vec_rot)(i1,3) - DEV_VAR(g_vec_rot)(i2,3))
       !
       if (i2==1.or.i1<=iG_max) then
         DEV_VAR(ivec_GmG)(i2,i1,1)=iv_1
         DEV_VAR(ivec_GmG)(i2,i1,2)=iv_2
         DEV_VAR(ivec_GmG)(i2,i1,3)=iv_3
         !ln_1=max(ln_1,iv_1)
         !ln_2=max(ln_2,iv_2)
         !ln_3=max(ln_3,iv_3)
       endif
       !
       if (i4>0.and..not.ONLY_SIZE) then
                       temp_1 = mod(iv_1,fft_dim_1)
                       temp_2 = mod(iv_2,fft_dim_2)
                       temp_3 = mod(iv_3,fft_dim_3)
            if(iv_1<0) temp_1 = mod(temp_1 + fft_dim_1, fft_dim_1)
            if(iv_2<0) temp_2 = mod(temp_2 + fft_dim_2, fft_dim_2)
            if(iv_3<0) temp_3 = mod(temp_3 + fft_dim_3, fft_dim_3)
            !
            DEV_VAR(fft_g_table)(i1,i2)=1+temp_1+&
&                                  temp_2*fft_dim_1+&
&                                  temp_3*fft_dim_1*fft_dim_2
       endif
       !
     enddo
   enddo
   !DEV_OMPGPU end target
   !DEV_ACC_DEBUG end data
   !
   if (i4>0.and..not.ONLY_SIZE) then
     ! D2H fft_g_table <= fft_g_table_d
     call devxlib_memcpy_d2h(fft_g_table,DEV_VAR(fft_g_table))
   endif
   !
   call devxlib_memcpy_d2h(ivec_GmG,DEV_VAR(ivec_GmG))
   ln(1)=maxval(ivec_GmG(:,:,1))
   ln(2)=maxval(ivec_GmG(:,:,2))
   ln(3)=maxval(ivec_GmG(:,:,3))
   !ln(1) = ln_1
   !ln(2) = ln_2
   !ln(3) = ln_3
   !
   YAMBO_FREE_GPU(DEV_VAR(ivec_GmG))
   YAMBO_FREE(ivec_GmG)
   !
#else
   do i1=1,min(max(iG_max,wf_ng),ng_vec)
     do i2=1,iGo_max
       !
       v1=(g_vec_rot(i1,:)-g_vec_rot(i2,:))
       iv=nint(v1)
       !
       if (i2==1.or.i1<=iG_max) forall(i3=1:3) ln(i3)=max(ln(i3),iv(i3))
#  if defined _FFTQE
       if (i4>0.and..not.ONLY_SIZE) fft_g_table(i1,i2)=fft_setmap(iv,dffts)
#  else
       if (i4>0.and..not.ONLY_SIZE) fft_g_table(i1,i2)=1+modx(iv(1),fft_dim(1))+&
&                                   modx(iv(2),fft_dim(2))*fft_dim(1)+&
&                                   modx(iv(3),fft_dim(3))*fft_dim(1)*fft_dim(2)
#  endif
     enddo
   enddo
#endif
   !
   !
   ln=ln*fft_multiplier
   call fft_best_size(ln)
   !
   if (i4>0) then
      call timing("FFT_setup",opr="stop")
      YAMBO_FREE_GPU(DEV_VAR(g_vec_rot))
      YAMBO_FREE(g_vec_rot)
      return
   endif
   !
   fft_dim=ln
   fft_size=product(fft_dim)
   ! to avoid issues with CUDA
   fft_size=max(fft_size,1)
   !
   fft_norm=sqrt(1._SP/real(fft_size,SP))
   !
   if (ONLY_SIZE) then
     i4=1
     cycle
   endif
   !
   YAMBO_FREE_GPU(DEV_VAR(fft_rot_r))
   YAMBO_FREE(fft_rot_r)
   YAMBO_FREE_GPU(DEV_VAR(fft_rot_r_inv))
   YAMBO_FREE(fft_rot_r_inv)
   !
   YAMBO_ALLOC(fft_rot_r,(fft_size,nsym))
   YAMBO_ALLOC(fft_rot_r_inv,(fft_size))
   if (have_gpu) then
     YAMBO_ALLOC_GPU(DEV_VAR(fft_rot_r),(fft_size,nsym))
     YAMBO_ALLOC_GPU(DEV_VAR(fft_rot_r_inv),(fft_size))
   endif

   !
   !Remember
   !-------
   !
   ! r_j= (I_i-1)/Ni a(j,i) = at(j,i) (i-1)/Ni
   !
   ! at=transpose(a)
   !
   ! a(i,j)*b(k,j)=b(k,j)*at(j,i)=d_ik 2 pi
   ! atm1=inverse(transpose(a))=b/2./pi
   !
   ! r(s)_j=at(i,l) (I_l-1)/Nl = (R_s r)_i = R_s(i,k) at(k,j) (j-1)/Nj
   !
   ! => (I_l-1)/Nl = atm1(l,i) R_s(i,k) at(k,j) (j-1)/Nj
   !
   ! Now I want to rewrite wf_ks(r)= wf_k(r(s^-1))
   !
   do is=1,nsym+1
     if( is<=nsym/(1+i_time_rev) )                M1=matmul( dl_sop(:,:,sop_inv(is)),transpose(a))
     if( is> nsym/(1+i_time_rev) .and. is<=nsym ) M1=matmul(-dl_sop(:,:,sop_inv(is)),transpose(a))
     if( is==nsym+1 )                             M1=matmul( space_inv,transpose(a))
     M2=matmul(b,M1)/2.0_SP/pi
     forall (i1=1:3,i2=1:3) M2(i1,i2)=M2(i1,i2)*fft_dim(i1)/fft_dim(i2)
     !
     do i1=0,fft_dim(1)-1
       do i2=0,fft_dim(2)-1
         do i3=0,fft_dim(3)-1
           iv=nint(matmul(M2,(/i1,i2,i3/)))
           i4=1+i1+i2*fft_dim(1)+i3*fft_dim(1)*fft_dim(2)
           if( is==nsym+1) then
             fft_rot_r_inv(i4)=1+modx(iv(1),fft_dim(1))+&
&                            modx(iv(2),fft_dim(2))*fft_dim(1)+&
&                            modx(iv(3),fft_dim(3))*fft_dim(1)*fft_dim(2)
             cycle
           endif
           fft_rot_r(i4,is)=1+modx(iv(1),fft_dim(1))+&
&                          modx(iv(2),fft_dim(2))*fft_dim(1)+&
&                          modx(iv(3),fft_dim(3))*fft_dim(1)*fft_dim(2)
         enddo
       enddo
     enddo
   enddo
   i4=1
   !
   if (have_gpu) then
     call devxlib_memcpy_h2d(DEV_VAR(fft_rot_r),fft_rot_r)
     call devxlib_memcpy_h2d(DEV_VAR(fft_rot_r_inv),fft_rot_r_inv)
   endif
   !
 enddo
 !
#if defined _FFTW
 fftw_plan=0
#endif
#if defined _GPU
 cufft_plan=0
 hipfft_plan=c_null_ptr
#if defined _MKLGPU
 ierr = DftiFreeDescriptor(mklgpu_desc)
#endif
#endif
 !
 YAMBO_FREE_GPU(DEV_VAR(g_vec_rot))
 YAMBO_FREE(g_vec_rot)
 call timing("FFT_setup",opr="stop")
 !
 contains
   !
   subroutine fft_best_size(test_fft_size)
     !
#if defined _FFTQE
     use fft_scalar, ONLY:good_fft_order
#endif
     !
     implicit none
     integer :: test_fft_size(3)
     !
     ! Work Space
     !
     integer, parameter :: nn=82
     integer :: i1,i2,nallwd(nn)
     data nallwd/& ! taken from CTRIG
&      3,   4,   5,   6,   8,   9,  12,  15,  16,  18,&
&     20,  24,  25,  27,  30,  32,  36,  40,  45,  48,&
&     54,  60,  64,  72,  75,  80,  81,  90,  96, 100,&
&    108, 120, 125, 128, 135, 144, 150, 160, 162, 180,&
&    192, 200, 216, 225, 240, 243, 256, 270, 288, 300,&
&    320, 324, 360, 375, 384, 400, 405, 432, 450, 480,&
&    486, 500, 512, 540, 576, 600, 625, 640, 648, 675,&
&    720, 729, 750, 768, 800, 810, 864, 900, 960, 972,&
&    1000,1024/
     !
     ! The size is calculated on the components of the RL vectors
     ! that are positive and negative. Thus I need 2N+1 elements
     !
     test_fft_size=2*test_fft_size+1
     !
#if defined _FFTQE
     ! use the good_fft_order from the quantum-espresso suite
     do i1=1,3
       test_fft_size(i1)=good_fft_order(test_fft_size(i1))
     enddo
#endif
     !
#if !defined _FFTQE && defined _FFTW
     ! the standard FFTW distribution works most efficiently for arrays
     ! whose size can be factored into small primes (2, 3, 5, and 7),
     ! and otherwise it uses a slower general-purpose routine
     do i1=1,3
       if (any((/mod(test_fft_size(i1),2),mod(test_fft_size(i1),3),&
&                mod(test_fft_size(i1),5),mod(test_fft_size(i1),7)/)==0)) cycle
       test_fft_size(i1)=test_fft_size(i1)+mod(test_fft_size(i1),2)
     enddo
#endif
     !
#if !defined _FFTQE && defined _FFTSG
     do i1=1,3
       do i2=1,nn
         if (nallwd(i2)>=test_fft_size(i1)) then
           test_fft_size(i1)=nallwd(i2)
           exit
         endif
       enddo
      if (test_fft_size(i1)>nallwd(nn)) test_fft_size(i1)=nallwd(nn)
     enddo
#endif
     !
#if !defined _FFTQE && !defined _FFTSG && !defined _FFTW
#error "[FFT] inconsistent FFT lib config"
#endif
     !
   end subroutine
   !
end subroutine
