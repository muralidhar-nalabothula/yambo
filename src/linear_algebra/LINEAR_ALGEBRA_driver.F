!
! License-Identifier: GPL
!
! Copyright (C) 2016 The Yambo Team
!
! Authors (see AUTHORS file for details): AM AF
!
subroutine LINEAR_ALGEBRA_driver(idriver,lib_in,&
&                                M,M_slk,&
&                                M_bse,&
&                                B,B_slk,&
&                                C,C_slk,&
&                                V_left,V_right,E_real,E_cmpl,&
&                                SVD_digits,det)
 !
 ! Operations:
 !
 ! * INV:   M_slk/M => M_slk/M
 !
 ! * DIAGO: M => M + E_real/E_cmpl + V_left/V_right (SLK external arrays still to implement)
 !
 ! * LIN_SYSTEM: M_slk/M + B_slk/B => B_slk/B 
 !
 ! * MAT_MUL: M_slk/M + B_slk/B => C_slk/C 
 !
 use pars,          ONLY:SP,cONE,cZERO
 use linear_algebra,ONLY:INV,DIAGO,LIN_SYS,SVD_INV,MAT_MUL,USE_LK,USE_SLK
 use matrix,        ONLY:PAR_matrix,MATRIX_reset
 use wrapper,       ONLY:M_by_M
 use parallel_m,    ONLY:linear_algebra_is_parallel,ncpu
 use interfaces,    ONLY:MATRIX_transfer
 use BS,            ONLY:BS_block,BS_H_dim
 use timing_m,      ONLY:timing
 use gpu_m,         ONLY:have_gpu
 use devxlib,       ONLY:devxlib_mapped
 !
#include<y_memory.h>
#include<dev_defs.h>
 !
 integer                    :: idriver
 integer,          optional :: lib_in
 complex(SP),      optional :: M(:,:)
 type(PAR_matrix), optional :: M_slk
 type(BS_block),   optional :: M_bse(:)
 complex(SP),      optional :: B(:,:)
 type(PAR_matrix), optional :: B_slk
 complex(SP),      optional :: C(:,:)
 type(PAR_matrix), optional :: C_slk
 complex(SP),      optional :: V_left(:,:)
 complex(SP),      optional :: V_right(:,:)
 real(SP),         optional :: E_real(:)
 complex(SP),      optional :: E_cmpl(:)
 integer,          optional :: SVD_digits 
 complex(SP),      optional :: det
 !
 ! Work Spaces ...
 !
 complex(SP)         :: det_
 integer             :: N,lib_in_use
 type (PAR_matrix)   :: M_loc,B_loc,C_loc,V_loc
 logical             :: USE_GPU
 !
 call timing("LINEAR ALGEBRA",OPR="start")
 !
 ! M dimension
 !
 USE_GPU=.false.
 !
 if (present(M_slk)) then
   N=M_slk%N
#if defined _SCALAPACK 
   if (M_slk%kind=="SLK") lib_in_use=USE_SLK
#endif
   if (have_gpu.and.devxlib_mapped(DEV_VAR(M_slk%blc))) USE_GPU=.true.
 else if (present(M_bse)) then
   N=BS_H_dim
 else if (present(M)) then
   N=size(M,1)
 endif

 !
 ! Decide which to use among LK or SLK
 !
 lib_in_use=USE_LK
#if defined _SCALAPACK 
 lib_in_use=USE_SLK
#endif
 if (present(lib_in)) then
   lib_in_use=lib_in
 endif
 if (idriver==SVD_INV.or.(idriver==DIAGO.and.present(E_cmpl))) lib_in_use=USE_LK 
 if (.not.linear_algebra_is_parallel) lib_in_use=USE_LK
 !
 ! whether to use CUDA lib
 !
 if (idriver==SVD_INV.or.idriver==INV.or.idriver==DIAGO&
&                    .or.idriver==MAT_MUL) USE_GPU=.false.
 if (USE_GPU) lib_in_use=USE_LK
 !
