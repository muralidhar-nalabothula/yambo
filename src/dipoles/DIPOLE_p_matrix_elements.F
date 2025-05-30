!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
#include<dev_defs.h>
!
subroutine DIPOLE_p_matrix_elements(Xk,iv_wf,ic_wf,ik,rho,rho_spinor,P2,l_eval_P2,l_eval_M_spin)
 !
 use pars,          ONLY:SP,cZERO,pi
 use wrapper_omp,   ONLY:Vstar_dot_V_omp
 use D_lattice,     ONLY:alat
 use wave_func,     ONLY:WF,wf_ncx,wf_nc_k,wf_igk,DEV_VAR(wf_igk)
 use electrons,     ONLY:n_spinor
 use R_lattice,     ONLY:g_vec,DEV_VAR(g_vec),bz_samp
#if defined _RT
 use real_time,     ONLY:l_update_SOC
#endif
 !
 implicit none
 !
 type(bz_samp), intent(in)  :: Xk
 integer,       intent(in)  :: iv_wf,ic_wf,ik
 logical,       intent(in)  :: l_eval_P2,l_eval_M_spin
 complex(SP),   intent(out) :: rho(3),rho_spinor(3,n_spinor,n_spinor),P2
 ! 
 ! Work Space
 !
 integer      :: ic,ig
 logical      :: eval_spinor_matrix
 integer      :: i_spinor,j_spinor,i1
 complex(SP)  :: wf_grad(wf_ncx,n_spinor),wf_der_sq(wf_ncx,n_spinor)
 !
 complex(SP), pointer DEV_ATTR :: WF_p(:,:,:)
#ifdef _GPU
 complex(SP)  :: rho_acc
 real(SP)     :: rho_acc_r,rho_acc_i
 real(SP)     :: alat_i1,xk_i1
 integer      :: wf_nc_ik
#endif
 !
 rho=cZERO
 rho_spinor=cZERO
 P2=cZERO
 ! 
 eval_spinor_matrix=.false.
#if defined _RT
 eval_spinor_matrix=l_eval_M_spin.and.n_spinor==2.and.l_update_SOC
#endif
 !
 WF_p => DEV_VAR(WF%c)
 !
 do i1=1,3
   !
   ! wf_grad = -i grad fdo(iv,ik)
   !
#ifdef _GPU
! AF_FIX: to be cleaned up
   !
   xk_i1=Xk%pt(ik,i1)
   alat_i1=alat(i1)
   wf_nc_ik=wf_nc_k(ik)
   !
   if(eval_spinor_matrix) then
     !
     do i_spinor=1,n_spinor
       do j_spinor=1,n_spinor
         !
         rho_acc_r=0.0_SP
         rho_acc_i=0.0_SP
         !
         !DEV_ACC_DEBUG data present(WF_p,g_vec,wf_igk)
         !DEV_ACC parallel loop private(ig,rho_acc) reduction(+:rho_acc_r,rho_acc_i)
         !DEV_CUF kernel do(1)
         !DEV_OMPGPU target map(present,alloc:WF_p,g_vec,wf_igk) map(tofrom:rho_acc_r,rho_acc_i)
         !DEV_OMPGPU teams loop private(ig,rho_acc) reduction(+:rho_acc_r,rho_acc_i)
         do ic=1,wf_nc_ik
           ig=DEV_VAR(wf_igk)(ic,ik)
           rho_acc= conjg(WF_p(ic,i_spinor,iv_wf))*(xk_i1+DEV_VAR(g_vec)(ig,i1))*2.0_SP*pi/alat_i1* &
&                         WF_p(ic,j_spinor,ic_wf)
           rho_acc_r=rho_acc_r + real(rho_acc,SP)
           rho_acc_i=rho_acc_i + aimag(rho_acc)
         enddo
         !DEV_OMPGPU end target
         !DEV_ACC_DEBUG end data
         !
         rho_spinor(i1,i_spinor,j_spinor)=cmplx(rho_acc_r,rho_acc_i,SP)
       enddo
       rho(i1)=rho(i1)+rho_spinor(i1,i_spinor,i_spinor)
     enddo
     !
   else
     !
     rho_acc_r=0.0_SP
     rho_acc_i=0.0_SP
     ! 
     !DEV_ACC_DEBUG data present(WF_p,g_vec,wf_igk)
     !DEV_ACC parallel loop collapse(2) private(ig,rho_acc) reduction(+:rho_acc_r,rho_acc_i)
     !DEV_CUF kernel do(2)
     !DEV_OMPGPU target map(present,alloc:WF_p,g_vec,wf_igk) map(tofrom:rho_acc_r,rho_acc_i)
     !DEV_OMPGPU teams loop collapse(2) private(ig,rho_acc) reduction(+:rho_acc_r,rho_acc_i)
     do i_spinor=1,n_spinor
     do ic=1,wf_nc_ik
        ig=DEV_VAR(wf_igk)(ic,ik)
        rho_acc= conjg(WF_p(ic,i_spinor,iv_wf))*(xk_i1+DEV_VAR(g_vec)(ig,i1))*2.0_SP*pi/alat_i1* &
