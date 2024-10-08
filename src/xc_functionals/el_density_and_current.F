!
! License-Identifier: GPL
!
! Copyright (C) 2015 The Yambo Team
!
! Authors (see AUTHORS file for details): AM DS
!
subroutine el_density_and_current(E,k,rho,drho,J,bands,force_spatial_inversion)
 !
 ! Electronic density (and current).
 !
 ! When defining the density there are two possible conventions.
 ! a) "physical density", rho(r)=rho_phys(r) is independent on the fft_size
 ! b) "computationally convenient density": rho(r)=rho_comp(r) is such that $sum_i rho(r_i) = n_{el}$
 !
 ! The difference is that "rho comp" includes the "dr" factor which is obtained from the conversion of the integral into a sum.
 ! $\int dr rho(r) --> \sum_i V/fft_size rho(r_i) = \sum_i rho_comp(r_i)$
 !
 ! In yambo rho=rho_comp. The libxc_library for example usese rho=rho_phys and in XC_libxc_driver.F there is a $dr$ conversion factor.
 !
 ! Note that here the identity
 !
 ! \sum_{S_k} F(S_k r) = 1/R_k \sum_{S} F(S r) (1)
 ! 
 ! where S_k is a symm. op. in the star of k, S is a generic symm. op.
 ! and R_k is the rank of the small group at k.
 !
 ! Using (1) the density is calculated in two steps
 !
 !  rho(r) = 1/nkibz \sum_{ n k S_k } f_{n k} |wf_{n k}(S_k^-1 r)|^2=
 !         = 1/nkibz \sum_{S} \sum_{n k} f_{n k}/R_k |wf_{n k}(S^-1 r)|^2 =
 !         = 1/nsym \sum_{S} ( \sum_{n k} f_{n k} w_k |wf_{n k}(S^-1 r)|^2 )
 !
 ! where we have used the relation
 !
 ! w_k = nsym/(nkibz * R_k)
 !
 ! Same procedure for the current
 !
 use pars,          ONLY:SP,DP
 use com,           ONLY:msg
 use stderr,        ONLY:real2ch
 use electrons,     ONLY:levels,n_spinor,n_sp_pol
 use R_lattice,     ONLY:bz_samp
 use D_lattice,     ONLY:nsym,i_time_rev,mag_syms,dl_sop
 use FFT_m,         ONLY:fft_size,fft_dim,fft_rot_r,fft_rot_r_inv,fft_g_table
#if defined _FFTW
 use FFT_m,         ONLY:fftw_plan
#endif
 use wave_func,     ONLY:WF
 use parallel_m,    ONLY:PAR_IND_WF_linear,PAR_COM_density
 use parallel_int,  ONLY:PP_redux_wait
 use pseudo,        ONLY:pp_is_uspp,qe_pseudo_alloc,becp,pp_has_nlcc
 use qe_pseudo_m,   ONLY:qe_omega=>omega,qe_ngm=>ngm, becsum
 use timing_m,      ONLY:timing
#if defined _RT
 use drivers,       ONLY:l_real_time
#endif
#if defined _YPP_RT
 use RT_occupations,ONLY:RT_el_occ
 use real_time,     ONLY:RTibz
#endif
 !
#include<y_memory.h>
 !
 type(bz_samp)::k
 type(levels) ::E       
 real(SP), optional             ::rho(fft_size)
 real(SP), optional             ::drho(fft_size,3)
 real(SP), optional             ::J(fft_size,3)
 integer,  optional, intent(in) ::bands(2)
 logical,  optional, intent(in) ::force_spatial_inversion
 !
 ! Work Space 
 !
#if defined _YPP_RT
 integer    :: ik_RT
#endif
 integer    :: ib,ik,i_sp_pol,i_spinor,rho_syms,i_symm,i_wf,bands_range(2)
 integer    :: i_r,ig,i_dir,ifft
 real(SP)   :: f_occ,raux,kw
 logical    :: warn_done,l_si,l_rho,l_drho,l_J
 !
 real(SP),    allocatable :: rho_no_sym(:),drho_no_sym(:,:),J_no_sym(:,:)
 complex(SP), allocatable :: WF_der(:,:,:)
 complex(DP), allocatable :: rhog_aug_DP(:,:), aux_DP(:)
 !
#if defined _RT
 call timing('el_density',OPR='start')