#if defined _SCALAPACK
 if (idriver==DIAGO.and.present(E_cmpl).and.ncpu>1) then
   !
   call warning('Parallel non-herm diag not yet implemented. Switching to LK')
   lib_in_use=USE_LK
   !
 endif

 !
 ! =============== PARALLEL SECTION ==========================================================
 !
 if (lib_in_use==USE_SLK.and..not.USE_GPU) then 
   !
   if (.not.present(M_slk)) then
     !
     call MATRIX_init( "SLK", M_loc, N, 1 )
     YAMBO_ALLOC(M_loc%blc,(M_loc%BLCrows(1):M_loc%BLCrows(2),M_loc%BLCcols(1):M_loc%BLCcols(2),M_loc%Nb))
     !
     if (present(M_bse)) then
       call MATRIX_transfer( M_out= M_loc, M_bse=M_bse )
     else if (present(M)) then
       call MATRIX_transfer( M_out= M_loc, M=M )
     endif
     !
   endif
   !
   if (idriver==DIAGO) then
     !
     call MATRIX_init("SLK",  V_loc, N, 1 )
     YAMBO_ALLOC(V_loc%blc,(V_loc%BLCrows(1):V_loc%BLCrows(2),V_loc%BLCcols(1):V_loc%BLCcols(2),V_loc%Nb))
     !
     call PARALLEL_HERMITIAN_diagonalization( M_loc, V_loc, N, E_real )
     !
     call MATRIX_transfer( M_in = V_loc , M=M )
     YAMBO_FREE(V_loc%blc)
     call MATRIX_reset(V_loc)
     !
   else if (idriver==INV) then
     !
     if (present(M)) then
       call PARALLEL_inversion( M_loc, N ) 
       call MATRIX_transfer( M_in = M_loc , M=M )
     else
       call PARALLEL_inversion( M_slk, N ) 
     endif
     !
   else if (idriver==LIN_SYS) then
     !
     if (.not.present(B_slk)) then
       !
       call MATRIX_init("SLK",  B_loc, N, 1 )
       YAMBO_ALLOC(B_loc%blc,(B_loc%BLCrows(1):B_loc%BLCrows(2),B_loc%BLCcols(1):B_loc%BLCcols(2),B_loc%Nb))
       call MATRIX_transfer( M_out = B_loc, M=B )
       !
       call PARALLEL_lin_system( M_loc, B_loc, N, N)
       !
       call MATRIX_transfer( M_in =  B_loc, M=B )
       !
       YAMBO_FREE(B_loc%blc)
       call MATRIX_reset(B_loc)
       !
     else
       !
       call PARALLEL_lin_system( M_slk, B_slk, N, N)
       !
     endif
     !
   else if (idriver==MAT_MUL) then
     !
     if (.not.present(B_slk)) then
       !
       call MATRIX_init("SLK",  B_loc, N, 1 )
       YAMBO_ALLOC(B_loc%blc,(B_loc%BLCrows(1):B_loc%BLCrows(2),B_loc%BLCcols(1):B_loc%BLCcols(2),B_loc%Nb))
       call MATRIX_transfer( M_out =  B_loc, M=B )
       !
       call MATRIX_init("SLK",  C_loc, N, 1 )
       YAMBO_ALLOC(C_loc%blc,(C_loc%BLCrows(1):B_loc%BLCrows(2),C_loc%BLCcols(1):C_loc%BLCcols(2),C_loc%Nb))
       call MATRIX_transfer( M_out =  C_loc, M=C )
       !
       call PARALLEL_M_by_M( M_loc, B_loc, C_loc, 'N', 'N', N, N , N )
       call MATRIX_transfer( M_in =  C_loc, M=C )
       !
       call MATRIX_reset(B_loc)
       YAMBO_FREE(B_loc%blc)
       !
       call MATRIX_reset(C_loc)
       YAMBO_FREE(C_loc%blc)
       !
     else
       !
       call PARALLEL_M_by_M( M_slk, B_slk, C_slk, 'N', 'N', N, N , N )
       !
     endif
     !
   endif
   !
 endif
 !
#endif
 !
 ! =============== SERIAL SECTION ============================================================
 !
 if (lib_in_use==USE_LK.and..not.USE_GPU) then
   !
   ! ####> SVD INVERSION (Using Singular Value decomposition)
   !
   if (idriver==SVD_INV) then
     if (present(M_slk)) then
       call SERIAL_SVD_inversion(N,M_slk%blc(:,:,M_slk%I),SVD_digits)
     else
       call SERIAL_SVD_inversion(N,M,SVD_digits)
     endif
   endif
   !
   ! ###> SERIAL INVERSION 
   !
   if (idriver==INV) then
     if (present(M_slk)) then
       call SERIAL_inversion(N,M_slk%blc(:,:,M_slk%I),det_,present(det))
     else
       call SERIAL_inversion(N,M,det_,present(det))
     endif
     if(present(det)) det=det_
   endif
   !
   ! ###> SERIAL DIAGONALIZATION
   !
   if (idriver==DIAGO) then
     !
     if (present(E_cmpl)) then
       !
       !... non-Hermitian case
       if (present(M_slk)) then
         call SERIAL_diagonalization(N,M_slk%blc(:,:,M_slk%I),E_cmpl,V_left,V_right)
       else
         call SERIAL_diagonalization(N,M,E_cmpl,V_left,V_right)
       endif
     else
       !
       !... Hermitian case
       if (present(M_slk)) then
         call SERIAL_HERMITIAN_diagonalization(N,M_slk%blc(:,:,M_slk%I),E_real)
       else
         call SERIAL_HERMITIAN_diagonalization(N,M,E_real)
       endif
     endif
     !
   endif
   !
   ! ####> LINEAR SYSTEM SOLUTION
   !
   if (idriver==LIN_SYS) then
     if (present(M_slk)) then
       call SERIAL_lin_system(N,N,M_slk%blc(:,:,M_slk%I),B_slk%blc(:,:,B_slk%I))
     else
       call SERIAL_lin_system(N,size(B,2),M,B)
     endif
   endif
   !
   ! ####> MAT_MUL
   ! C = M * B
   if (idriver==MAT_MUL) then
     if (present(M_slk)) then
       call M_by_M('N','N',N,N,N,cONE,M_slk%blc(:,:,M_slk%I),N,&
&                          B_slk%blc(:,:,B_slk%I),N,cZERO,C_slk%blc(:,:,C_slk%I),N)
     else
       call M_by_M('N','N',size(C,1),size(C,2),size(M,2),cONE,M,size(M,1),&
&                          B,size(B,1),cZERO,C,size(C,1))
     endif
   endif
   !
 endif
 !
 ! =============== SERIAL SECTION GPU ============================================================
 !
 if (lib_in_use==USE_LK.and.USE_GPU) then
   !
   ! ####> LINEAR SYSTEM SOLUTION
   !
   if (idriver==LIN_SYS) then
#if defined _GPU && defined _PGI
     call SERIAL_lin_system_gpu(N,N,DEV_VAR(M_slk%blc)(:,:,M_slk%I),DEV_VAR(B_slk%blc)(:,:,B_slk%I))
#else
     call error('[LA] GPU support required but not present')
#endif
   endif
   !
 endif
 !
 ! ===========================================================================================
 !
 call timing("LINEAR ALGEBRA",OPR="stop")
 !
end subroutine
