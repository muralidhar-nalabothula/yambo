!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): AM
!
module collision_el
 !
 !=====================
 ! ELEMENTAL COLLISION
 !=====================
 !
 use pars,        ONLY:DP,SP,LP,schlen
 use parallel_m,  ONLY:PP_indexes
 use qe_pseudo_m, ONLY:bec_type,deallocate_bec_type
 use gpu_m,       ONLY:have_gpu
 !
#include<dev_defs.h>
#include<y_memory.h>
 !
 type elemental_collision
   !
   !  is(3)=(ib,ik,is,isp) --<--:--<-- os(3)=(ob,ok,os,osp)
   !                            :
   !                           /:\ iqs=(ig0,iq,is)
   !                            :
   !  iq_is = bz(ik_is-ok_os)+Go
   !
   integer :: is(4) 
   integer :: os(4)
   integer :: qs(3)
   integer :: ngrho
   integer :: iqref
   !
   character(schlen) :: name="El_Coll"
   !
   complex(SP), allocatable :: gamp(:,:)
   complex(SP), allocatable :: rhotw(:)
   !
   ! scatter bamp workspace
   !
   complex(DP), allocatable :: rho_tw_rs(:)
   complex(SP), allocatable :: WF_symm_i(:,:)
   complex(SP), allocatable :: WF_symm_o(:,:)
   !
   ! USPP workspace
   !
   type(bec_type) :: ibec      ! contains:  < beta_j | wf_in>
   type(bec_type) :: obec      ! contains:  < beta_j | wf_om>
   real(DP),    allocatable :: ylmk0(:,:)
   real(DP),    allocatable :: qmod(:)
   complex(DP), allocatable :: qgm(:,:,:,:)
   complex(SP), allocatable :: becprod(:,:,:,:)
   complex(SP), allocatable :: eiqtau(:)
   !
   complex(SP), allocatable DEV_ATTR :: rhotw_d(:)
   complex(SP), allocatable DEV_ATTR :: gamp_d(:,:)
   complex(DP), allocatable DEV_ATTR :: rho_tw_rs_d(:)
   complex(SP), allocatable DEV_ATTR :: WF_symm_i_d(:,:)
   complex(SP), allocatable DEV_ATTR :: WF_symm_o_d(:,:)
   !
 end type elemental_collision
 !
 contains
   !
   subroutine elemental_collision_copy(I,O)
     type(elemental_collision), target::I,O
     O%is=I%is
     O%os=I%os
     O%qs=I%qs
   end subroutine
   !
   subroutine elemental_collision_free(ggw)
     type(elemental_collision), target::ggw
     !
     YAMBO_FREE_GPU(DEV_VAR(ggw%gamp))
     YAMBO_FREE_GPU(DEV_VAR(ggw%rhotw))
     YAMBO_FREE_GPU(DEV_VAR(ggw%rho_tw_rs))
     YAMBO_FREE_GPU(DEV_VAR(ggw%WF_symm_i))
     YAMBO_FREE_GPU(DEV_VAR(ggw%WF_symm_o))
     !
     YAMBO_FREE(ggw%gamp)
     YAMBO_FREE(ggw%rhotw)
     YAMBO_FREE(ggw%rho_tw_rs)
     YAMBO_FREE(ggw%WF_symm_i)
     YAMBO_FREE(ggw%WF_symm_o)
     ! 
     ! USPP workspace
     call deallocate_bec_type(ggw%ibec)
     call deallocate_bec_type(ggw%obec)
     YAMBO_FREE(ggw%ylmk0)
     YAMBO_FREE(ggw%qmod)
     YAMBO_FREE(ggw%qgm)
     YAMBO_FREE(ggw%becprod)
     YAMBO_FREE(ggw%eiqtau)
     !
     !DEV_ACC exit data delete(ggw)
     !
   end subroutine
   !
   subroutine elemental_collision_alloc(ggw,NG,NG_GAMP,GRADIENT,TITLE)
     use electrons,      ONLY:n_spinor
     use FFT_m,          ONLY:fft_size
     type(elemental_collision), target ::ggw
     integer,         OPTIONAL :: NG
     integer,         OPTIONAL :: NG_GAMP(2)
     logical,         OPTIONAL :: GRADIENT
     character(*),    OPTIONAL :: TITLE
     !
     integer :: RHOSIZE
     !
     if (present(TITLE)) then
       ggw%name=TITLE
     endif
     !
     !DEV_ACC enter data copyin(ggw)
     if (fft_size>0) then
       YAMBO_ALLOC(ggw%rho_tw_rs,(fft_size))
       YAMBO_ALLOC(ggw%WF_symm_i,(fft_size,n_spinor))
       YAMBO_ALLOC(ggw%WF_symm_o,(fft_size,n_spinor))
       !
       if (have_gpu) then
         YAMBO_ALLOC_GPU(DEV_VAR(ggw%rho_tw_rs),(fft_size))
         YAMBO_ALLOC_GPU(DEV_VAR(ggw%WF_symm_i),(fft_size,n_spinor))
         YAMBO_ALLOC_GPU(DEV_VAR(ggw%WF_symm_o),(fft_size,n_spinor))
       endif
     endif
     !
     if (present(NG)) then
       if (NG>0) then
         !
         if (     present(GRADIENT)) RHOSIZE=3*NG
         if (.not.present(GRADIENT)) RHOSIZE=1*NG
         YAMBO_ALLOC(ggw%rhotw,(RHOSIZE))
         if (have_gpu) then
           YAMBO_ALLOC_GPU(DEV_VAR(ggw%rhotw),(RHOSIZE))
         endif
         !
       endif
       ggw%ngrho=NG
     endif
     if (present(NG_GAMP)) then
       if (all((/NG_GAMP>0/))) then
         YAMBO_ALLOC(ggw%gamp,(NG_GAMP(1),NG_GAMP(2)))
         if (have_gpu) then
           YAMBO_ALLOC_GPU(DEV_VAR(ggw%gamp),(NG_GAMP(1),NG_GAMP(2)))
         endif
       endif
     endif
     !
   end subroutine
   !
end module collision_el