&                      WF_p(ic,i_spinor,ic_wf)
        rho_acc_r=rho_acc_r + real(rho_acc,SP)
        rho_acc_i=rho_acc_i + aimag(rho_acc)
     enddo
     enddo
     !DEV_OMPGPU end target
     !DEV_ACC_DEBUG end data
     !
     rho(i1)=cmplx(rho_acc_r,rho_acc_i,SP)
     !
   endif
   !
 enddo
 !
#else
   !
   wf_grad=cZERO
   !DEV_OMP parallel do default(shared), private(ic,ig,i_spinor), collapse(2)
   do i_spinor=1,n_spinor
     do ic=1,wf_nc_k(ik)
       ig=wf_igk(ic,ik)
       wf_grad(ic,i_spinor)=WF_p(ic,i_spinor,iv_wf)*(Xk%pt(ik,i1)+g_vec(ig,i1))*2.0_SP*pi/alat(i1)
     enddo
   enddo
   !DEV_OMP end parallel do
   !
   ! WARNING: 
   ! ========
   ! The convention is to revert the order of the bands
   ! indexes in the definition of DIP_P and DIP_iR :
   ! DIP_P(iv,ic)  = P_cv ; DIP_iR(iv,ic) = (iR)_cv 
   !
   ! Note that P is Hermitian and iR anti-hermitian.
   !
   ! rho = <v|p|c> = P_vc =
   !     = wf_xyz^* fdo(ic,ik)= - i < fdo(iv,ik)| grad |  fdo(ic,ik) > =
   !       \sum_G -i u^*_{iv ik}(G) i ( k + G ) u_{ic ik}(G)
   !     = \sum_G u^*_{iv ik}(G) ( k + G ) u_{ic ik}(G)
   !
   ! P2 =  \sum_G u^*_{iv ik}(G) ( k + G )^2 u_{ic ik}(G)
   !
   ! spinor indexes do not follow band indexes, i.e. they are not reverted
   !
   if(eval_spinor_matrix) then
     !
     do i_spinor=1,n_spinor
       do j_spinor=1,n_spinor
         rho_spinor(i1,i_spinor,j_spinor)=&
         &  Vstar_dot_V_omp(wf_nc_k(ik),wf_grad(:wf_nc_k(ik),i_spinor),WF_p(:wf_nc_k(ik),j_spinor,ic_wf))
       enddo
       rho(i1)=rho(i1)+rho_spinor(i1,i_spinor,i_spinor)
     enddo
     !
   else
     !
     rho(i1)=Vstar_dot_V_omp(wf_nc_k(ik)*n_spinor,wf_grad(:wf_nc_k(ik),:),WF_p(:wf_nc_k(ik),:,ic_wf))
     !
   endif
   !
 enddo
 !
#endif
 !
 if(l_eval_P2) then
   !DEV_OMP parallel do default(shared), private(ic,ig,i_spinor), collapse(2)
   do i_spinor=1,n_spinor
     do ic=1,wf_nc_k(ik)
       ig=wf_igk(ic,ik)
       wf_der_sq(ic,i_spinor) = WF%c(ic,i_spinor,iv_wf) *  &
&                      ( (Xk%pt(ik,1) + g_vec(ig,1))**2 * (2.0_SP*pi/alat(1))**2  &
&                      + (Xk%pt(ik,2) + g_vec(ig,2))**2 * (2.0_SP*pi/alat(2))**2  &
&                      + (Xk%pt(ik,3) + g_vec(ig,3))**2 * (2.0_SP*pi/alat(3))**2 )
     enddo
   enddo
   !DEV_OMP end parallel do
   P2=Vstar_dot_V_omp(wf_nc_k(ik)*n_spinor,wf_der_sq(:wf_nc_k(ik),:),WF%c(:wf_nc_k(ik),:,ic_wf))
 endif
 !
end subroutine