#endif
 !
 ! Basic Setups
 !
 l_rho     =present(rho)
 l_drho    =present(drho)
 l_J       =present(J)
 l_si      =.false.
 if (present(force_spatial_inversion)) l_si=force_spatial_inversion
 !
 !
 if (l_rho) then
   YAMBO_ALLOC(rho_no_sym,(fft_size))
   rho       =0._SP
   rho_no_sym=0._SP
 endif
 !
 if (l_drho) then
   if(pp_is_uspp)  call warning(" USPP corrections to rho gradient not implemented")
   if(pp_has_nlcc) call warning(" NLCC corrections to rho gradient not implemented")
   YAMBO_ALLOC(WF_der,(fft_size,n_spinor,3))
   YAMBO_ALLOC(drho_no_sym,(fft_size,3))
   drho       =0._SP
   drho_no_sym=0._SP
 endif
 !
 if (l_J) then
   YAMBO_ALLOC(WF_der,(fft_size,n_spinor,3))
   call error(" Calculation of current is implemented but not tested")
   J         =0._SP
   J_no_sym  =0._SP
 endif
 !
 ! USPP contribution
 ! 
 if (l_rho.and.pp_is_uspp) then
   !
   if (.not. qe_pseudo_alloc) call error(' [PP] qe_pseudo not alloc in XC driver')
   !
   becsum=0.0
   !
 endif
 !
 warn_done=.false.
 !
 !
 do i_sp_pol=1,n_sp_pol
   bands_range=(/1,E%nbm(i_sp_pol)/)
   if(present(bands)) bands_range=bands
   do ik=1,k%nibz
     !
     do ib=bands_range(1),bands_range(2)
       !
       if (allocated(PAR_IND_WF_linear%element_2D)) then
         if (.not.PAR_IND_WF_linear%element_2D(ib,ik)) cycle
       endif
       !
       if (size(WF%index,1)<ib)        cycle
       if (size(WF%index,2)<ik)        cycle
       if (size(WF%index,3)<i_sp_pol)  cycle
       !
       f_occ=E%f(ib,ik,i_sp_pol)
#if defined _RT
       if(l_real_time.and.allocated(E%fo)) f_occ=E%fo(ib,ik,i_sp_pol) 
#endif
#if defined _YPP_RT
       if(present(bands)) then
         f_occ=0._SP
         do ik_RT=RTibz%k_range(ik,1),RTibz%k_range(ik,2)
           f_occ=f_occ+RT_el_occ%dN(ib,ik_RT)*RTibz%weights(ik_RT)
         enddo
       endif
#endif
       !
       i_wf=WF%index(ib,ik,i_sp_pol)
       !
       if (i_wf==0) then
         if (.not.warn_done) call warning('Not enough states to calculate rho')
         warn_done=.true.
         cycle
       endif
       !
       !
       if (l_rho) then
         !
         kw=k%weights(ik)
         !
         !$omp parallel do default(shared), private(i_spinor,i_r), collapse(2), reduction(+:rho_no_sym)
         do i_spinor=1,n_spinor
           do i_r = 1, fft_size
             rho_no_sym(i_r)=rho_no_sym(i_r)+f_occ*kw*abs(WF%c(i_r,i_spinor,i_wf))**2
           enddo
         enddo
         !
         ! uspp becsum
         !
         if (pp_is_uspp) then
           !
           call sum_bec(ik,i_sp_pol, ib,ib,1, (/f_occ*k%weights(ik)/), becp(ik,i_sp_pol) )
           !
         endif
         !
       endif
       !
       if (l_drho) then
         !
         call eval_Gradient(WF%c(:,:,i_wf),WF_der,n_spinor,"wave")
         !
         do i_dir=1,3
           do i_spinor=1,n_spinor
             do ifft=1,fft_size
               drho_no_sym(ifft,i_dir)=drho_no_sym(ifft,i_dir)+E%f(ib,ik,i_sp_pol)*&
               &  k%weights(ik)*2._SP*real(WF%c(ifft,i_spinor,i_wf)*WF_der(ifft,i_spinor,i_dir))
             enddo
           enddo
         enddo
         !
       endif
       !
       if (l_J) then
         !
         call eval_Gradient(WF%c(:,:,i_wf),WF_der,n_spinor,"wave")
         !
         do i_dir=1,3
           do i_spinor=1,n_spinor
             do ifft=1,fft_size
               J_no_sym(ifft,i_dir)=J_no_sym(ifft,i_dir)+E%f(ib,ik,i_sp_pol)*&
               &   k%weights(ik)*aimag(WF%c(ifft,i_spinor,i_wf)*WF_der(ifft,i_spinor,i_dir))
             enddo
           enddo
         enddo
         !
       endif
       !
     enddo
     !
   enddo
 enddo
 !
 !
 ! finalize USPP contribution
 !
 if (l_rho.and.pp_is_uspp) then
   !
   YAMBO_ALLOC(aux_DP,(fft_size))
   YAMBO_ALLOC(rhog_aug_DP,(qe_ngm,n_sp_pol))
   rhog_aug_DP=0.0
   !
   call addusdens(qe_ngm,n_sp_pol,qe_ngm,rhog_aug_DP)
   !
   do i_sp_pol=1,n_sp_pol
      !
      aux_DP=0.0
      do ig = 1, qe_ngm
         aux_DP(fft_g_table(ig,1)) = rhog_aug_DP(ig,i_sp_pol)
      enddo
      !
