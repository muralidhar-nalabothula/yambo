!
! License-Identifier: GPL
!
! Copyright (C) 2018 The Yambo Team
!
! Authors (see AUTHORS file for details): AF IM
!
subroutine PP_vloc_augment(QP_Vloc,Vloc,ik,ib,ibp)
 !
 ! Add the USPP augmentation to the matrix element of a local potential
 ! All quantities given in real space.
 !
 use pars,          ONLY:SP,DP
 use electrons,     ONLY:n_sp_pol
 use pseudo,        ONLY:pp_is_uspp,qe_pseudo_alloc,becp
 use FFT_m,         ONLY:fft_size,fft_dim,fft_g_table
#if defined _FFTW
 use FFT_m,         ONLY:fftw_plan
#endif
 use qe_pseudo_m,   ONLY:qe_omega=>omega,qe_ngm=>ngm,becprod
 !
#include<y_memory.h>
 !
 ! vars
 !
 complex(SP), intent(inout) :: QP_Vloc
 integer,     intent(in)    :: ik,ib,ibp
 real(SP),    intent(in)    :: Vloc(fft_size,n_sp_pol)
 !
 ! Workspace
 !
 integer :: ig,ifft,i_sp_pol
 complex(SP):: QP_aug
 complex(DP), allocatable :: rhog_aug_DP(:,:), aux_DP(:)
 

 !
 ! checks
 !
 if (.not.pp_is_uspp) return
 if (.not.qe_pseudo_alloc) call error(' [PP] qe_pseudo not alloc PP_vloc_aug')
 !
 if (n_sp_pol/=1) call error(" [PP] n_spin>1 not implemented in PP_Vloc_augment")
 
 !
 ! compute becprod
 !--------------------------------
 !
 becprod=0.0
 !
 i_sp_pol=1
 call PP_becprod_calc(becprod, 1, i_sp_pol, .false., ib, ibp, becp(ik,i_sp_pol), becp(ik,i_sp_pol) )
 
 !
 ! augmentation
 !--------------------------------
 !
 YAMBO_ALLOC(aux_DP,(fft_size))
 YAMBO_ALLOC(rhog_aug_DP,(qe_ngm,n_sp_pol))
 rhog_aug_DP=0.0
 !
 call PP_addus_vloc_aug(becprod,qe_ngm,n_sp_pol,qe_ngm,rhog_aug_DP)
 !
 QP_aug=0.0
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
    !
    do ifft=1,fft_size
       QP_aug = QP_aug + Vloc(ifft,i_sp_pol)*aux_DP(ifft)
    enddo
    !
 enddo
 !
 YAMBO_FREE(rhog_aug_DP)
 YAMBO_FREE(aux_DP)
 !
 QP_Vloc = QP_Vloc + QP_aug
 return
 !
end subroutine PP_vloc_augment