#if defined _FFTW
      call dfftw_destroy_plan(fftw_plan)
      fftw_plan = 0
      call fft_3d(aux_DP,fft_dim,+1,fftw_plan)
#else
      call fft_3d(aux_DP,fft_dim,+1)
#endif
      !
      aux_DP=aux_DP*qe_omega/real(fft_size,DP)
      rho_no_sym(:)=rho_no_sym(:)+real(aux_DP(:),SP)
      !
   enddo
   !
   YAMBO_FREE(rhog_aug_DP)
   YAMBO_FREE(aux_DP)
   !
   raux = sum(rho_no_sym)
   call msg('nr','[PP] USPP charge normalization :  '//trim(real2ch(raux))//' [el/cell]')
   !
 endif
 !
 if (l_rho ) call PP_redux_wait(rho_no_sym, COMM=PAR_COM_density%COMM)
 if (l_drho) call PP_redux_wait(drho_no_sym,COMM=PAR_COM_density%COMM)
 if ( l_J  ) call PP_redux_wait(J_no_sym,   COMM=PAR_COM_density%COMM)
 !
 if (l_drho.or.l_J) then
   YAMBO_FREE(WF_der)
 endif
 !
 ! Symmetrization
 !
 rho_syms=nsym/(i_time_rev+1)
 !
 if (mag_syms) rho_syms=nsym 
 !
 if (l_rho) then
   !
   !#EV_OMP parallel do default(shared), private(i_symm,i_r), collapse(2), reduction(+:rho)
   do i_symm=1,rho_syms
     do i_r = 1, fft_size
       rho(i_r)=rho(i_r)+rho_no_sym(fft_rot_r(i_r,i_symm))/real(nsym,SP)
     enddo
   enddo
   !#EV_OMP end parallel do
   !
   if (.not.mag_syms) then
     if (.not.l_si) rho(:)=real(1+i_time_rev,SP)*rho(:)
     if (     l_si) rho(:)=real(  i_time_rev,SP)*rho(fft_rot_r_inv(:))+rho(:)
   endif
 endif
 !
 if (l_drho) then
   do i_symm=1,rho_syms
     do ifft=1,fft_size
       drho(ifft,:)=drho(ifft,:)+matmul(dl_sop(:,:,i_symm),drho_no_sym(fft_rot_r(ifft,i_symm),:))/real(nsym,SP)
     enddo
   enddo
   if (.not.mag_syms) then
     if (.not.l_si) drho(:,:)=real(1+i_time_rev,SP)*drho(:,:)
     if (     l_si) drho(:,:)=real(  i_time_rev,SP)*drho(fft_rot_r_inv(:),:)+drho(:,:)
   endif
 endif
 !
 if (l_J) then
   call warning(" Application of symmetries to be fixed")
   do i_symm=1,rho_syms
     J(:,:)=J(:,:)+real(J_no_sym(fft_rot_r(:,i_symm),:),SP)/real(nsym,SP)
   enddo
 endif
 !
 YAMBO_FREE(rho_no_sym)
 !
#if defined _RT
 call timing('el_density',OPR='stop')
#endif
 ! 
end subroutine
